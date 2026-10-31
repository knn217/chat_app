#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
NODE="${1:-node1}"
if [[ "$NODE" == node1 || "$NODE" == node2 || "$NODE" == node3 || "$NODE" == node4 ]]; then
  CONTAINER="${COMPOSE_PROJECT_NAME:-crdb}-${NODE}-1"
else
  CONTAINER="cockroach-${NODE}"
fi
if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "Container '$CONTAINER' not found. Start the cluster first." >&2; exit 1
fi
docker exec "$CONTAINER" ./cockroach init --certs-dir=/cockroach/certs --host="${NODE}:26257"
