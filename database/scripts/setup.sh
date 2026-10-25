#!/bin/sh
# Idempotent bootstrap. Safe to re-run (also used after a restore).
set -eu

CRDB=/cockroach/cockroach
HOST=cockroach:26257

fail() { echo "[setup] ERROR: $*" >&2; exit 1; }

: "${APP_DB_NAME:?}" "${APP_DB_USER:?}" "${APP_DB_PASSWORD:?}"

# Values are interpolated into SQL, so restrict them to safe characters.
case "$APP_DB_NAME" in ""|*[!a-z0-9_]*) fail "APP_DB_NAME must match [a-z0-9_]+";; esac
case "$APP_DB_USER" in ""|*[!a-z0-9_]*) fail "APP_DB_USER must match [a-z0-9_]+";; esac
case "$APP_DB_PASSWORD" in ""|*[!A-Za-z0-9._-]*) fail "APP_DB_PASSWORD may only contain A-Z a-z 0-9 . _ -";; esac
[ "${#APP_DB_PASSWORD}" -ge 12 ] || fail "APP_DB_PASSWORD must be at least 12 characters"

sql() { "$CRDB" sql --certs-dir=/certs --host="$HOST" "$@"; }

echo "[setup] database and role"
sql -e "CREATE DATABASE IF NOT EXISTS ${APP_DB_NAME};"
sql -e "CREATE USER IF NOT EXISTS ${APP_DB_USER};"
sql -e "ALTER USER ${APP_DB_USER} WITH PASSWORD '${APP_DB_PASSWORD}';"

if [ -n "${COCKROACH_LICENSE:-}" ]; then
  [ -n "${COCKROACH_ORG:-}" ] || fail "COCKROACH_ORG is required when COCKROACH_LICENSE is set"
  case "${COCKROACH_ORG}${COCKROACH_LICENSE}" in *\'*) fail "license/org must not contain single quotes";; esac
  echo "[setup] applying license"
  sql -e "SET CLUSTER SETTING cluster.organization = '${COCKROACH_ORG}';"
  sql -e "SET CLUSTER SETTING enterprise.license = '${COCKROACH_LICENSE}';"
else
  echo "[setup] WARNING: COCKROACH_LICENSE not set (see README, License section)"
fi

echo "[setup] schema"
for f in /chat-db/sql/*.sql; do
  echo "[setup]   applying $f"
  sql --database="$APP_DB_NAME" -f "$f"
done

echo "[setup] grants (app role: no DDL, no DELETE)"
sql --database="$APP_DB_NAME" -e "GRANT CONNECT ON DATABASE ${APP_DB_NAME} TO ${APP_DB_USER};"
sql --database="$APP_DB_NAME" -e "GRANT SELECT, INSERT, UPDATE ON TABLE users TO ${APP_DB_USER};"
sql --database="$APP_DB_NAME" -e "REVOKE CREATE ON SCHEMA public FROM public;" \
  || echo "[setup] WARNING: could not revoke CREATE on schema public (non-fatal)"

echo "[setup] done"
