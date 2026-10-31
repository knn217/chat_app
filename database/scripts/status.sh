#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
docker compose ps
# Node status via node1; works once the cluster has been initialized.
docker compose exec -T node1 ./cockroach node status --certs-dir=/cockroach/certs --host=node1:26257 || true
