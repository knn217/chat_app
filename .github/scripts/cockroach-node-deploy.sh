#!/usr/bin/env bash
# Set up ONE CockroachDB node on an existing Multipass VM, start to finish:
#   1. generate the node certificate (database/scripts/generate-cert-node.sh)
#   2. check the certificate's subjectAltName
#   3. send the shared deployment package and this node's certs to the VM
#   4. run compose_db_cloud.sh inside the VM (installs Docker, starts the node)
#
# The CA, client certs and the deployment package must already exist
# (they are shared by all nodes, so create them once before looping).
#
# Usage:
#   cockroach-node-deploy.sh --vm VM --node NAME --ip IP --lb-ip LB_IP \
#       --join ADDR[,ADDR...] --image IMAGE --package PATH \
#       [--db-dir ./database] [--sql-port 26257] [--http-port 8080] [--prefix PFX]
#
#   --vm        Multipass VM name (e.g. db-node1)
#   --node      cert/data name for this node (e.g. node1)
#   --ip        the VM's IP; goes into the certificate SAN and --advertise-addr
#   --lb-ip     load balancer IP; also goes into the certificate SAN
#   --join      comma-separated ip:port list of ALL nodes
#   --package   path to cockroach-cluster-package.tar.gz on this machine
#
# stdout: PFX_VM  PFX_NODE  PFX_IP  PFX_CERT_DIR   (PFX defaults to the upper-cased --node)
# stderr: logs.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

VM="" NODE="" IP="" LB_IP="" JOIN="" IMAGE="" PACKAGE=""
DB_DIR=./database
SQL_PORT=26257
HTTP_PORT=8080
PREFIX=""

while (($#)); do
  case "$1" in
    --vm)        opt_val "$@"; VM=$2;        shift 2 ;;
    --node)      opt_val "$@"; NODE=$2;      shift 2 ;;
    --ip)        opt_val "$@"; IP=$2;        shift 2 ;;
    --lb-ip)     opt_val "$@"; LB_IP=$2;     shift 2 ;;
    --join)      opt_val "$@"; JOIN=$2;      shift 2 ;;
    --image)     opt_val "$@"; IMAGE=$2;     shift 2 ;;
    --package)   opt_val "$@"; PACKAGE=$2;   shift 2 ;;
    --db-dir)    opt_val "$@"; DB_DIR=$2;    shift 2 ;;
    --sql-port)  opt_val "$@"; SQL_PORT=$2;  shift 2 ;;
    --http-port) opt_val "$@"; HTTP_PORT=$2; shift 2 ;;
    --prefix)    opt_val "$@"; PREFIX=$2;    shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "unknown argument: $1" ;;
  esac
done

for var in VM NODE IP LB_IP JOIN IMAGE PACKAGE; do
  [[ -n "${!var}" ]] || { usage; die "missing required option for $var"; }
done
[[ -f "$PACKAGE" ]] || die "deployment package not found: $PACKAGE"
[[ -d "$DB_DIR/scripts" ]] || die "database scripts not found in: $DB_DIR/scripts"
PFX=$(to_key "${PREFIX:-$NODE}")

log "=== $NODE ($VM, $IP): certificate ==="
bash "$DB_DIR/scripts/generate-cert-node.sh" "$DB_DIR" "$NODE" "$NODE" "$IP" "$LB_IP" >&2

CERT_DIR="$DB_DIR/certs/$NODE"
[[ -f "$CERT_DIR/node.crt" ]] || die "node certificate was not generated: $CERT_DIR/node.crt"
log "subjectAltName of $NODE:"
openssl x509 -in "$CERT_DIR/node.crt" -noout -ext subjectAltName >&2

log "=== $NODE: send files ==="
bash "$LIB_DIR/multipass-send.sh" "$VM" "$PACKAGE" /opt/crdb-deploy
bash "$LIB_DIR/multipass-send.sh" "$VM" "$CERT_DIR" /opt/crdb-deploy/node-certs

log "=== $NODE: start CockroachDB ==="
mp exec "$VM" -- sudo bash -s -- \
  "$NODE" "$IP" "$IMAGE" "$JOIN" "$SQL_PORT" "$HTTP_PORT" \
  < "$LIB_DIR/compose_db_cloud.sh" >&2

emit "${PFX}_VM"       "$VM"
emit "${PFX}_NODE"     "$NODE"
emit "${PFX}_IP"       "$IP"
emit "${PFX}_CERT_DIR" "$CERT_DIR"
