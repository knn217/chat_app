#!/usr/bin/env bash
# Runs INSIDE a backend VM (as root): installs Docker, loads the backend image
# and starts the container, mirroring the "docker run" in setup.sh.
#
# Usage (stdin script, as be-node-deploy.sh does):
#   multipass exec <vm> -- sudo bash -s -- DB_HOST DB_PORT DB_NAME DB_USER BE_PORT \
#     HEALTH_PATH IMAGE TAR_NAME < run_be_cloud.sh
#
# DATABASE_URL is assembled here from its parts, because characters like & and ?
# do not survive being passed as command-line arguments through multipass exec.
#
# Expects these files to be in place already (see multipass-send.sh):
#   /opt/be-deploy/<TAR_NAME>          image saved with `docker save`
#   /opt/be-deploy/certs/              ca.crt, client.<user>.crt, client.<user>.pem
set -Eeuo pipefail

DB_HOST="$1"
DB_PORT="$2"
DB_NAME="$3"
DB_USER="$4"
BE_PORT="$5"
HEALTH_PATH="$6"
IMAGE="$7"
TAR_NAME="$8"

DEPLOY_DIR=/opt/be-deploy
CONTAINER=backend-container
CERTS_IN_CONTAINER=/app/certs

[[ -f "$DEPLOY_DIR/$TAR_NAME" ]] ||
  { echo "Missing $DEPLOY_DIR/$TAR_NAME" >&2; exit 1; }
[[ -d "$DEPLOY_DIR/certs" ]] ||
  { echo "Missing $DEPLOY_DIR/certs" >&2; exit 1; }

# Install docker
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io curl

systemctl enable --now docker
docker version

# Load the backend image
docker load -i "$DEPLOY_DIR/$TAR_NAME"

JDBC_OPTIONS="sslmode=verify-full"
JDBC_OPTIONS+="&sslrootcert=$CERTS_IN_CONTAINER/ca.crt"
JDBC_OPTIONS+="&sslcert=$CERTS_IN_CONTAINER/client.$DB_USER.crt"
JDBC_OPTIONS+="&sslkey=$CERTS_IN_CONTAINER/client.$DB_USER.pem"
DATABASE_URL="postgresql://$DB_USER@$DB_HOST:$DB_PORT/$DB_NAME?$JDBC_OPTIONS"

# Replace a previous container, if any (the script is safe to re-run)
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -p "$BE_PORT:$BE_PORT" \
  -v "$DEPLOY_DIR/certs:$CERTS_IN_CONTAINER:ro" \
  -e NO_COLOR=1 \
  -e TERM=dumb \
  -e PORT="$BE_PORT" \
  -e RUST_BACKTRACE=full \
  -e DATABASE_URL="$DATABASE_URL" \
  -e CHAT_BE_PORT="$BE_PORT" \
  "$IMAGE"

# Wait until the backend answers on its health route
echo "Waiting for http://127.0.0.1:$BE_PORT$HEALTH_PATH ..."
for attempt in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$BE_PORT$HEALTH_PATH" >/dev/null 2>&1; then
    echo "Backend is healthy."
    docker ps
    exit 0
  fi
  sleep 2
done

echo "Backend did not become healthy in time. Container logs:" >&2
docker ps -a >&2
docker logs --tail 100 "$CONTAINER" >&2 || true
exit 1
