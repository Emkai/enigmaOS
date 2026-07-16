#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

while read -r svc; do
    svc_enable "$svc" "$ENIGMA_ROOT/services/system.txt"
done < <(pkg_list "$ENIGMA_ROOT/services/system.txt")

while read -r svc; do
    svc_enable_user "$svc" "$ENIGMA_ROOT/services/user.txt"
done < <(pkg_list "$ENIGMA_ROOT/services/user.txt")

current=$(systemctl get-default)
if [[ "$current" != "graphical.target" ]]; then
    log "Setting default target to graphical.target"
    sudo systemctl set-default graphical.target
fi
