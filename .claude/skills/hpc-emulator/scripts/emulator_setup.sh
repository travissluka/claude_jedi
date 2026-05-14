#!/usr/bin/env bash
# hpc-emulator: set up the slow filesystem + netem fabric.
#
# On first use per host+kernel, runs emulator_verify.sh first and caches the
# result so subsequent setups skip verify. Override via HPC_EMU_FORCE_VERIFY=1
# (re-verify) or HPC_EMU_SKIP_VERIFY=1 (skip even on fresh host).
#
# All knobs are env vars — see SKILL.md "Configuration" for the full list.

set -euo pipefail
cd "$(dirname "$0")"

# ------------------------------------------------------------ config (defaults)
IMG="${HPC_EMU_IMG:-/dev/shm/hpc_emu.img}"
IMG_GB="${HPC_EMU_IMG_GB:-25}"
MNT="${HPC_EMU_MNT:-/mnt/hpc_emu}"
READ_MS="${HPC_EMU_READ_MS:-3}"
WRITE_MS="${HPC_EMU_WRITE_MS:-5}"
NETEM_DELAY="${HPC_EMU_NETEM_DELAY:-10us}"
NETEM_JITTER="${HPC_EMU_NETEM_JITTER:-2us}"
STAGE_SRC="${HPC_EMU_STAGE_SRC:-}"
STAGE_GLOB="${HPC_EMU_STAGE_GLOB:-*}"
DM_NAME="hpc_emu"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hpc-emulator"
CACHE_FILE="$CACHE_DIR/verified-$(hostname)-$(uname -r)"

# ------------------------------------------------------------ sudoers gate
# Probe for NOPASSWD on dmsetup. If missing, point at the bootstrap script
# rather than hanging on a password prompt mid-setup.
if ! sudo -n -l /usr/sbin/dmsetup >/dev/null 2>&1; then
  cat >&2 <<EOF
