#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

grep -q '^ParallelDownloads = 20$' /etc/pacman.conf && { log "pacman ParallelDownloads already 20"; exit 0; }

log "Setting pacman ParallelDownloads = 20"
sudo sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 20/' /etc/pacman.conf
grep -q '^ParallelDownloads' /etc/pacman.conf || sudo sed -i '/^\[options\]/a ParallelDownloads = 20' /etc/pacman.conf
