#!/usr/bin/env bash
# quiescent installer — copies the units + watcher into place and enables them.
#
# IMPORTANT: the shipped units reference *worlock's* drives by serial. Edit the
# by-id paths in systemd/*.service and bin/idle-disk-park.sh to match YOUR drives
# BEFORE running this (see README "Install / adapt"). This script will refuse to
# run if the example serials are still present.
set -euo pipefail
cd "$(dirname "$0")/.."

WORLOCK_SERIALS='VBGZSTNF|MK0171YFJHSSDA|WD-WCC4J2CHPRRU'
if grep -rqE "$WORLOCK_SERIALS" systemd/ bin/ 2>/dev/null; then
  echo "refusing to install: example worlock serials still present." >&2
  echo "edit the by-id device paths in systemd/*.service and bin/idle-disk-park.sh first." >&2
  exit 1
fi

[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo)"; exit 1; }

install -m0644 systemd/wd-backup-spindown.service systemd/idle-hdd-spindown.service \
               systemd/idle-disk-park.service systemd/idle-disk-park.timer /etc/systemd/system/
install -m0755 bin/idle-disk-park.sh /usr/local/sbin/idle-disk-park.sh

systemctl daemon-reload
systemctl enable --now wd-backup-spindown.service idle-hdd-spindown.service idle-disk-park.timer

echo "installed. verify with:  systemctl list-timers idle-disk-park.timer ; hdparm -C /dev/disk/by-id/<your-drive>"
