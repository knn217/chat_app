
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-crdb-ci}"
export COCKROACH_IMAGE="${COCKROACH_IMAGE:-cockroachdb/cockroach:v26.2.2}"

COMPOSE_FILE="$ROOT/docker-compose.yml"
NETWORK="crdb-cluster"
CLIENT_CERTS="$ROOT/certs/client"

command -v docker >/dev/null 2>&1 || {
  echo "docker is required" >&2
  exit 1
}

docker info >/dev/null

# Remove certificates from the previous session.
rm -rf "$ROOT/certs" "$ROOT/secrets"
echo "Removed certificates and secrets from last session."

# Generate common CA and certificates.
bash "$ROOT/scripts/generate-ca.sh" "$ROOT"
bash "$ROOT/scripts/generate-cert-node.sh" "$ROOT" node1 node1 127.0.0.1
bash "$ROOT/scripts/generate-cert-node.sh" "$ROOT" node2 node2 127.0.0.1
bash "$ROOT/scripts/generate-cert-node.sh" "$ROOT" node3 node3 127.0.0.1
bash "$ROOT/scripts/generate-cert-client.sh" "$ROOT" root

# Ensure the shared Docker network exists.
if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
  docker network create "$NETWORK"
fi

JOIN_ADDRS="node1:26257,node2:26257,node3:26257"

# Start one Compose project per node.
compose_node() {
  local node="$1"
  local sql_port="$2"
  local http_port="$3"
  shift 3

  env \
    NODE_NAME="$node" \
    NODE_ADVERTISE_ADDR="$node" \
    NODE_SQL_PORT="$sql_port" \
    NODE_HTTP_PORT="$http_port" \
    JOIN_ADDRS="$JOIN_ADDRS" \
    COCKROACH_IMAGE="$COCKROACH_IMAGE" \
    docker compose \
      -p "${COMPOSE_PROJECT_NAME}-${node}" \
      -f "$COMPOSE_FILE" \
      --project-directory "$ROOT" \
      "$@"
}

echo "Pulling CockroachDB image..."
docker pull "$COCKROACH_IMAGE"

echo "Starting CockroachDB nodes..."

compose_node node1 26257 8080 up -d
compose_node node2 26258 8081 up -d
compose_node node3 26259 8082 up -d

# Check whether the SQL endpoint is ready.
sql_ready() {
  docker run --rm \
    --network "$NETWORK" \
    -v "$CLIENT_CERTS:/cockroach/certs:ro" \
    "$COCKROACH_IMAGE" \
    sql \
    --certs-dir=/cockroach/certs \
    --host=node1:26257 \
    --execute="SELECT 1;" \
    >/dev/null 2>&1
}

# First, check whether an existing cluster is already ready.
echo "Checking whether CockroachDB is already initialized..."

connected=false

for attempt in $(seq 1 5); do
  if sql_ready; then
    connected=true
    echo "Existing CockroachDB cluster is already ready. Skipping initialization."
    break
  fi

  echo "Waiting for an existing cluster ($attempt/15)..."
  sleep 2
done

# If SQL isn't ready, attempt cluster initialization.
if [[ "$connected" != true ]]; then
  echo "SQL is not ready. Attempting cluster initialization..."

  container="cockroach-node1"
  initialized=false

  for attempt in $(seq 1 60); do
    if docker inspect "$container" >/dev/null 2>&1 &&
       [[ "$(docker inspect -f '{{.State.Running}}' "$container")" == "true" ]]; then

      init_output="$(
        docker run --rm \
          --network "$NETWORK" \
          -v "$CLIENT_CERTS:/cockroach/certs:ro" \
          "$COCKROACH_IMAGE" \
          init \
          --certs-dir=/cockroach/certs \
          --host=node1:26257 2>&1
      )" && {
        echo "$init_output"
        initialized=true
        break
      }

      # An already-initialized cluster is an expected condition.
      if grep -qi "already been initialized" <<< "$init_output"; then
        echo "Cluster has already been initialized. Continuing."
        initialized=true
        break
      fi

      echo "Initialization attempt $attempt failed:"
      echo "$init_output"
    fi

    echo "Waiting for CockroachDB before initialization ($attempt/60)..."
    sleep 5
  done

  if [[ "$initialized" != true ]]; then
    echo "Cluster initialization did not succeed within 5 minutes." >&2
    docker logs "$container" >&2 || true
    exit 1
  fi
fi

# Wait for SQL endpoint readiness.
connected=false

echo "Waiting for CockroachDB SQL endpoint..."

for attempt in $(seq 1 60); do
  if sql_ready; then
    connected=true
    echo "CockroachDB SQL endpoint is ready."
    break
  fi

  echo "Waiting for SQL endpoint ($attempt/60)..."
  sleep 2
done

if [[ "$connected" != true ]]; then
  echo "CockroachDB SQL endpoint did not become ready." >&2

  compose_node node1 26257 8080 logs --tail=100 --no-color >&2 || true
  compose_node node2 26258 8081 logs --tail=100 --no-color >&2 || true
  compose_node node3 26259 8082 logs --tail=100 --no-color >&2 || true

  exit 1
fi

echo "CockroachDB containers:"
docker ps --filter "name=cockroach-node"

echo "Secure three-node CockroachDB cluster is ready."
