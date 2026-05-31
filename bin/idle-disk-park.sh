#!/bin/sh
# Force-park drives whose firmware IGNORES the ATA standby idle timer (e.g. the
# WD AV-GP WD10EURX, built to spin 24/7 for surveillance). Driven by
# idle-disk-park.timer (~every 1 min). For each listed drive: if it has had NO
# block I/O for >= IDLE seconds, issue `hdparm -y` (immediate standby). State is
# kept in /run (tmpfs, rebuilt after boot). Drives pinned by-id (survive SATA
# letter drift). Drives that honor the -S timer are handled by the simpler
# wd-backup-spindown.service / idle-hdd-spindown.service instead.

IDLE=300   # park after 5 min of no I/O

DEVS="
/dev/disk/by-id/ata-WDC_WD10EURX-63UY4Y0_WD-WCC4J2CHPRRU
"

for DEV in $DEVS; do
    [ -e "$DEV" ] || continue
    blk=$(basename "$(readlink -f "$DEV")")
    [ -e "/sys/block/$blk/stat" ] || continue

    # Already parked? skip — never wake it.
    pw=$(hdparm -C "$DEV" 2>/dev/null | awk -F: '/state/{gsub(/ /,"",$2);print $2}')
    case "$pw" in standby|sleeping) continue ;; esac

    state="/run/idle-disk-park.$blk"
    io=$(awk '{print $1"-"$5}' "/sys/block/$blk/stat")   # completed read+write I/Os
    now=$(date +%s)

    if [ -f "$state" ]; then
        read pio pts < "$state"
        if [ "$io" = "$pio" ]; then
            # No I/O since the idle window opened; park if idle long enough.
            if [ $((now - pts)) -ge "$IDLE" ]; then
                hdparm -y "$DEV" >/dev/null 2>&1
                rm -f "$state"
            fi
            continue
        fi
    fi
    # First sighting, or I/O changed since last check -> (re)open the idle window.
    printf '%s %s\n' "$io" "$now" > "$state"
done
