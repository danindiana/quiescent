## Unit tests for quiescent/config.parseConfig — the original pure string->Config parser.

import std/[unittest, strutils]
import ../src/quiescent/[config, drive]

suite "config.parseConfig":
  test "interval defaults to 60 when unspecified":
    let cfg = parseConfig("# only a comment\n")
    check cfg.intervalSecs == 60
    check cfg.drives.len == 0

  test "interval override is honored":
    check parseConfig("interval 120\n").intervalSecs == 120

  test "comments and blank lines are skipped":
    let cfg = parseConfig("""
# header

interval 30
   # indented comment

/dev/disk/by-id/ata-X  timer  12
""")
    check cfg.intervalSecs == 30
    check cfg.drives.len == 1

  test "a timer-mode drive row parses into typed fields":
    let cfg = parseConfig("/dev/disk/by-id/ata-Hitachi_X  timer  12\n")
    check cfg.drives.len == 1
    let d = cfg.drives[0]
    check d.byId == "/dev/disk/by-id/ata-Hitachi_X"
    check d.mode == mTimer
    check d.value == 12

  test "a watch-mode drive row parses with its idle threshold":
    let d = parseConfig("/dev/disk/by-id/ata-WD_X  watch  300\n").drives[0]
    check d.mode == mWatch
    check d.value == 300

  test "mode is case-insensitive":
    check parseConfig("/dev/disk/by-id/x  TIMER  12\n").drives[0].mode == mTimer

  test "multiple drives accumulate in order":
    let cfg = parseConfig("""
/dev/disk/by-id/a  timer  12
/dev/disk/by-id/b  watch  300
""")
    check cfg.drives.len == 2
    check cfg.drives[0].byId.endsWith("a")
    check cfg.drives[1].mode == mWatch

  test "an unknown mode raises ConfigError":
    expect ConfigError:
      discard parseConfig("/dev/disk/by-id/x  sometimes  5\n")

  test "a short drive row (missing value) raises ConfigError":
    expect ConfigError:
      discard parseConfig("/dev/disk/by-id/x  timer\n")

  test "interval without a value raises ConfigError":
    expect ConfigError:
      discard parseConfig("interval\n")
