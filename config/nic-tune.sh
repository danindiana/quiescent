#!/usr/bin/env bash
# Usage: nic-tune.sh <iface> [combined] [target_ring]
# Safe: never exits nonzero. Handles link-bounce only if ring change is needed.
set -u
IF="${1:?iface like enp3s0f0}"
Q="${2:-8}"
TARGET="${3:-4096}"

log() { echo "[nic-tune] $*"; }
round32() { local n="$1"; echo $(( n - (n % 32) )); }

# Ensure iface exists
if [[ ! -e "/sys/class/net/$IF" ]]; then
  log "iface $IF not present; skipping"
  exit 0
fi

# Ensure tools exist
if ! command -v ethtool >/dev/null 2>&1; then
  log "ethtool not in PATH"
  exit 0
fi
command -v ip >/dev/null 2>&1 || true

# 1) Queues (Combined)
if ethtool -l "$IF" >/dev/null 2>&1; then
  max=$(ethtool -l "$IF" 2>/dev/null | awk '/Pre-set maximums/{f=1;next} f&&/Combined:/ {print $2; exit}')
  cur=$(ethtool -l "$IF" 2>/dev/null | awk '/Current hardware settings/{f=1;next} f&&/Combined:/ {print $2; exit}')
  if [[ "${max:-0}" -gt 0 ]]; then
    want=$(( Q<=max ? Q : max ))
    if [[ "${cur:-0}" -ne "$want" ]]; then
      log "Setting $IF Combined queues: $cur -> $want (max $max)"
      ethtool -L "$IF" combined "$want" >/dev/null 2>&1 || log "queue change not supported now"
    fi
  fi
fi

# 2) Ring sizes (with conditional link bounce)
setring() {
  local rx="$1"; local tx="$1"
  ethtool -G "$IF" rx "$rx" tx "$tx" >/dev/null 2>&1 && return 0
  # try with link bounce if ip exists
  if command -v ip >/dev/null 2>&1; then
    log "Bouncing link on $IF to apply rings..."
    ip link set "$IF" down 2>/dev/null || true
    ethtool -G "$IF" rx "$rx" tx "$tx" >/dev/null 2>&1 || true
    ip link set "$IF" up 2>/dev/null || true
  fi
}

if ethtool -g "$IF" >/dev/null 2>&1; then
  # maxima
  rmax=$(ethtool -g "$IF" | awk '/Pre-set maximums/{f=1;next} /Current hardware settings/{f=0} f&&/^RX:/{rx=$2} f&&/^TX:/{tx=$2} END{print (rx<tx?rx:tx)+0}')
  # current
  rcur=$(ethtool -g "$IF" | awk '/Current hardware settings/{f=1;next} f&&/RX:/{print $2; exit}')
  if [[ "$rmax" -gt 0 ]]; then
    want=$(round32 $(( TARGET<rmax ? TARGET : rmax )))
    if [[ "${rcur:-0}" -lt "$want" || "${rcur:-0}" -gt "$want" ]]; then
      log "Setting $IF rings: $rcur -> $want (max $rmax)"
      setring "$want"
    fi
  fi
fi

# 3) Coalescing (only fields you support)
if ethtool -c "$IF" >/dev/null 2>&1; then
  ethtool -c "$IF" | grep -q '^rx-usecs:' && ethtool -C "$IF" rx-usecs 25 >/dev/null 2>&1 || true
  ethtool -c "$IF" | grep -q '^tx-usecs:' && ethtool -C "$IF" tx-usecs 25 >/dev/null 2>&1 || true
fi

# 4) Forwarding-safe offload (LRO off if on)
if ethtool -k "$IF" 2>/dev/null | grep -q '^large-receive-offload: on'; then
  ethtool -K "$IF" lro off >/dev/null 2>&1 || true
fi

log "done for $IF"
exit 0
