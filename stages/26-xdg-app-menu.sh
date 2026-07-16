#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

# KDE apps outside Plasma (Dolphin on Hyprland) build their application
# database (ksycoca) from an XDG menu file selected by XDG_MENU_PREFIX.
# Hyprland sets XDG_MENU_PREFIX=hyprland- at startup, but nothing ships a
# hyprland-applications.menu, so the database ends up empty: Open With
# menus show no apps and double-clicking files silently does nothing.
# archlinux-xdg-menu (installed in 10-packages-core.sh) provides
# arch-applications.menu; symlink the names KDE will actually look for
# onto it, then rebuild the database.

menus_dir="/etc/xdg/menus"
arch_menu="$menus_dir/arch-applications.menu"

if [[ ! -f "$arch_menu" ]]; then
    log "archlinux-xdg-menu not installed ($arch_menu missing), skipping XDG app menu setup"
    exit 0
fi

log "Linking hyprland-/default applications.menu to arch-applications.menu"
sudo ln -sfn arch-applications.menu "$menus_dir/hyprland-applications.menu"
sudo ln -sfn arch-applications.menu "$menus_dir/applications.menu"

if command -v kbuildsycoca6 >/dev/null 2>&1; then
    log "Rebuilding KDE application database (kbuildsycoca6)"
    kbuildsycoca6 >/dev/null 2>&1 || true
fi
