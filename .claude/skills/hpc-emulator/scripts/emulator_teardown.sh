#!/usr/bin/env bash
# hpc-emulator: tear down everything emulator_setup.sh created. Idempotent.

set -euo pipefail

IMG="${HPC_EMU_IMG:-/dev/shm/hpc_emu.img}"
MNT="${HPC_EMU_MNT:-/mnt/hpc_emu}"
DM_NAME="hpc_emu"

echo "=== removing netem on lo ==="
sudo tc qdisc del dev lo root 2>/dev/null || true

echo "=== unmount + remove dm-delay ==="
sudo umount "$MNT" 2>/dev/null || true
sudo dmsetup remove "$DM_NAME" 2>/dev/null || true

echo "=== detaching loop devices for known image paths ==="
# Detach loops for the configured image plus the legacy slow.img location so
# this script can also clean up stale state from the pre-rename rig.
for img in "$IMG" /dev/shm/slow.img /var/tmp/slow.img; do
  PRIOR_LOOP=$(losetup -j "$img" 2>/dev/null | awk -F: '{print $1}' | head -1)
  if [ -n "${PRIOR_LOOP:-}" ]; then
    echo "  detaching $PRIOR_LOOP (image=$img)"
    sudo losetup -d "$PRIOR_LOOP" || true
  fi
  rm -f "$img"
done

echo "=== clean state ==="
tc qdisc show dev lo | head -1
mount | grep -E 'hpc_emu|slowfs' || echo "(no emulator mount)"
