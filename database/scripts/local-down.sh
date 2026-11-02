
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-crdb-ci}"
COMPOSE_FILE="$ROOT/docker-compose.yml"
COCKROACH_IMAGE="${COCKROACH_IMAGE:-cockroachdb/cockroach:v26.2.2}"
NETWORK="crdb-cluster"
GRACE_SECONDS="${CI_STOP_TIMEOUT:-10}"

JOIN_ADDRS="node1:26257,node2:26257,node3:26257"

# Stop and remove one node's Compose project.
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

echo "Stopping CockroachDB nodes..."

compose_node node1 26257 8080 \
    down --volumes --remove-orphans --timeout "$GRACE_SECONDS"

compose_node node2 26258 8081 \
    down --volumes --remove-orphans --timeout "$GRACE_SECONDS"

compose_node node3 26259 8082 \
    down --volumes --remove-orphans --timeout "$GRACE_SECONDS"

# Remove the shared external network after all node projects are down.
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
    echo "Removing Docker network: $NETWORK"
    docker network rm "$NETWORK"
fi

echo "CockroachDB cluster stopped."
