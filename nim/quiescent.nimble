# Package
version       = "0.1.0"
author        = "danindiana"
description   = "Encapsulated idle-disk spin-down daemon (Nim port of quiescent's watcher)"
license       = "MIT"
srcDir        = "src"
bin           = @["quiescentd", "quiescentctl", "quiescent_wear", "quiescent_mountd"]

# Dependencies
requires "nim >= 2.0.0"
