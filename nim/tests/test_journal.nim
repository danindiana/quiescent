## Unit tests for quiescent/journal.parseUnmounts — pure, no journalctl needed.

import std/unittest
import ../src/quiescent/journal

const Sample = """
2026-06-11T07:19:28-0500 worlock systemd[1]: Unmounting /mnt/hitachi_2tb...
2026-06-11T07:19:28-0500 worlock systemd[1]: Unmounting /mnt/sda1...
2026-06-11T07:19:33-0500 worlock systemd[1]: Unmounted /mnt/sda1.
2026-06-11T07:19:39-0500 worlock systemd[1]: Unmounted /mnt/hitachi_2tb.
2026-06-11T07:19:54-0500 worlock systemd[1]: Unmounting /mnt/raid0...
2026-06-11T07:19:54-0500 worlock systemd[1]: Unmounted /mnt/raid0.
"""

suite "journal.parseUnmounts":
  let events = parseUnmounts(Sample)

  test "pairs every Unmounting with its Unmounted":
    check events.len == 3

  test "computes the 11s hitachi spin-up and flags it woke":
    var found = false
    for e in events:
      if e.mount == "/mnt/hitachi_2tb":
        found = true
        check e.seconds == 11
        check e.wokeUp
    check found

  test "a 5s unmount meets the default wake threshold":
    for e in events:
      if e.mount == "/mnt/sda1":
        check e.seconds == 5
        check e.wokeUp

  test "an instant (0s) unmount is 'already awake'":
    for e in events:
      if e.mount == "/mnt/raid0":
        check e.seconds == 0
        check not e.wokeUp

  test "custom threshold reclassifies the 5s unmount":
    for e in parseUnmounts(Sample, wakeThresholdSecs = 8):
      if e.mount == "/mnt/sda1":
        check not e.wokeUp

  test "midnight rollover is handled via full ISO date":
    const NightSample = """
2026-06-10T23:59:58-0500 worlock systemd[1]: Unmounting /mnt/x...
2026-06-11T00:00:04-0500 worlock systemd[1]: Unmounted /mnt/x.
"""
    let ev = parseUnmounts(NightSample)
    check ev.len == 1
    check ev[0].seconds == 6
    check ev[0].wokeUp

  test "an unpaired Unmounting is dropped":
    const Orphan = "2026-06-11T07:19:28-0500 h systemd[1]: Unmounting /mnt/lonely...\n"
    check parseUnmounts(Orphan).len == 0
