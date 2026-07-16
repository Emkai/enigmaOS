#!/bin/bash
# Shared helpers, sourced by install.sh and every stage script.

log() { printf '\033[1;34m[enigmaOS]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[enigmaOS] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Strip comments/blank lines from a package or service list file.
pkg_list() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    grep -vE '^\s*#|^\s*$' "$f"
}

pacman_install() {
    local f="$1" pkgs
    pkgs=$(pkg_list "$f")
    [[ -n "$pkgs" ]] || return 0
    log "pacman -S --needed: $(basename "$f")"
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm $pkgs
}

aur_install() {
    local f="$1" pkgs
    pkgs=$(pkg_list "$f")
    [[ -n "$pkgs" ]] || return 0
    command -v yay &>/dev/null || die "yay not found — did stages/00-bootstrap-yay.sh run?"
    log "yay -S --needed: $(basename "$f")"
    log "(AUR packages compile from source — long silent stretches are normal)"
    # shellcheck disable=SC2086
    yay -S --needed --noconfirm $pkgs
}

clone_or_pull() {
    local url="$1" dest="$2"
    if [[ -d "$dest/.git" ]]; then
        log "Updating $dest"
        git -C "$dest" pull --ff-only
    else
        log "Cloning $url -> $dest"
        mkdir -p "$(dirname "$dest")"
        git clone "$url" "$dest"
    fi
}

svc_enable() {
    systemctl is-enabled --quiet "$1" 2>/dev/null && return 0
    log "systemctl enable $1"
    sudo systemctl enable "$1"
}

svc_enable_user() {
    systemctl --user is-enabled --quiet "$1" 2>/dev/null && return 0
    log "systemctl --user enable $1"
    systemctl --user enable "$1"
}
