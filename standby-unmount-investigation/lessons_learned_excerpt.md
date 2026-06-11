# 🧠 Lessons Learned: Graphify Indexing & Hosting
**Date:** June 7, 2026  
**Session:** Graphify Setup & Workspace Deployment  

---

## 1. Subprocess Resource Exhaustion & Segmentation Faults
### The Problem
When extracting a large codebase (38k+ files in `/home/jeb/programs/gemini_cli_workspace`), the parser spawned 32 workers (one per CPU core) which quickly exhausted system memory. Additionally, performing cross-file symbol resolution on tens of thousands of nodes exceeded C-level recursion stacks, causing the Python interpreter itself to crash with a segmentation fault (`sig=11` in `libpython3.13.so`).

### The Lesson
1. **Low-Concurrency Boundaries**: High core-count processors (32 threads) require artificial caps (`--max-workers 4`) when dealing with heavy AST resolution to prevent memory thrashing.
2. **Aggressive Ignorance is Bliss**: Huge dependency directories (like `ai-agent-architectures/` or `openclaw/ui/` with thousands of node/test files) must be proactively ignored via `.graphifyignore` to keep the symbol map small and prevent stack overflows.

---

## 2. `.graphifyignore` Pattern Architecture
### The Problem
Using recursive patterns like `**/*.png` failed to match recursively under Graphify's python-based `_is_ignored` implementation, because the underlying code uses a simple path component splitter with `fnmatch`. 

### The Lesson
Use flat wildcard patterns like `*.png` or `*.[pP][nN][gG]`. Since the ignore evaluator recursively splits path components and matches them individually, simple non-anchored wildcards naturally apply tree-wide, whereas prefixing `**/` breaks the matching logic.

---

## 3. Remote Neo4j Discovery Loopbacks
### The Problem
Exposing an existing local docker Neo4j container (`127.0.0.1:7474`) via `socat` to a remote LAN port (`7686`) resulted in a blank browser page. This occurred because Neo4j's internal API advertises database/transaction discovery endpoints hardcoded to loopback (`127.0.0.1`), causing the remote browser to attempt queries on its own local loopback instead of `worlock`.

### The Lesson
For remote graph sharing on the LAN:
1. Either configure Neo4j's advertised addresses (`dbms.connector.bolt.advertised_address` and `dbms.connector.http.advertised_address`) to the external LAN hostname/IP.
2. Or use Graphify's **standalone HTML visualization** (`graph.html`), which hosts the entire D3 interactive data payload in a single, zero-dependency HTML file, completely bypassing database-connection networking issues.

---

## 4. Spawning Independent Terminal Windows
### The Problem
Starting background processes with standard shell syntax (`cmd &`) inside the agent's runner environment causes them to receive a `SIGHUP` and terminate immediately when the main shell exits. `nohup` also fails on systemd-managed user slices that reap orphan processes.

### The Lesson
1. To run a persistent CLI command in the background, spawn it as a managed background task in the runner system (`run_command` asynchronously).
2. To spawn interactive graphical shells on the operator's desktop, use `xterm -hold -e /path/to/script &`. The `-hold` flag is crucial to prevent the window from closing instantly if the child process completes or hits an error.

---

## 5. Quiescent HDD Standby & System Shutdown Delays
### The Problem
During system shutdown, mechanical hard drives that were parked in standby (quiescent mode) were being woken up (spun up), causing the shutdown process to hang for 11–26 seconds while `udisks2` and filesystem unmount tasks blocked waiting for the disks to spin up.

### The Lesson
1. **Unmount Write Signature**: Ext4 filesystems mounted as read-write (`rw`) must update superblock metadata and flush their journal during unmount, which forces the kernel to spin up parked platters to perform physical writes.
2. **Read-Only Mitigation**: Mounting quiescent archive/backup drives as read-only (`ro,noatime,nofail`) in `/etc/fstab` completely avoids the unmount write signature, permitting clean unmounts without waking up standby mechanical disks, saving start/stop wear cycles, and eliminating shutdown delays.

