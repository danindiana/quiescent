# quiescentd — Nim implementation

A typed, encapsulated reimplementation of the shell watcher
([`../bin/idle-disk-park.sh`](../bin/idle-disk-park.sh)) as a single long-running daemon.

## Why a second implementation?

The shell version works, but its state is stringly-typed and lives in shell globals + `/run`
files. The Nim port encapsulates it properly:

- **`Drive` object** with a `PowerState` enum and a `Mode` enum (`mWatch` / `mTimer`) instead
  of string-matching `hdparm -C` output ad hoc.
- **Idle tracking is private** — the `lastIo` / `idleSince` / `haveSample` fields are *not*
  `*`-exported, so the only way to advance a drive's state is `poll()`. No `/run` state files;
  the window lives in memory.
- **Pure, testable config parser** (`parseConfig`: string → `Config`), separate from I/O.
- **One process** arms timer-mode drives once, then polls watch-mode drives on a cadence —
  config-driven, so it generalizes to any number of drives (the "generalize the watcher"
  future-direction).

| | shell (`idle-disk-park.sh`) | Nim (`quiescentd`) |
|---|---|---|
| state | `/run/*` files + globals | in-memory, private fields |
| types | strings | `Drive` / `PowerState` / `Mode` |
| drive list | hard-coded in script | `/etc/quiescent.conf` |
| process model | oneshot per timer tick | one daemon |

## Layout

```
nim/
├── quiescent.nimble          package manifest
├── quiescent.conf.example    sample /etc/quiescent.conf
├── systemd/quiescentd.service
└── src/
    ├── quiescentd.nim        main: arm timers, watch loop
    └── quiescent/
        ├── drive.nim         Drive model + hdparm/sysfs ops (encapsulated)
        └── config.nim        typed config parser
```

## Build

```bash
cd nim
nimble build            # -> ./quiescentd   (or: nim c -d:release src/quiescentd.nim)
```

## Configure & run

```bash
sudo cp quiescent.conf.example /etc/quiescent.conf   # then edit the by-id paths
sudo install -m0755 quiescentd /usr/local/bin/
sudo install -m0644 systemd/quiescentd.service /etc/systemd/system/
sudo systemctl enable --now quiescentd.service
journalctl -u quiescentd -f
```

It needs root (it calls `hdparm`). `hdparm -C` is used to read power state and is non-intrusive
(it neither wakes a drive nor resets its standby timer).

> **Note:** this is an *alternative* to the shell oneshots/watcher — run one or the other, not
> both against the same drives. The reference worlock deployment uses the shell version; this
> daemon is validated (it force-parks a real drive at the configured idle threshold) and ready
> to drop in.
