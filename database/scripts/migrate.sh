#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

COCKROACH_HOST="${COCKROACH_HOST:-127.0.0.1:26257}"
COCKROACH_DATABASE="${COCKROACH_DATABASE:-chat_db}"
CLIENT_CERTS="${CLIENT_CERTS:-$ROOT/certs/client}"

JDBC_OPTIONS="sslmode=verify-full&sslrootcert=${CLIENT_CERTS}/ca.crt&sslcert=${CLIENT_CERTS}/client.root.crt&sslkey=${CLIENT_CERTS}/client.root.pem"

main() {
    check_dependencies
    create_database
    run_migrations
}

check_dependencies() {
    command -v flyway >/dev/null 2>&1 || {
        echo "Flyway CLI is required" >&2
        exit 1
    }
}

create_database() {
    echo "Ensuring database '$COCKROACH_DATABASE' exists..."

    flyway \
        "-url=jdbc:postgresql://${COCKROACH_HOST}/defaultdb?${JDBC_OPTIONS}" \
        -user=root \
        "-locations=filesystem:${ROOT}/bootstrap" \
        -executeInTransaction=false \
        migrate
}

run_migrations() {
    echo "Applying application migrations..."

    flyway \
        "-url=jdbc:postgresql://${COCKROACH_HOST}/${COCKROACH_DATABASE}?${JDBC_OPTIONS}" \
        -user=root \
        "-locations=filesystem:${ROOT}/migrations" \
        migrate
}

main "$@"