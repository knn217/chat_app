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

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
# Set WAIT_FOR_VERBOSE=1 to log every failed attempt's output.
WAIT_FOR_LAST_OUTPUT=""
wait_for() {
  local timeout=$1 interval=$2
  shift 2
  local deadline=$((SECONDS + timeout)) attempt=0
  WAIT_FOR_LAST_OUTPUT=""
  while true; do
    attempt=$((attempt + 1))
    if WAIT_FOR_LAST_OUTPUT=$("$@" 2>&1); then
      return 0
    fi
    if [[ -n "${WAIT_FOR_VERBOSE:-}" ]]; then
      [[ -z "$WAIT_FOR_LAST_OUTPUT" ]] || printf '%s\n' "$WAIT_FOR_LAST_OUTPUT" >&2
      log "attempt $attempt failed; retrying in ${interval}s"
    fi
    ((SECONDS < deadline)) || return 1
    sleep "$interval"
  done
}

# ---- CockroachDB helpers -------------------------------------------------

# Where the temporary root client certificates live inside the VM.
CRDB_REMOTE_CERTS=/tmp/crdb-client/root

# crdb_client_certs_push VM LOCAL_CERTS_DIR
crdb_client_certs_push() {
  bash "$LIB_DIR/multipass-send.sh" "$1" "$2" "$CRDB_REMOTE_CERTS"
}

# crdb_client_certs_drop VM   (never fails; safe in an EXIT trap)
crdb_client_certs_drop() {
  mp exec "$1" -- sudo rm -rf "$(dirname "$CRDB_REMOTE_CERTS")" >&2 || true
}

# crdb_cli VM IMAGE REMOTE_CERTS_DIR cockroach-args...
# Runs the cockroach CLI from the given image inside the VM, host networking.
crdb_cli() {
  local vm=$1 image=$2 certs=$3
  shift 3
  mp exec "$vm" -- sudo docker run --rm \
    --network host \
    -v "$certs:/cockroach/certs:ro" \
    "$image" "$@" --certs-dir=/cockroach/certs
}