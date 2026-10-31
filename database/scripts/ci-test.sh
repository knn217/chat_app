#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-crdb-ci}"
export COCKROACH_IMAGE="${COCKROACH_IMAGE:-cockroachdb/cockroach:v26.2.2}"
IMAGE="$COCKROACH_IMAGE"

[[ -f "$ROOT/certs/client/client.root.crt" && -f "$ROOT/certs/client/client.root.key" ]] || {
  echo "Client certificates are missing; run scripts/ci-up.sh first." >&2
  exit 1
}

# Run the CockroachDB CLI in a short-lived container on the runner's network
# namespace. The SQL connection is TLS-authenticated using the generated root
# client certificate and verifies the localhost SAN against the private CA.
run_cli() {
  docker run --rm --network host \
    -v "$ROOT/certs/client:/cockroach-certs:ro" \
    "$IMAGE" "$@"
}

node_status="$(run_cli node status \
  --certs-dir=/cockroach-certs \
  --host=127.0.0.1:26257 \
  --format=tsv)"
printf '%s\n' "$node_status"

node_count="$(printf '%s\n' "$node_status" | awk -F '\t' '$1 ~ /^[[:space:]]*[0-9]+[[:space:]]*$/ { n++ } END { print n+0 }')"
if [[ "$node_count" -ne 3 ]]; then
  echo "Expected exactly 3 live nodes; node status reported $node_count." >&2
  exit 1
fi

setup_sql=$(cat <<'SQL'
CREATE DATABASE IF NOT EXISTS ci_test;
CREATE SCHEMA IF NOT EXISTS ci_test.workflow_test;
CREATE TABLE IF NOT EXISTS ci_test.workflow_test.records (
  id INT PRIMARY KEY,
  payload STRING NOT NULL,
  amount INT NOT NULL
);
UPSERT INTO ci_test.workflow_test.records (id, payload, amount) VALUES
  (1, 'alpha', 10),
  (2, 'bravo', 20),
  (3, 'charlie', 30);
SQL
)

run_cli sql \
  --certs-dir=/cockroach-certs \
  --host=127.0.0.1:26257 \
  --format=tsv \
  --execute="$setup_sql"

result="$(run_cli sql \
  --certs-dir=/cockroach-certs \
  --host=127.0.0.1:26257 \
  --format=tsv \
  --execute="SELECT CASE WHEN count(*) = 3 AND sum(amount) = 60 AND count(DISTINCT payload) = 3 THEN 'CI_DB_TEST_OK' ELSE 'CI_DB_TEST_FAILED' END AS result FROM ci_test.workflow_test.records;")"
printf '%s\n' "$result"

grep -q 'CI_DB_TEST_OK' <<<"$result" || {
  echo "SQL read-after-write assertion failed." >&2
  exit 1
}

# Also prove the test objects exist in the expected database/schema.
run_cli sql \
  --certs-dir=/cockroach-certs \
  --host=127.0.0.1:26257 \
  --execute='SHOW TABLES FROM ci_test.workflow_test;'

echo "PASS: three-node membership, TLS SQL connection, schema/table creation, inserts, and query assertion."
