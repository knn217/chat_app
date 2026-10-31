#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-crdb-ci}"
export COCKROACH_IMAGE="${COCKROACH_IMAGE:-cockroachdb/cockroach:v26.2.2}"
COMPOSE=(docker compose -p "$COMPOSE_PROJECT_NAME" -f "$ROOT/docker-compose.yml" --project-directory "$ROOT")

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
docker info >/dev/null

if [[ -e "$ROOT/secrets/ca.key" ]]; then
  echo "Refusing to reuse an existing CA key in CI. Use a clean runner/worktree." >&2
  exit 1
fi

# Use the exact certificate-generation path documented for local development.
"$ROOT/scripts/generate-certs.sh" local

# Start all three nodes on the Compose bridge network.
"${COMPOSE[@]}" pull
"${COMPOSE[@]}" up -d

# cockroach init is the cluster bootstrap operation. Retry while the nodes start.
# It is executed once successfully; do not rerun it after success.
container="${COMPOSE_PROJECT_NAME}-node1-1"
initialized=false
for attempt in $(seq 1 60); do
  if docker inspect "$container" >/dev/null 2>&1; then
    if docker exec "$container" ./cockroach init \
      --certs-dir=/cockroach/certs --host=node1:26257; then
      initialized=true
      break
    fi
  fi
  echo "Waiting for CockroachDB nodes before initialization ($attempt/60)..."
  sleep 5
done

if [[ "$initialized" != true ]]; then
  echo "Cluster initialization did not succeed within 5 minutes." >&2
  "${COMPOSE[@]}" ps >&2 || true
  "${COMPOSE[@]}" logs --no-color >&2 || true
  exit 1
fi

"${COMPOSE[@]}" ps
echo "Secure three-node CockroachDB cluster initialized."
