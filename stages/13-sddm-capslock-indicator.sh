#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

# The sddm-silent-theme AUR package (installed in 10-packages-core.sh) ships
# a caps lock indicator that's easy to miss: it's routed through the same
# shared warning-message label used for login errors, driven by a manually
# toggled flag that desyncs whenever a Key_CapsLock press isn't caught by
# whichever component currently has focus. This overlays a patched copy of
# the theme with a dedicated, reliably visible indicator: bold warning text
# under the password field plus a matching border highlight, bound directly
# to the live keyboard LED state instead of the fragile toggle.
#
# The theme itself isn't tracked in this repo (it's pulled from AUR), so the
# patch has to be reapplied here every run rather than living purely as a
# git-tracked config.

theme_dir="/usr/share/sddm/themes/silent"
overrides_dir="$ENIGMA_ROOT/configs/sddm/silent"

if [[ ! -d "$theme_dir" ]]; then
    log "sddm-silent-theme not installed, skipping caps lock indicator patch"
    exit 0
fi

log "Patching sddm silent theme: caps lock indicator on the login screen"
sudo install -m644 "$overrides_dir/Main.qml" "$theme_dir/Main.qml"
sudo install -m644 "$overrides_dir"/components/*.qml -t "$theme_dir/components/"
