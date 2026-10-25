#!/bin/sh
# Installs the packaged database: loads the image, creates .env, starts it.
# Usage: sh install.sh   (from the extracted release folder, anywhere)
set -eu
cd "$(dirname "$0")"

command -v docker >/dev/null 2>&1 || { echo "[install] docker is required" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "[install] the docker compose plugin is required" >&2; exit 1; }

echo "[install] loading image"
docker load -i chat-db.tar.gz

if [ ! -f .env ]; then
  # 48 hex chars: satisfies the setup.sh password rules
  PW=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
  sed "s/^APP_DB_PASSWORD=.*/APP_DB_PASSWORD=${PW}/" .env.example > .env
  chmod 600 .env
  echo "[install] created .env with a generated app password"
else
  echo "[install] keeping existing .env"
fi

echo "[install] starting (no build, the image was loaded above)"
docker compose up -d --no-build

echo "[install] setup log:"
docker compose logs -f db-setup
echo "[install] done. Connection details are in README.md"