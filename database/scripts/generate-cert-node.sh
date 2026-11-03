#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

main() {
    if (( $# < 4 || $# > 5 )); then
        echo "Usage: $0 <output-dir> <node-name> <dns-name> <ip-address> [lb-ip]" >&2
        exit 1
    fi

    local output_dir="$1"
    local node_name="$2"
    local dns_name="$3"
    local ip_address="$4"
    local lb_ip="${5:-}"

    cert_validate_identity "$node_name"
    cert_init "$output_dir"
    cert_check_ca

    local node_dir="$CERT_OUTPUT_DIR/certs/$node_name"

    cert_check_not_exists "$node_dir/node.crt"
    cert_check_not_exists "$node_dir/node.key"

    mkdir -p "$node_dir"
    cp "$CERT_OUTPUT_DIR/certs/ca/ca.crt" "$node_dir/ca.crt"

    echo "Generating node certificate: $node_name"

    local hosts=(
        "$node_name"
        "$dns_name"
        "localhost"
        "$ip_address"
    )

    if [[ -n "$lb_ip" ]]; then
        hosts+=("$lb_ip")
    fi

    cert_run cert create-node \
        "${hosts[@]}" \
        --certs-dir="/work/certs/$node_name" \
        --ca-key=/work/secrets/ca.key

    [[ -f "$node_dir/node.crt" && -f "$node_dir/node.key" ]] || {
        echo "Error: Node certificate generation failed." >&2
        exit 1
    }

    chmod 644 "$node_dir/ca.crt" "$node_dir/node.crt"
    chmod 600 "$node_dir/node.key"

    echo "Node certificate generated: $node_dir"
}

main "$@"