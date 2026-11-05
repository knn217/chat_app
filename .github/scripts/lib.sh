#!/usr/bin/env bash
# Shared helpers for .github/scripts/*.sh. Source this file; do not execute it.
#
# Contract for every script that sources it:
#   stdout = machine-readable KEY=VALUE lines only (safe to append to $GITHUB_OUTPUT)
#   stderr = human-readable logs
#
# Environment:
#   MULTIPASS_SUDO=1   run multipass through sudo (needed on GitHub runners)

if [[ -n "${_CI_LIB_LOADED:-}" ]]; then
  return 0
fi
_CI_LIB_LOADED=1

set -Eeuo pipefail

# Default login user inside Multipass guests.
VM_USER=ubuntu

log() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Fail with a clear message when an option is missing its value.
# Usage inside an arg-parsing loop: opt_val "$@"
opt_val() { (($# >= 2)) || die "option $1 needs a value"; }

# multipass wrapper: sudo only when MULTIPASS_SUDO=1.
mp() {
  if [[ "${MULTIPASS_SUDO:-0}" == "1" ]]; then
    sudo multipass "$@"
  else
    multipass "$@"
  fi
}

# First IPv4 address of a running VM.
vm_ip() {
  mp exec "$1" -- hostname -I | awk '{print $1}'
}

# "db-node1" -> "DB_NODE1" (usable as a KEY prefix).
to_key() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_'
}

# Print one KEY=VALUE line. Whitespace in values becomes "_" so output
# stays safe for both `eval` and $GITHUB_OUTPUT.
emit() {
  local value="${2:-}"
  printf '%s=%s\n' "$1" "${value//[[:space:]]/_}"
}

# wait_for TIMEOUT_SEC INTERVAL_SEC command...
# Re-runs the command until it exits 0. Returns 1 on timeout.
# The last combined output is left in WAIT_FOR_LAST_OUTPUT.
WAIT_FOR_LAST_OUTPUT=""
wait_for() {
  local timeout=$1 interval=$2
  shift 2
  local deadline=$((SECONDS + timeout))
  WAIT_FOR_LAST_OUTPUT=""
  while true; do
    if WAIT_FOR_LAST_OUTPUT=$("$@" 2>&1); then
      return 0
    fi
    ((SECONDS < deadline)) || return 1
    sleep "$interval"
  done
}
