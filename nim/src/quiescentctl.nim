## quiescentctl — Command-line control and status utility for quiescent storage.
##
## Reads the active configuration to report power states of watched/timed drives,
## and provides administrative commands to remount drives or trigger manual standby.

import std/[os, osproc, strutils, terminal]
import quiescent/[drive, config]

const DefaultConf = "/etc/quiescent.conf"

proc printHelp() =
  echo """quiescentctl — Storage Power Control Utility

Usage:
  quiescentctl status [config_path]   Shows power state for all configured drives
  quiescentctl park <drive_by_id>     Immediately spins down the specified drive
  quiescentctl remount-ro <path>      Safely remounts a mountpoint to Read-Only
  quiescentctl remount-rw <path>      Safely remounts a mountpoint to Read-Write
"""

proc showStatus(confPath: string) =
  var cfg: Config
  try:
    cfg = loadConfig(confPath)
  except CatchableError as e:
    styledEcho fgRed, "Error: ", fgWhite, "failed to load config " & confPath & ": " & e.msg
    quit(1)

  styledEcho styleBright, fgCyan, "\n==================== QUIESCENT STORAGE STATUS ===================="
  styledEcho styleDim, "Config: " & confPath & " | Active drives: " & $cfg.drives.len & "\n"
  
  styledEcho styleBright, "  DRIVE NAME / BY-ID                           MODE    STATE"
  styledEcho styleDim, "  ----------------------------------------------------------"

  for d in cfg.drives:
    let name = extractFilename(d.byId)
    let modeStr = if d.mode == mWatch: "watch" else: "timer"
    
    if not d.present:
      styledEcho "  ", fgRed, name.alignLeft(44), fgWhite, modeStr.alignLeft(8), fgRed, "ABSENT"
      continue

    let state = d.powerState
    let stateStr = case state
      of psStandby: "STANDBY (Spun down)"
      of psSleeping: "SLEEPING (Spun down)"
      of psActive: "ACTIVE/IDLE"
      of psUnknown: "UNKNOWN"
    
    let stateColor = case state
      of psStandby, psSleeping: fgGreen
      of psActive: fgYellow
      of psUnknown: fgRed

    styledEcho "  ", fgCyan, name.alignLeft(44), fgWhite, modeStr.alignLeft(8), stateColor, stateStr

  styledEcho styleBright, fgCyan, "==================================================================\n"

proc parkDrive(driveId: string) =
  let d = Drive(byId: driveId, mode: mWatch)
  if not d.present:
    styledEcho fgRed, "Error: ", fgWhite, "Drive ID symlink does not exist: " & driveId
    quit(1)
  
  styledEcho fgYellow, "Sending ATA Standby (spindown) command to: " & extractFilename(driveId)
  d.forcePark()
  styledEcho fgGreen, "Park command sent."

proc remountPath(mountPoint: string, readOnly: bool) =
  let opt = if readOnly: "ro" else: "rw"
  styledEcho fgYellow, "Remounting " & mountPoint & " as " & opt & "..."
  let p = startProcess("mount", args = ["-o", "remount," & opt, mountPoint],
                       options = {poUsePath, poParentStreams})
  let code = p.waitForExit()
  if code == 0:
    styledEcho fgGreen, "Remount successful."
  else:
    styledEcho fgRed, "Failed to remount path (exit code: " & $code & ")."

proc main() =
  if paramCount() < 1:
    printHelp()
    quit(0)

  let cmd = paramStr(1)
  case cmd
  of "status":
    let path = if paramCount() >= 2: paramStr(2) else: DefaultConf
    showStatus(path)
  of "park":
    if paramCount() < 2:
      styledEcho fgRed, "Error: ", fgWhite, "Please specify a drive identifier (/dev/disk/by-id/...)"
      quit(1)
    parkDrive(paramStr(2))
  of "remount-ro":
    if paramCount() < 2:
      styledEcho fgRed, "Error: ", fgWhite, "Please specify a mountpoint path"
      quit(1)
    remountPath(paramStr(2), true)
  of "remount-rw":
    if paramCount() < 2:
      styledEcho fgRed, "Error: ", fgWhite, "Please specify a mountpoint path"
      quit(1)
    remountPath(paramStr(2), false)
  else:
    printHelp()

when isMainModule:
  main()
