#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

command -v yay &>/dev/null && { log "yay already installed"; exit 0; }

# The install ISO bakes a pre-built yay into its offline repo — installing
# that beats a multi-minute Go compile. Falls through to the AUR build when
# no configured repo provides yay (plain non-ISO runs).
if pacman -Si yay &>/dev/null; then
    log "Installing pre-built yay from a configured repo."
    sudo pacman -S --needed --noconfirm yay && exit 0
    warn "repo install of yay failed — building it from the AUR instead."
fi

sudo pacman -S --needed --noconfirm base-devel git

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

git clone https://aur.archlinux.org/yay.git "$build_dir/yay"
log "Building yay from AUR. The Go compile prints nothing for several minutes — not hung, just quiet."
(cd "$build_dir/yay" && makepkg -si --noconfirm)
log "yay built and installed."
