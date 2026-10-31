
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-crdb-ci}"

COMPOSE=(docker compose -p "$COMPOSE_PROJECT_NAME" -f "$ROOT/docker-compose.yml" --project-directory "$ROOT")

GRACE_SECONDS="${CI_STOP_TIMEOUT:-10}"
LOG_INTERVAL=3

echo "Stopping CockroachDB containers..."

containers=("${COMPOSE_PROJECT_NAME}-node1-1"
            "${COMPOSE_PROJECT_NAME}-node2-1"
            "${COMPOSE_PROJECT_NAME}-node3-1")

for container in "${containers[@]}"; do
  if ! docker inspect "$container" >/dev/null 2>&1; then
    continue
  fi

  if [[ "$(docker inspect -f '{{.State.Running}}' "$container")" != "true" ]]; then
    continue
  fi

  echo "Requesting graceful shutdown: $container"
  docker stop --time "$GRACE_SECONDS" "$container" >/dev/null &
  stop_pid=$!

  elapsed=0

  while kill -0 "$stop_pid" 2>/dev/null && (( elapsed < GRACE_SECONDS )); do
    sleep "$LOG_INTERVAL"
    elapsed=$((elapsed + LOG_INTERVAL))

    if kill -0 "$stop_pid" 2>/dev/null; then
      echo "Still waiting for $container (${elapsed}s elapsed)..."
      docker logs --tail 15 "$container" 2>&1 || true
    fi
  done

  if kill -0 "$stop_pid" 2>/dev/null; then
    echo "Shutdown timed out for $container. Sending SIGKILL..."
    docker kill "$container" >/dev/null 2>&1 || true
  fi

  wait "$stop_pid" 2>/dev/null || true
done

echo "Removing containers, networks, and volumes..."
"${COMPOSE[@]}" down \
  --volumes \
  --remove-orphans \
  --timeout 10

echo "CockroachDB CI cluster stopped and cleaned up."

# Remove all the certs and secrets
rm -rf "$ROOT/certs"
rm -rf "$ROOT/secrets"
echo "Removed all certs and secrets for this session."
