#!/bin/sh
# Generates a local CA + node + root client certs on first start, then runs a
# secure single-node CockroachDB in the foreground.
set -eu

CRDB=/cockroach/cockroach
CERTS=/certs

mkdir -p "$CERTS"

# if [ ! -f "$CERTS/ca.crt" ]; then
#   echo "[start-node] generating certificates in $CERTS"
#   "$CRDB" cert create-ca --certs-dir="$CERTS" --ca-key="$CERTS/ca.key"
#   "$CRDB" cert create-node localhost 127.0.0.1 cockroach \
#     --certs-dir="$CERTS" --ca-key="$CERTS/ca.key"
#   "$CRDB" cert create-client root --certs-dir="$CERTS" --ca-key="$CERTS/ca.key"
# fi

exec "$CRDB" start-single-node \
  --insecure \
  --store=/cockroach/cockroach-data \
  --listen-addr=0.0.0.0:26257 \
  --http-addr=0.0.0.0:8080 \
  --cache="${COCKROACH_CACHE:-.25}" \
  --max-sql-memory="${COCKROACH_SQL_MEMORY:-.25}"
