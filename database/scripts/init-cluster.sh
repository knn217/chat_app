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
  echo "Container '$CONTAINER' not found. Start the cluster first." >&2
  exit 1
fi

if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]]; then
  echo "Container '$CONTAINER' is not running." >&2
  exit 1
fi

IMAGE="${COCKROACH_IMAGE:-cockroachdb/cockroach:v26.2.2}"
CLIENT_CERTS="$ROOT/certs/client"

for file in ca.crt client.root.crt client.root.key; do
  if [[ ! -r "$CLIENT_CERTS/$file" ]]; then
    echo "Missing or unreadable client certificate: $CLIENT_CERTS/$file" >&2
    exit 1
  fi
done

NETWORK="$(docker inspect "$CONTAINER" \
  --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' \
  | head -n 1)"

if [[ -z "$NETWORK" ]]; then
  echo "Could not determine Docker network for $CONTAINER" >&2
  exit 1
fi

docker run --rm \
  --network "$NETWORK" \
  -v "$CLIENT_CERTS:/cockroach/certs:ro" \
  "$IMAGE" \
  init \
  --certs-dir=/cockroach/certs \
  --host="${NODE}:26257"
