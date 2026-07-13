#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

pacman_install "$ENIGMA_ROOT/packages/core.txt"
aur_install "$ENIGMA_ROOT/packages/core-aur.txt"
