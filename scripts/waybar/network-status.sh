#!/bin/bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Script to output network status as JSON for waybar custom module

# Check connection type
connection_type=$(nmcli -t -f type,state,connection dev status | grep -E '^(wifi|ethernet):connected:' | head -n1 | cut -d: -f1)

if [ "$connection_type" = "ethernet" ]; then
    # Ethernet connection
    eth_device=$(nmcli -t -f type,device,connection dev status | grep '^ethernet:connected:' | head -n1 | cut -d: -f2)
    icon=$'\uf0ac'  # Ethernet icon
    tooltip="Ethernet: ${eth_device}"
    
    # Also show WiFi networks in tooltip if available
    wifi_tooltip=$("$SCRIPT_DIR/wifi-networks.sh" 2>/dev/null)
    if [ -n "$wifi_tooltip" ] && [ "$wifi_tooltip" != "No devices connected" ]; then
        tooltip="${tooltip}\n\nWiFi Networks:\n${wifi_tooltip}"
    fi
elif [ "$connection_type" = "wifi" ]; then
    # WiFi connection
    # Get connected WiFi SSID and signal
    connected_info=$(nmcli -t -f active,ssid,signal dev wifi | grep '^yes:' | head -n1)
    if [ -n "$connected_info" ]; then
        IFS=':' read -r active ssid signal <<< "$connected_info"
        
        # Get signal strength icon
        icon=$'\uf1eb'  # WiFi icon
    else
        icon=$'\uf1eb'
    fi
    
    # Get networks for tooltip
    tooltip=$("$SCRIPT_DIR/network-tooltip.sh" 2>/dev/null)
    
    if [ -z "$tooltip" ]; then
        tooltip="No networks available"
    fi
else
    # No connection or WiFi not connected
    wifi_status=$(nmcli -t -f type,state dev status | grep '^wifi:' | cut -d: -f2)
    wifi_device=$(nmcli -t -f type,device,state dev status | grep '^wifi:' | head -n1 | cut -d: -f2)
    
    if [ -n "$wifi_device" ]; then
        wifi_enabled=$(nmcli radio wifi 2>/dev/null)
        if [ "$wifi_enabled" = "enabled" ]; then
            icon=$'\uf1eb'  # WiFi icon (disconnected)
            tooltip=$("$SCRIPT_DIR/wifi-networks.sh" 2>/dev/null)
            if [ -z "$tooltip" ]; then
                tooltip="WiFi disconnected"
            fi
        else
            icon=$'\uf1eb'  # WiFi icon (disabled)
            tooltip="WiFi disabled"
        fi
    else
        icon=$'\uf1eb'  # WiFi icon
        tooltip="No WiFi adapter"
    fi
fi

#tooltip="test"
#tooltip='<span color=\"yellow\">test</span>\n<span color=\"blue\">test</span>'

# Use Python to properly encode JSON, passing tooltip via stdin and icon as environment variable
printf '{"text": "%s", "tooltip": "%s"}' "$icon" "$tooltip" 
