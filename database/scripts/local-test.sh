
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-crdb-ci}"
export COCKROACH_IMAGE="${COCKROACH_IMAGE:-cockroachdb/cockroach:v26.2.2}"

IMAGE="$COCKROACH_IMAGE"
COCKROACH_HOST="${COCKROACH_HOST:-127.0.0.1:26257}"
COCKROACH_DATABASE="${COCKROACH_DATABASE:-chat_db}"

main() {
    check_certificates
    wait_for_cluster
    test_database_operations
    cleanup_test_table
    verify_application_schema

    echo "PASS: three-node membership, TLS SQL connection, schema/table creation, inserts, query assertion, cleanup, and application migration verification."
}

# This test needs to monitor cluster's status, which is a root operation, use root cert
check_certificates() {
    [[ -f "$ROOT/certs/root/client.root.crt" && -f "$ROOT/certs/root/client.root.key" ]] || {
        echo "Client certificates are missing; generate them before running the tests." >&2
        exit 1
    }
}

# Run the CockroachDB CLI in a short-lived container on the runner's
# network namespace. This allows connections to either localhost or a
# remote guest IP while keeping the root client key on the runner.
run_cli() {
    docker run --rm --network host \
        -v "$ROOT/certs/root:/cockroach-certs:ro" \
        "$IMAGE" "$@"
}

wait_for_cluster() {
    echo "Checking CockroachDB cluster at $COCKROACH_HOST..."

    local node_count=0
    local node_status=""

    # Wait for all three nodes to become visible and live.
    for attempt in $(seq 1 60); do
        if node_status="$(run_cli node status \
            --ranges \
            --certs-dir=/cockroach-certs \
            --host="$COCKROACH_HOST" \
            --format=tsv 2>&1)"; then

            node_count="$(printf '%s\n' "$node_status" |
                awk -F '\t' '
                    NR == 1 {
                        for (i = 1; i <= NF; i++) {
                            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
                            if ($i == "id") id_col = i
                            if ($i == "is_live") live_col = i
                        }
                        next
                    }
                    id_col && live_col &&
                    $id_col ~ /^[[:space:]]*[0-9]+[[:space:]]*$/ {
                        live = $live_col
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", live)
                        if (tolower(live) == "true") n++
                    }
                    END {
                        if (!id_col || !live_col) exit 2
                        print n+0
                    }')"

            if [[ "$node_count" -eq 3 ]]; then
                break
            fi
        fi

        echo "Waiting for all 3 nodes (attempt $attempt/60; currently $node_count)..."
        sleep 5
    done

    printf '%s\n' "$node_status"

    if [[ "$node_count" -ne 3 ]]; then
        echo "Expected exactly 3 live nodes; node status reported $node_count." >&2
        exit 1
    fi
}

test_database_operations() {
    local setup_sql
    local result

    setup_sql=$(cat <<'SQL'
CREATE DATABASE IF NOT EXISTS ci_test;
CREATE SCHEMA IF NOT EXISTS ci_test.workflow_test;
CREATE TABLE IF NOT EXISTS ci_test.workflow_test.records (
    id INT PRIMARY KEY,
    payload STRING NOT NULL,
    amount INT NOT NULL
);
DELETE FROM ci_test.workflow_test.records;
UPSERT INTO ci_test.workflow_test.records (id, payload, amount) VALUES
    (1, 'alpha', 10),
    (2, 'bravo', 20),
    (3, 'charlie', 30);
SQL
)

    run_cli sql \
        --certs-dir=/cockroach-certs \
        --host="$COCKROACH_HOST" \
        --format=tsv \
        --execute="$setup_sql"

    result="$(run_cli sql \
        --certs-dir=/cockroach-certs \
        --host="$COCKROACH_HOST" \
        --format=tsv \
        --execute="SELECT CASE WHEN count(*) = 3 AND sum(amount) = 60 AND count(DISTINCT payload) = 3 THEN 'CI_DB_TEST_OK' ELSE 'CI_DB_TEST_FAILED' END AS result FROM ci_test.workflow_test.records;")"

    printf '%s\n' "$result"

    grep -q 'CI_DB_TEST_OK' <<<"$result" || {
        echo "SQL read-after-write assertion failed." >&2
        exit 1
    }

    run_cli sql \
        --certs-dir=/cockroach-certs \
        --host="$COCKROACH_HOST" \
        --execute='SHOW TABLES FROM ci_test.workflow_test;'
}

cleanup_test_table() {
    echo "Removing test table..."

    run_cli sql \
        --certs-dir=/cockroach-certs \
        --host="$COCKROACH_HOST" \
        --execute='DROP TABLE IF EXISTS ci_test.workflow_test.records;'
}

verify_application_schema() {
    local result

    echo "Verifying application migration..."

    result="$(run_cli sql \
        --certs-dir=/cockroach-certs \
        --host="$COCKROACH_HOST" \
        --format=tsv \
        --execute="SELECT CASE WHEN EXISTS (
            SELECT 1
            FROM [SHOW TABLES FROM ${COCKROACH_DATABASE}.public]
            WHERE table_name = 'users'
        ) THEN 'USERS_TABLE_EXISTS' ELSE 'USERS_TABLE_MISSING' END AS result;")"

    printf '%s\n' "$result"

    grep -q 'USERS_TABLE_EXISTS' <<<"$result" || {
        echo "Expected table '${COCKROACH_DATABASE}.public.users' was not found. Have migrations been applied?" >&2
        exit 1
    }
}

main "$@"
