## quiescent_mountd — Remount-on-Demand automation helper and wrapper.
##
## Provides two modes:
## 1. CLI Wrapper: mount -o remount,rw -> run command -> sync -> mount -o remount,ro
## 2. Unix Socket Listener: runs in background and handles remote mount/unmount triggers.

import std/[os, osproc, strutils, terminal, net]

const SocketPath = "/run/quiescent_mountd.sock"

proc printHelp() =
  echo """quiescent_mountd — Remount-on-Demand automation helper

Usage:
  quiescent_mountd run -m <mountpoint> -c "<command>"
      Executes a command inside a read-write window:
      1. Remounts target mountpoint as read-write (rw)
      2. Executes specified command
      3. Flushes disk caches (sync)
      4. Remounts target mountpoint back to read-only (ro)

  quiescent_mountd listen
      Runs as a background daemon, listening on Unix socket:
      /run/quiescent_mountd.sock for commands:
        "rw <mountpoint>"
        "ro <mountpoint>"
"""

proc remount(mountPoint: string, readOnly: bool): bool =
  let opt = if readOnly: "ro" else: "rw"
  let p = startProcess("mount", args = ["-o", "remount," & opt, mountPoint],
                       options = {poUsePath})
  return p.waitForExit() == 0

proc runWrapper(mountPoint: string, command: string) =
  if mountPoint.len == 0 or command.len == 0:
    styledEcho fgRed, "Error: ", fgWhite, "Both mountpoint (-m) and command (-c) must be specified."
    quit(1)

  styledEcho fgYellow, "Preparing Write Window for: " & mountPoint
  
  if not remount(mountPoint, false):
    styledEcho fgRed, "Aborting: Failed to remount " & mountPoint & " as read-write."
    quit(1)

  styledEcho fgGreen, "Mount is Read-Write. Executing command: " & command
  
  let exitCode = execCmd(command)
  styledEcho fgYellow, "Command completed with exit code: " & $exitCode
  
  styledEcho fgYellow, "Flushing filesystem cache (sync)..."
  discard execCmd("sync")

  styledEcho fgYellow, "Closing Write Window. Remounting Read-Only..."
  if remount(mountPoint, true):
    styledEcho fgGreen, "Write window closed. Partition is safely Read-Only."
  else:
    styledEcho fgRed, "CRITICAL: Failed to remount " & mountPoint & " as read-only!"
    quit(1)

proc handleSocketConnection(client: Socket) =
  try:
    var rawLine = ""
    client.readLine(rawLine)
    let line = rawLine.strip()
    let parts = line.splitWhitespace()
    if parts.len < 2:
      client.send("ERROR: expected '<ro|rw> <mountpoint>'\n")
      return

    let cmd = parts[0].toLowerAscii()
    let mountPoint = parts[1]

    case cmd
    of "rw":
      if remount(mountPoint, false):
        client.send("OK: remounted rw\n")
      else:
        client.send("ERROR: remount rw failed\n")
    of "ro":
      discard execCmd("sync")
      if remount(mountPoint, true):
        client.send("OK: remounted ro\n")
      else:
        client.send("ERROR: remount ro failed\n")
    else:
      client.send("ERROR: unknown command\n")
  except CatchableError as e:
    discard
  finally:
    client.close()

proc runListener() =
  # Clean up existing socket if present
  if fileExists(SocketPath):
    try:
      removeFile(SocketPath)
    except CatchableError:
      styledEcho fgRed, "Error: ", fgWhite, "Socket file " & SocketPath & " is busy or cannot be removed."
      quit(1)

  var server = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
  try:
    server.bindUnix(SocketPath)
    server.listen()
  except CatchableError as e:
    styledEcho fgRed, "Error: ", fgWhite, "Failed to bind to socket " & SocketPath & ": " & e.msg
    quit(1)

  styledEcho fgGreen, "quiescent_mountd listening on Unix socket: " & SocketPath

  while true:
    var client: Socket
    new(client)
    try:
      server.accept(client)
      handleSocketConnection(client)
    except CatchableError:
      continue

proc main() =
  if paramCount() < 1:
    printHelp()
    quit(0)

  let mode = paramStr(1)
  case mode
  of "run":
    var mountPoint = ""
    var command = ""
    var i = 2
    while i <= paramCount():
      let arg = paramStr(i)
      if arg == "-m" and i + 1 <= paramCount():
        mountPoint = paramStr(i + 1)
        inc i
      elif arg == "-c" and i + 1 <= paramCount():
        command = paramStr(i + 1)
        inc i
      inc i
    runWrapper(mountPoint, command)
  of "listen":
    runListener()
  else:
    printHelp()

when isMainModule:
  main()
