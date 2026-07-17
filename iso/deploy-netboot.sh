#!/usr/bin/env bash
# Push the netboot artifacts (built by `make netboot`) to the home server's
# nginx dir over SSH, generating boot.ipxe with the server URL on the way.
# Resumable: rerun after an interrupted transfer and rsync picks up where the
# 3 GB squashfs left off. The serving side lives in ~/src/home-server
# (./deploy/netboot.sh there brings up nginx + proxy-DHCP).
#
#   NETBOOT_HOST=10.13.37.109 NETBOOT_PORT=8480 ./iso/deploy-netboot.sh
set -euo pipefail

ISO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETBOOT_HOST="${NETBOOT_HOST:-10.13.37.109}"
NETBOOT_PORT="${NETBOOT_PORT:-8480}"
NETBOOT_SSH="${NETBOOT_SSH:-$NETBOOT_HOST}"          # ssh target (config picks the user)
NETBOOT_DIR="${NETBOOT_DIR:-home-server/netboot/data}" # remote, relative to ~
SRC="$ISO_DIR/out/arch"
IPXE="$ISO_DIR/cache/ipxe/ipxe.efi"
BASE_URL="http://${NETBOOT_HOST}:${NETBOOT_PORT}"

log() { printf '\033[1;34m[deploy-netboot]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[deploy-netboot] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "$SRC" ]]  || die "no netboot tree at iso/out/arch — run: make netboot"
[[ -f "$IPXE" ]] || die "no ipxe.efi in iso/cache/ipxe — run: make netboot"

# boot.ipxe is generated at deploy time so its URLs always match the target.
STAGE="$ISO_DIR/work/netboot-stage"
mkdir -p "$STAGE"
{
    printf '#!ipxe\n'
    printf 'kernel %s/arch/boot/x86_64/vmlinuz-linux\n' "$BASE_URL"
    # ucode initrds only if the tree carries them — current builds embed
    # microcode in the initramfs (releng's mkinitcpio 'microcode' hook)
    for uc in intel-ucode.img amd-ucode.img; do
        [[ -f "$SRC/boot/$uc" ]] && printf 'initrd %s/arch/boot/%s\n' "$BASE_URL" "$uc"
    done
    printf 'initrd %s/arch/boot/x86_64/initramfs-linux.img\n' "$BASE_URL"
    # trailing slash on archiso_http_srv is load-bearing: the initramfs hook
    # appends "arch/x86_64/airootfs.sfs" directly onto it
    printf 'imgargs vmlinuz-linux initrd=initramfs-linux.img archisobasedir=arch archiso_http_srv=%s/ ip=dhcp BOOTIF=01-${netX/mac} checksum=y\n' "$BASE_URL"
    printf 'boot\n'
} > "$STAGE/boot.ipxe"

log "Pushing $SRC -> $NETBOOT_SSH:$NETBOOT_DIR/arch/ (resumable) ..."
ssh -o ConnectTimeout=10 "$NETBOOT_SSH" "mkdir -p '$NETBOOT_DIR/arch'" \
    || die "can't SSH to $NETBOOT_SSH — is the server up? (override with NETBOOT_SSH=)"
# no -z: the sfs is already zstd. --partial --inplace: an interrupted 3 GB
# transfer resumes and the server never needs 2x free space (tradeoff: the
# file is torn while the sync runs — don't netboot mid-deploy). --delete is
# scoped to arch/ so stale kernels/checksums from older builds get cleared.
rsync -rlt --info=progress2 --partial --inplace --delete \
    "$SRC/" "$NETBOOT_SSH:$NETBOOT_DIR/arch/"
rsync -lt "$STAGE/boot.ipxe" "$IPXE" "$NETBOOT_SSH:$NETBOOT_DIR/"

log "Smoke-testing $BASE_URL ..."
curl -sfI "$BASE_URL/boot.ipxe" >/dev/null || die "boot.ipxe not served — deployed netboot service? (home-server: ./deploy/netboot.sh)"
curl -sf -r 0-0 -o /dev/null "$BASE_URL/arch/x86_64/airootfs.sfs" || die "airootfs.sfs not served / Range requests broken."
log "Done. PXE-boot the target (UEFI, IPv4) and it will chain $BASE_URL/boot.ipxe"
