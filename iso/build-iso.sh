#!/usr/bin/env bash
# Build a custom Arch ISO with this enigmaOS repo and the guided installer
# baked in. Run on any Arch box (needs the `archiso` package + root for
# mkarchiso). Output: iso/out/enigmaos-*.iso — dd that to a USB (flash-usb.sh).
#
#   ./iso/build-iso.sh
#
# The ISO carries a snapshot of the repo *as it is on disk right now*
# (working tree, uncommitted changes included) — rebuild after you change
# anything you want on the target. It also bakes an offline pacman repo
# (base + packages/core.txt + pre-built packages/core-aur.txt) so the base
# install runs without network and the first boot skips AUR compiles.
set -euo pipefail

ISO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ISO_DIR/.." && pwd)"
WORK="$ISO_DIR/work"
OUT="$ISO_DIR/out"
CACHE="$ISO_DIR/cache"
PROFILE="$WORK/profile"
RELENG="/usr/share/archiso/configs/releng"
STAMP="$(date +%Y.%m.%d)"
# Offline pacman repo baked into the ISO: base-install closure + core.txt +
# pre-built core-aur.txt packages. pacstrap and the first-boot stages install
# from it instead of the network. Name must match what enigma-install expects.
OFFLINE_REPO_NAME="enigma-offline"
# NETBOOT=1 additionally exports HTTP-netboot artifacts (out/arch/: kernel,
# initramfs, airootfs.sfs) from the same run — mkarchiso builds the squashfs
# once and shares it between the two modes, so this is nearly free.
BUILDMODES="iso"
[[ "${NETBOOT:-0}" == 1 ]] && BUILDMODES="iso netboot"

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
# A tarball, not a plain tree: mkarchiso copies airootfs with
# --no-preserve=mode, which strips exec bits off everything not listed in
# profiledef.sh's file_permissions. Tar keeps the modes intact end-to-end;
# enigma-install extracts it onto the target.
mkdir -p "$PROFILE/airootfs/usr/local/share"
tar -czf "$PROFILE/airootfs/usr/local/share/enigmaOS.tar.gz" \
    --exclude './iso/work' --exclude './iso/out' --exclude './iso/cache' \
    -C "$REPO_ROOT" .

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

# ---- Offline package repo ---------------------------------------------------
# Bake a pacman repo holding the full dependency closure of the base install
# (BASE_PACKAGES + both ucodes), packages/core.txt, and pre-built AUR packages
# from packages/core-aur.txt (plus yay, so the target never compiles it).
# pacstrap and the first-boot core stages then install from the USB instead of
# the network. Downloads and AUR builds persist in iso/cache/ across rebuilds
# (rm -rf iso/cache/aur to force fresh AUR builds).

strip_list() { sed -e 's/[[:space:]]*#.*//' -e '/^[[:space:]]*$/d' "$1"; }

