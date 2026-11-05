#!/usr/bin/env bash
# Runs INSIDE a node VM (as root): installs Docker and starts one CockroachDB
# node with docker compose.
#
# Usage (stdin script, as the workflow does):
#   multipass exec <vm> -- sudo bash -s -- NODE IP IMAGE JOIN_ADDRS SQL_PORT HTTP_PORT \
#     < compose_db_cloud.sh
#
# Expects these files to be in place already (see multipass-send.sh):
#   /opt/crdb-deploy/cockroach-cluster-package.tar.gz   deployment package
#   /opt/crdb-deploy/node-certs/                        this node's certificates
set -Eeuo pipefail

NODE="$1"
IP="$2"
COCKROACH_IMAGE="$3"
JOIN_ADDRS="$4"
NODE_SQL_PORT="$5"
NODE_HTTP_PORT="$6"

DEPLOY_DIR=/opt/crdb-deploy

[[ -f "$DEPLOY_DIR/cockroach-cluster-package.tar.gz" ]] ||
  { echo "Missing $DEPLOY_DIR/cockroach-cluster-package.tar.gz" >&2; exit 1; }
[[ -d "$DEPLOY_DIR/node-certs" ]] ||
  { echo "Missing $DEPLOY_DIR/node-certs" >&2; exit 1; }

# Install docker
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker.io \
  docker-compose-v2

systemctl enable --now docker
docker version
docker compose version

# Unpack the deployment package into /opt/database
mkdir -p /opt/database
tar -xzf "$DEPLOY_DIR/cockroach-cluster-package.tar.gz" -C /opt

# Create distinct cert and data path for each node
mkdir -p "/opt/database/certs/$NODE"
mkdir -p "/opt/database/data/$NODE"
cp -a "$DEPLOY_DIR/node-certs/." "/opt/database/certs/$NODE/"

cd /opt/database

# Export env var before composing image
export NODE_NAME="$NODE"
export NODE_ADVERTISE_ADDR="$IP"
export COCKROACH_IMAGE="$COCKROACH_IMAGE"
export JOIN_ADDRS="$JOIN_ADDRS"
export NODE_SQL_PORT="$NODE_SQL_PORT"
export NODE_HTTP_PORT="$NODE_HTTP_PORT"

# Create external network for docker image 1st
if ! docker network inspect crdb-cluster >/dev/null 2>&1; then
  docker network create crdb-cluster
fi

# Compose the image
docker compose -f docker-compose.yml up -d

docker ps
