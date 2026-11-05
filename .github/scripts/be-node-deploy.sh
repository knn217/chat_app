#!/usr/bin/env bash
# Set up ONE backend node on an existing Multipass VM, start to finish:
#   1. send the backend image tar and the database client certificates
#   2. run run_be_cloud.sh inside the VM (installs Docker, loads the image,
#      starts the container, waits for the health route)
#
# The backend connects to the database through the DB load balancer, so the
# load balancer address must be in the node certificates' SAN
# (cockroach-node-deploy.sh already does that).
#
# Usage:
#   be-node-deploy.sh --vm VM --db-host HOST --image-tar PATH --certs-dir DIR
#       [--db-port 26257] [--db-name chat_db] [--db-user user_be]
#       [--port 8090] [--health-path /api/v1/auth/me]
#       [--image backend_img:latest] [--prefix PFX]
#
#   --vm         Multipass VM name (e.g. be-node1)
#   --db-host    address of the DB load balancer (IP)
#   --image-tar  backend-image.tar on this machine (see be-image-build.sh)
#   --certs-dir  local client cert directory of the DB user (database/certs/user_be)
#
# stdout: PFX_VM  PFX_PORT   (PFX defaults to the upper-cased VM name)
# stderr: logs.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

VM="" DB_HOST="" IMAGE_TAR="" CERTS=""
DB_PORT=26257
DB_NAME=chat_db
DB_USER=user_be
BE_PORT=8090
HEALTH_PATH=/api/v1/auth/me
IMAGE=backend_img:latest
PREFIX=""

while (($#)); do
  case "$1" in
    --vm)          opt_val "$@"; VM=$2;          shift 2 ;;
    --db-host)     opt_val "$@"; DB_HOST=$2;     shift 2 ;;
    --image-tar)   opt_val "$@"; IMAGE_TAR=$2;   shift 2 ;;
    --certs-dir)   opt_val "$@"; CERTS=$2;       shift 2 ;;
    --db-port)     opt_val "$@"; DB_PORT=$2;     shift 2 ;;
    --db-name)     opt_val "$@"; DB_NAME=$2;     shift 2 ;;
    --db-user)     opt_val "$@"; DB_USER=$2;     shift 2 ;;
    --port)        opt_val "$@"; BE_PORT=$2;     shift 2 ;;
    --health-path) opt_val "$@"; HEALTH_PATH=$2; shift 2 ;;
    --image)       opt_val "$@"; IMAGE=$2;       shift 2 ;;
    --prefix)      opt_val "$@"; PREFIX=$2;      shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "unknown argument: $1" ;;
  esac
done

for var in VM DB_HOST IMAGE_TAR CERTS; do
  [[ -n "${!var}" ]] || { usage; die "missing required option for $var"; }
done
[[ -f "$IMAGE_TAR" ]] || die "image tar not found: $IMAGE_TAR"
[[ -d "$CERTS" ]] || die "client cert directory not found: $CERTS"
PFX=$(to_key "${PREFIX:-$VM}")

log "=== $VM: send files ==="
bash "$LIB_DIR/multipass-send.sh" "$VM" "$IMAGE_TAR" /opt/be-deploy
bash "$LIB_DIR/multipass-send.sh" "$VM" "$CERTS" /opt/be-deploy/certs

log "=== $VM: start backend ==="
mp exec "$VM" -- sudo bash -s -- \
  "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "$BE_PORT" "$HEALTH_PATH" "$IMAGE" \
  "$(basename "$IMAGE_TAR")" \
  < "$LIB_DIR/run_be_cloud.sh" >&2

emit "${PFX}_VM"   "$VM"
emit "${PFX}_PORT" "$BE_PORT"
