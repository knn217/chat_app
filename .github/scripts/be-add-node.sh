#!/usr/bin/env bash
# Add ONE backend node to the cluster, start to finish:
#   launch VM -> deploy image + database client certs -> wait until healthy
#   -> add it to the load balancer
#
# Usage:
#   be-add-node.sh <index> --db-host IP --db-port N --image-tar FILE
#                  --certs-dir DIR --port N --health-path P
#                  [--known-ips ip1,ip2,...] [--lb-vm be-lb] [--memory 1G]
#
#   <index>       1-based node number (VM be-node<index>)
#   --known-ips   IPs of the nodes added before this one, in order (empty for node 1)
#
# Backend nodes do not know about each other, so there is no join step.
#
# stdout (KEY=VALUE, safe to append to $GITHUB_OUTPUT):
#   BE_NODE<i>_*            full VM handle (BE_NODE<i>_IP, ...)
#   be_node<i>_deploy_*     outputs of be-node-deploy.sh
# stderr: logs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
set -Eeuo pipefail

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

IDX=""
LB_VM=be-lb
KNOWN=""
DB_HOST=""
DB_PORT=""
IMAGE_TAR=""
CERTS_DIR=""
PORT=""
HEALTH_PATH=""
MEMORY=1G

while (($#)); do
  case "$1" in
    --lb-vm)       opt_val "$@"; LB_VM=$2;       shift 2 ;;
    --known-ips)   opt_val "$@"; KNOWN=$2;       shift 2 ;;
    --db-host)     opt_val "$@"; DB_HOST=$2;     shift 2 ;;
    --db-port)     opt_val "$@"; DB_PORT=$2;     shift 2 ;;
    --image-tar)   opt_val "$@"; IMAGE_TAR=$2;   shift 2 ;;
    --certs-dir)   opt_val "$@"; CERTS_DIR=$2;   shift 2 ;;
    --port)        opt_val "$@"; PORT=$2;        shift 2 ;;
    --health-path) opt_val "$@"; HEALTH_PATH=$2; shift 2 ;;
    --memory)      opt_val "$@"; MEMORY=$2;      shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    -*)            die "unknown option: $1" ;;
    *)             [[ -z "$IDX" ]] || die "unexpected argument: $1"; IDX=$1; shift ;;
  esac
done

[[ "$IDX" =~ ^[1-9][0-9]*$ ]] || { usage; die "<index> must be a positive integer"; }
for v in DB_HOST DB_PORT IMAGE_TAR CERTS_DIR PORT HEALTH_PATH; do
  [[ -n "${!v}" ]] || die "missing required option for $v"
done

VM="be-node$IDX"
PFX="BE_NODE$IDX"

# 1. Launch the guest.
log "=== [$VM] launching ==="
out=$(bash "$SCRIPT_DIR/multipass-launch.sh" "$VM" --prefix "$PFX" \
  --cpus 1 --memory "$MEMORY" --disk 6G --timeout 900)
printf '%s\n' "$out"
IP=$(grep -m1 "^${PFX}_IP=" <<<"$out" | cut -d= -f2-)
[[ -n "$IP" ]] || die "no IP for $VM"

all="${KNOWN:+$KNOWN,}$IP"
IFS=, read -ra ALL <<<"$all"

# 2. Image tar + database client certs, then start the container.
log "=== [$VM] deploying ($IP) ==="
bash "$SCRIPT_DIR/be-node-deploy.sh" \
  --vm "$VM" \
  --db-host "$DB_HOST" \
  --db-port "$DB_PORT" \
  --image-tar "$IMAGE_TAR" \
  --certs-dir "$CERTS_DIR" \
  --port "$PORT" \
  --health-path "$HEALTH_PATH" \
  --prefix "be_node${IDX}_deploy"

# 3. Only a node that answers its health route goes behind the load balancer.
url="http://$IP:$PORT$HEALTH_PATH"
log "=== [$VM] waiting for GET $url ==="
bash "$SCRIPT_DIR/wait-for.sh" --timeout 60 --interval 2 \
  --desc "GET $url" -- curl -fsS "$url" >&2

# 4. Put it behind the load balancer. The config is rendered again from all
#    nodes so far; HAProxy is only installed on the first run.
log "=== [$VM] adding it to $LB_VM ==="
skip=()
((IDX == 1)) || skip=(--skip-install)
bash "$SCRIPT_DIR/haproxy-lb-setup.sh" "$LB_VM" \
  --prefix be_lb \
  --service-name api \
  --backend-port "$PORT" \
  --health-path "$HEALTH_PATH" \
  ${skip[@]+"${skip[@]}"} \
  "${ALL[@]}" >/dev/null

log "=== [$VM] is in service ==="
