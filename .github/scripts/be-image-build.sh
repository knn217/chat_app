#!/usr/bin/env bash
# Build the backend docker image with docker compose and save it as a tar file.
# Needs only Docker (Dockerfile.backend compiles the Rust code itself).
#
# Usage:
#   be-image-build.sh --out PATH [--compose-file docker-compose.backend.yml]
#                     [--image backend_img:latest] [--prune]
#
#   --out       tar file to write (parent directories are created)
#   --prune     afterwards remove the build cache and unused images, to give
#               disk space back (useful on CI runners; the tar is kept)
#
# stdout: BE_IMAGE  BE_IMAGE_TAR  BE_IMAGE_TAR_BYTES
# stderr: logs and docker output.
#
# Example:
#   bash be-image-build.sh --out "$RUNNER_TEMP/be-image/backend-image.tar" --prune

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

OUT=""
COMPOSE_FILE=docker-compose.backend.yml
IMAGE=backend_img:latest
PRUNE=false

while (($#)); do
  case "$1" in
    --out)          opt_val "$@"; OUT=$2;          shift 2 ;;
    --compose-file) opt_val "$@"; COMPOSE_FILE=$2; shift 2 ;;
    --image)        opt_val "$@"; IMAGE=$2;        shift 2 ;;
    --prune)        PRUNE=true; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "unknown argument: $1" ;;
  esac
done

[[ -n "$OUT" ]] || { usage; die "--out is required"; }
[[ -f "$COMPOSE_FILE" ]] || die "compose file not found: $COMPOSE_FILE"
have docker || die "docker is not installed"

mkdir -p "$(dirname "$OUT")"

log "Building backend image via $COMPOSE_FILE ..."
docker compose -f "$COMPOSE_FILE" build >&2

log "Saving $IMAGE to $OUT ..."
docker save -o "$OUT" "$IMAGE" >&2
[[ -s "$OUT" ]] || die "image tar is empty: $OUT"

bytes=$(stat -c %s "$OUT")
log "Saved $(numfmt --to=iec "$bytes" 2>/dev/null || echo "$bytes bytes")"

if [[ "$PRUNE" == true ]]; then
  log "Pruning build cache and unused images..."
  docker builder prune -af >&2 || true
  docker image prune -af >&2 || true
fi

emit BE_IMAGE           "$IMAGE"
emit BE_IMAGE_TAR       "$OUT"
emit BE_IMAGE_TAR_BYTES "$bytes"
