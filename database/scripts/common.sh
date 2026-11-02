#!/usr/bin/env bash

COCKROACH_IMAGE="${COCKROACH_IMAGE:-cockroachdb/cockroach:v26.2.2}"

cert_init() {
    command -v docker >/dev/null 2>&1 || {
        echo "Error: docker is required." >&2
        return 1
    }

    local output_dir="$1"

    mkdir -p "$output_dir"
    CERT_OUTPUT_DIR="$(cd "$output_dir" && pwd)"
}

cert_run() {
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$CERT_OUTPUT_DIR:/work" \
        "$COCKROACH_IMAGE" \
        "$@"
}

cert_check_ca() {
    [[ -f "$CERT_OUTPUT_DIR/certs/ca/ca.crt" ]] || {
        echo "Error: CA certificate not found." >&2
        return 1
    }

    [[ -f "$CERT_OUTPUT_DIR/secrets/ca.key" ]] || {
        echo "Error: CA private key not found." >&2
        return 1
    }
}

cert_validate_identity() {
    local identity="$1"

    if [[ ! "$identity" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "Error: Invalid identity: $identity" >&2
        return 1
    fi
}

cert_check_not_exists() {
    local path="$1"

    if [[ -e "$path" ]]; then
        echo "Error: Already exists: $path" >&2
        echo "Refusing to overwrite existing certificate files." >&2
        return 1
    fi
}