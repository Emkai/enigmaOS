#!/bin/bash

# Script to get WiFi networks with signal strength for tooltip.
# Columns: hostname (SSID), signal strength (bars), locked/unlocked icon (aligned like tailscale).

LOCKED_ICON=$'\uf023'    # Nerd Font lock
UNLOCKED_ICON=$'\uf3c1'  # Nerd Font lock-open

# Get connected WiFi network
connected=$(nmcli -t -f active,ssid,signal,security dev wifi | grep '^yes:' | head -n1)

lines=()
# Add connected network first
if [ -n "$connected" ]; then
    IFS=':' read -r active ssid signal security <<< "$connected"
    if [ -n "$ssid" ] && [ "$ssid" != "--" ]; then
        locked="0"
        [ -n "$security" ] && [ "$security" != "--" ] && [ "$security" != "" ] && locked="1"
        lines+=("${ssid}|${signal}|${locked}|1")  # 1 = connected
    fi
fi

# Get available WiFi networks (excluding connected)
available=$(nmcli -t -f active,ssid,signal,security dev wifi | grep '^no:' | sort -t: -k3 -rn | head -n10)
if [ -n "$available" ]; then
    while IFS= read -r line; do
        IFS=':' read -r active ssid signal security <<< "$line"
        [ -z "$ssid" ] || [ "$ssid" = "--" ] && continue
        locked="0"
        [ -n "$security" ] && [ "$security" != "--" ] && [ "$security" != "" ] && locked="1"
        lines+=("${ssid}|${signal}|${locked}|0")  # 0 = available
    done <<< "$available"
fi

# No networks
if [ ${#lines[@]} -eq 0 ]; then
    printf ''
    exit 0
fi

# Max SSID length for column alignment
max_ssid_len=0
for entry in "${lines[@]}"; do
    IFS='|' read -r ssid _ _ _ <<< "$entry"
    (( ${#ssid} > max_ssid_len )) && max_ssid_len=${#ssid}
done

tooltip="WiFi"
for entry in "${lines[@]}"; do
    IFS='|' read -r ssid signal locked connected <<< "$entry"
    padded_ssid=$(printf '%-*s' "$max_ssid_len" "$ssid")
    if [ "$locked" = "1" ]; then
        lock_display="$LOCKED_ICON"
    else
        lock_display="$UNLOCKED_ICON"
    fi
    signal_num=${signal:-0}
    if [ "$signal_num" -ge 75 ]; then
        signal_icon="▂▄▆█"   # Strong signal (4 bars)
        signal_span="<span color='green'>${signal_icon}</span>"
    elif [ "$signal_num" -ge 50 ]; then
        signal_icon="▂▄▆ "   # Good signal (3 bars)
        signal_span="<span color='blue'>${signal_icon}</span>"
    elif [ "$signal_num" -ge 25 ]; then
        signal_icon="▂▄  "   # Fair signal (2 bars)
        signal_span="<span color='yellow'>${signal_icon}</span>"
    else
        signal_icon="▂   "   # Weak signal (1 bar)
        signal_span="<span color='red'>${signal_icon}</span>"
    fi
    line_text="${padded_ssid} ${signal_span} ${lock_display}"
    line_text=${line_text//&/&amp;}
    if [ "$connected" = "1" ]; then
        tooltip="${tooltip}\r<span color='green'>${line_text}</span>"
    else
        tooltip="${tooltip}\r<span>${line_text}</span>"
    fi
done

printf '%s' "$tooltip"
