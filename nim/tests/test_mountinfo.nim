## Unit tests for quiescent/mountinfo — pure /proc/mounts parser.

import std/unittest
import ../src/quiescent/mountinfo

const Sample = """
/dev/nvme2n1p1 / ext4 rw,relatime 0 0
/dev/sde1 /mnt/hitachi_2tb ext4 rw,noatime 0 0
/dev/sdc1 /mnt/sda1 ext4 ro,noatime 0 0
/dev/md0 /mnt/raid0 ext4 rw,noatime 0 0
/dev/sda1 /mnt/with\040space ext4 rw 0 0
"""

suite "mountinfo.parseMounts":
  let entries = parseMounts(Sample)

  test "parses every line":
    check entries.len == 5

  test "reads rw vs ro from the options field":
    for e in entries:
      if e.mountPoint == "/mnt/hitachi_2tb": check not e.readOnly
      if e.mountPoint == "/mnt/sda1":        check e.readOnly

  test "unescapes octal in the mount point":
    var found = false
    for e in entries:
      if e.dev == "/dev/sda1":
        found = true
        check e.mountPoint == "/mnt/with space"
    check found

suite "mountinfo.mountsForDevice":
  let entries = parseMounts(Sample)

  test "matches a disk's partitions by kernel name":
    let m = mountsForDevice(entries, "sde")
    check m.len == 1
    check m[0].mountPoint == "/mnt/hitachi_2tb"

  test "does not match an unrelated similarly-prefixed device":
    # "sda" must not match "/dev/sde1"; only /dev/sda*
    let m = mountsForDevice(entries, "sda")
    check m.len == 1
    check m[0].dev == "/dev/sda1"

  test "empty kernel name matches nothing":
    check mountsForDevice(entries, "").len == 0

  test "nvme p-partition naming matches":
    let m = mountsForDevice(entries, "nvme2n1")
    check m.len == 1
    check m[0].mountPoint == "/"
