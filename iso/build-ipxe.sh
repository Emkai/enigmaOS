#!/usr/bin/env bash
# Build ipxe.efi — the network boot program a PXE-booting machine loads first —
# with an embedded script that chains straight to boot.ipxe on the netboot
# server. Two-stage on purpose: iterating on kernel params only means editing
# boot.ipxe on the server (deploy-netboot.sh regenerates it), never rebuilding
# iPXE; and the embedded script ignores DHCP-provided filenames, so the DHCP
# server pointing at ipxe.efi can't loop iPXE back into itself.
#
#   NETBOOT_HOST=10.13.37.109 NETBOOT_PORT=8480 ./iso/build-ipxe.sh
#
# Build deps: git gcc binutils make perl xz mtools. The clone and the built
# binary persist in iso/cache/ipxe/ across rebuilds (cleared by clean-cache);
# a rebuild is only triggered when the embedded URL changes.
set -euo pipefail

ISO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="$ISO_DIR/cache/ipxe"
SRC="$CACHE/src"
IPXE_TAG="${IPXE_TAG:-v2.0.0}"   # what Arch packages today
NETBOOT_HOST="${NETBOOT_HOST:-10.13.37.109}"
NETBOOT_PORT="${NETBOOT_PORT:-8480}"
CHAIN_URL="http://${NETBOOT_HOST}:${NETBOOT_PORT}/boot.ipxe"

log() { printf '\033[1;34m[build-ipxe]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[build-ipxe] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

for cmd in git gcc make perl mtools; do
    command -v "$cmd" >/dev/null || die "$cmd is required (pacman -S base-devel git mtools)."
done

mkdir -p "$CACHE"
if [[ ! -d "$SRC/.git" ]]; then
    log "Cloning iPXE $IPXE_TAG (once — cached in iso/cache/ipxe/) ..."
    git clone --quiet --depth 1 --branch "$IPXE_TAG" https://github.com/ipxe/ipxe.git "$SRC"
fi

EMBED="$CACHE/embed.ipxe"
new_embed="#!ipxe
:retry
dhcp || goto retry
echo Chaining ${CHAIN_URL}
chain ${CHAIN_URL} || shell
"
# only touch the file when the URL actually changed, so the mtime check below
# keeps cache hits on repeated builds
[[ -f "$EMBED" && "$(cat "$EMBED")" == "$new_embed" ]] || printf '%s' "$new_embed" > "$EMBED"

if [[ -f "$CACHE/ipxe.efi" && ! "$EMBED" -nt "$CACHE/ipxe.efi" ]]; then
    log "ipxe.efi up to date (chains $CHAIN_URL)."
    exit 0
fi

log "Building bin-x86_64-efi/snponly.efi (embeds: chain $CHAIN_URL) ..."
# snponly, not the full ipxe.efi: it drives the NIC through the firmware's
# own network stack (SNP) instead of iPXE's native drivers, which don't
# cover every laptop NIC — the firmware just PXE-booted on this NIC, so SNP
# is guaranteed to work. Deployed under the name ipxe.efi regardless.
# iPXE occasionally trips -Werror on brand-new GCC releases; retry without.
make -C "$SRC/src" -j"$(nproc)" bin-x86_64-efi/snponly.efi EMBED="$EMBED" \
    || make -C "$SRC/src" -j"$(nproc)" bin-x86_64-efi/snponly.efi EMBED="$EMBED" NO_WERROR=1

cp "$SRC/src/bin-x86_64-efi/snponly.efi" "$CACHE/ipxe.efi"
touch "$CACHE/ipxe.efi"
log "Done: $CACHE/ipxe.efi ($(du -h "$CACHE/ipxe.efi" | cut -f1))"
