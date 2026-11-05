#!/usr/bin/env bash
# HAProxy for the CockroachDB cluster: haproxy-lb-setup.sh with database defaults.
#
# Usage:
#   haproxy-db-setup.sh <lb-vm> [options] <node-ip>...
#
# Defaults (override by passing the same option again, last one wins):
#   --service-name psql
#   --listen-port 26257 --backend-port 26257    SQL port
#   --health-path '/health?ready=1' --health-port 8080
#   --tcp-check                                 plain TCP check instead
#
# All other options and the stdout contract are those of haproxy-lb-setup.sh.
#
# Example:
#   bash haproxy-db-setup.sh db-lb --prefix db_lb "$IP1" "$IP2" >> "$GITHUB_OUTPUT"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/haproxy-lb-setup.sh" \
  --service-name psql \
  --listen-port 26257 \
  --backend-port 26257 \
  --health-path '/health?ready=1' \
  --health-port 8080 \
  "$@"
