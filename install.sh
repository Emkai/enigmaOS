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

# Long stages (AUR builds) outlive sudo's cached credentials, and a password
# prompt buried mid-build times out after 5 minutes and kills the run. Ask
# once up front and keep the timestamp fresh. No-op under NOPASSWD.
if ! sudo -n true 2>/dev/null; then
    log "sudo is needed for package installs — asking once up front."
    sudo -v || die "sudo authentication failed"
fi
( while sleep 60; do sudo -n -v 2>/dev/null || exit; done ) &
sudo_keepalive=$!
trap 'kill "$sudo_keepalive" 2>/dev/null' EXIT

for stage in "$ENIGMA_ROOT"/stages/*.sh; do
    name=$(basename "$stage")
    prefix="${name%%-*}"
    if [[ -n "$ENIGMA_FROM_STAGE" && "$prefix" < "$ENIGMA_FROM_STAGE" ]]; then
        continue
    fi
    log "=== $name ==="
    bash "$stage"
done
