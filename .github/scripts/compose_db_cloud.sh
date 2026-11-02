#!/usr/bin/env bash
set -Eeuo pipefail

NODE="$1"
IP="$2"
JOIN_ADDRS="$3"
COCKROACH_IMAGE="$4"

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
export JOIN_ADDRS=$JOIN_ADDRS
export COCKROACH_IMAGE=$COCKROACH_IMAGE

# Compose the image
docker compose -f docker-compose.cloud.yml up -d
docker ps
