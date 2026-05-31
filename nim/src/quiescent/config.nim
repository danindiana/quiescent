## config.nim — parse /etc/quiescent.conf into a typed Config.
##
## Format (whitespace-separated; '#' comments and blank lines ignored):
##   interval <seconds>                      # poll cadence for watch-mode drives
##   <by-id path>  watch  <idle-seconds>     # force `hdparm -y` after idle
##   <by-id path>  timer  <hdparm -S value>  # arm the drive's own standby timer

import std/[strutils]
import drive

type
  Config* = object
    intervalSecs*: int
    drives*: seq[Drive]

  ConfigError* = object of CatchableError

proc parseMode(s: string): Mode =
  case s.toLowerAscii()
  of "watch": mWatch
  of "timer": mTimer
  else: raise newException(ConfigError, "unknown mode: " & s)

proc parseConfig*(text: string): Config =
  ## Pure parser (string in, Config out) — trivially unit-testable, no I/O.
  result.intervalSecs = 60
  var lineNo = 0
  for raw in text.splitLines:
    inc lineNo
    let line = raw.strip()
    if line.len == 0 or line.startsWith("#"): continue
    let f = line.splitWhitespace()
    if f[0].toLowerAscii() == "interval":
      if f.len < 2: raise newException(ConfigError, "line " & $lineNo & ": interval needs a value")
      result.intervalSecs = parseInt(f[1])
      continue
    if f.len < 3:
      raise newException(ConfigError, "line " & $lineNo & ": expected '<by-id> <mode> <value>'")
    result.drives.add Drive(byId: f[0], mode: parseMode(f[1]), value: parseInt(f[2]))

proc loadConfig*(path: string): Config =
  parseConfig(readFile(path))
