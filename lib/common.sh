#!/bin/bash
# Shared helpers, sourced by install.sh and every stage script.

log()  { printf '\033[1;34m[enigmaOS]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[enigmaOS] WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[enigmaOS] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Package/service failures append here (one TSV line: item, list file, note)
# and are reported by stages/90-summary.sh instead of aborting the install.
# install.sh truncates it at the start of a full run.
ENIGMA_FAILURES="${ENIGMA_FAILURES:-$ENIGMA_ROOT/.install-failures.tsv}"

# Strip comments (full-line and trailing) and blank lines from a package or
# service list file.
pkg_list() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    sed -e 's/[[:space:]]*#.*//' -e '/^[[:space:]]*$/d' "$f"
}

# Feature annotation for a list entry: its trailing "pkg  # note" comment,
# falling back to the section comment above it. The failure report prints
# this, so notes should say what stops working without the package.
pkg_note() {
    local f="$1" pkg="$2"
    [[ -f "$f" ]] || return 0
    awk -v pkg="$pkg" '
        /^[[:space:]]*#/ {
            c = $0; sub(/^[[:space:]]*#[[:space:]]*/, "", c)
            section = prev ? section " " c : c
            prev = 1; next
        }
        { prev = 0 }
        /^[[:space:]]*$/ { next }
        {
            line = $0; inline = ""
            i = index(line, "#")
            if (i) {
                inline = substr(line, i + 1); sub(/^[[:space:]]*/, "", inline)
                line = substr(line, 1, i - 1)
            }
            gsub(/[[:space:]]/, "", line)
            if (line == pkg) { print (inline != "" ? inline : section); exit }
        }
    ' "$f"
}

# Append one failure for the summary report: the item, the list file it came
# from, and that file's feature note for it.
record_failure() {
    local item="$1" src="${2:-}" note=""
    [[ -n "$src" ]] && note=$(pkg_note "$src" "$item")
    printf '%s\t%s\t%s\n' "$item" "${src#"$ENIGMA_ROOT"/}" "$note" >> "$ENIGMA_FAILURES"
}

# After an install attempt, warn about + record anything from the list that
# still isn't present, rather than failing the run.
record_missing() {
    local f="$1" pkg; shift
    local missing=()
    for pkg in "$@"; do
        pacman -Qq "$pkg" &>/dev/null && continue
        missing+=("$pkg")
        record_failure "$pkg" "$f"
    done
    [[ ${#missing[@]} -eq 0 ]] || warn "failed to install: ${missing[*]} (details in the end-of-install summary)"
}

pacman_install() {
    local f="$1" pkgs p
    pkgs=$(pkg_list "$f")
    [[ -n "$pkgs" ]] || return 0
    log "pacman -S --needed: $(basename "$f")"
    # shellcheck disable=SC2086
    if ! sudo pacman -S --needed --noconfirm $pkgs; then
        # pacman aborts the whole transaction over a single bad target, so
        # fall back to one at a time; record_missing reports the casualties.
        for p in $pkgs; do
            pacman -Qq "$p" &>/dev/null && continue
            sudo pacman -S --needed --noconfirm "$p" || true
        done
    fi
    # shellcheck disable=SC2086
    record_missing "$f" $pkgs
}

aur_install() {
    local f="$1" pkgs p
    pkgs=$(pkg_list "$f")
    [[ -n "$pkgs" ]] || return 0
    command -v yay &>/dev/null || die "yay not found — did stages/00-bootstrap-yay.sh run?"
    log "yay -S --needed: $(basename "$f")"
    log "(AUR packages compile from source — long silent stretches are normal)"
    # One target per call: a package whose build breaks (or that vanished
    # from the AUR) only takes itself down, not the rest of the list.
    for p in $pkgs; do
        yay -S --needed --noconfirm "$p" || true
    done
    # shellcheck disable=SC2086
    record_missing "$f" $pkgs
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

# svc_enable <unit> [list file] — the list file feeds the failure report's
# feature note if enabling fails (usually: the owning package didn't install).
svc_enable() {
    systemctl is-enabled --quiet "$1" 2>/dev/null && return 0
    log "systemctl enable $1"
    if ! sudo systemctl enable "$1"; then
        warn "could not enable $1 — did its package fail to install?"
        record_failure "$1" "${2:-}"
    fi
}

svc_enable_user() {
    systemctl --user is-enabled --quiet "$1" 2>/dev/null && return 0
    log "systemctl --user enable $1"
    if ! systemctl --user enable "$1"; then
        warn "could not enable $1 — did its package fail to install?"
        record_failure "$1" "${2:-}"
    fi
}
