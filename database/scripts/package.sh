#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/dist}"
ARCHIVE_NAME="cockroach-cluster-package"
BASE="$(basename "$ROOT")"
mkdir -p "$OUT_DIR"
# Deliberately exclude credentials, generated certs, data, local env, and old archives.
tar -czf "$OUT_DIR/${ARCHIVE_NAME}.tar.gz" -C "$(dirname "$ROOT")" \
  --exclude="$BASE/.git" \
  --exclude="$BASE/.env" \
  --exclude="$BASE/certs/*" --exclude="$BASE/secrets/*" --exclude="$BASE/data/*" \
  --exclude="$BASE/dist" \
  "$BASE"
echo "Created: $OUT_DIR/${ARCHIVE_NAME}.tar.gz"
echo "Generated certs, CA private key, and database data are intentionally not packaged."
