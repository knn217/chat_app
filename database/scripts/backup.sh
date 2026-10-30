#!/bin/sh
# Host-side. Runs BACKUP inside the node and copies it to ./backups/<timestamp>.
set -eu
cd "$(dirname "$0")/.."

DB=$(grep -E '^APP_DB_NAME=' .env 2>/dev/null | cut -d= -f2- || true)
DB=${DB:-chat_db}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

docker compose exec -T cockroach /cockroach/cockroach sql \
  --certs-dir=/certs --host=localhost:26257 \
  -e "BACKUP DATABASE ${DB} INTO 'nodelocal://1/backups/${STAMP}';"

mkdir -p backups
docker compose cp "cockroach:/cockroach/cockroach-data/extern/backups/${STAMP}" "backups/${STAMP}"
echo "backup written to backups/${STAMP}"
