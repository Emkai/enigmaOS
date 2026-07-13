#!/bin/bash

# Ping 8.8.8.8 with 500ms timeout
# Track consecutive failures and last successful ping

CACHE_DIR="$HOME/.cache/waybar"
FAIL_FILE="$CACHE_DIR/ping-fails"
LAST_PING_FILE="$CACHE_DIR/ping-last"
NOTIFIED_FILE="$CACHE_DIR/ping-notified"
TARGET="8.8.8.8"
TIMEOUT="0.5"
MAX_FAILS=5

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# Initialize files if not exists
[[ ! -f "$FAIL_FILE" ]] && echo 0 > "$FAIL_FILE"
[[ ! -f "$LAST_PING_FILE" ]] && echo "?" > "$LAST_PING_FILE"
[[ ! -f "$NOTIFIED_FILE" ]] && echo 0 > "$NOTIFIED_FILE"

# Run ping with 500ms timeout, single packet
result=$(ping -c 1 -W "$TIMEOUT" "$TARGET" 2>/dev/null)

if [[ $? -eq 0 ]]; then
    # Success - extract latency and reset fail counter
    latency=$(echo "$result" | grep -oP 'time=\K[0-9.]+')
    formatted=$(printf "%.0f ms" "$latency")
    echo 0 > "$FAIL_FILE"
    echo "$formatted" > "$LAST_PING_FILE"
    echo 0 > "$NOTIFIED_FILE"  # Reset notification flag when back online
    echo "{\"text\": \"$formatted\", \"class\": \"ok\"}"
else
    # Failed - increment counter
    fails=$(cat "$FAIL_FILE")
    ((fails++))
    echo "$fails" > "$FAIL_FILE"
    last_ping=$(cat "$LAST_PING_FILE")
    notified=$(cat "$NOTIFIED_FILE")
    
    if [[ $fails -ge $MAX_FAILS ]]; then
        # Send notification once when going offline
        if [[ $notified -eq 0 ]]; then
            notify-send "Network Offline" "Connection to $TARGET failed" -u critical
            echo 1 > "$NOTIFIED_FILE"
        fi
        echo "{\"text\": \"⚠ offline\", \"class\": \"offline\"}"
    else
        echo "{\"text\": \"$last_ping\", \"class\": \"stale\"}"
    fi
fi
