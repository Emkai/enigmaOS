#!/bin/bash

VPN_SCRIPT="${VPN_SCRIPT:-$HOME/src/scripts/linux/os/src/vpn.sh}"
# shellcheck source=/dev/null
[ -f "$VPN_SCRIPT" ] && source "$VPN_SCRIPT"

# Show nothing when not connected
if ! openvpn_connected 2>/dev/null; then
    printf '{"text": "", "tooltip": ""}'
    exit 0
fi

SHIELD=$'\uf132'   # nf-fa-shield
DARK_WHITE='#989898'   # slightly darker white for the letter
ICON="${SHIELD}<span color=\\\"${DARK_WHITE}\\\">O</span>"
# Pango markup: green checkmark for connected, red cross for not connected
CONNECTED_ICON="<span color='#4ade80'>✓</span>"
DISCONNECTED_ICON="<span color='#ef4444'>✗</span>"

first=true
while IFS= read -r config_name; do
    [[ -z "$config_name" ]] && continue
    if openvpn3_config_connected "$config_name" 2>/dev/null; then
        line="${config_name} ${CONNECTED_ICON}"
    else
        line="${config_name} ${DISCONNECTED_ICON}"
    fi
    if [[ "$first" == true ]]; then
        first=false
        tooltip="$line"
    else
        tooltip="${tooltip}\r${line}"
    fi
done < <(openvpn3_configs_list 2>/dev/null)

# If no openvpn3 configs (e.g. legacy openvpn only), show simple message
[[ -z "$tooltip" ]] && tooltip="No VPN connections"

printf '{"text": "%s", "tooltip": "%s"}' "$ICON" "$tooltip"
