#!/usr/bin/env bash
# Re-run a command until it succeeds or a timeout expires.
#
# Usage:
#   wait-for.sh [--timeout SEC] [--interval SEC] [--desc TEXT] -- <command...>
#
# Defaults: --timeout 60, --interval 2.
# Exit status: 0 once the command succeeds, 1 on timeout (last output is
# printed to stderr). The command must be a real executable here; scripts that
# source lib.sh can call the `wait_for` function directly instead.
#
# Example:
#   wait-for.sh --timeout 30 --interval 1 --desc "HAProxy listener" -- \
#     bash -c '</dev/tcp/10.0.0.5/26257'

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

TIMEOUT=60
INTERVAL=2
DESC=""

while (($#)); do
  case "$1" in
    --timeout)  opt_val "$@"; TIMEOUT=$2;  shift 2 ;;
    --interval) opt_val "$@"; INTERVAL=$2; shift 2 ;;
    --desc)     opt_val "$@"; DESC=$2;     shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    --)         shift; break ;;
    *)          die "unexpected argument: $1 (put the command after --)" ;;
  esac
done

(($# > 0)) || { usage; exit 2; }
DESC="${DESC:-$*}"

log "Waiting for: $DESC (timeout ${TIMEOUT}s, every ${INTERVAL}s)"
if wait_for "$TIMEOUT" "$INTERVAL" "$@"; then
  log "Ready: $DESC"
else
  log "Timed out after ${TIMEOUT}s: $DESC"
  if [[ -n "$WAIT_FOR_LAST_OUTPUT" ]]; then
    log "Last output:"
    printf '%s\n' "$WAIT_FOR_LAST_OUTPUT" >&2
  fi
  exit 1
fi
