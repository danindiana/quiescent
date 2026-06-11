# Contributing to quiescent

Thanks for your interest. quiescent is a small, focused project — idle-disk spin-down by stable
device identity, plus a typed Nim suite around it. A few notes keep changes safe and consistent.

## Golden rule: pin to identity, not position

Never reference a drive by `/dev/sdX` or a NIC by `enpXsY`. PCIe renumbering (a GPU swap, a card
added, a BIOS reorder) silently moves the same hardware to a different kernel name. Always use
`/dev/disk/by-id/*` (or `UUID` in fstab, MAC for NICs). This is the lesson the whole project was
born from — see [`LESSONS_LEARNED.md`](LESSONS_LEARNED.md) §1.

## Two implementations

- **Shell** (`bin/`, `systemd/`) is the **reference deployment** on worlock.
- **Nim** (`nim/`) is a typed, encapsulated reimplementation plus companion CLIs.

Run one or the other against a given drive set, not both.

## Building & testing the Nim suite

Requires Nim ≥ 2.0.0 and `nimble`.

```bash
cd nim
nimble build      # compiles every binary (daemon, ctl, wear, mountd, and the read-only trio)
nimble test       # pure-parser unit tests: config, journal, mountinfo
```

The pure parsers (`parseConfig`, `parseUnmounts`, `parseMounts`) take a string and return a typed
value with no I/O — keep them that way so they stay trivially testable. New parsing logic should
come with a test in `nim/tests/`. CI runs `nimble build` + `nimble test` on every push.

## Style

- `.editorconfig` covers whitespace/indentation (2-space Nim, tab shell, LF, final newline).
- Match the surrounding code's naming and comment density. Comments explain *why*, not *what*.
- Hardware claims (temperatures, firmware quirks, cycle counts) should be measured, not assumed —
  cite how you verified.

## Commits & PRs

- Keep commits logically scoped with a clear subject line.
- For behavior changes, note the verification you ran (build, tests, a live read-only check).
