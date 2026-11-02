#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

main() {
    if (( $# > 1 )); then
        echo "Usage: $0 [output-dir]" >&2
        exit 1
    fi

    cert_init "${1:-./cockroach-certs}"

    local ca_cert_dir="$CERT_OUTPUT_DIR/certs/ca"
    local ca_key_dir="$CERT_OUTPUT_DIR/secrets"
    local ca_cert="$ca_cert_dir/ca.crt"
    local ca_key="$ca_key_dir/ca.key"

    cert_check_not_exists "$ca_cert"
    cert_check_not_exists "$ca_key"

    mkdir -p "$ca_cert_dir" "$ca_key_dir"
    chmod 700 "$ca_key_dir"

    echo "Generating common CA..."

    cert_run cert create-ca \
        --certs-dir=/work/certs/ca \
        --ca-key=/work/secrets/ca.key

    [[ -f "$ca_cert" && -f "$ca_key" ]] || {
        echo "Error: CA generation failed." >&2
        exit 1
    }

    chmod 644 "$ca_cert"
    chmod 600 "$ca_key"

    echo "CA generated successfully."
    echo "Certificate: $ca_cert"
    echo "Private key: $ca_key"
}

main "$@"