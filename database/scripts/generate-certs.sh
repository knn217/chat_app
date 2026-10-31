#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-local}"
IMAGE="${COCKROACH_IMAGE:-cockroachdb/cockroach:v26.2.2}"
NODES_FILE="${2:-$ROOT/config/nodes.local}"

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
[[ -f "$NODES_FILE" ]] || { echo "Nodes file not found: $NODES_FILE" >&2; exit 1; }
mkdir -p "$ROOT/certs" "$ROOT/secrets"
if [[ -e "$ROOT/secrets/ca.key" ]]; then
  echo "CA key already exists; refusing to overwrite it. Back it up and remove it explicitly to regenerate." >&2
  exit 1
fi

# CockroachDB's own cert utility is used, avoiding a host CockroachDB install.
docker pull "$IMAGE"
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$ROOT:/work" -w /work "$IMAGE" cert create-ca \
  --certs-dir=/work/certs/ca --ca-key=/work/secrets/ca.key
chmod 600 "$ROOT/secrets/ca.key"

while read -r name dns ip extra; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue
  [[ -z "${dns:-}" || -z "${ip:-}" || -n "${extra:-}" ]] && { echo "Invalid node row: $name $dns $ip" >&2; exit 1; }
  mkdir -p "$ROOT/certs/$name"
  cp "$ROOT/certs/ca/ca.crt" "$ROOT/certs/$name/ca.crt"
  docker run --rm --user "$(id -u):$(id -g)" \
    -v "$ROOT:/work" -w /work "$IMAGE" cert create-node \
    "$name" "$dns" "$ip" localhost 127.0.0.1 \
    --certs-dir="/work/certs/$name" --ca-key=/work/secrets/ca.key
  chmod 600 "$ROOT/certs/$name/node.key"
done < "$NODES_FILE"

mkdir -p "$ROOT/certs/client"
cp "$ROOT/certs/ca/ca.crt" "$ROOT/certs/client/ca.crt"
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$ROOT:/work" -w /work "$IMAGE" cert create-client root \
  --certs-dir=/work/certs/client --ca-key=/work/secrets/ca.key
chmod 600 "$ROOT/certs/client/client.root.key"

cat <<MSG
Certificates generated.
- Keep secrets/ca.key offline and tightly restricted; never copy it to database hosts.
- Distribute each certs/<node>/ directory only to its matching node.
- Distribute certs/client/ only to trusted root SQL clients.
- The CA private key is required only to issue/rotate certificates.
MSG
