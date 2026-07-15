#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

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
