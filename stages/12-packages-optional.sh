#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

for tier in $ENIGMA_EXTRAS; do
    native="$ENIGMA_ROOT/packages/optional/$tier.txt"
    aur="$ENIGMA_ROOT/packages/optional/$tier-aur.txt"
    if [[ ! -f "$native" && ! -f "$aur" ]]; then
        log "Unknown optional tier '$tier', skipping"
        continue
    fi
    pacman_install "$native"
    aur_install "$aur"
done
