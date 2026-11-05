#!/usr/bin/env bash
# Wait until every given node appears in `cockroach node status`.
# Sends the root client certificates to the VM for the duration of the call
# and always removes them again (also on failure).
#
# Usage:
#   cockroach-verify.sh <vm> --image IMAGE --certs-dir DIR
#                            [--port 26257] [--timeout 300] [--prefix PFX]
#                            <node-ip>...
#
#   <vm>         VM to run the CLI on (e.g. db-node1)
#   --certs-dir  local root client cert directory (e.g. database/certs/root)
#   <node-ip>... every node that must be registered; the first one is also
#                the node the status query is sent to
#
# stdout: PFX_NODES_VERIFIED   (PFX defaults to CRDB)
# stderr: logs and CLI output.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

VM="" IMAGE="" CERTS=""
PORT=26257
TIMEOUT=300
PREFIX=""
IPS=()

while (($#)); do
  case "$1" in
    --image)     opt_val "$@"; IMAGE=$2;   shift 2 ;;
    --certs-dir) opt_val "$@"; CERTS=$2;   shift 2 ;;
    --port)      opt_val "$@"; PORT=$2;    shift 2 ;;
    --timeout)   opt_val "$@"; TIMEOUT=$2; shift 2 ;;
    --prefix)    opt_val "$@"; PREFIX=$2;  shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          die "unknown option: $1" ;;
    *)
      if [[ -z "$VM" ]]; then VM=$1; else IPS+=("$1"); fi
      shift
      ;;
  esac
done

for var in VM IMAGE CERTS; do
  [[ -n "${!var}" ]] || { usage; die "missing required value for $var"; }
done
((${#IPS[@]} > 0)) || { usage; die "at least one node IP is required"; }
[[ -d "$CERTS" ]] || die "client cert directory not found: $CERTS"
PFX=$(to_key "${PREFIX:-crdb}")

trap 'crdb_client_certs_drop "$VM"' EXIT
log "Sending temporary root client certificates to $VM"
crdb_client_certs_push "$VM" "$CERTS"

try_verify() {
  local status ip pattern
  if ! status=$(crdb_cli "$VM" "$IMAGE" "$CRDB_REMOTE_CERTS" node status \
    --host="${IPS[0]}:$PORT" 2>&1); then
    printf '%s\n' "$status"
    return 1
  fi
  printf '%s\n' "$status"
  for ip in "${IPS[@]}"; do
    # Whole-address match, so 10.0.0.1:26257 does not match 110.0.0.1:26257.
    pattern="(^|[[:space:]])${ip//./\\.}:${PORT}([[:space:]]|\$)"
    if ! grep -Eq "$pattern" <<<"$status"; then
      echo "Not registered yet: $ip:$PORT"
      return 1
    fi
  done
}

log "Waiting for ${#IPS[@]} node(s) to register (up to ${TIMEOUT}s)..."
WAIT_FOR_VERBOSE=1 wait_for "$TIMEOUT" 5 try_verify \
  || die "cluster verification failed: expected ${#IPS[@]} node(s)"
printf '%s\n' "$WAIT_FOR_LAST_OUTPUT" >&2
log "All ${#IPS[@]} node(s) are registered in the cluster."

emit "${PFX}_NODES_VERIFIED" "${#IPS[@]}"
