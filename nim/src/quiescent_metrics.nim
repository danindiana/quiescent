## quiescent-metrics — Prometheus textfile collector for the quiescent spin-down set.
##
## Future Directions §3 (park-ratio / power-state telemetry) + §7 (shutdown spin-up).
## Emits node_exporter/Netdata textfile-collector format on stdout:
##   quiescent_drive_present{drive=...}            0|1
##   quiescent_drive_power_state{drive=...}        0=unknown 1=active 2=standby 3=sleeping
##   quiescent_last_unmount_seconds{mount=...,drive=...}
##   quiescent_last_shutdown_spinup{mount=...,drive=...}   0|1
##
## power_state uses the non-intrusive `hdparm -C` check (drive.powerState) — it does NOT
## wake a parked drive or reset its idle timer (Lessons §4), so sampling is safe to run on
## a tight cadence. Run as root only if your hdparm needs it; the journal/mount reads do not.
##
## Usage: quiescent-metrics [/etc/quiescent.conf] > /var/lib/node_exporter/textfile/quiescent.prom

import std/[os, osproc, strutils, tables]
import quiescent/[drive, config, journal, mountinfo]

proc stateCode(ps: PowerState): int =
  case ps
  of psUnknown:  0
  of psActive:   1
  of psStandby:  2
  of psSleeping: 3

proc lbl(s: string): string =
  ## Escape a Prometheus label value (backslash, quote, newline).
  s.multiReplace(("\\", "\\\\"), ("\"", "\\\""), ("\n", "\\n"))

proc main() =
  let confPath = if paramCount() >= 1: paramStr(1) else: "/etc/quiescent.conf"
  var cfg: Config
  try:
    cfg = loadConfig(confPath)
  except CatchableError as e:
    quit("quiescent-metrics: failed to load " & confPath & ": " & e.msg, 1)

  # --- per-drive present + power state ---
  echo "# HELP quiescent_drive_present Whether the managed drive is currently attached."
  echo "# TYPE quiescent_drive_present gauge"
  echo "# HELP quiescent_drive_power_state Power state (0=unknown 1=active 2=standby 3=sleeping)."
  echo "# TYPE quiescent_drive_power_state gauge"
  for d in cfg.drives:
    let id = lbl(extractFilename(d.byId))
    let present = d.present
    echo "quiescent_drive_present{drive=\"", id, "\"} ", (if present: "1" else: "0")
    let code = if present: stateCode(d.powerState) else: 0
    echo "quiescent_drive_power_state{drive=\"", id, "\"} ", code

  # --- map mount point -> owning drive id (for labelling shutdown spin-up events) ---
  let mounts = parseMounts(readFile("/proc/mounts"))
  var mountToDrive = initTable[string, string]()
  for d in cfg.drives:
    if not d.present: continue
    for m in mountsForDevice(mounts, d.kernelName()):
      mountToDrive[m.mountPoint] = extractFilename(d.byId)

  # --- last shutdown's unmount durations (spin-up proxy) ---
  echo "# HELP quiescent_last_unmount_seconds Unmount duration at the last shutdown (standby->active proxy)."
  echo "# TYPE quiescent_last_unmount_seconds gauge"
  echo "# HELP quiescent_last_shutdown_spinup Whether the mount was spun up at the last shutdown."
  echo "# TYPE quiescent_last_shutdown_spinup gauge"
  let (jtext, jcode) = execCmdEx("journalctl -b -1 -o short-iso --no-pager")
  if jcode == 0:
    for e in parseUnmounts(jtext):
      # Only emit series for mounts backed by a managed drive — keeps cardinality bounded
      # (skips ephemeral docker/overlay/run unmounts) and keeps the collector on-topic.
      if not mountToDrive.hasKey(e.mount): continue
      let labels = "mount=\"" & lbl(e.mount) & "\",drive=\"" & lbl(mountToDrive[e.mount]) & "\""
      echo "quiescent_last_unmount_seconds{", labels, "} ", e.seconds
      echo "quiescent_last_shutdown_spinup{", labels, "} ", (if e.wokeUp: "1" else: "0")

when isMainModule:
  main()
