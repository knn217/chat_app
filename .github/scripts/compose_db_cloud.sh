#!/usr/bin/env bash
set -Eeuo pipefail

NODE="$1"

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
mkdir -p /opt/database/certs/$NODE
mkdir -p /opt/database/data/$NODE
cp -a /opt/crdb-deploy/node-certs/. \
  /opt/database/certs/$NODE/
cp /opt/crdb-deploy/.env /opt/database/.env
cd /opt/database
docker compose -f docker-compose.cloud.yml up -d
docker ps
