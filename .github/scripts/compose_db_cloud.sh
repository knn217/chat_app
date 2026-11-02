#!/usr/bin/env bash
set -Eeuo pipefail

NODE="$1"
IP="$2"
COCKROACH_IMAGE="$3"
JOIN_ADDRS="$4"
NODE_SQL_PORT="$5"
NODE_HTTP_PORT="$6"

# Install docker
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker.io \
  docker-compose-v2

systemctl enable --now docker
docker version
docker compose version

# Compose db image
mkdir -p /opt/crdb-deploy /opt/database
tar -xzf /home/ubuntu/deploy.tar.gz \
  -C /opt/crdb-deploy
tar -xzf \
  /opt/crdb-deploy/cockroach-cluster-package.tar.gz \
  -C /opt

# Create distinct cert and data path for each node
mkdir -p /opt/database/certs/$NODE
mkdir -p /opt/database/data/$NODE
cp -a /opt/crdb-deploy/node-certs/. \
  /opt/database/certs/$NODE/
cd /opt/database

# Export env var before composing image
export NODE_NAME=$NODE
export NODE_ADVERTISE_ADDR=$IP
export COCKROACH_IMAGE=$COCKROACH_IMAGE
export JOIN_ADDRS=$JOIN_ADDRS
export NODE_SQL_PORT=$NODE_SQL_PORT
export NODE_HTTP_PORT=$NODE_HTTP_PORT

# Create external network for docker image 1st
if ! docker network inspect crdb-cluster >/dev/null 2>&1; then
    docker network create crdb-cluster
fi

# Compose the image
docker compose -f docker-compose.cloud.yml up -d
docker ps
