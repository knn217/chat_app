#!/usr/bin/env bash
# Send a file or directory into a Multipass VM using `multipass transfer`.
#
# Usage:
#   multipass-send.sh <vm> <src> <dest-dir>
#
#   <src> is a directory : its CONTENTS are copied into <dest-dir>
#                          (like `cp -a src/. dest-dir/`)
#   <src> is a file      : it is copied into <dest-dir> under its own name
#   <dest-dir>           : absolute path inside the VM; created if missing.
#                          Existing directory permissions are left untouched.
#
# Files end up owned by root (extracted with sudo, --no-same-owner) and keep
# the file modes of the source, so private keys stay 0600.
#
# Examples:
#   multipass-send.sh db-node1 database/certs/node1 /opt/crdb-deploy/node-certs
#   multipass-send.sh db-lb "$tmp/haproxy.cfg" /etc/haproxy

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

if (($# == 1)) && [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi
(($# == 3)) || { usage; exit 2; }

VM=$1
SRC=$2
DEST=$3

[[ -e "$SRC" ]] || die "source does not exist: $SRC"
[[ "$DEST" == /* ]] || die "destination must be an absolute path inside the VM: $DEST"

# The Multipass snap is confined and has its own private /tmp, so the archive
# must live somewhere it can read: $RUNNER_TEMP in CI, otherwise $HOME
# (non-hidden directory; snap home access excludes dot-directories).
tmp=$(mktemp -d -p "${RUNNER_TEMP:-$HOME}" multipass-send.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
archive="$tmp/payload.tgz"
remote="/tmp/multipass-send.$RANDOM$RANDOM.tgz"

if [[ -d "$SRC" ]]; then
  tar -C "$SRC" -czf "$archive" .
else
  tar -C "$(dirname "$SRC")" -czf "$archive" "$(basename "$SRC")"
fi

log "Sending $SRC -> $VM:$DEST"
mp transfer "$archive" "$VM:$remote" >&2

mp exec "$VM" -- sudo bash -s -- "$remote" "$DEST" >&2 <<'EOS'
set -Eeuo pipefail
archive=$1
dest=$2
mkdir -p "$dest"
tar -xzf "$archive" -C "$dest" --no-same-owner --no-overwrite-dir
rm -f "$archive"
EOS