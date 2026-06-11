## drive.nim — an encapsulated model of a managed disk and its spin-down policy.
##
## Only the `*`-exported symbols are visible to other modules; the idle-tracking
## fields (`lastIo`, `idleSince`, `haveSample`) are module-private, so the only way
## to advance a drive's state is through `poll`. That is the encapsulation the shell
## version lacks — there, the same state lived in `/run` files and shell globals.

import std/[os, osproc, strutils, times]

type
  PowerState* = enum
    psUnknown, psActive, psStandby, psSleeping

  Mode* = enum
    mWatch   ## force `hdparm -y` after `value` seconds of no block I/O (timer-ignoring drives)
    mTimer   ## arm `hdparm -S value` once at startup; the drive self-parks

  Drive* = object
    byId*:  string         ## /dev/disk/by-id/... — stable identity, survives letter drift
    mode*:  Mode
    value*: int            ## watch: idle seconds before forced park · timer: hdparm -S value
    # --- encapsulated idle-tracking state (unexported) ---
    lastIo:    string
    idleSince: Time
    haveSample: bool

proc parsePowerState(s: string): PowerState =
  let t = s.toLowerAscii()
  if   "standby" in t: psStandby
  elif "sleep"   in t: psSleeping
  elif "active" in t or "idle" in t: psActive
  else: psUnknown

proc blockDev(d: Drive): string =
  ## Resolve the by-id symlink to its (drift-prone) kernel name, e.g. "sdg". Private.
  if not symlinkExists(d.byId): return ""
  extractFilename(expandSymlink(d.byId))

proc present*(d: Drive): bool =
  ## Is the drive currently attached?
  symlinkExists(d.byId)

proc kernelName*(d: Drive): string =
  ## Exported wrapper over `blockDev` — resolve the by-id symlink to its (drift-prone)
  ## kernel name, e.g. "sdg". Returns "" if the drive is absent. Used by mount-audit
  ## and quiescent-metrics to correlate a managed drive with its /proc/mounts entries.
  d.blockDev()

proc powerState*(d: Drive): PowerState =
  ## `hdparm -C` — non-intrusive: does not wake the drive or reset its standby timer.
  let outp = execProcess("hdparm", args = ["-C", d.byId],
                          options = {poUsePath, poStdErrToStdOut})
  for line in outp.splitLines:
    if "drive state is:" in line:
      return parsePowerState(line.rsplit(":", 1)[^1])
  psUnknown

proc ioCounter(d: Drive): string =
  ## Completed read+write I/O ops (fields 1 & 5 of /sys/block/<dev>/stat). Private.
  let dev = d.blockDev()
  if dev.len == 0: return ""
  let p = "/sys/block/" & dev & "/stat"
  if not fileExists(p): return ""
  let f = readFile(p).splitWhitespace()
  if f.len < 5: return ""
  f[0] & "-" & f[4]

proc forcePark*(d: Drive) =
  ## Immediate standby — for drives whose firmware ignores the `-S` idle timer.
  discard execProcess("hdparm", args = ["-y", d.byId],
                      options = {poUsePath, poStdErrToStdOut})

proc armTimer*(d: Drive) =
  ## Arm the drive's own ATA standby timer once (for firmware that honors it).
  discard execProcess("hdparm", args = ["-S", $d.value, d.byId],
                      options = {poUsePath, poStdErrToStdOut})

proc poll*(d: var Drive): bool =
  ## One watch-mode tick. Returns true iff it parked the drive on this call.
  ## Holds the idle window entirely in memory — no on-disk state.
  if d.mode != mWatch or not d.present: return false
  case d.powerState
  of psStandby, psSleeping:
    d.haveSample = false              # already parked — reset the window, never wake it
    return false
  else: discard

  let io = d.ioCounter()
  if io.len == 0: return false
  let now = getTime()

  if d.haveSample and io == d.lastIo:
    if (now - d.idleSince).inSeconds >= d.value:
      d.forcePark()
      d.haveSample = false
      return true
  else:                                # first sighting or I/O moved → (re)open idle window
    d.lastIo = io
    d.idleSince = now
    d.haveSample = true
  false