[setup] NOPASSWD sudo not wired for dmsetup.

  One-time setup needed. Open a normal terminal window (not via Claude Code's
  \`!\` prefix — bootstrap needs an interactive TTY for the sudo prompt) and run:

    $(dirname "$0")/emulator_bootstrap.sh

EOF
  exit 1
fi

# ------------------------------------------------------------ verify gate
if [ "${HPC_EMU_SKIP_VERIFY:-}" = "1" ]; then
  echo "[setup] HPC_EMU_SKIP_VERIFY=1 — skipping verify"
elif [ "${HPC_EMU_FORCE_VERIFY:-}" = "1" ] || [ ! -f "$CACHE_FILE" ]; then
  if [ "${HPC_EMU_FORCE_VERIFY:-}" = "1" ]; then
    echo "[setup] HPC_EMU_FORCE_VERIFY=1 — re-running verify"
  else
    echo "[setup] no verify cache for $(hostname) kernel $(uname -r) — running verify first"
  fi
  if "$(dirname "$0")/emulator_verify.sh"; then
    mkdir -p "$CACHE_DIR"
    {
      echo "host=$(hostname)"
      echo "kernel=$(uname -r)"
      echo "verified_at=$(date -Iseconds)"
      echo "read_ms=$READ_MS"
      echo "write_ms=$WRITE_MS"
      echo "netem_delay=$NETEM_DELAY"
      echo "netem_jitter=$NETEM_JITTER"
    } > "$CACHE_FILE"
    echo "[setup] verify passed, cached at $CACHE_FILE"
  else
    echo "[setup] verify FAILED — refusing to set up emulator with broken layers" >&2
    exit 1
  fi
else
  echo "[setup] verify cache hit ($CACHE_FILE) — skipping verify"
fi

# ------------------------------------------------------------ path gate
# sudoers.example only permits the default IMG and MNT paths — any override
# will silently hang on a password prompt. Reject up front instead.
if [ "$IMG" != "/dev/shm/hpc_emu.img" ] || [ "$MNT" != "/mnt/hpc_emu" ]; then
  echo "[setup] HPC_EMU_IMG / HPC_EMU_MNT overrides aren't permitted by the default sudoers." >&2
  echo "         You set:   IMG=$IMG  MNT=$MNT" >&2
  echo "         Allowed:   IMG=/dev/shm/hpc_emu.img  MNT=/mnt/hpc_emu" >&2
  echo "         Either unset the overrides, or edit /etc/sudoers.d/hpc-emulator." >&2
  exit 1
fi

# ------------------------------------------------------------ cleanup prior
echo "=== cleanup any prior hpc-emulator state ==="
sudo umount "$MNT" 2>/dev/null || true
sudo dmsetup remove "$DM_NAME" 2>/dev/null || true
PRIOR_LOOP=$(losetup -j "$IMG" 2>/dev/null | awk -F: '{print $1}' | head -1)
[ -n "${PRIOR_LOOP:-}" ] && sudo losetup -d "$PRIOR_LOOP" || true
rm -f "$IMG"
sudo tc qdisc del dev lo root 2>/dev/null || true

# ------------------------------------------------------------ loop + dm-delay (0/0 for staging)
echo "=== creating ${IMG_GB} GB sparse image + loop device ==="
truncate -s "${IMG_GB}G" "$IMG"
LOOP=$(sudo losetup -f --show "$IMG")
echo "loop=$LOOP"
SECS=$(sudo blockdev --getsz "$LOOP")

echo "=== dm-delay with 0/0 (fast staging) ==="
printf '0 %d delay %s 0 0 %s 0 0\n' "$SECS" "$LOOP" "$LOOP" | sudo dmsetup create "$DM_NAME"
sudo /usr/sbin/mkfs.ext4 -q -F "/dev/mapper/$DM_NAME"
sudo mkdir -p "$MNT"
sudo mount "/dev/mapper/$DM_NAME" "$MNT"
sudo chown "$USER" "$MNT"

# ------------------------------------------------------------ stage (optional)
if [ -n "$STAGE_SRC" ]; then
  if [ ! -d "$STAGE_SRC" ]; then
    echo "[setup] HPC_EMU_STAGE_SRC=$STAGE_SRC is not a directory" >&2
    exit 1
  fi
  STAGE_NAME=$(basename "$STAGE_SRC")
  STAGE_DST="$MNT/$STAGE_NAME"
  mkdir -p "$STAGE_DST"
  echo "=== staging $STAGE_SRC/$STAGE_GLOB -> $STAGE_DST ==="
  # shellcheck disable=SC2086  # we want $STAGE_GLOB to glob
  (cd "$STAGE_SRC" && cp -r $STAGE_GLOB "$STAGE_DST/")
  sync
  echo "=== staged: $(du -sh "$STAGE_DST" | cut -f1) ==="
fi

# ------------------------------------------------------------ reload dm-delay (slow)
echo "=== reloading dm-delay with read=${READ_MS}ms write=${WRITE_MS}ms ==="
sudo umount "$MNT"
sudo dmsetup suspend "$DM_NAME"
printf '0 %d delay %s 0 %d %s 0 %d\n' "$SECS" "$LOOP" "$READ_MS" "$LOOP" "$WRITE_MS" \
  | sudo dmsetup reload "$DM_NAME"
sudo dmsetup resume "$DM_NAME"
sudo mount "/dev/mapper/$DM_NAME" "$MNT"

echo "=== dm-delay table now ==="
sudo dmsetup table "$DM_NAME"

# ------------------------------------------------------------ netem
echo "=== adding netem on lo: delay=${NETEM_DELAY} jitter=${NETEM_JITTER} ==="
sudo tc qdisc add dev lo root handle 1: netem delay "$NETEM_DELAY" "$NETEM_JITTER" distribution normal

echo
echo "=== EMULATOR READY ==="
echo "  mount:        $MNT (read=${READ_MS}ms write=${WRITE_MS}ms)"
echo "  netem on lo:  delay=${NETEM_DELAY} jitter=${NETEM_JITTER}"
[ -n "$STAGE_SRC" ] && echo "  staged input: $MNT/$(basename "$STAGE_SRC")"
echo
echo "Next:"
echo "  - Run your benchmark with MPIR_CVAR_NOLOCAL=1 FI_PROVIDER=tcp and"
echo "    taskset -c 0-\$((\$(nproc)-2)) mpiexec -n \$((\$(nproc)-1)) (see SKILL.md)"
echo "  - When done: $(dirname "$0")/emulator_teardown.sh"
