#!/bin/bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Script to output bluetooth status as JSON for waybar custom module

# Check if bluetooth is enabled
bt_enabled=$(bluetoothctl show 2>/dev/null | grep -i "powered" | awk '{print $2}')

if [ "$bt_enabled" != "yes" ]; then
    echo "{\"text\":\"\",\"tooltip\":\"\"}"
    exit 0
fi

icon=$'\uf293'  # Bluetooth icon (FontAwesome)

# Get connected devices for tooltip
tooltip=$("$SCRIPT_DIR/bluetooth-tooltip.sh" 2>/dev/null)

if [ -z "$tooltip" ] || [ "$tooltip" = "No devices connected" ]; then
    tooltip="No devices connected"
fi

printf '{"text": "%s", "tooltip": "%s"}' "$icon" "$tooltip" 
