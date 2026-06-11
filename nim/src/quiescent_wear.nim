## quiescent-wear — Spindown diagnostic and mechanical wear calculator.
##
## Queries SMART parameters safely, ensuring it does not spin up sleeping drives
## unless the --force option is passed.

import std/[os, osproc, strutils, terminal]
import quiescent/[drive, config]

const DefaultConf = "/etc/quiescent.conf"

type
  SmartStats = object
    model: string
    serial: string
    poh: int
    pc: int
    ss: int
    lc: int
    temp: int

proc printHelp() =
  echo """quiescent-wear — Spindown Diagnostic & Wear Calculator

Usage:
  quiescent-wear [options] [config_path]

Options:
  --force     Force query of drives even if currently spun down (will trigger spin-up)
  --help      Show this help text
"""

proc parseSmart(drivePath: string, force: bool): (bool, SmartStats) =
  var stats: SmartStats
  let d = Drive(byId: drivePath, mode: mWatch)
  
  if not d.present:
    return (false, stats)
    
  let state = d.powerState
  if not force and state in {psStandby, psSleeping}:
    # Skip to avoid waking the drive
    return (false, stats)

  let outp = execProcess("smartctl", args = ["-a", drivePath],
                          options = {poUsePath, poStdErrToStdOut})
  
  for rawLine in outp.splitLines:
    let line = rawLine.strip()
    if line.startsWith("Device Model:") or line.startsWith("Device:") or line.startsWith("Model Number:"):
      stats.model = line.split(":", 1)[1].strip()
    elif line.startsWith("Serial Number:"):
      stats.serial = line.split(":", 1)[1].strip()
    
    # Parse attributes
    let f = line.splitWhitespace()
    if f.len >= 10:
      let attrId = f[0]
      let val = f[9]
      try:
        case attrId
        of "4":   stats.ss = parseInt(val)
        of "9":   stats.poh = parseInt(val)
        of "12":  stats.pc = parseInt(val)
        of "193": stats.lc = parseInt(val)
        of "194": stats.temp = parseInt(val)
        else: discard
      except ValueError:
        discard

  return (true, stats)

proc runDiagnostics(confPath: string, force: bool) =
  var cfg: Config
  try:
    cfg = loadConfig(confPath)
  except CatchableError as e:
    styledEcho fgRed, "Error: ", fgWhite, "failed to load config " & confPath & ": " & e.msg
    quit(1)

  styledEcho styleBright, fgMagenta, "\n==================== STANDBY WEAR DIAGNOSTICS ===================="
  styledEcho styleDim, "Config: " & confPath
  if force:
    styledEcho fgYellow, "WARNING: Running with --force. Standby disks WILL be spun up!"
  else:
    styledEcho styleDim, "Note: Standby disks will be skipped to prevent spin-up. Run with --force to query them."
  echo ""

  for d in cfg.drives:
    let name = extractFilename(d.byId)
    if not d.present:
      continue

    let (polled, stats) = parseSmart(d.byId, force)
    if not polled:
      styledEcho fgCyan, name, ": ", fgYellow, "SKIPPED (Drive is in Standby/Sleep)"
      continue

    styledEcho fgCyan, name, " (", stats.model, " / ", stats.serial, "):"
    echo "  Power-On Hours (POH):      " & $stats.poh & " hrs"
    echo "  Power Cycles (System):     " & $stats.pc
    echo "  Platter Start/Stops (SS):  " & $stats.ss
    if stats.lc > 0:
      echo "  Head Load/Unloads (LC):    " & $stats.lc
    if stats.temp > 0:
      echo "  Temperature:               " & $stats.temp & "°C"

    if stats.pc > 0:
      let ratio = stats.ss.float / stats.pc.float
      let wearPercent = if stats.ss > 0: (ratio - 1.0) * 100.0 else: 0.0
      stdout.write "  Spin-up to Boot Ratio:     "
      if ratio > 15.0:
        styledEcho fgRed, styleBright, formatFloat(ratio, ffDecimal, 2) & " (CRITICAL WEAR)"
        styledEcho fgRed, "    [!] Warning: High wear fatigue. Aggressive spindown script has generated "
        styledEcho fgRed, "        " & $int(stats.ss - stats.pc) & " additional start/stop cycles."
      elif ratio > 5.0:
        styledEcho fgYellow, styleBright, formatFloat(ratio, ffDecimal, 2) & " (Moderate Spindown Wear)"
      else:
        styledEcho fgGreen, formatFloat(ratio, ffDecimal, 2) & " (Healthy / Low Spindown)"
    echo ""
  
  styledEcho styleBright, fgMagenta, "==================================================================\n"

proc main() =
  var force = false
  var confPath = DefaultConf

  for i in 1..paramCount():
    let p = paramStr(i)
    if p == "--force":
      force = true
    elif p == "--help" or p == "-h":
      printHelp()
      quit(0)
    else:
      confPath = p

  runDiagnostics(confPath, force)

when isMainModule:
  main()
