#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

# Brand the installed system as enigmaOS so `cat /etc/os-release`,
# hostnamectl, fastfetch etc. show what's actually running — including WHICH
# enigmaOS: VERSION_ID is the date this stage last ran and BUILD_ID is the
# repo commit it ran from, so a machine can be checked against the repo at a
# glance.
#
# Two Arch-specific wrinkles:
#  - /etc/os-release is a symlink to /usr/lib/os-release owned by the
#    `filesystem` package. Per os-release(5) a regular file in /etc takes
#    precedence, so we replace the symlink — ID_LIKE=arch keeps tooling that
#    checks for Arch derivatives working.
#  - pacman re-extracts that symlink on every `filesystem` upgrade (it's not
#    in the package's backup array), silently reverting us to "Arch Linux".
#    A NoExtract rule in pacman.conf makes the override stick.

build_id="$(git -C "$ENIGMA_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
[[ -z "$(git -C "$ENIGMA_ROOT" status --porcelain 2>/dev/null)" ]] || build_id="$build_id-dirty"

log "Writing /etc/os-release (enigmaOS $(date +%Y.%m.%d), build $build_id)"
cat <<EOF | sudo install -m644 /dev/stdin /etc/os-release
NAME="enigmaOS"
PRETTY_NAME="enigmaOS (Arch Linux)"
ID=enigmaos
ID_LIKE=arch
VERSION_ID=$(date +%Y.%m.%d)
BUILD_ID=$build_id
ANSI_COLOR="38;2;122;162;247"
HOME_URL="https://github.com/Emkai/enigmaOS"
LOGO=archlinux-logo
EOF

if ! grep -q '^NoExtract.*etc/os-release' /etc/pacman.conf; then
    log "Adding NoExtract guard to /etc/pacman.conf (filesystem pkg would restore the Arch symlink)"
    sudo sed -i '/^\[options\]/a NoExtract   = etc/os-release' /etc/pacman.conf
fi
