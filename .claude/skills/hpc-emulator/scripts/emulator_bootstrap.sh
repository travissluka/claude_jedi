#!/usr/bin/env bash
# hpc-emulator: one-time bootstrap. Installs the NOPASSWD sudoers fragment so
# emulator_setup.sh / emulator_verify.sh / emulator_teardown.sh can run
# unattended. Requires one sudo password prompt (to write into /etc/sudoers.d/);
# after that the skill is hands-off.
#
# **RUN THIS IN YOUR OWN TERMINAL, NOT THROUGH CLAUDE.** Writing to
# /etc/sudoers.d/ is a deliberate security boundary that should be crossed
# explicitly by the human operator, and a Claude session won't render the
# interactive sudo password prompt cleanly anyway.
#
# Idempotent: if NOPASSWD is already wired, exits 0 with a note.

set -euo pipefail
cd "$(dirname "$0")"

SUDOERS_TARGET=/etc/sudoers.d/hpc-emulator
RENDERED=$(mktemp)
trap 'rm -f "$RENDERED"' EXIT

# ------------------------------------------------------------ probe
probe_nopasswd() {
  # Returns 0 if dmsetup is callable via sudo without a password.
  sudo -n -l /usr/sbin/dmsetup >/dev/null 2>&1
}

if probe_nopasswd; then
  echo "[bootstrap] NOPASSWD sudo already wired for dmsetup — nothing to do."
  echo "            (existing file: $(ls -l $SUDOERS_TARGET 2>/dev/null || echo 'not at default location, but probe succeeded'))"
  exit 0
fi

# ------------------------------------------------------------ render
echo "[bootstrap] no NOPASSWD entry detected. About to install one."
echo
echo "Target file: $SUDOERS_TARGET"
echo "User:        $USER"
echo
echo "--- contents to be installed ---"
sed "s/__USER__/$USER/g" sudoers.example | tee "$RENDERED"
echo "--- end contents ---"
echo

# ------------------------------------------------------------ confirm
if [ -t 0 ]; then
  read -r -p "Install this sudoers fragment? You will be prompted for your sudo password. [y/N] " ANS
  case "$ANS" in
    y|Y|yes|YES) ;;
    *) echo "[bootstrap] aborted by user."; exit 1 ;;
  esac
else
  cat >&2 <<EOF

[bootstrap] stdin is not a TTY — cannot show the y/N or sudo password prompt.

  This script requires an interactive terminal. The Claude Code \`!\` prefix
  runs commands in a non-interactive subshell, so the prompts fail silently
  there. Open a normal terminal window (gnome-terminal, tmux, ssh session,
  etc. — NOT via Claude) and run:

    $(realpath "$0")

  Or, if you'd rather install manually with no prompts:

    sed "s/__USER__/\$USER/g" $(dirname "$(realpath "$0")")/sudoers.example \\
      | sudo tee $SUDOERS_TARGET >/dev/null
    sudo chmod 0440 $SUDOERS_TARGET
    sudo visudo -cf $SUDOERS_TARGET

EOF
  exit 1
fi

# ------------------------------------------------------------ install
echo "[bootstrap] running visudo syntax check on the rendered fragment..."
if ! sudo visudo -cqf "$RENDERED"; then
  echo "[bootstrap] sudoers fragment failed syntax check — refusing to install." >&2
  exit 2
fi

echo "[bootstrap] installing to $SUDOERS_TARGET (mode 0440, owner root)..."
sudo install -m 0440 -o root -g root "$RENDERED" "$SUDOERS_TARGET"

# ------------------------------------------------------------ verify it took
if probe_nopasswd; then
  echo
  echo "[bootstrap] SUCCESS — NOPASSWD entries active."
  echo "  The hpc-emulator skill is ready. Tell Claude to set up / verify / tear"
  echo "  down the emulator as needed — no further user action required."
  exit 0
else
  echo
  echo "[bootstrap] installed but probe still fails." >&2
  echo "  Check $SUDOERS_TARGET and run 'sudo -l' to see what sudo thinks." >&2
  exit 3
fi
