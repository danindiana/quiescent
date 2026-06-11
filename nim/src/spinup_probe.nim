## spinup-probe — did a parked drive get spun up at shutdown?
##
## Lessons Learned §7: the gap between systemd's `Unmounting /mnt/X...` and
## `Unmounted /mnt/X` is a standby->active spin-up proxy. This tool reads recent boots'
## journals (`journalctl -b -<i> -o short-iso`), parses them with quiescent/journal, and
## prints a per-boot table of unmount durations. Read-only; needs no root (a normal user
## in the `systemd-journal` group can read the journal).
##
## Usage: spinup-probe [--boots N] [--prefix /mnt/] [--all]
##   --boots N    how many recent boots to inspect (default 3; boot -1 .. -N)
##   --prefix P   only report mounts under P (default /mnt/; drops docker/overlay noise)
##   --all        report every mount (overrides --prefix)

import std/[os, osproc, strutils, sequtils]
import quiescent/journal

proc journalForBoot(i: int): string =
  ## `journalctl -b -i -o short-iso` for one boot. Returns "" on failure.
  let (outp, code) = execCmdEx("journalctl -b -" & $i & " -o short-iso --no-pager")
  if code != 0: return ""
  outp

proc main() =
  var boots = 3
  var prefix = "/mnt/"
  var all = false
  var i = 1
  while i <= paramCount():
    case paramStr(i)
    of "--boots":
      inc i
      if i > paramCount(): quit("--boots needs a value", 2)
      boots = parseInt(paramStr(i))
    of "--prefix":
      inc i
      if i > paramCount(): quit("--prefix needs a value", 2)
      prefix = paramStr(i)
    of "--all": all = true
    of "-h", "--help":
      echo "usage: spinup-probe [--boots N] [--prefix /mnt/] [--all]"
      return
    else: quit("unknown argument: " & paramStr(i), 2)
    inc i

  for b in 1 .. boots:
    let text = journalForBoot(b)
    if text.len == 0:
      echo "boot -", b, ": (no journal / unavailable)"
      continue
    var events = parseUnmounts(text)
    if not all:
      events = events.filterIt(it.mount.startsWith(prefix))
    echo "boot -", b, "  (", events.len, " unmount", (if events.len == 1: "" else: "s"), ")"
    if events.len == 0:
      echo "  (none under ", prefix, ")"
    for e in events:
      let flag = if e.wokeUp: "WOKE (spun up)" else: "already awake"
      echo "  ", align($e.seconds & "s", 5), "  ", flag, "  ", e.mount
    echo ""

when isMainModule:
  main()
