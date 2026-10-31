#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE="${1:-node1}"
case "$NODE" in
  node1) PORT=26257;; node2) PORT=26258;; node3) PORT=26259;; node4) PORT=26260;;
  *) echo "Local SQL helper supports node1-node4 only" >&2; exit 2;;
esac
exec docker run --rm -it --network host \
  -v "$ROOT/certs/client:/cockroach-certs:ro" \
  "${COCKROACH_IMAGE:-cockroachdb/cockroach:v26.2.2}" sql \
  --certs-dir=/cockroach-certs --host=127.0.0.1:"$PORT"
