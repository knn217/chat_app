#!/usr/bin/env bash
# Add ONE CockroachDB node to the cluster, start to finish:
#   launch VM -> node certificate + deploy -> (cluster init, first node only)
#   -> wait until the node is part of the cluster -> add it to the load balancer
#
# Usage:
#   db-add-node.sh <index> --lb-ip IP --image IMG --package TGZ --db-dir DIR
#                  --certs-dir DIR [--known-ips ip1,ip2,...] [--lb-vm db-lb]
#                  [--sql-port 26257] [--http-port 8080] [--memory 2G]
#
#   <index>       1-based node number (VM db-node<index>, node name node<index>)
#   --known-ips   IPs of the nodes added before this one, in order (empty for node 1)
#   --certs-dir   directory with the root client certificate (init / verify)
#
# Only node 1 runs `cockroach init`. Every later node just starts with --join
# (all previous nodes + itself) and is pulled into the running cluster.
#
# stdout (KEY=VALUE, safe to append to $GITHUB_OUTPUT):
#   DB_NODE<i>_*            full VM handle (DB_NODE<i>_IP, ...)
#   db_node<i>_deploy_*     outputs of cockroach-node-deploy.sh
# stderr: logs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
set -Eeuo pipefail

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

IDX=""
LB_VM=db-lb
LB_IP=""
KNOWN=""
IMAGE=""
PACKAGE=""
DB_DIR=""
CERTS_DIR=""
SQL_PORT=26257
HTTP_PORT=8080
MEMORY=2G

while (($#)); do
  case "$1" in
    --lb-vm)     opt_val "$@"; LB_VM=$2;     shift 2 ;;
    --lb-ip)     opt_val "$@"; LB_IP=$2;     shift 2 ;;
    --known-ips) opt_val "$@"; KNOWN=$2;     shift 2 ;;
    --image)     opt_val "$@"; IMAGE=$2;     shift 2 ;;
    --package)   opt_val "$@"; PACKAGE=$2;   shift 2 ;;
    --db-dir)    opt_val "$@"; DB_DIR=$2;    shift 2 ;;
    --certs-dir) opt_val "$@"; CERTS_DIR=$2; shift 2 ;;
    --sql-port)  opt_val "$@"; SQL_PORT=$2;  shift 2 ;;
    --http-port) opt_val "$@"; HTTP_PORT=$2; shift 2 ;;
    --memory)    opt_val "$@"; MEMORY=$2;    shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          die "unknown option: $1" ;;
    *)           [[ -z "$IDX" ]] || die "unexpected argument: $1"; IDX=$1; shift ;;
  esac
done

[[ "$IDX" =~ ^[1-9][0-9]*$ ]] || { usage; die "<index> must be a positive integer"; }
for v in LB_IP IMAGE PACKAGE DB_DIR CERTS_DIR; do
  [[ -n "${!v}" ]] || die "missing required option for $v"
done
if ((IDX == 1)) && [[ -n "$KNOWN" ]]; then
  die "node 1 must not have --known-ips"
fi

VM="db-node$IDX"
NODE="node$IDX"
PFX="DB_NODE$IDX"

# 1. Launch the guest.
log "=== [$NODE] launching $VM ==="
out=$(bash "$SCRIPT_DIR/multipass-launch.sh" "$VM" --prefix "$PFX" \
  --cpus 1 --memory "$MEMORY" --disk 6G --timeout 900)
printf '%s\n' "$out"
IP=$(grep -m1 "^${PFX}_IP=" <<<"$out" | cut -d= -f2-)
[[ -n "$IP" ]] || die "no IP for $VM"

# Nodes in the cluster once this one is added, and this node's --join list.
all="${KNOWN:+$KNOWN,}$IP"
IFS=, read -ra ALL <<<"$all"
join=""
for ip in "${ALL[@]}"; do
  join+="${join:+,}$ip:$SQL_PORT"
done

# 2. Certificate + deploy.
log "=== [$NODE] deploying ($IP), --join=$join ==="
bash "$SCRIPT_DIR/cockroach-node-deploy.sh" \
  --vm "$VM" \
  --node "$NODE" \
  --ip "$IP" \
  --lb-ip "$LB_IP" \
  --join "$join" \
  --image "$IMAGE" \
  --package "$PACKAGE" \
  --db-dir "$DB_DIR" \
  --sql-port "$SQL_PORT" \
  --http-port "$HTTP_PORT" \
  --prefix "db_node${IDX}_deploy"

# 3. The very first node bootstraps the cluster.
if ((IDX == 1)); then
  log "=== [$NODE] initializing the cluster ==="
  bash "$SCRIPT_DIR/cockroach-init.sh" db-node1 \
    --ip "$IP" \
    --image "$IMAGE" \
    --certs-dir "$CERTS_DIR" \
    --port "$SQL_PORT" >&2
fi

# 4. Wait until the cluster lists every node added so far, this one included.
log "=== [$NODE] waiting until it has joined the cluster ==="
bash "$SCRIPT_DIR/cockroach-verify.sh" db-node1 \
  --image "$IMAGE" \
  --certs-dir "$CERTS_DIR" \
  --port "$SQL_PORT" \
  "${ALL[@]}" >&2

# 5. Put it behind the load balancer. The config is rendered again from all
#    nodes so far; HAProxy is only installed on the first run.
log "=== [$NODE] adding it to $LB_VM ==="
skip=()
((IDX == 1)) || skip=(--skip-install)
bash "$SCRIPT_DIR/haproxy-db-setup.sh" "$LB_VM" \
  --prefix db_lb \
  ${skip[@]+"${skip[@]}"} \
  "${ALL[@]}" >/dev/null

log "=== [$NODE] is in service ==="
