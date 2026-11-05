#!/usr/bin/env bash
# Launch one load balancer VM and N node VMs for a cluster.
#
# Usage:
#   multipass-cluster-launch.sh <name> --nodes N [--cpus 1] [--memory 2G]
#                               [--disk 6G] [--timeout 900] [--prefix PFX]
#
# VMs created (load balancer first, because node certificates often need its IP):
#   <name>-lb, <name>-node1 ... <name>-nodeN
#
# stdout (PFX defaults to the upper-cased <name>, e.g. db -> DB):
#   PFX_LB_*        full handle of the load balancer VM (PFX_LB_IP, ...)
#   PFX_NODE<i>_*   full handle of node i (PFX_NODE1_IP, ...)
#   PFX_NODE_IPS    comma-separated node IPs, in node order
#   PFX_NODE_COUNT  N
# stderr: logs.
#
# Example:
#   bash multipass-cluster-launch.sh db --nodes 3 >> "$GITHUB_OUTPUT"
#   bash multipass-cluster-launch.sh be --nodes 1 --memory 1G >> "$GITHUB_OUTPUT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

NAME=""
NODES=""
CPUS=1
MEMORY=2G
DISK=6G
TIMEOUT=900
PREFIX=""

while (($#)); do
  case "$1" in
    --nodes)   opt_val "$@"; NODES=$2;   shift 2 ;;
    --cpus)    opt_val "$@"; CPUS=$2;    shift 2 ;;
    --memory)  opt_val "$@"; MEMORY=$2;  shift 2 ;;
    --disk)    opt_val "$@"; DISK=$2;    shift 2 ;;
    --timeout) opt_val "$@"; TIMEOUT=$2; shift 2 ;;
    --prefix)  opt_val "$@"; PREFIX=$2;  shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)        die "unknown option: $1" ;;
    *)         [[ -z "$NAME" ]] || die "unexpected argument: $1"; NAME=$1; shift ;;
  esac
done

[[ -n "$NAME" ]] || { usage; exit 2; }
[[ "$NODES" =~ ^[1-9][0-9]*$ ]] || die "--nodes must be a positive integer, got: '${NODES}'"
PFX=$(to_key "${PREFIX:-$NAME}")

# value_of "<KEY=VALUE lines>" KEY
value_of() { grep -m1 "^$2=" <<<"$1" | cut -d= -f2-; }

launch() { # launch VM_NAME KEY_PREFIX  -> echoes the handle, returns the IP in $LAST_IP
  local out
  out=$(bash "$SCRIPT_DIR/multipass-launch.sh" "$1" --prefix "$2" \
    --cpus "$CPUS" --memory "$MEMORY" --disk "$DISK" --timeout "$TIMEOUT")
  LAST_IP=$(value_of "$out" "${2}_IP")
  [[ -n "$LAST_IP" ]] || die "no IP for $1"
  printf '%s\n' "$out"
}

LAST_IP=""
launch "$NAME-lb" "${PFX}_LB"

ips=()
for i in $(seq 1 "$NODES"); do
  launch "$NAME-node$i" "${PFX}_NODE$i"
  ips+=("$LAST_IP")
done

emit "${PFX}_NODE_IPS"   "$(IFS=,; echo "${ips[*]}")"
emit "${PFX}_NODE_COUNT" "$NODES"
