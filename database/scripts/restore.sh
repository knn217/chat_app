#!/bin/sh
# Host-side. DESTRUCTIVE: drops the app database, then restores it from a backup.
# Usage: scripts/restore.sh backups/<timestamp> --yes
set -eu
cd "$(dirname "$0")/.."

SRC=${1:-}
[ -d "$SRC" ] || { echo "usage: $0 backups/<timestamp> --yes" >&2; exit 1; }
[ "${2:-}" = "--yes" ] || { echo "refusing to drop the database without --yes" >&2; exit 1; }

DB=$(grep -E '^APP_DB_NAME=' .env 2>/dev/null | cut -d= -f2- || true)
DB=${DB:-chat_db}
STAMP=$(basename "$SRC")

docker compose exec -T cockroach mkdir -p /cockroach/cockroach-data/extern/backups
docker compose cp "$SRC" "cockroach:/cockroach/cockroach-data/extern/backups/"

docker compose exec -T cockroach /cockroach/cockroach sql \
  --insecure --host=localhost:26257 \
  -e "DROP DATABASE IF EXISTS ${DB} CASCADE; RESTORE DATABASE ${DB} FROM LATEST IN 'nodelocal://1/backups/${STAMP}';"

# Re-apply role password, schema and grants (idempotent).
docker compose run --rm db-setup
echo "restored ${DB} from ${SRC}"