# <name>: reuse a cached build, else clone from the AUR and makepkg. Built
# packages land in iso/cache/aur/<name>/.
build_aur_pkg() {
    local name="$1" dir="$CACHE/aur/$name"
    if compgen -G "$dir/*.pkg.tar.*" >/dev/null; then
        log "  $name: using cached build."
        return 0
    fi
    log "  $name: building from the AUR (makepkg -s may install build deps on this host) ..."
    rm -rf "$WORK/aur/$name"
    git clone --quiet --depth 1 "https://aur.archlinux.org/$name.git" "$WORK/aur/$name" || return 1
    ( cd "$WORK/aur/$name" && makepkg -s --noconfirm --noprogressbar ) || return 1
    mkdir -p "$dir"
    cp "$WORK/aur/$name"/*.pkg.tar.* "$dir/"
}

log "Building the offline package repo (cache: iso/cache/)."
OFFLINE_DIR="$PROFILE/airootfs/usr/local/share/$OFFLINE_REPO_NAME"
PACDB="$WORK/pacdb"
mkdir -p "$CACHE/pkg" "$CACHE/aur" "$OFFLINE_DIR" "$PACDB" "$WORK/aur"

# The base-install package set, read from the installer that uses it.
eval "$(grep '^BASE_PACKAGES=' "$ISO_DIR/airootfs/usr/local/bin/enigma-install")"
[[ ${#BASE_PACKAGES[@]} -gt 0 ]] || die "could not read BASE_PACKAGES from enigma-install."
official=( "${BASE_PACKAGES[@]}" intel-ucode amd-ucode )
mapfile -t -O "${#official[@]}" official < <(strip_list "$REPO_ROOT/packages/core.txt")

# Pre-build the AUR set. A failed build is not fatal — that package simply
# builds on the target as before (recorded there if it breaks again).
aur_built=()
if [[ $EUID -eq 0 ]]; then
    log "Running as root — skipping AUR pre-builds (makepkg refuses root);"
    log "those packages will build on the target instead."
else
    while read -r name; do
        # </dev/null: makepkg must not eat the package list off our stdin
        if build_aur_pkg "$name" </dev/null; then
            aur_built+=("$name")
        else
            log "  WARNING: AUR build failed for $name — it will build on the target instead."
        fi
    done < <({ echo yay; strip_list "$REPO_ROOT/packages/core-aur.txt"; })
fi

# Runtime deps of the pre-built AUR packages must be resolvable offline too.
for name in "${aur_built[@]}"; do
    for f in "$CACHE/aur/$name"/*.pkg.tar.*; do
        [[ "$f" == *.sig ]] && continue
        while read -r dep; do
            dep="${dep%%[<>=]*}"
            [[ -n "$dep" && "$dep" != None ]] && official+=("$dep")
        done < <(pacman -Qip "$f" 2>/dev/null \
                 | awk -F' *: *' '/^Depends On/{n=split($2,a," "); for(i=1;i<=n;i++) print a[i]}')
    done
done
mapfile -t official < <(printf '%s\n' "${official[@]}" | sort -u)

# Download against a scratch DB (empty local db -> the FULL closure downloads,
# not just what this build host happens to be missing) and a pinned
# core+extra-only config (host's custom repos must not leak into the ISO).
cat > "$WORK/pacman-offline-dl.conf" <<CONF
[options]
Architecture = auto
SigLevel = Required DatabaseOptional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
CONF

log "Downloading ${#official[@]} packages + dependencies -> iso/cache/pkg (needs sudo) ..."
dl() { sudo pacman --config "$WORK/pacman-offline-dl.conf" --dbpath "$PACDB" --cachedir "$CACHE/pkg" --noconfirm "$@"; }
if ! dl -Syw "${official[@]}"; then
    # one bad name aborts the whole transaction; retry one at a time so an
    # AUR dep that isn't an official package just gets skipped
    log "Batch download failed — retrying per package (unknown names get dropped)."
    kept=()
    for p in "${official[@]}"; do
        if dl -Sw "$p" &>/dev/null; then kept+=("$p")
        else log "  WARNING: '$p' not downloadable from core/extra — left to the network install."
        fi
    done
    official=( "${kept[@]}" )
fi

log "Assembling the repo at airootfs/usr/local/share/$OFFLINE_REPO_NAME ..."
while read -r url; do
    f="$CACHE/pkg/$(basename "$url")"
    [[ -f "$f" ]] || { log "  WARNING: $(basename "$url") missing from the cache — skipped."; continue; }
    ln "$f" "$OFFLINE_DIR/" 2>/dev/null || cp "$f" "$OFFLINE_DIR/"
done < <(dl -Sp "${official[@]}" 2>/dev/null)
for name in "${aur_built[@]}"; do
    for f in "$CACHE/aur/$name"/*.pkg.tar.*; do
        [[ "$f" == *.sig ]] && continue
        ln "$f" "$OFFLINE_DIR/" 2>/dev/null || cp "$f" "$OFFLINE_DIR/"
    done
done
repo-add --quiet "$OFFLINE_DIR/$OFFLINE_REPO_NAME.db.tar.gz" "$OFFLINE_DIR"/*.pkg.tar.* \
    || die "repo-add failed."
log "Offline repo: $(ls "$OFFLINE_DIR" | grep -c '\.pkg\.tar\.') packages, $(du -sh "$OFFLINE_DIR" | cut -f1)."

# The repo is multiple GB of already-compressed packages — releng's xz squashfs
# would grind over it for no gain. zstd builds far faster at a similar size.
sed -i "s/^airootfs_image_tool_options=.*/airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')/" \
    "$PROFILE/profiledef.sh"

log "Running mkarchiso (this takes a few minutes and needs sudo) ..."
sudo mkarchiso -v -m "$BUILDMODES" -w "$WORK/mkarchiso" -o "$OUT" "$PROFILE"

iso_path="$(ls -t "$OUT"/*.iso 2>/dev/null | head -1)"
[[ -n "$iso_path" ]] || die "mkarchiso finished but no .iso appeared in $OUT."
log "Done: $iso_path"
log "Flash it:  ./iso/flash-usb.sh \"$iso_path\""
if [[ "${NETBOOT:-0}" == 1 ]]; then
    [[ -d "$OUT/arch" ]] || die "netboot mode ran but no tree appeared at $OUT/arch."
    log "Netboot tree: $OUT/arch ($(du -sh "$OUT/arch" | cut -f1)) — push it:  make deploy"
fi
