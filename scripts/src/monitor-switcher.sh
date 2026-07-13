#!/bin/bash

KEEP_LAPTOP_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/monitor-switch-keep-laptop"
MONITOR_SWITCH_DEBUG_LOG="${MONITOR_SWITCH_DEBUG_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/monitor-switch.log}"

# Append a debug snapshot if MONITOR_SWITCH_DEBUG is set.
# Captures the current monitor state and a free-form note so a tail of the log
# tells you which input triggered each switch and what hyprctl saw at that moment.
function _monitor_debug_log() {
    [[ -z "$MONITOR_SWITCH_DEBUG" ]] && return 0
    mkdir -p "$(dirname "$MONITOR_SWITCH_DEBUG_LOG")"
    {
        printf '=== %s :: %s ===\n' "$(date -Is)" "$*"
        hyprctl monitors -j 2>&1
        printf '\n'
    } >> "$MONITOR_SWITCH_DEBUG_LOG"
}

function switch_monitor() {
    local keep_laptop=-1
    local trigger="manual"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keep-laptop|-k) keep_laptop=1 ;;
            --no-keep-laptop|-K) keep_laptop=0 ;;
            --debug|-d) MONITOR_SWITCH_DEBUG=1 ;;
            --trigger) trigger="$2"; shift ;;
        esac
        shift
    done

    if [[ $keep_laptop -eq 1 ]]; then
        mkdir -p "$(dirname "$KEEP_LAPTOP_CACHE")"
        touch "$KEEP_LAPTOP_CACHE"
    elif [[ $keep_laptop -eq 0 ]]; then
        rm -f "$KEEP_LAPTOP_CACHE"
    fi

    _monitor_debug_log "switch_monitor entry, trigger=$trigger keep_laptop=$keep_laptop"

    local action
    if hyprctl monitors | grep -q "Monitor DP-\|Monitor HDMI-\|Monitor VGA-"; then
        if [[ -f "$KEEP_LAPTOP_CACHE" ]]; then
            # Park eDP-1 off-screen first so its prior position can't overlap
            # any external while we recompute the right edge.
            hyprctl keyword monitor "eDP-1,3200x2000@120,20000x0,2"
            local right_edge
            right_edge=$(hyprctl monitors -j | jq '[.[] | select(.name != "eDP-1") | (.x + (.width / .scale))] | max | floor')
            hyprctl keyword monitor "eDP-1,3200x2000@120,${right_edge}x0,2"
            action="external+laptop right_edge=$right_edge"
        else
            hyprctl keyword monitor "eDP-1,disable"
            action="external only (laptop disabled)"
        fi
    else
        # Re-enable the laptop panel. `hyprctl keyword monitor` cannot revive
        # eDP-1 while Hyprland sits in its headless FALLBACK state (all real
        # outputs just removed): it returns "ok" but the panel stays disabled.
        # Only `hyprctl reload` — which re-applies monitors.conf's
        # `monitor=eDP-1,preferred,auto,2` — actually brings the output back.
        # So: attempt the direct modeset; if eDP-1 is still disabled, reload to
        # wake it, then pin the intended mode/position.
        hyprctl keyword monitor "eDP-1,3200x2000@120,0x0,2"
        sleep 0.5
        local dis
        dis=$(hyprctl monitors all -j | jq -r '.[] | select(.name == "eDP-1") | .disabled')
        if [[ "$dis" != "false" ]]; then
            hyprctl reload
            sleep 0.5
            hyprctl keyword monitor "eDP-1,3200x2000@120,0x0,2"
            action="laptop only (via reload)"
        else
            action="laptop only"
        fi
    fi

    _monitor_debug_log "switch_monitor done, action=$action"
}

function watch_monitor() {
    local debug_flag=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug|-d) MONITOR_SWITCH_DEBUG=1; debug_flag=(--debug) ;;
        esac
        shift
    done
    [[ -n "$MONITOR_SWITCH_DEBUG" ]] && _monitor_debug_log "watch_monitor starting"

    socat -U - UNIX-CONNECT:"$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" \
        | while read -r line; do
            # Match the Hyprland event prefix without forking grep per line.
            # Covers monitoradded / monitorremoved and their v2 variants.
            [[ "$line" == monitoradded* || "$line" == monitorremoved* ]] || continue

            # Coalesce the event burst: keep draining until ~1s of silence,
            # capped at 5s for runaway sources (e.g. a flaky USB-C hub).
            # Also serves as a "let hyprctl settle" delay.
            local deadline=$(( SECONDS + 5 ))
            while read -r -t 1 _ && (( SECONDS < deadline )); do :; done

            switch_monitor --trigger "watch:$line" "${debug_flag[@]}"
        done
}
