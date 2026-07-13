#!/bin/bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

VPN_SCRIPT="$SCRIPT_DIR/../src/vpn.sh"
[ -f "$VPN_SCRIPT" ] && source "$VPN_SCRIPT"

CACHE_DIR="${HOME}/.cache/waybar"
CACHE_FILE="${CACHE_DIR}/tailscale-devices"
BLACKLIST_FILE="${HOME}/.config/waybar/scripts/tailscale.conf"

# Load notification blacklist (hostnames, one per line; # = comment)
declare -a NOTIFY_BLACKLIST
if [[ -f "$BLACKLIST_FILE" ]]; then
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line#\"${line%%[![:space:]]*}}"
        line="${line%\"${line##*[![:space:]]}}"
        [[ -n "$line" ]] && NOTIFY_BLACKLIST+=("$line")
    done < "$BLACKLIST_FILE"
fi

is_blacklisted() {
    local name="$1"
    local entry
    for entry in "${NOTIFY_BLACKLIST[@]:-}"; do
        [[ "$entry" == "$name" ]] && return 0
    done
    return 1
}

# Show nothing when not connected
if ! tailscale_connected 2>/dev/null; then
    printf '{"text": "", "tooltip": ""}'
    exit 0
fi

SHIELD=$'\uf132'   # nf-fa-shield
DARK_WHITE='#989898'   # slightly darker white for the letter
ICON="${SHIELD}<span color=\\\"${DARK_WHITE}\\\">T</span>"

# Tooltip: devices on network — active→connected icon, idle→idle icon, "-"→online icon
# Use \r for newline; active=green, idle=blue, rest=no color
# Align status column: pad "hostname (ip)" so "— status" starts at same column
CONNECTED_ICON=$'\uf058'   # nerdfont check-circle (Font Awesome)
IDLE_ICON=$'\uf017'        # nerdfont clock (idle)
ONLINE_ICON=''
FADING_ICON=$'\uf111'      # nerdfont circle (counter < 5, missing but still in list)      

lines=()
while IFS= read -r line; do
    hostname=$(echo "$line" | awk -F'\t' '{print $2}')
    ip=$(echo "$line" | awk -F'\t' '{print $3}')
    status=$(echo "$line" | awk -F'\t' '{print $4}')
    [ -z "$hostname" ] && continue
    # Skip offline (only show active, idle, or "-")
    [[ "$status" != active* ]] && [[ "$status" != idle* ]] && [[ "$status" != "-" ]] && continue
    lines+=("${hostname}|${ip}|${status}")
done < <(tailscale_sorted_devices 2>/dev/null)

# --- Cache and notifications ---
# Cache format: hostname|ip|norm_status|counter (counter 1-5; 5 = present, decrement when missing, remove at 0)
MISSING_COUNTER_INIT=5
mkdir -p "$CACHE_DIR"
declare -A prev_devices    # hostname -> "ip|norm_status|counter"
declare -A curr_devices   # hostname -> "ip|norm_status"
norm_status() {
    local s="$1"
    if [[ "$s" == active* ]]; then echo "active"; elif [[ "$s" == idle* ]]; then echo "idle"; else echo "online"; fi
}
# Status sort order: active=0, idle=1, online=2 (matches tailscale_sorted_devices order)
status_rank() {
    local s="$1"
    if [[ "$s" == active* ]] || [[ "$s" == "active" ]]; then echo 0; elif [[ "$s" == idle* ]] || [[ "$s" == "idle" ]]; then echo 1; else echo 2; fi
}
# Load previous state (format: hostname|ip|norm_status or hostname|ip|norm_status|counter per line)
had_prev_cache=false
if [[ -f "$CACHE_FILE" ]]; then
    had_prev_cache=true
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        IFS='|' read -r h ip_prev status_prev counter_prev <<< "$line"
        [[ -z "$counter_prev" ]] && counter_prev=$MISSING_COUNTER_INIT
        prev_devices["$h"]="${ip_prev}|${status_prev}|${counter_prev}"
    done < "$CACHE_FILE"
fi

# Build current state from tailscale (hostname -> ip|norm_status)
for entry in "${lines[@]}"; do
    IFS='|' read -r hostname ip status <<< "$entry"
    n=$(norm_status "$status")
    curr_devices["$hostname"]="${ip}|${n}"
