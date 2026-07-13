#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

# Only relevant if steam (which needs multilib) is in a selected extras tier.
grep -q '^steam$' "$ENIGMA_ROOT/packages/optional/extras.txt" 2>/dev/null || exit 0
[[ " $ENIGMA_EXTRAS " == *" extras "* ]] || exit 0

grep -q '^\[multilib\]' /etc/pacman.conf && { log "multilib already enabled"; exit 0; }

log "Enabling [multilib] in /etc/pacman.conf"
sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
sudo pacman -Sy
