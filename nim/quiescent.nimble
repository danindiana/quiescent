# Package
version       = "0.2.0"
author        = "danindiana"
description   = "Encapsulated idle-disk spin-down daemon (Nim port of quiescent's watcher)"
license       = "MIT"
srcDir        = "src"
bin           = @["quiescentd", "quiescentctl", "quiescent_wear", "quiescent_mountd"]
# Hyphenated CLI names map to underscore module files (Nim identifiers can't contain '-').
namedBin["spinup_probe"]      = "spinup-probe"
namedBin["quiescent_metrics"] = "quiescent-metrics"
namedBin["mount_audit"]       = "mount-audit"

# Dependencies
requires "nim >= 2.0.0"

# Tasks
task test, "run unit tests for the pure parsers":
  exec "nim r --hints:off tests/test_config.nim"
  exec "nim r --hints:off tests/test_journal.nim"
  exec "nim r --hints:off tests/test_mountinfo.nim"
