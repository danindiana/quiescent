## mount-audit — find managed drives that could be mounted read-only.
##
## Future Directions §7: a parked drive holding a *mounted read-write* filesystem is
## spun up at shutdown to flush its ext4 journal. A drive that is never written could be
## mounted read-only (a clean `ro` unmount writes nothing) for a zero-spin-up shutdown.
## This tool resolves each configured drive's by-id -> kernel name -> /proc/mounts entries
## and flags the rw-mounted ones as read-only candidates. Read-only; needs no root.
##
## Usage: mount-audit [/etc/quiescent.conf]

import std/[os, strutils]
import quiescent/[drive, config, mountinfo]

proc main() =
  let confPath = if paramCount() >= 1: paramStr(1) else: "/etc/quiescent.conf"
  var cfg: Config
  try:
    cfg = loadConfig(confPath)
  except CatchableError as e:
    quit("mount-audit: failed to load " & confPath & ": " & e.msg, 1)

  let mounts = parseMounts(readFile("/proc/mounts"))

  echo "drive (by-id)".alignLeft(46), "dev".alignLeft(8),
       "mountpoint".alignLeft(22), "mode".alignLeft(6), "recommendation"
  echo repeat('-', 100)

  for d in cfg.drives:
    let id = extractFilename(d.byId)
    if not d.present:
      echo id.alignLeft(46), "-".alignLeft(8), "(absent)".alignLeft(22),
           "-".alignLeft(6), "drive not attached"
      continue
    let dev = d.kernelName()
    let ms = mountsForDevice(mounts, dev)
    if ms.len == 0:
      echo id.alignLeft(46), dev.alignLeft(8), "(unmounted)".alignLeft(22),
           "-".alignLeft(6), "OK — never woken at shutdown"
      continue
    for m in ms:
      let mode = if m.readOnly: "ro" else: "rw"
      let rec =
        if m.readOnly: "OK — ro unmount writes nothing"
        else: "rw -> candidate for read-only (zero-spin-up) if pure-read archive"
      echo id.alignLeft(46), m.dev.extractFilename.alignLeft(8),
           m.mountPoint.alignLeft(22), mode.alignLeft(6), rec

when isMainModule:
  main()
