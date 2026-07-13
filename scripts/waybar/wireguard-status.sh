#!/bin/bash

VPN_SCRIPT="${VPN_SCRIPT:-$HOME/src/scripts/linux/os/src/vpn.sh}"
# shellcheck source=/dev/null
[ -f "$VPN_SCRIPT" ] && source "$VPN_SCRIPT"

if ! wireguard_connected 2>/dev/null; then
    printf '{"text": "", "tooltip": ""}'
    exit 0
fi

SHIELD=$'\uf132'   # nf-fa-shield
DARK_WHITE='#989898'   # slightly darker white for the letter
ICON="${SHIELD}<span color=\\\"${DARK_WHITE}\\\">W</span>"

# Build tooltip from active WireGuard interfaces
tooltip="WireGuard"
while IFS= read -r iface; do
    [[ -z "$iface" ]] && continue
    ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}')
    tooltip="${tooltip}\r${iface} (${ip:-no ip})"
done < <(wg show interfaces 2>/dev/null | tr ' ' '\n')

# Escape for JSON: \ -> \\, " -> \", newlines -> \n
#tooltip="${tooltip//\\/\\\\}"
#tooltip="${tooltip//\"/\\\"}"
#tooltip="${tooltip//$'\n'/\\n}"

printf '{"text": "%s", "tooltip": "%s"}' "$ICON" "$tooltip"
