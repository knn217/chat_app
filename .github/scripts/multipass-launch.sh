#!/usr/bin/env bash
# Launch (or reuse) a Multipass VM and print its handle as KEY=VALUE lines.
#
# Usage:
#   multipass-launch.sh <name> [--image 24.04] [--cpus 1] [--memory 2G]
#                              [--disk 6G] [--timeout 900] [--prefix PFX]
#
# stdout (PFX defaults to the upper-cased VM name, e.g. db-node1 -> DB_NODE1):
#   PFX_NAME  PFX_IP  PFX_ALL_IPS  PFX_STATE  PFX_USER  PFX_IMAGE
#   PFX_RELEASE  PFX_CPUS  PFX_MEMORY_TOTAL  PFX_DISK_TOTAL
# stderr: logs and multipass output.
#
# Example:
#   bash multipass-launch.sh db-node1 --prefix node1 >> "$GITHUB_OUTPUT"
#   eval "$(bash multipass-launch.sh db-node1 --prefix node1)"; echo "$NODE1_IP"

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

NAME=""
IMAGE=24.04
CPUS=1
MEMORY=2G
DISK=6G
TIMEOUT=900
PREFIX=""

while (($#)); do
  case "$1" in
    --image)   opt_val "$@"; IMAGE=$2;   shift 2 ;;
    --cpus)    opt_val "$@"; CPUS=$2;    shift 2 ;;
    --memory)  opt_val "$@"; MEMORY=$2;  shift 2 ;;
    --disk)    opt_val "$@"; DISK=$2;    shift 2 ;;
    --timeout) opt_val "$@"; TIMEOUT=$2; shift 2 ;;
    --prefix)  opt_val "$@"; PREFIX=$2;  shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)        die "unknown option: $1" ;;
    *)         [[ -z "$NAME" ]] || die "unexpected argument: $1"; NAME=$1; shift ;;
  esac
done

[[ -n "$NAME" ]] || { usage; exit 2; }
PFX=$(to_key "${PREFIX:-$NAME}")

# Field from `multipass info`; prints "unknown" when jq is missing or the
# field is absent. Usage: info_field '<jq filter>'
info_field() {
  if ! have jq; then echo unknown; return 0; fi
  mp info "$NAME" --format json 2>/dev/null \
    | jq -r --arg n "$NAME" ".info[\$n] | ($1) // \"unknown\"" 2>/dev/null \
    || echo unknown
}

if mp info "$NAME" >/dev/null 2>&1; then
  state=$(info_field '.state')
  log "VM $NAME already exists (state: $state); reusing it, launch options ignored"
  if [[ "$state" != "Running" ]]; then
    mp start "$NAME" >&2
  fi
else
  log "Launching $NAME (image $IMAGE, $CPUS cpu, $MEMORY ram, $DISK disk)..."
  mp launch "$IMAGE" \
    --name "$NAME" \
    --cpus "$CPUS" \
    --memory "$MEMORY" \
    --disk "$DISK" \
    --timeout "$TIMEOUT" >&2
fi

have_ip() { [[ -n "$(vm_ip "$NAME")" ]]; }
wait_for 120 2 have_ip || die "could not obtain an IP for $NAME"
IP=$(vm_ip "$NAME")
log "$NAME = $IP"

emit "${PFX}_NAME"         "$NAME"
emit "${PFX}_IP"           "$IP"
emit "${PFX}_ALL_IPS"      "$(info_field '.ipv4 | join(",")')"
emit "${PFX}_STATE"        "$(info_field '.state')"
emit "${PFX}_USER"         "$VM_USER"
emit "${PFX}_IMAGE"        "$IMAGE"
emit "${PFX}_RELEASE"      "$(info_field '.release')"
emit "${PFX}_CPUS"         "$(info_field '.cpu_count')"
emit "${PFX}_MEMORY_TOTAL" "$(info_field '.memory.total')"
emit "${PFX}_DISK_TOTAL"   "$(info_field '(.disks // {}) | to_entries | .[0].value.total')"
