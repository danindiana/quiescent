## journal.nim — pure parser for systemd unmount durations from journald output.
##
## Lessons Learned §7: the gap between `Unmounting /mnt/X...` and `Unmounted /mnt/X`
## is a reliable standby->active spin-up proxy. A parked disk holding a mounted RW
## filesystem must spin up to flush its ext4 journal at shutdown; a long unmount means
## it was asleep and woke, a ~0s unmount means it was already spinning.
##
## This module is pure (string in -> seq[UnmountEvent] out), mirroring config.nim's
## `parseConfig` — no journalctl invocation here, so it is trivially unit-testable.
## The binary (`spinup-probe`) supplies the text; feed it `journalctl -o short-iso`.

import std/[strutils, times, tables]

type
  UnmountEvent* = object
    mount*:   string   ## the mount point, e.g. "/mnt/hitachi_2tb"
    seconds*: int      ## wall-clock gap between Unmounting and Unmounted
    wokeUp*:  bool     ## seconds >= wakeThresholdSecs (likely a standby->active spin-up)

const IsoFmt = "yyyy-MM-dd'T'HH:mm:sszzz"  ## journald `-o short-iso` timestamp format

proc normalizeOffset(stamp: string): string =
  ## journald `-o short-iso` writes the UTC offset without a colon ("-0500"), but Nim's
  ## `zzz` specifier wants "-05:00". Insert the colon so `parse` accepts it.
  if stamp.len >= 5:
    let tail = stamp[^5 .. ^1]
    if tail[0] in {'+', '-'} and tail[1].isDigit and tail[2].isDigit and
       tail[3].isDigit and tail[4].isDigit:
      return stamp[0 .. ^3] & ":" & stamp[^2 .. ^1]
  stamp

proc parseIso(stamp: string): DateTime =
  ## Parse a leading `short-iso` timestamp token, e.g. "2026-06-11T07:19:28-0500".
  normalizeOffset(stamp).parse(IsoFmt)

proc extractMount(line, marker: string): string =
  ## Pull the mount path that follows `marker` on a systemd unmount line, trimming the
  ## trailing "..." (Unmounting) or "." (Unmounted). Returns "" if the marker is absent.
  let idx = line.find(marker)
  if idx < 0: return ""
  var rest = line[idx + marker.len .. ^1].strip()
  rest.removeSuffix("...")
  rest.removeSuffix(".")
  rest.strip()

proc parseUnmounts*(text: string; wakeThresholdSecs = 5): seq[UnmountEvent] =
  ## Pair `Unmounting <path>...` with the later `Unmounted <path>` and report the gap.
  ## Uses full ISO timestamps, so it is correct across a midnight boundary. Lines that
  ## never pair (an Unmounting with no matching Unmounted, or vice-versa) are dropped.
  const StartMark = "Unmounting "
  const EndMark   = "Unmounted "
  var started = initOrderedTable[string, DateTime]()  # mount -> Unmounting time
  for raw in text.splitLines:
    let line = raw.strip()
    if line.len == 0: continue
    # The first whitespace-delimited token of `-o short-iso` is the timestamp.
    let sp = line.find(' ')
    if sp <= 0: continue
    let ts =
      try: parseIso(line[0 ..< sp])
      except TimeParseError, ValueError: continue

    if StartMark in line:
      let m = extractMount(line, StartMark)
      if m.len > 0 and m.startsWith("/"): started[m] = ts
    elif EndMark in line:
      let m = extractMount(line, EndMark)
      if m.len > 0 and started.hasKey(m):
        let secs = max(0, (ts - started[m]).inSeconds.int)
        result.add UnmountEvent(mount: m, seconds: secs,
                                wokeUp: secs >= wakeThresholdSecs)
        started.del(m)
