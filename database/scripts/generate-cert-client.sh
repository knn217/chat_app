#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

main() {
    if (( $# != 2 )); then
        echo "Usage: $0 <output-dir> <username>" >&2
        exit 1
    fi

    local output_dir="$1"
    local username="$2"

    cert_validate_identity "$username"
    cert_init "$output_dir"
    cert_check_ca

    command -v openssl >/dev/null 2>&1 || {
        echo "Error: openssl is required." >&2
        exit 1
    }

    local client_dir="$CERT_OUTPUT_DIR/certs/$username"
    local client_cert="$client_dir/client.$username.crt"
    local client_key="$client_dir/client.$username.key"
    local client_pem="$client_dir/client.$username.pem"

    cert_check_not_exists "$client_cert"
    cert_check_not_exists "$client_key"
    cert_check_not_exists "$client_pem"

    mkdir -p "$client_dir"
    cp "$CERT_OUTPUT_DIR/certs/ca/ca.crt" "$client_dir/ca.crt"

    echo "Generating client certificate: $username"

    cert_run cert create-client "$username" \
        --certs-dir=/work/certs/$username \
        --ca-key=/work/secrets/ca.key

    [[ -f "$client_cert" && -f "$client_key" ]] || {
        echo "Error: Client certificate generation failed." >&2
        exit 1
    }

    echo "Converting client private key to PKCS#8 PEM..."

    openssl pkcs8 \
        -topk8 \
        -inform PEM \
        -outform PEM \
        -in "$client_key" \
        -out "$client_pem" \
        -nocrypt

    chmod 644 "$client_dir/ca.crt" "$client_cert"
    chmod 600 "$client_key" "$client_pem"

    echo "Client certificate generated: $client_dir"
}

main "$@"