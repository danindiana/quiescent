# Lessons Learned

![lessons learned](assets/diagrams/lessons-learned.png)

A "spin down idle disks" task turned into a multi-hour investigation. The lessons generalise
well beyond this one machine.

## 1. Pin to *identity*, not *position*

`/dev/sdX` and `enpXsY` encode **bus position**, not device identity. On a machine where the
PCIe topology changes — a GPU swap, a card added, BIOS reorder, a drive added — the kernel
reassigns those names, and **the same physical hardware lands at a different name**. Any config
pinned to the old name silently acts on the wrong device, *without erroring*.

On worlock the RTX 5080/3080 installs drifted the NIC `enp7s0 → enp8s0 → enp9s0` and rotated
SATA letters (the WD Black moved `/dev/sda → /dev/sdg`). Casualties:

- `smartd.conf` applied per-drive temperature thresholds to the **wrong disks**.
- `ethtool@enp8s0` tuned a dead NIC → **~90 s boot timeout**.
- Firewall snapshots, `netplan`, `sysctl`, NetworkManager dispatcher scripts all named a NIC
  that no longer existed.

**Fix:** pin everything to stable identifiers — `/dev/disk/by-id/*` or `UUID` for disks, MAC
for NICs. `fstab` (UUID) and `hdparm.conf` (by-id) were already correct; everything that used
raw names had drifted. *After any hardware change, grep your configs for positional names.*

## 2. `pm-utils` is dead — `hdparm.conf` silently doesn't apply

`hdparm.conf`'s `-S`/`-B` settings are applied at boot by a `udev RUN+=/lib/udev/hdparm` rule
that delegates to `pm-utils`' `95hdparm-apm`. `pm-utils` is deprecated (it showed `un` in
`dpkg`), and that path is unreliable under `systemd-udevd`: it works when you run it by hand,
but **silently no-ops during boot**. Result — drives that `hdparm.conf` *intended* to spin down
came up with no standby timer armed and spun 24/7.

**Fix:** don't trust the legacy path. Own the setting with a deterministic **systemd oneshot**
(or a timer + watcher). The same applies to other "I put it in the config but it didn't take"
hdparm/udev mysteries on modern systemd.

## 3. Drive firmware varies wildly — verify, per drive

Three drives, three behaviours:

- **WD Black (WD4005FZBX):** honors *short* standby timers but **ignores long ones**. `-S 12`
  (1 min) parks reliably; `-S 60` (5 min) and `-S 120` (10 min) never park — verified with the
  drive completely idle (flat block I/O for >10 min).
- **Hitachi (HUA723020ALA640):** honors `-S 12` like the WD Black.
- **WD10EURX (AV-GP / surveillance-class):** ignores the `-S` timer **entirely** and doesn't
  support APM — but **obeys a forced `hdparm -y`**. It's built to spin 24/7 for DVRs.

**Fix:** there is no universal value. Probe each drive: set `-S`, wait, check `hdparm -C`; if it
won't time out, try forced `-y`. Honors timer → oneshot. Obeys only `-y` → software watcher.

## 4. Measure, don't assume — and mind the observer effect

- **APM 254 was a red herring.** The obvious hypothesis ("max-performance APM blocks spin-down")
  was wrong — a 60-second `-S 12` test parked the drive regardless of APM 254.
- **The observer effect is real.** `fuser -m /dev/sdX` *opens* the block device and resets the
  standby idle timer; an early "it didn't park after 10 min" reading was partly self-inflicted.
  `hdparm -C` (CHECK POWER MODE), by contrast, is genuinely non-intrusive — it doesn't reset the
  timer or wake the drive, which makes it the right tool for watching power state.
- You **cannot read a parked drive's temperature without spinning it up** (SMART temp needs the
  drive awake). Plan measurements around that.

## 5. Mind your own processes

A runaway filesystem-wide `grep` — a leftover of *this investigation's own* searches — had been
crawling a 2 TB drive's millions of files for **75 minutes**, keeping it spinning (and warm) for
zero benefit. The drive looked "busy" until we traced the reader. Killing one stray process was
itself a measurable cooling win. Always check *what* is doing the I/O before concluding a drive
is legitimately active.

## 6. Fewer spinning platters cools the neighbours too

The payoff wasn't limited to the parked drives. The always-on RAID0 IronWolfs dropped
**−3…−7 °C without being parked**, purely because their idle neighbours stopped dumping heat
into the shared cage. In a dense, airflow-constrained enclosure, every platter you can stop is
heat you remove from *every* drive around it.

## 7. A parked drive gets spun back up at shutdown — and that's correct

A follow-up investigation (2026-06-11) asked the obvious question: if a drive is parked,
doesn't *shutting the machine down* needlessly spin it back up? It does — for any disk holding a
**mounted read-write filesystem** — and that spin-up is **necessary, not a bug**.

- **The actor is the kernel/systemd unmount path, not `udisks2`.** `udisksd` only *monitors*
  devices. Cleanly unmounting a mounted RW ext4 filesystem flushes the journal and clears the
  dirty superblock flag — a **write** — so a parked disk must spin up to service it. Skipping the
  write would leave the filesystem flagged dirty and force an `fsck` on the next boot. Strictly
  worse than a ~6 s spin-up.
- **Only *mounted* RW disks are affected.** An *unmounted* parked drive (on worlock: `sdg`, the
  WD Black backup) has nothing to flush and is **never woken** at shutdown. The quiescent design
  already gets this right by leaving the backup unmounted.
- **Unmount duration is a free spin-up probe.** In `journalctl`, the gap between
  `Unmounting /mnt/X...` and `Unmounted /mnt/X` is a reliable standby→active proxy: ~8–11 s means
  the drive was parked and spun up; ~0 s means it was already awake from recent use. So the cost
  is *at most* one spin-up per mounted parked disk per shutdown, and often zero.
- **The wear is negligible.** One extra `Start_Stop_Count` per shutdown (~1–2×/day) is dwarfed by
  the daily parking cycles the watcher/timer themselves drive (the Hitachi was already at
  ~18 k start/stops). Not a concern.
- **If you truly want zero shutdown spin-up**, mount the archive read-only — a clean `ro` ext4
  unmount writes nothing. Only worth it for a *pure read* archive, since writes then need
  `mount -o remount,rw` first.

*Full write-up + diagrams: `worlock-session-archive` →
`2026-06-11_072443_destructive-transaction-investigation/DISK_SHUTDOWN_SPINUP.md`.*
