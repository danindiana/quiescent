## mountinfo.nim — pure parser for /proc/mounts.
##
## Used by mount-audit (Future Directions §7: find pure-read archive drives that could
## be mounted read-only to eliminate the shutdown spin-up) and by quiescent-metrics to
## map a mount point back to the owning kernel device. Pure: string in -> seq out,
## mirroring config.nim's `parseConfig`, so it is unit-testable without touching /proc.

import std/[strutils]

type
  MountEntry* = object
    dev*:        string  ## device node, e.g. "/dev/sde1"
    mountPoint*: string  ## e.g. "/mnt/hitachi_2tb"
    fsType*:     string  ## e.g. "ext4"
    readOnly*:   bool    ## true if the options field begins ro / contains a standalone "ro"

proc unescapeOctal(s: string): string =
  ## /proc/mounts escapes space/tab/newline/backslash as octal (e.g. "\040" for space).
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 3 < s.len and
       s[i+1] in {'0'..'7'} and s[i+2] in {'0'..'7'} and s[i+3] in {'0'..'7'}:
      result.add chr(((ord(s[i+1]) - ord('0')) shl 6) or
                     ((ord(s[i+2]) - ord('0')) shl 3) or
                      (ord(s[i+3]) - ord('0')))
      i += 4
    else:
      result.add s[i]
      inc i

proc parseMounts*(text: string): seq[MountEntry] =
  ## Parse the space-separated /proc/mounts format:
  ##   <dev> <mountpoint> <fstype> <options> <dump> <pass>
  ## ro/rw is taken from the comma-separated options field (field 4).
  for raw in text.splitLines:
    let line = raw.strip()
    if line.len == 0: continue
    let f = line.splitWhitespace()
    if f.len < 4: continue
    let opts = f[3].split(',')
    result.add MountEntry(
      dev:        unescapeOctal(f[0]),
      mountPoint: unescapeOctal(f[1]),
      fsType:     f[2],
      readOnly:   "ro" in opts)

proc mountsForDevice*(entries: seq[MountEntry]; kernelDev: string): seq[MountEntry] =
  ## All mount entries backed by partitions of one disk, e.g. kernelDev="sde" matches
  ## /dev/sde, /dev/sde1, /dev/sde2 ... (but not /dev/sdee). Empty kernelDev matches none.
  if kernelDev.len == 0: return
  let base = "/dev/" & kernelDev
  for e in entries:
    if e.dev == base or e.dev.startsWith(base) and
       (e.dev.len == base.len or e.dev[base.len] in {'0'..'9', 'p'}):
      result.add e
