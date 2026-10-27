#!/bin/sh
# Removes the database containers and, by default, its data, certificates and image.
# Usage: sh uninstall.sh [--yes] [--keep-data]
#   --yes        skip the confirmation prompt
#   --keep-data  keep the data and cert volumes (only remove containers and image)
set -eu
cd "$(dirname "$0")"

YES=false
KEEP_DATA=false
for arg in "$@"; do
  case "$arg" in
    --yes)       YES=true ;;
    --keep-data) KEEP_DATA=true ;;
    *) echo "usage: $0 [--yes] [--keep-data]" >&2; exit 1 ;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "[uninstall] docker is required" >&2; exit 1; }

# If stdin is NOT a terminal (non-interactive/CI/cron/pipe), auto-accept
if [ "$KEEP_DATA" = false ] && [ "$YES" = false ] && [ -t 0 ]; then
  echo "This permanently deletes the database, its data volume and its certificates."
  echo "Run scripts/backup.sh first if you need the data."
  printf "Type 'delete' to continue: "
  answer=""
  read -r answer || true
  [ "$answer" = "delete" ] || { echo "[uninstall] aborted"; exit 1; }
fi

# The compose file requires these variables even for `down`; the values are unused.
export COCKROACH_VERSION=unused APP_DB_PASSWORD=unused

if [ "$KEEP_DATA" = true ]; then
  echo "[uninstall] removing containers (keeping volumes)"
  docker compose down
else
  echo "[uninstall] removing containers and volumes"
  docker compose down --volumes
fi

echo "[uninstall] removing image"
docker rmi chat-db:local 2>/dev/null || echo "[uninstall] image not removed (already gone or still in use)"

echo "[uninstall] done. Left in place: .env, ca.crt and backups/ (delete them yourself if you want)"