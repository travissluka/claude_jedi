#!/usr/bin/env bash
# hpc-emulator: prove each of the 3 emulator layers measurably exists on this
# kernel. Runs end-to-end with sudo (NOPASSWD entries assumed — see
# sudoers.example). Uses separate dm/mount/image names from the main rig so it
# can run even if the main rig is up... but it DOES manipulate the lo qdisc
# globally, so refuses to run if a netem qdisc is already present.

set -euo pipefail
cd "$(dirname "$0")"

VERIFY_DM_NAME="hpc_emu_verify"
VERIFY_MNT="/mnt/hpc_emu_verify"
VERIFY_IMG="/dev/shm/hpc_emu_verify.img"
READ_MS=3
WRITE_MS=5

# Per-layer pass/fail; we collect all results then exit non-zero if any failed.
LAYER1_OK=0
LAYER2_OK=0
LAYER3_OK=0

# ------------------------------------------------------------ sudoers gate
if ! sudo -n -l /usr/sbin/dmsetup >/dev/null 2>&1; then
  cat >&2 <<EOF
[verify] NOPASSWD sudo not wired for dmsetup.

  One-time setup needed. Open a normal terminal window (not via Claude Code's
  \`!\` prefix — bootstrap needs an interactive TTY for the sudo prompt) and run:

    $(dirname "$0")/emulator_bootstrap.sh

EOF
  exit 1
fi

# ------------------------------------------------------------ safety check
if tc qdisc show dev lo | grep -q netem; then
  echo "[verify] lo already has a netem qdisc — main rig is probably up." >&2
  echo "         Tear it down first with emulator_teardown.sh." >&2
  exit 1
fi

# ------------------------------------------------------------ build pingpong if missing
if [ ! -x ./pingpong ]; then
  echo "=== building pingpong ==="
  make pingpong
fi

cleanup() {
  set +e
  sudo umount "$VERIFY_MNT" 2>/dev/null
  sudo dmsetup remove "$VERIFY_DM_NAME" 2>/dev/null
  PRIOR_LOOP=$(losetup -j "$VERIFY_IMG" 2>/dev/null | awk -F: '{print $1}' | head -1)
  [ -n "${PRIOR_LOOP:-}" ] && sudo losetup -d "$PRIOR_LOOP" 2>/dev/null
  rm -f "$VERIFY_IMG"
  sudo tc qdisc del dev lo root 2>/dev/null
}
trap cleanup EXIT

# ============================================================================
# LAYER 1: MPI off shared-memory onto loopback TCP
# ============================================================================
echo
echo "==============================================================="
echo " LAYER 1: MPI shared-memory vs loopback TCP"
echo "==============================================================="

# shm baseline
SHM_OUT=$(mpiexec -n 2 ./pingpong)
SHM_US=$(echo "$SHM_OUT" | awk '/half-RT/ {print $8}')
echo "shm baseline: half-RT = ${SHM_US} us"

# TCP loopback
TCP_OUT=$(mpiexec -n 2 -genv MPIR_CVAR_NOLOCAL=1 -genv FI_PROVIDER=tcp ./pingpong)
TCP_US=$(echo "$TCP_OUT" | awk '/half-RT/ {print $8}')
echo "TCP loopback: half-RT = ${TCP_US} us"

# Expect TCP at least 3× slower than shm. Anything less and the env vars didn't take.
RATIO=$(awk -v t="$TCP_US" -v s="$SHM_US" 'BEGIN{print (s>0)?t/s:0}')
echo "ratio (TCP/shm): $RATIO"
if awk -v r="$RATIO" 'BEGIN{exit !(r>=3)}'; then
  echo "[layer 1] PASS (TCP at least 3× shm)"
  LAYER1_OK=1
else
  echo "[layer 1] FAIL — TCP not measurably slower than shm; env vars probably not applied"
fi

# ============================================================================
# LAYER 2: netem on lo
# ============================================================================
echo
echo "==============================================================="
echo " LAYER 2: netem on lo"
echo "==============================================================="

# baseline ping
echo "--- baseline ping (no netem) ---"
BASE_RTT=$(ping -c 5 -i 0.2 -q 127.0.0.1 | awk -F'/' '/rtt/ {print $5}')
echo "baseline RTT: ${BASE_RTT} ms"

# add 1ms netem (visible in ping)
sudo tc qdisc add dev lo root handle 1: netem delay 1ms 200us distribution normal
echo "--- with netem 1ms ---"
NETEM_RTT=$(ping -c 5 -i 0.2 -q 127.0.0.1 | awk -F'/' '/rtt/ {print $5}')
echo "netem RTT: ${NETEM_RTT} ms"
sudo tc qdisc del dev lo root

# Expect netem RTT to be at least 1.5 ms (baseline is usually <0.1 ms; netem
# adds 2 ms round-trip on a 1 ms one-way; allow slack for jitter and the
# distribution=normal spread).
if awk -v n="$NETEM_RTT" 'BEGIN{exit !(n>=1.5)}'; then
  echo "[layer 2] PASS (netem RTT >= 1.5 ms)"
  LAYER2_OK=1
else
  echo "[layer 2] FAIL — netem RTT not measurably elevated"
fi

# ============================================================================
# LAYER 3: dm-delay block device on tmpfs
# ============================================================================
echo
echo "==============================================================="
echo " LAYER 3: dm-delay block device"
echo "==============================================================="

# cleanup any prior verify state
sudo umount "$VERIFY_MNT" 2>/dev/null || true
sudo dmsetup remove "$VERIFY_DM_NAME" 2>/dev/null || true

echo "--- creating 1 GiB sparse image on tmpfs ---"
truncate -s 1G "$VERIFY_IMG"
LOOP=$(sudo losetup -f --show "$VERIFY_IMG")
SECS=$(sudo blockdev --getsz "$LOOP")
echo "loop=$LOOP sectors=$SECS"

echo "--- creating dm-delay (read=${READ_MS}ms, write=${WRITE_MS}ms) ---"
printf '0 %d delay %s 0 %d %s 0 %d\n' "$SECS" "$LOOP" "$READ_MS" "$LOOP" "$WRITE_MS" \
  | sudo dmsetup create "$VERIFY_DM_NAME"
sudo /usr/sbin/mkfs.ext4 -q -F "/dev/mapper/$VERIFY_DM_NAME"
sudo mkdir -p "$VERIFY_MNT"
sudo mount "/dev/mapper/$VERIFY_DM_NAME" "$VERIFY_MNT"
sudo chown "$USER" "$VERIFY_MNT"

# 200 × 4 KiB direct writes should take ~200 × 5 ms = ~1 s (plus a bit of overhead).
echo "--- 200 × 4KiB direct writes (expect ~1s for ${WRITE_MS}ms write delay) ---"
DD_OUT=$( { /usr/bin/time -f '%e' dd if=/dev/zero of="$VERIFY_MNT/dd_slow" bs=4k count=200 oflag=direct status=none; } 2>&1 )
echo "elapsed: ${DD_OUT} s"

# Expect at least 0.5 s (50% of theoretical 1 s minimum). If it's much faster,
# direct I/O isn't actually going through dm-delay.
if awk -v t="$DD_OUT" 'BEGIN{exit !(t>=0.5)}'; then
  echo "[layer 3] PASS (write took >= 0.5 s)"
  LAYER3_OK=1
else
  echo "[layer 3] FAIL — write completed too fast; dm-delay not engaged"
fi

# ============================================================================
# Summary
# ============================================================================
echo
echo "==============================================================="
echo " SUMMARY"
echo "==============================================================="
printf "  layer 1 (TCP MPI):       %s\n" "$([ $LAYER1_OK = 1 ] && echo PASS || echo FAIL)"
printf "  layer 2 (netem on lo):   %s\n" "$([ $LAYER2_OK = 1 ] && echo PASS || echo FAIL)"
printf "  layer 3 (dm-delay):      %s\n" "$([ $LAYER3_OK = 1 ] && echo PASS || echo FAIL)"

if [ "$LAYER1_OK" = 1 ] && [ "$LAYER2_OK" = 1 ] && [ "$LAYER3_OK" = 1 ]; then
  echo
  echo "[verify] ALL LAYERS PASS"
  exit 0
else
  echo
  echo "[verify] one or more layers failed — see SKILL.md failure modes" >&2
  exit 2
fi
