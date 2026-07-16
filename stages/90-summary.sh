#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

if [[ -s "$ENIGMA_FAILURES" ]]; then
    printf '\n\033[1;31m[enigmaOS] Install finished, but some items FAILED:\033[0m\n\n'
    while IFS=$'\t' read -r item src note; do
        printf '  \033[1m%s\033[0m  %s\n' "$item" "${src:+[$src]}"
        printf '      disables: %s\n' "${note:-unknown — see ${src:-the stage log above}}"
    done < <(sort -u "$ENIGMA_FAILURES")
    cat <<EOF

  Everything else is installed and configured — the failures above only
  disable the features listed. Once fixed, retry with:
      cd $ENIGMA_ROOT && bash install.sh
  (--needed skips everything already installed, so re-runs are quick.)
  This report is saved at: $ENIGMA_FAILURES

EOF
else
    log "All packages installed and services enabled — no failures."
fi

cat <<'EOF'

[enigmaOS] Install stages complete. Manual follow-ups:

  1. Reboot.
  2. At the SDDM login screen, pick the "Hyprland (uwsm-managed)" session
     (provided by the uwsm package — nothing to configure).
  3. Set up GitHub auth (SSH key, or `gh auth login`), then clone the
     private scripts repo for edit/work convenience scripts:
       git clone git@github.com:Emkai/scripts.git ~/src/scripts
  4. Sign in to 1Password.
  5. `tailscale up`.
  6. Import any VPN/RDP connection profiles you need (the vpn/rdp menus
     start empty on a fresh machine — credentials are never stored in git).
  7. Dolphin: open Settings > Configure Dolphin > Interface > Previews and
     enable all available plugins (the ones baked into dolphinrc are a best
     guess — this confirms/fixes the real plugin id string for this Dolphin
     version). Run `kvantummanager` once to confirm the TokyoNight theme
     loaded without errors.

EOF
