## quiescentd — idle-disk spin-down daemon (Nim port of bin/idle-disk-park.sh).
##
## A single long-running process that holds each drive's idle state in memory
## (no /run state files): arms timer-mode drives once at startup, then polls
## watch-mode drives on a fixed cadence, forcing `hdparm -y` after the configured
## idle period. Run as root (it calls hdparm). Driven by quiescentd.service.

import std/[os, times]
import quiescent/[drive, config]

const DefaultConf = "/etc/quiescent.conf"

proc log(msg: string) =
  stdout.writeLine(now().format("HH:mm:ss") & "  " & msg)
  flushFile(stdout)

proc main() =
  let confPath = if paramCount() >= 1: paramStr(1) else: DefaultConf
  var cfg: Config
  try:
    cfg = loadConfig(confPath)
  except CatchableError as e:
    stderr.writeLine("quiescentd: failed to load " & confPath & ": " & e.msg)
    quit(1)

  log("quiescentd up — " & $cfg.drives.len & " drives, interval " & $cfg.intervalSecs & "s")

  # Arm the standby timer once for firmware that honors it.
  for d in cfg.drives:
    if d.mode == mTimer and d.present:
      d.armTimer()
      log("armed -S " & $d.value & " on " & d.byId)

  # Watch loop: force-park timer-ignoring drives after idle.
  while true:
    for d in cfg.drives.mitems:
      if d.mode == mWatch and d.poll():
        log("parked (idle " & $d.value & "s) " & d.byId)
    sleep(cfg.intervalSecs * 1000)

when isMainModule:
  main()
