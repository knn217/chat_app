#!/usr/bin/env bash
# Install and configure HAProxy as a TCP load balancer on an existing
# Multipass VM. Not specific to any service: the database and the backend
# clusters both use it (see haproxy-db-setup.sh for the database defaults).
#
# Usage:
#   haproxy-lb-setup.sh <lb-vm> --backend-port N [options] <backend-ip>...
#
# Options:
#   --backend-port N    port every backend listens on          (required)
#   --listen-port N     port HAProxy listens on     (default: the backend port)
#   --service-name S    name of the HAProxy listen section     (default: app)
#   --health-path P     HTTP health check "GET P"   (default: plain TCP check)
#   --health-port N     port used for the health check (default: the backend port)
#   --tcp-check         force a plain TCP check (clears --health-path/--health-port)
#   --skip-install      do not install HAProxy (an earlier run already did);
#                       the config is still rendered again and HAProxy reloaded
#   --prefix PFX        KEY prefix for stdout (default: upper-cased VM name)
#
# Options may be repeated; the last occurrence wins.
#
# stdout:
#   PFX_NAME  PFX_IP  PFX_PORT  PFX_ENDPOINT  PFX_BACKENDS  PFX_CHECK
# stderr: logs.
#
# Example (backend API on port 8090, HTTP health route):
#   bash haproxy-lb-setup.sh be-lb --prefix be_lb --backend-port 8090 \
#     --service-name api --health-path /api/v1/auth/me "$IP1" "$IP2" >> "$GITHUB_OUTPUT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

LB=""
BACKEND_PORT=""
LISTEN_PORT=""
HEALTH_PORT=""
HEALTH_PATH=""
SERVICE=app
PREFIX=""
SKIP_INSTALL=0
BACKENDS=()

while (($#)); do
  case "$1" in
    --backend-port) opt_val "$@"; BACKEND_PORT=$2; shift 2 ;;
    --listen-port)  opt_val "$@"; LISTEN_PORT=$2;  shift 2 ;;
    --service-name) opt_val "$@"; SERVICE=$2;      shift 2 ;;
    --health-path)  opt_val "$@"; HEALTH_PATH=$2;  shift 2 ;;
    --health-port)  opt_val "$@"; HEALTH_PORT=$2;  shift 2 ;;
    --prefix)       opt_val "$@"; PREFIX=$2;       shift 2 ;;
    --tcp-check)    HEALTH_PATH=""; HEALTH_PORT=""; shift ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    -*)             die "unknown option: $1" ;;
    *)
      if [[ -z "$LB" ]]; then LB=$1; else BACKENDS+=("$1"); fi
      shift
      ;;
  esac
done

[[ -n "$LB" ]] || { usage; exit 2; }
[[ -n "$BACKEND_PORT" ]] || die "--backend-port is required"
((${#BACKENDS[@]} > 0)) || die "at least one backend IP is required"
LISTEN_PORT="${LISTEN_PORT:-$BACKEND_PORT}"
PFX=$(to_key "${PREFIX:-$LB}")
CHECK=tcp
[[ -z "$HEALTH_PATH" ]] || CHECK=http

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

listen ${SERVICE}
    bind *:${LISTEN_PORT}
    mode tcp
    balance roundrobin
EOF
  if [[ "$CHECK" == http ]]; then
    echo "    option httpchk GET ${HEALTH_PATH}"
  fi
  local i=0 ip check_opts
  for ip in "${BACKENDS[@]}"; do
    i=$((i + 1))
    check_opts=check
    if [[ -n "$HEALTH_PORT" ]]; then
      check_opts="check port ${HEALTH_PORT}"
    fi
    printf '    server %s%d %s:%s %s\n' "$SERVICE" "$i" "$ip" "$BACKEND_PORT" "$check_opts"
  done
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/conf"

if ((SKIP_INSTALL)); then
  log "Skipping HAProxy install on $LB"
else
  log "Installing HAProxy on $LB..."
  mp exec "$LB" -- sudo bash -c \
    'export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y haproxy' >&2
fi

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
  systemctl reload-or-restart haproxy
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

backend_list=""
for ip in "${BACKENDS[@]}"; do
  backend_list+="${backend_list:+,}$ip:$BACKEND_PORT"
done

emit "${PFX}_NAME"     "$LB"
emit "${PFX}_IP"       "$LB_IP"
emit "${PFX}_PORT"     "$LISTEN_PORT"
emit "${PFX}_ENDPOINT" "$LB_IP:$LISTEN_PORT"
emit "${PFX}_BACKENDS" "$backend_list"
emit "${PFX}_CHECK"    "$CHECK"