#!/usr/bin/env bash
# Build a custom Arch ISO with this enigmaOS repo and the guided installer
# baked in. Run on any Arch box (needs the `archiso` package + root for
# mkarchiso). Output: iso/out/enigmaos-*.iso — dd that to a USB (flash-usb.sh).
#
#   ./iso/build-iso.sh
#
# The ISO carries a snapshot of the repo *as it is on disk right now*
# (working tree, uncommitted changes included) — rebuild after you change
# anything you want on the target.
set -euo pipefail

ISO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ISO_DIR/.." && pwd)"
WORK="$ISO_DIR/work"
OUT="$ISO_DIR/out"
PROFILE="$WORK/profile"
RELENG="/usr/share/archiso/configs/releng"
STAMP="$(date +%Y.%m.%d)"

log() { printf '\033[1;34m[build-iso]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[build-iso] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v rsync >/dev/null || die "rsync is required (pacman -S rsync)."

# archiso / releng profile present?
if [[ ! -d "$RELENG" ]]; then
    log "archiso not found. Installing it (needs sudo)."
    sudo pacman -S --needed --noconfirm archiso || die "could not install archiso."
    [[ -d "$RELENG" ]] || die "releng profile still missing at $RELENG."
fi

log "Preparing a clean work tree at $WORK"
sudo rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
cp -r "$RELENG" "$PROFILE"

log "Overlaying enigmaOS live-env files (installer + auto-launch)."
rsync -a "$ISO_DIR/airootfs/" "$PROFILE/airootfs/"
chmod 0755 "$PROFILE/airootfs/usr/local/bin/enigma-install"

log "Baking the repo snapshot into the live filesystem."
mkdir -p "$PROFILE/airootfs/usr/local/share/enigmaOS"
rsync -a --delete \
    --exclude '/iso/work/' --exclude '/iso/out/' \
    "$REPO_ROOT/" "$PROFILE/airootfs/usr/local/share/enigmaOS/"

# mkarchiso honours a file_permissions map in profiledef.sh; make sure our
# executables land with the right mode regardless of the host umask.
log "Registering file permissions in profiledef.sh"
python3 - "$PROFILE/profiledef.sh" <<'PY' 2>/dev/null || \
  sed -i '/^file_permissions=(/a\  ["/usr/local/bin/enigma-install"]="0:0:755"' "$PROFILE/profiledef.sh"
import sys, re
p = sys.argv[1]
s = open(p).read()
add = '  ["/usr/local/bin/enigma-install"]="0:0:755"\n'
if "enigma-install" not in s:
    s = re.sub(r"(file_permissions=\(\n)", r"\1" + add, s, count=1)
    open(p, "w").write(s)
PY

# Make sure the live env can partition/format/pacstrap (releng already ships
# most of these; appending is a no-op if present).
log "Ensuring installer dependencies are in the live package list."
for pkg in arch-install-scripts gptfdisk dosfstools e2fsprogs git; do
    grep -qx "$pkg" "$PROFILE/packages.x86_64" || echo "$pkg" >> "$PROFILE/packages.x86_64"
done

log "Running mkarchiso (this takes a few minutes and needs sudo) ..."
sudo mkarchiso -v -w "$WORK/mkarchiso" -o "$OUT" "$PROFILE"

iso_path="$(ls -t "$OUT"/*.iso 2>/dev/null | head -1)"
[[ -n "$iso_path" ]] || die "mkarchiso finished but no .iso appeared in $OUT."
log "Done: $iso_path"
log "Flash it:  ./iso/flash-usb.sh \"$iso_path\""
