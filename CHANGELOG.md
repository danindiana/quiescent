# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the Nim suite versions
track `nim/quiescent.nimble`.

## [Unreleased]

## [0.2.0]
### Added
- Read-only investigative trio in the Nim suite, sharing the existing `Drive` / `PowerState` /
  `byId` model:
  - `spinup-probe` — parse journald unmount durations to detect which mounts were spun up at
    shutdown (unmount duration = standby→active proxy).
  - `quiescent-metrics` — Prometheus/Netdata textfile collector for power state and last-shutdown
    spin-up (series restricted to managed drives for bounded cardinality).
  - `mount-audit` — flag rw-mounted managed drives as read-only candidates for a zero-spin-up
    shutdown.
- Pure, unit-tested parser modules `quiescent/journal.nim` and `quiescent/mountinfo.nim`, plus
  `tests/test_config.nim` completing parser coverage.
- Control/automation tools `quiescentctl`, `quiescent_wear`, and `quiescent_mountd`.
- GitHub Actions CI (`nimble build` + `nimble test`), `CONTRIBUTING.md`, `.editorconfig`, root
  `.gitignore`, and this changelog.

### Documentation
- `LESSONS_LEARNED.md` §7 and `FUTURE_DIRECTIONS.md` §7: a parked drive holding a *mounted
  read-write* filesystem is spun up at shutdown for the ext4 journal-flush / dirty-flag unmount
  write — necessary, unmounted drives exempt, read-only mounts avoid it.

## [0.1.0]
### Added
- Initial release: shell spin-down system (`bin/idle-disk-park.sh` + systemd oneshots/timer) that
  parks idle HDDs by stable `by-id` name, cutting worlock's drive-cage heat from ~40–53 °C to
  ~33–43 °C, with handling for three drive firmware classes (honors `-S`, ignores `-S` but obeys
  `-y`, and always-on RAID0).
- Nim daemon `quiescentd`: typed `Drive` / `PowerState` / `Mode`, in-memory idle tracking, and a
  pure config parser driven by `/etc/quiescent.conf`.