done

# Build display list: current devices (counter=5) + missing devices with counter>0 (decrement each run)
# Format: hostname|ip|status|counter|status_rank (rank 0=active, 1=idle, 2=online for sorting)
# Also send "New device" / "Device gone" notifications
declare -a display_entries
for entry in "${lines[@]}"; do
    IFS='|' read -r hostname ip status <<< "$entry"
    n=$(norm_status "$status")
    r=$(status_rank "$status")
    display_entries+=("${hostname}|${ip}|${status}|5|${r}")
done
# Write cache: current devices with counter 5, missing-but-kept with decremented counter
: > "$CACHE_FILE"
for entry in "${lines[@]}"; do
    IFS='|' read -r hostname ip status <<< "$entry"
    n=$(norm_status "$status")
    echo "${hostname}|${ip}|${n}|${MISSING_COUNTER_INIT}" >> "$CACHE_FILE"
done
for h in "${!prev_devices[@]}"; do
    [[ -n "${curr_devices[$h]:-}" ]] && continue
    IFS='|' read -r ip_prev status_prev counter_prev <<< "${prev_devices[$h]}"
    (( counter_prev -= 1 ))
    if (( counter_prev > 0 )); then
        r=$(status_rank "$status_prev")
        display_entries+=("${h}|${ip_prev}|${status_prev}|${counter_prev}|${r}")
        echo "${h}|${ip_prev}|${status_prev}|${counter_prev}" >> "$CACHE_FILE"
    fi
done

# Sort: counter 5 first (present), then 4,3,2,1 (fading); within same counter by status (active, idle, online), then hostname
mapfile -t display_entries < <(printf '%s\n' "${display_entries[@]}" | sort -t'|' -k4 -rn -k5 -n -k1)

# Find max hostname length (align IPs) and max IP length (so prefix width is correct for status alignment)
# Output prefix is "padded_hostname (ip)" = max_hostname_len + 3 + len(ip) chars
max_hostname_len=0
max_ip_len=0
for entry in "${display_entries[@]}"; do
    IFS='|' read -r hostname ip status counter _ <<< "$entry"
    (( ${#hostname} > max_hostname_len )) && max_hostname_len=${#hostname}
    (( ${#ip} > max_ip_len )) && max_ip_len=${#ip}
done
max_prefix_len=$((max_hostname_len + 3 + max_ip_len))

tooltip="Tailscale"
for entry in "${display_entries[@]}"; do
    IFS='|' read -r hostname ip status counter _ <<< "$entry"
    padded_hostname=$(printf '%-*s' "$max_hostname_len" "$hostname")
    prefix="${padded_hostname} (${ip})"
    padded_prefix=$(printf '%-*s' "$max_prefix_len" "$prefix")
    # counter < 5 = missing but still in list (fading out) → yellow circle, shown last
    if [[ -n "$counter" ]] && [[ "$counter" -lt 5 ]]; then
        display="$FADING_ICON"
        line_text="${padded_prefix} ${display}"
        tooltip="${tooltip}\r<span color='yellow'>${line_text}</span>"
    elif [[ "$status" == active* ]] || [[ "$status" == "active" ]]; then
        display="$CONNECTED_ICON"
        line_text="${padded_prefix} ${display}"
        tooltip="${tooltip}\r<span color='green'>${line_text}</span>"
    elif [[ "$status" == idle* ]] || [[ "$status" == "idle" ]]; then
        display="$IDLE_ICON"
        line_text="${padded_prefix} ${display}"
        tooltip="${tooltip}\r<span color='blue'>${line_text}</span>"
    else
        display="$ONLINE_ICON"
        line_text="${padded_prefix} ${display}"
        tooltip="${tooltip}\r<span>${line_text}</span>"
    fi
done

# Escape for JSON: preserve \r as literal \r in output
#tooltip="${tooltip//$'\r'/@@@CR@@@}"
#tooltip="${tooltip//\\/\\\\}"
#tooltip="${tooltip//\"/\\\"}"
#tooltip="${tooltip//@@@CR@@@/\r}"

printf '{"text": "%s", "tooltip": "%s"}' "$ICON" "$tooltip"
