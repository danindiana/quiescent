# Stale Positional-Reference Cleanup — worlock

**Date:** 2026-05-31 14:46 CDT
**Host:** worlock · Linux 6.8.12
**Trigger:** "careful stale ref cleanup" — follow-up to this session's REPORT.md (Finding 1)
**Parent report:** `REPORT.md` (smartd by-id fix) · memory: `feedback_unstable_device_names.md`

---

## TL;DR

A sweep of `/etc` found several configs still naming the **dead `enp7s0`/`enp8s0` NICs**
and **wrong `/dev/sdX` disks** — fallout from the RTX 5080/3080 PCIe renumbering (the same
root cause as the `enp8s0→enp9s0` and smartd by-id fixes). **None affected a running
service** (UFW live ruleset already used `enp9s0`). Cleaned them all up.

**Safety principle:** every change was to an **on-disk file only**. No `netplan apply`,
`sysctl -p`, `ufw reload`, `nft -f`, or network/firewall restart was run — the live network,
firewall, and SSH session were never touched. All edits take effect on next boot. Every
edited file has a `.bak-2026-05-31` (or `.disabled-2026-05-31`) sibling. Reversible.

---

## Changes

| # | File | Action | Rationale |
|---|------|--------|-----------|
| 1 | `/etc/iproute2/rt_tables` | removed `200 rt_enp7s0` | orphaned table name; no `ip rule` uses table 200 |
| 2 | `/etc/sysctl.conf:106` | commented `net.ipv4.conf.enp7s0.rp_filter` | dead NIC; X540-T2 multipath removed; key errored at boot |
| 3 | `/etc/nftables.conf:384` | `oifname "enp7s0"` → `"enp9s0"` | dormant (nftables.service inactive); correct-if-ever-enabled |
| 4 | `/etc/iptables/rules.v4` + `rules.v6` | regenerated via `netfilter-persistent save` | stale `iptables-save` snapshots (`-o enp7s0`); refreshed from live UFW (enp9s0) |
| 5 | `/etc/iptables.rules` (root) | → `.disabled-2026-05-31` | legacy file; **nothing loads it** (grep of /etc, /usr/local empty) |
| 6 | `/etc/netplan/01-netcfg.yaml` | removed → `.disabled-2026-05-31` | targeted dead `enp7s0`; redundant — `01-network-manager-all.yaml` already delegates all to NM (user-approved deletion) |
| 7 | `/etc/update-motd.d/99-nvme-status:91` | removed "Backup Ubuntu on /dev/sdd2" line | **false**: sdd2 is a `linux_raid_member` (md0), not a bootable Ubuntu |
| 8 | `/etc/NetworkManager/dispatcher.d/90-ethtool-buffers` + `99-enp7s0-tuning` | moved to `dispatcher.d.disabled/` | NIC-tuning scripts for dead `enp7s0`; **superseded** by `ethtool@enp9s0.service` (`nic-tune.sh enp9s0 8 4096`, set up last session) |

Items 1–7 were in the approved plan. **Item 8 was discovered during verification** (the
initial sweep was truncated by `head`): two NetworkManager dispatcher scripts that tune the
NIC on link-up but target `enp7s0`, so they never fire — the NM analogue of the
`ethtool@enp8s0` unit fixed in the boot-log audit. Confirmed `nic-tune.sh` already applies
both ring buffers (4096 target) and coalescing (25 µs, live on enp9s0), so disabling them
loses nothing. NM runs *any executable* in `dispatcher.d` regardless of name, so a `.disabled`
rename wasn't enough — they were moved out of the directory entirely.

## Verification (`raw/cleanup-verification.txt`)

- ✅ Final sweep — **no `enp7s0`/`enp8s0` in any loaded config** (only a dated comment in
  `sysctl.conf` remains, intentionally).
- ✅ `rules.v4`: enp7s0 = 0, enp9s0 = 2 (matches live UFW).
- ✅ Live unchanged: UFW active (SSH <custom-port> on enp9s0), smartd active, enp9s0 up at
  192.168.1.85, coalescing still 25 µs.
- ✅ `netplan generate` exit 0; `nft -c` parses (modulo the pre-existing include below).

## Pre-existing items found (NOT caused by this cleanup, NOT fixed)

1. **nftables include gap:** `nftables.conf:1008` includes `/etc/nftables.d/pia-vpn.nft`,
   but only `pia-vpn.nft.disabled` exists. Inert — `nftables.service` is inactive. Predates
   this work.
2. **Ring-buffer at driver default — ✅ RESOLVED 2026-05-31.** Live enp9s0 ring was **256**
   though `nic-tune.sh` targets 4096. Root cause was a **bug in `nic-tune.sh` (line 53)**, not
   the hardware: the `rmax` awk set its flag at `Pre-set maximums` but never cleared it at the
   `Current hardware settings` boundary, so it read RX/TX from *both* blocks and computed
   `rmax=256` (the current value) instead of 4096. → `want=min(4096,256)=256 == rcur` → the
   ring change was skipped silently (no "Setting rings" log). Fixed by adding
   `/Current hardware settings/{f=0}` and anchoring `^RX:`/`^TX:`. Applied live (user-approved;
   the `ethtool -G` triggered a brief igb adapter reset / ~3-5 s link blip that auto-recovered).
   Now: ring **4096/4096**, coalesce 25 µs, Combined queues 2 (= I211 hardware max), link up,
   gateway reachable. Persists across reboot via the enabled `ethtool@enp9s0.service`. Backup:
   `/usr/local/sbin/nic-tune.sh.bak-2026-05-31`. Evidence: `raw/igb-ring-fix-verification.txt`.

## Reverting

Each change is reversible: restore the `.bak-2026-05-31` over the live file (items 1–4, 7),
rename the `.disabled-2026-05-31` files back (items 5, 6), or move the dispatcher scripts
from `dispatcher.d.disabled/` back into `dispatcher.d/` (item 8). For items 4 (iptables) the
backup is the pre-`save` snapshot; re-running `netfilter-persistent save` re-syncs to live.
