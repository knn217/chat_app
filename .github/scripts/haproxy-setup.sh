#!/usr/bin/env bash
# Install and configure HAProxy as a TCP load balancer in front of CockroachDB
# nodes, on an existing Multipass VM. Prints the load balancer handle.
#
# Usage:
#   haproxy-setup.sh <lb-vm> [options] <backend-ip>...
#
# Options:
#   --listen-port N    port HAProxy listens on          (default 26257)
#   --backend-port N   SQL port on every backend        (default 26257)
#   --health-port N    HTTP port used for health checks (default 8080)
#   --tcp-check        plain TCP check instead of GET /health?ready=1
#   --prefix PFX       KEY prefix for stdout            (default: upper-cased VM name)
#
# stdout:
#   PFX_NAME  PFX_IP  PFX_PORT  PFX_ENDPOINT  PFX_BACKENDS  PFX_CHECK
# stderr: logs.
#
# Example:
#   bash haproxy-setup.sh db-lb --prefix haproxy "$N1" "$N2" "$N3" >> "$GITHUB_OUTPUT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

LB=""
LISTEN_PORT=26257
BACKEND_PORT=26257
HEALTH_PORT=8080
CHECK=http
PREFIX=""
BACKENDS=()

while (($#)); do
  case "$1" in
    --listen-port)  opt_val "$@"; LISTEN_PORT=$2;  shift 2 ;;
    --backend-port) opt_val "$@"; BACKEND_PORT=$2; shift 2 ;;
    --health-port)  opt_val "$@"; HEALTH_PORT=$2;  shift 2 ;;
    --prefix)       opt_val "$@"; PREFIX=$2;       shift 2 ;;
    --tcp-check)    CHECK=tcp; shift ;;
    -h|--help)      usage; exit 0 ;;
    -*)             die "unknown option: $1" ;;
    *)
      if [[ -z "$LB" ]]; then LB=$1; else BACKENDS+=("$1"); fi
      shift
      ;;
  esac
done

[[ -n "$LB" ]] || { usage; exit 2; }
((${#BACKENDS[@]} > 0)) || die "at least one backend IP is required"
PFX=$(to_key "${PREFIX:-$LB}")

# The config mirrors what `cockroach gen haproxy` emits, but is built from the
# explicit backend list instead of querying the cluster.
render_config() {
  cat <<EOF
global
  maxconn 4096

defaults
    mode                tcp
    timeout connect     10s
    timeout client      10m
    timeout server      10m
    option              clitcpka

listen psql
    bind *:${LISTEN_PORT}
    mode tcp
    balance roundrobin
EOF
  if [[ "$CHECK" == http ]]; then
    echo "    option httpchk GET /health?ready=1"
  fi
  local i=0 ip
  for ip in "${BACKENDS[@]}"; do
    i=$((i + 1))
    if [[ "$CHECK" == http ]]; then
      printf '    server cockroach%d %s:%s check port %s\n' \
        "$i" "$ip" "$BACKEND_PORT" "$HEALTH_PORT"
    else
      printf '    server cockroach%d %s:%s check\n' "$i" "$ip" "$BACKEND_PORT"
    fi
  done
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/conf"

log "Installing HAProxy on $LB..."
mp exec "$LB" -- sudo bash -c \
  'export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y haproxy' >&2

log "Rendering config for ${#BACKENDS[@]} backend(s), check: $CHECK"
render_config > "$tmp/conf/haproxy.cfg"
chmod 644 "$tmp/conf/haproxy.cfg"
for ip in "${BACKENDS[@]}"; do
  grep -Fq "$ip:$BACKEND_PORT" "$tmp/conf/haproxy.cfg" || die "backend missing from config: $ip"
done
log "--- haproxy.cfg ---"
cat "$tmp/conf/haproxy.cfg" >&2
log "-------------------"

bash "$SCRIPT_DIR/multipass-send.sh" "$LB" "$tmp/conf" /etc/haproxy

log "Validating and starting HAProxy..."
mp exec "$LB" -- sudo bash -c '
  set -Eeuo pipefail
  haproxy -c -f /etc/haproxy/haproxy.cfg
  systemctl enable haproxy
  systemctl restart haproxy
  systemctl is-active --quiet haproxy
' >&2

dump_diagnostics() {
  mp exec "$LB" -- sudo systemctl status haproxy --no-pager >&2 || true
  mp exec "$LB" -- sudo journalctl -u haproxy -n 100 --no-pager >&2 || true
}

local_listening() {
  mp exec "$LB" -- timeout 2 bash -c "</dev/tcp/127.0.0.1/${LISTEN_PORT}"
}
wait_for 30 1 local_listening || { dump_diagnostics; die "HAProxy is not listening on $LB:$LISTEN_PORT"; }

LB_IP=$(vm_ip "$LB")
[[ -n "$LB_IP" ]] || die "could not obtain IP for $LB"

# Also check from the caller's side: this is the path clients will use.
remote_listening() { timeout 2 bash -c "</dev/tcp/${LB_IP}/${LISTEN_PORT}"; }
wait_for 30 1 remote_listening || { dump_diagnostics; die "HAProxy not reachable at $LB_IP:$LISTEN_PORT"; }

log "HAProxy is up on $LB ($LB_IP:$LISTEN_PORT)"

emit "${PFX}_NAME"     "$LB"
emit "${PFX}_IP"       "$LB_IP"
emit "${PFX}_PORT"     "$LISTEN_PORT"
emit "${PFX}_ENDPOINT" "$LB_IP:$LISTEN_PORT"
backend_list=""
for ip in "${BACKENDS[@]}"; do
  backend_list+="${backend_list:+,}$ip:$BACKEND_PORT"
done

emit "${PFX}_BACKENDS" "$backend_list"
emit "${PFX}_CHECK"    "$CHECK"
