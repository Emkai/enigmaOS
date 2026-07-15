#!/usr/bin/env bash
# Write an enigmaOS ISO to a USB stick. Guided + destructive: lists disks,
# makes you confirm, then dd's the image.
#
#   ./iso/flash-usb.sh [path/to/enigmaos.iso]
#
# With no argument it grabs the newest ISO in iso/out/.
set -euo pipefail

ISO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

c_red=$'\033[1;31m'; c_rst=$'\033[0m'
die() { printf '%s[flash-usb] ERROR:%s %s\n' "$c_red" "$c_rst" "$*" >&2; exit 1; }

ISO="${1:-$(ls -t "$ISO_DIR"/out/*.iso 2>/dev/null | head -1 || true)}"
[[ -n "$ISO" && -f "$ISO" ]] || die "no ISO given and none found in iso/out/ — run build-iso.sh first."

echo "ISO: $ISO ($(du -h "$ISO" | cut -f1))"
echo
echo "Removable disks:"
lsblk -dpno NAME,SIZE,MODEL,TRAN,RM | awk '$NF==1 || $(NF-1)=="usb"' | nl -w2 -s') '
echo "(if your stick isn't listed, re-plug it and re-run)"
echo
read -rp "Target USB device (full path, e.g. /dev/sda): " DEV
[[ -b "$DEV" ]] || die "'$DEV' is not a block device."

# refuse anything that is currently mounted at / or /home etc.
if lsblk -no MOUNTPOINT "$DEV" | grep -qE '^/($|home|boot)'; then
    die "'$DEV' has system mountpoints — that's almost certainly your main disk. Aborting."
fi

echo
lsblk "$DEV"
echo
printf '%sEVERYTHING on %s will be erased.%s\n' "$c_red" "$DEV" "$c_rst"
read -rp "Type YES (uppercase) to write the image: " ok
[[ "$ok" == "YES" ]] || die "not confirmed."

echo "Unmounting any partitions on $DEV ..."
sudo umount "$DEV"?* 2>/dev/null || true

echo "Writing (this takes a few minutes) ..."
sudo dd if="$ISO" of="$DEV" bs=4M conv=fsync oflag=direct status=progress
sudo sync
echo "Done. Eject the USB, boot the target machine from it (UEFI)."
