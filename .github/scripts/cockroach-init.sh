#!/usr/bin/env bash
# Initialize a CockroachDB cluster by running `cockroach init` from a node VM.
# Sends the root client certificates to the VM for the duration of the call
# and always removes them again (also on failure). Safe to re-run: an
# already-initialized cluster counts as success.
#
# Usage:
#   cockroach-init.sh <vm> --ip IP --image IMAGE --certs-dir DIR
#                          [--port 26257] [--timeout 300] [--prefix PFX]
#
#   <vm>         VM to run the CLI on (any node, e.g. db-node1)
#   --ip         address of the node to init against (that VM's IP)
#   --certs-dir  local root client cert directory (e.g. database/certs/root)
#
# stdout: PFX_INITIALIZED  PFX_INIT_HOST      (PFX defaults to CRDB)
# stderr: logs and CLI output.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

VM="" IP="" IMAGE="" CERTS=""
PORT=26257
TIMEOUT=300
PREFIX=""

while (($#)); do
  case "$1" in
    --ip)        opt_val "$@"; IP=$2;      shift 2 ;;
    --image)     opt_val "$@"; IMAGE=$2;   shift 2 ;;
    --certs-dir) opt_val "$@"; CERTS=$2;   shift 2 ;;
    --port)      opt_val "$@"; PORT=$2;    shift 2 ;;
    --timeout)   opt_val "$@"; TIMEOUT=$2; shift 2 ;;
    --prefix)    opt_val "$@"; PREFIX=$2;  shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          die "unknown option: $1" ;;
    *)           [[ -z "$VM" ]] || die "unexpected argument: $1"; VM=$1; shift ;;
  esac
done

for var in VM IP IMAGE CERTS; do
  [[ -n "${!var}" ]] || { usage; die "missing required value for $var"; }
done
[[ -d "$CERTS" ]] || die "client cert directory not found: $CERTS"
PFX=$(to_key "${PREFIX:-crdb}")

trap 'crdb_client_certs_drop "$VM"' EXIT
log "Sending temporary root client certificates to $VM"
crdb_client_certs_push "$VM" "$CERTS"

try_init() {
  local out
  if out=$(crdb_cli "$VM" "$IMAGE" "$CRDB_REMOTE_CERTS" init --host="$IP:$PORT" 2>&1); then
    printf '%s\n' "$out"
    return 0
  fi
  printf '%s\n' "$out"
  if grep -qi "cluster has already been initialized" <<<"$out"; then
    echo "Cluster is already initialized."
    return 0
  fi
  return 1
}

log "Initializing cluster via $IP:$PORT (up to ${TIMEOUT}s)..."
WAIT_FOR_VERBOSE=1 wait_for "$TIMEOUT" 5 try_init || die "cluster initialization failed"
printf '%s\n' "$WAIT_FOR_LAST_OUTPUT" >&2

emit "${PFX}_INITIALIZED" true
emit "${PFX}_INIT_HOST"   "$IP:$PORT"
