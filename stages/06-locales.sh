#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

# Locales the dotfiles need beyond the system default. waybar's clock
# (configs/waybar) renders its calendar and the ISO week number with
# sv_SE.UTF-8 — if it isn't generated, both silently break.
NEEDED=("sv_SE.UTF-8 UTF-8")

changed=0
for entry in "${NEEDED[@]}"; do
    name="${entry%% *}"
    pattern="${name//./\\.}"
    grep -q "^$pattern " /etc/locale.gen && continue
    log "Enabling locale $name in /etc/locale.gen"
    if grep -q "^#\s*$pattern " /etc/locale.gen; then
        sudo sed -i "s/^#\s*\($pattern \)/\1/" /etc/locale.gen
    else
        echo "$entry" | sudo tee -a /etc/locale.gen >/dev/null
    fi
    changed=1
done

if [[ "$changed" == 1 ]]; then
    sudo locale-gen
else
    log "all required locales already generated"
fi
