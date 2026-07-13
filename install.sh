#!/bin/bash
# Entrypoint: run every stage in stages/ in filename order.
# Usage: ./install.sh [--gpu=intel,nvidia] [--extras="embedded extras"] [--from=20]
set -euo pipefail

ENIGMA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$ENIGMA_ROOT/lib/common.sh"
source "$ENIGMA_ROOT/config.sh"

ENIGMA_FROM_STAGE=""

for arg in "$@"; do
    case "$arg" in
        --gpu=*)    GPU_VENDORS="${arg#*=}" ;;
        --extras=*) ENIGMA_EXTRAS="${arg#*=}" ;;
        --from=*)   ENIGMA_FROM_STAGE="${arg#*=}" ;;
        *) die "unknown flag: $arg" ;;
    esac
done

export ENIGMA_ROOT GPU_VENDORS CPU_VENDOR ENIGMA_EXTRAS

for stage in "$ENIGMA_ROOT"/stages/*.sh; do
    name=$(basename "$stage")
    prefix="${name%%-*}"
    if [[ -n "$ENIGMA_FROM_STAGE" && "$prefix" < "$ENIGMA_FROM_STAGE" ]]; then
        continue
    fi
    log "=== $name ==="
    bash "$stage"
done
