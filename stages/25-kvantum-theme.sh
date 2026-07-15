#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

# Kvantum has no ready-made Tokyo Night theme (checked AUR — none exists).
# TokyoNight.kvconfig (tracked in configs/kvantum/) recolors whichever
# bundled flat/dark base theme is available via its own palette-override
# keys; only the base theme's SVG asset needs copying in, since it's not
# committed to git (varies by kvantum package version/layout).

target_dir="$HOME/.config/Kvantum/TokyoNight"
svg_target="$target_dir/TokyoNight.svg"

if [[ -f "$svg_target" ]]; then
    log "Kvantum TokyoNight.svg already present, skipping"
    exit 0
fi

if [[ ! -d "$target_dir" ]]; then
    log "$target_dir missing — did stages/20-stow-dotfiles.sh run? Skipping Kvantum SVG setup"
    exit 0
fi

candidates=(KvArcDark KvGnomeDark KvDark KvAdaptaDark KvFlat KvAmbiance)
base_dir="/usr/share/Kvantum"
found=""

for name in "${candidates[@]}"; do
    if [[ -f "$base_dir/$name/$name.svg" ]]; then
        found="$base_dir/$name/$name.svg"
        break
    fi
done

if [[ -z "$found" ]]; then
    log "No known bundled Kvantum base theme found under $base_dir — falling back to Kvantum's default style (no custom SVG copied)"
    exit 0
fi

log "Using $found as the Tokyo Night Kvantum base SVG"
install -m644 "$found" "$svg_target"
