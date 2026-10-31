#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-crdb-ci}"
COMPOSE=(docker compose -p "$COMPOSE_PROJECT_NAME" -f "$ROOT/docker-compose.yml" --project-directory "$ROOT")

# CI owns this project name and its ephemeral named volumes.
"${COMPOSE[@]}" down --volumes --remove-orphans || true

# Remove only generated certs/keys. Preserve .gitkeep placeholders.
for dir in "$ROOT/certs" "$ROOT/secrets"; do
  if [[ -d "$dir" ]]; then
    find "$dir" -mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf -- {} +
  fi
done

echo "CI cluster, volumes, and generated certificate material cleaned up."
