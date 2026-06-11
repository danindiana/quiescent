# HDD Quiescent Standby & Shutdown Spin-Up Investigation

## 1. Overview
During analysis of the system shutdown sequence for boot session `-1`, a delay of ~36 seconds was observed. The primary contributors to this delay were storage management services blocking on mechanical hard drive spin-ups during the unmounting of archive filesystems. 

This document logs the investigation into this behavior, evaluates the SMART wear costs associated with disk power management, and outlines the permanent configuration change implemented to resolve it.

---

## 2. Shutdown Spin-Up Evidence
Logs from the unmounting sequence show a distinct signature of quiescent (sleeping) drives being forced to wake up to complete unmount transactions:
* **Boot -1 (Most Recent)**:
  * `/mnt/hitachi_2tb` (`sde`) unmount request: `07:19:28`
  * `/mnt/hitachi_2tb` (`sde`) unmount completed: `07:19:39` (**11.0 second delay**)
* **Boot -2**:
  * `/mnt/sda1` (`sdc`) unmount request: `16:29:17`
  * `/mnt/sda1` (`sdc`) unmount completed: `16:29:22` (**5.0 second delay**)

These delays (5–11s) match the exact physical platter spin-up profile of 3.5" mechanical hard drives.

---

## 3. The Mechanics of the Wake-up
When a drive is mounted read-write (`rw`), the kernel and systemd must perform filesystem housecleaning during unmount, which includes:
1. Syncing remaining dirty cache buffers.
2. Flushing the ext4 journal.
3. Updating the filesystem superblock flag to indicate a clean unmount state.

Even if no user files are written, these metadata operations require a physical write. When the drive is in standby mode, the SATA controller forces the drive to spin up to commit this write, causing systemd to block.

---

## 4. SMART Wear Analysis & Activity Profiling
Analyzing the wear profile of the three mechanical drives on the system:

| Device | Model / Purpose | Power-On Hours | Start/Stop Count | Power Cycles | Spin-up Ratio | Standby Mode |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `/dev/sde` | Hitachi 2TB (Archive) | 43,264 hrs | 18,209 | 751 | **24.2** | Aggressive (`idle-hdd-spindown`) |
| `/dev/sdc` | WD AV-GP 1TB (Archive) | 72,561 hrs | 526 | 471 | **1.1** | Custom (`idle-disk-park` script) |
| `/dev/sdg` | WD Black 4TB (Backup) | 22,382 hrs | 3,520 | 1,204 | **2.9** | Manual / Unmounted (`noauto`) |

### Key Observations
* **Hitachi 2TB (`sde`)**: The spin-up ratio is **24.2** (17,458 sleep-wake cycles induced by the power management script). This has consumed a significant chunk of the drive's rated mechanical start/stop cycles (typically 50,000 for older enterprise units).
* **WD AV-GP 1TB (`sdc`)**: The low start/stop count (526) reflects its design as a 24/7 surveillance drive. It has spent almost its entire 8-year lifespan spinning.
* **WD Black 4TB (`sdg`)**: Because it is unmounted by default (`noauto`), it is completely isolated from the system shutdown unmount phase and does not experience spurious wake-ups.
* **Write Counts**: `/proc/diskstats` confirmed that only **10 writes** occurred on `/dev/sdc1` and `/dev/sde1` since booting, confirming they are quiescent archive drives with no active user-level write traffic.

---

## 5. Resolution: Read-Only fstab Mounting
Because these archive drives do not require active writes during normal system runtimes, the unmount write signature was eliminated by remounting them read-only (`ro`).

### `/etc/fstab` Modifications
The following changes were persisted in `/etc/fstab`:

```diff
# /dev/sdc1 (WD AV-GP 1TB HDD)
- UUID=bdfa8aeb-2dba-4de8-a5e4-e116f8166c87 /mnt/sda1 ext4 defaults,noatime,commit=60,nofail 0 2
+ UUID=bdfa8aeb-2dba-4de8-a5e4-e116f8166c87 /mnt/sda1 ext4 ro,noatime,nofail 0 2

# /dev/sde1 (Hitachi 2TB HDD)
- UUID=3d285e0a-9860-42ec-8aa9-a89b17ce7262 /mnt/hitachi_2tb ext4 defaults,nofail,x-systemd.device-timeout=5s 0 2
+ UUID=3d285e0a-9860-42ec-8aa9-a89b17ce7262 /mnt/hitachi_2tb ext4 ro,noatime,nofail,x-systemd.device-timeout=5s 0 2
```

### Action Taken
1. Updated `/etc/fstab` with `ro` configuration.
2. Remounted the live filesystems:
   ```bash
   sudo mount -o remount,ro /mnt/sda1
   sudo mount -o remount,ro /mnt/hitachi_2tb
   ```
3. Reloaded systemd:
   ```bash
   sudo systemctl daemon-reload
   ```

### Live Synchronization Note
No system reboot is required to activate these changes. The live kernel mount options were dynamically updated to `ro,noatime` via the remount commands, and systemd's mount tracking units (`mnt-sda1.mount` and `mnt-hitachi_2tb.mount`) were synchronized with `/etc/fstab` via the `daemon-reload` command, ensuring perfect alignment between the running state and fstab.

A read-only unmount does not write to the superblock metadata. Consequently, both `/dev/sdc` and `/dev/sde` will remain in their standby/quiescent state during future shutdowns, preventing mechanical wear and eliminating up to 15+ seconds of shutdown latency.
