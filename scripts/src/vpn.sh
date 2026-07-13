#!/bin/bash

# Icons for waybar (Nerd Font / Material Design Icons)
VPN_ICON="󰒋"

# User-owned display-name mapping for the WireGuard menu (configs in
# /etc/wireguard are root:root 0600, so we can't read names from them as the
# user). Follows the repo convention used by src/rdp.sh and src/ask.sh.
WIREGUARD_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wofi-vpn"
WIREGUARD_NAMES_FILE="${WIREGUARD_NAMES_FILE:-$WIREGUARD_CONFIG_DIR/names.conf}"

# --- WireGuard ---
wireguard_configs_list() {
    local f
    for f in /etc/wireguard/*.conf; do
        [[ -e "$f" ]] || continue
        basename "$f" .conf
    done
}

# Create the names file on first run, seeding one "iface = iface" line per
# current config so behavior is unchanged until the user edits names.
wireguard_names_init() {
    mkdir -p "$WIREGUARD_CONFIG_DIR"
    [[ -f "$WIREGUARD_NAMES_FILE" ]] && return 0
    local iface
    {
        echo "# WireGuard menu display names.  Format:  <iface> = <Display Name>"
        echo "# <iface> is the .conf filename in /etc/wireguard minus .conf."
        echo "# Interfaces with no entry here fall back to showing the raw iface name."
        while IFS= read -r iface; do
            [[ -z "$iface" ]] && continue
            echo "$iface = $iface"
        done < <(wireguard_configs_list)
    } > "$WIREGUARD_NAMES_FILE"
}

# Map an interface to its display name; fall back to the iface if unmapped.
wireguard_display_name() {
    local iface="$1" name=""
    [[ -z "$iface" ]] && return 1
    if [[ -r "$WIREGUARD_NAMES_FILE" ]]; then
        name=$(awk -F= -v k="$iface" '
            /^[[:space:]]*#/ { next }
            {
                key=$1; gsub(/^[[:space:]]+|[[:space:]]+$/,"",key)
                if (key==k) { sub(/^[^=]*=/,""); gsub(/^[[:space:]]+|[[:space:]]+$/,"",$0); print; exit }
            }' "$WIREGUARD_NAMES_FILE")
    fi
    [[ -n "$name" ]] && echo "$name" || echo "$iface"
}

# Reverse lookup: display name -> real interface. Falls back to the input,
# which covers an unmapped iface shown raw.
wireguard_iface_from_display() {
    local want="$1" iface
    while IFS= read -r iface; do
        [[ -z "$iface" ]] && continue
        [[ "$(wireguard_display_name "$iface")" == "$want" ]] && { echo "$iface"; return 0; }
    done < <(wireguard_configs_list)
    echo "$want"
}

# Upsert the "iface = name" line (atomic). Empty name removes the entry,
# resetting that iface to its raw-name fallback.
wireguard_set_name() {
    local iface="$1" name="$2" tmp
    [[ -z "$iface" ]] && return 1
    name="$(printf '%s' "$name" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ "$name" == *"  •"* ]] && { notify-send "WireGuard" "Name can't contain '  •'"; return 1; }
    wireguard_names_init
    tmp="$(mktemp)"
    grep -vE "^[[:space:]]*${iface}[[:space:]]*=" "$WIREGUARD_NAMES_FILE" > "$tmp" 2>/dev/null
    [[ -n "$name" ]] && printf '%s = %s\n' "$iface" "$name" >> "$tmp"
    mv "$tmp" "$WIREGUARD_NAMES_FILE"
}

wireguard_interface_connected() {
    local iface="$1"
    [[ -z "$iface" ]] && return 1
    ip link show "$iface" type wireguard &>/dev/null
}

wireguard_any_connected() {
    local output
    output=$(ip link show type wireguard 2>/dev/null)
    [[ -n "$output" ]]
}

wireguard_connected() {
    wireguard_any_connected
}

wireguard_connect() {
    local iface="$1"
    [[ -z "$iface" ]] && return 1
    if wireguard_interface_connected "$iface"; then
        notify-send "WireGuard" "$iface is already connected"
        return 0
    fi
    local ret
    ret=$(sudo wg-quick up "$iface" 2>&1)
    if [[ $? -eq 0 ]]; then
        return 0
    else
        notify-send "WireGuard" "Failed to connect $iface: $ret"
        return 1
    fi
}

wireguard_disconnect() {
    local iface="$1"
    [[ -z "$iface" ]] && return 1
    if ! wireguard_interface_connected "$iface"; then
        notify-send "WireGuard" "$iface is already disconnected"
        return 0
    fi
    local ret
    ret=$(sudo wg-quick down "$iface" 2>&1)
    if [[ $? -eq 0 ]]; then
        return 0
    else
        notify-send "WireGuard" "Failed to disconnect $iface: $ret"
        return 1
    fi
}

wireguard_icon() {
    if wireguard_connected; then
        echo -n "$VPN_ICON"
    fi
}

# --- OpenVPN (openvpn3) ---
# List available config names (one per line), from openvpn3 configs-list
openvpn3_configs_list() {
    openvpn3 configs-list 2>/dev/null | while IFS= read -r line; do
        # Skip header, separator lines, and empty lines
        [[ "$line" =~ ^(Configuration Name|Last used|--+|\*+) ]] && continue
        [[ -z "$(echo "$line" | tr -d ' ')" ]] && continue
        # First column is the config name (rest is "Last used" value)
        echo "$line" | sed 's/[[:space:]][[:space:]].*$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    done | grep -v '^$'
}

# Output of openvpn3 sessions-list (for parsing or display)
openvpn3_sessions_list() {
    openvpn3 sessions-list 2>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    else 
        notify-send "OpenVPN" "Failed to list sessions"
        return 1
    fi
}

# Return 0 if at least one openvpn3 config has an active session
openvpn3_any_connected() {
    local out
    out=$(openvpn3_sessions_list)
    # No sessions when output is empty or exactly "No sessions available"
    [[ -z "$out" ]] && return 1
    [[ "$(echo "$out" | head -1)" == "No sessions available" ]] && [[ $(echo "$out" | wc -l) -le 1 ]] && return 1
    return 0
}

# Return 0 if the given config name has an active session
openvpn3_config_connected() {
    local config_name="$1"
    [[ -z "$config_name" ]] && return 1
    openvpn3_sessions_list | grep -q "$config_name"
}

# Start a session for config (by name)
openvpn3_connect() {
    local config_name="$1"
    [[ -z "$config_name" ]] && return 1
    ret=$(openvpn3 session-start --config "$config_name" --background)
    if [ $? -eq 0 ]; then
        return 0
    else 
        notify-send "OpenVPN" "Failed to connect to $config_name"
        return 1
    fi
}

# Disconnect session for config (by name)
openvpn3_disconnect() {
    local config_name="$1"
    [[ -z "$config_name" ]] && return 1
    openvpn3 session-manage --config "$config_name" --disconnect 2>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    else 
        notify-send "OpenVPN" "Failed to disconnect from $config_name"
        return 1
    fi
}

# --- OpenVPN: icon/status when any openvpn3 session or legacy process ---
openvpn_connected() {
    openvpn3_any_connected || pgrep -x openvpn >/dev/null
}

openvpn_icon() {
    if openvpn_connected; then
        echo -n "$VPN_ICON"
    fi
}

# --- Tailscale ---
tailscaled_service_running() {
    systemctl is-active --quiet tailscaled 2>/dev/null
}

tailscale_connected() {
    if tailscaled_service_running; then
        tailscale status 2>/dev/null | head -1 | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
        return $?
    else
        return 1
    fi
}

tailscale_up() {
    if  ! tailscaled_service_running; then
        notify-send "Tailscale" "Tailscale service not running"
        return 1
    else
        ret=$(tailscale up)
        if [[ $? -ne 0 ]]; then
            notify-send "Tailscale" "Failed to connect to Tailscale ${ret}"
            return 1
        else
            return 0
        fi
    fi
}

tailscale_down() {
    if  ! tailscaled_service_running; then
        notify-send "Tailscale" "Tailscale service not running"
        return 1
    else
        ret=$(tailscale down)
        if [[ $? -ne 0 ]]; then
            notify-send "Tailscale" "Failed to disconnect from Tailscale ${ret}"
            return 1
        else
            return 0
        fi
    fi
}

tailscale_start_service() {
    if ! tailscaled_service_running; then
        ret=$(sudo systemctl start tailscaled)
        if [[ $? -ne 0 ]]; then
            notify-send "Tailscale" "Failed to start Tailscale service ${ret}"
            return 1
        else
            return 0
        fi
    fi
}

tailscale_stop_service() {
    if ! tailscaled_service_running; then
        notify-send "Tailscale" "Tailscale service not running"
        return 1
    else
        tailscale_down
        if [[ $? -ne 0 ]]; then
            return 1
        fi
        ret=$(sudo systemctl stop tailscaled)
        if [[ $? -ne 0 ]]; then
            notify-send "Tailscale" "Failed to stop Tailscale service ${ret}"
            return 1
        else
            return 0
        fi
    fi
}

tailscale_icon() {
    if tailscale_connected; then
        echo -n "$VPN_ICON"
    fi
}

# Output one line per device: sortkey\thostname\tip\tstatus
# Active first (key -1), then online (key 0), then offline by last-seen ascending
tailscale_sorted_devices() {

    if ! tailscaled_service_running; then
        return
    fi

    tailscale status 2>/dev/null | while IFS= read -r line; do
        [[ -z "$(echo "$line" | tr -d ' ')" ]] && continue
        ip=$(echo "$line" | awk '{print $1}')
        [[ ! "$ip" =~ ^100\. ]] && continue
        hostname=$(echo "$line" | awk '{print $2}')
        status=$(echo "$line" | awk '{s=$5; for(i=6;i<=NF;i++) s=s" "$i; print s}')
        if [[ "$status" == active* ]]; then
            # active; direct ... = recently communicating, show at top
            echo -e "-2\t$hostname\t$ip\t$status"
        elif [[ "$status" == idle* ]]; then
            # idle, tx ... = connected but idle, after active
            echo -e "-1\t$hostname\t$ip\t$status"
        elif [[ "$status" == "-" ]]; then
            echo -e "0\t$hostname\t$ip\t$status"
        else
            key=9999
            if [[ "$status" =~ last\ seen\ ([0-9]+)d\ ago ]]; then
                key="${BASH_REMATCH[1]}"
            elif [[ "$status" =~ last\ seen\ ([0-9]+)h\ ago ]]; then
                key=$(echo "scale=4; ${BASH_REMATCH[1]}/24" | bc 2>/dev/null || echo "0.5")
            elif [[ "$status" =~ last\ seen\ ([0-9]+)m\ ago ]]; then
                key=$(echo "scale=4; ${BASH_REMATCH[1]}/24/60" | bc 2>/dev/null || echo "0.01")
            fi
            echo -e "${key}\t$hostname\t$ip\t$status"
        fi
    done | sort -t$'\t' -k1 -n
}

# --- Legacy ---
function list_vpn() {
    echo "List VPN"
    ls ~/.vpn 2>/dev/null || true
}

# --- CLI ---
# List every backend with its connection state.
vpn_list() {
    local iface cfg name state any

    wireguard_names_init
    echo "WireGuard:"
    any=0
    while IFS= read -r iface; do
        [[ -z "$iface" ]] && continue
        any=1
        name="$(wireguard_display_name "$iface")"
        if wireguard_interface_connected "$iface"; then state="Connected"; else state="Disconnected"; fi
        if [[ "$name" != "$iface" ]]; then
            printf '  %-28s %s\n' "$iface ($name)" "$state"
        else
            printf '  %-28s %s\n' "$iface" "$state"
        fi
    done < <(wireguard_configs_list)
    (( any )) || echo "  (no configs)"

    echo "OpenVPN:"
    any=0
    if command -v openvpn3 >/dev/null; then
        while IFS= read -r cfg; do
            [[ -z "$cfg" ]] && continue
            any=1
            if openvpn3_config_connected "$cfg"; then state="Connected"; else state="Disconnected"; fi
            printf '  %-28s %s\n' "$cfg" "$state"
        done < <(openvpn3_configs_list)
        (( any )) || echo "  (no configs)"
    else
        echo "  (openvpn3 not installed)"
    fi

    echo "Tailscale:"
    if ! tailscaled_service_running; then
        echo "  (tailscaled not running)"
    elif tailscale_connected; then
        echo "  Connected"
    else
        echo "  Disconnected"
    fi
}

# Resolve a user-supplied name to "backend<TAB>id". Match order (first wins):
# the literal "tailscale", a WireGuard interface, a WireGuard display name,
# an openvpn3 config name. Returns 1 if nothing matches.
vpn_resolve() {
    local want="$1" iface cfg
    [[ -z "$want" ]] && return 1
    if [[ "${want,,}" == "tailscale" ]]; then
        printf 'tailscale\ttailscale\n'
        return 0
    fi
    while IFS= read -r iface; do
        [[ "$iface" == "$want" ]] && { printf 'wireguard\t%s\n' "$iface"; return 0; }
    done < <(wireguard_configs_list)
    while IFS= read -r iface; do
        [[ -z "$iface" ]] && continue
        [[ "$(wireguard_display_name "$iface")" == "$want" ]] && { printf 'wireguard\t%s\n' "$iface"; return 0; }
    done < <(wireguard_configs_list)
    if command -v openvpn3 >/dev/null; then
        while IFS= read -r cfg; do
            [[ "$cfg" == "$want" ]] && { printf 'openvpn\t%s\n' "$cfg"; return 0; }
        done < <(openvpn3_configs_list)
    fi
    return 1
}

# Connect/disconnect by name, reporting the outcome on stdout/stderr — the
# backend functions themselves only notify-send, which is invisible over SSH.
vpn_toggle_cli() {
    local action="$1" want="$2" resolved backend id rc=0
    resolved="$(vpn_resolve "$want")" || {
        echo "vpn: no VPN named '$want' (see vpn -l)" >&2
        return 1
    }
    backend="${resolved%%$'\t'*}"
    id="${resolved#*$'\t'}"
    case "$backend:$action" in
        wireguard:connect)     wireguard_connect "$id"    || rc=1 ;;
        wireguard:disconnect)  wireguard_disconnect "$id" || rc=1 ;;
        openvpn:connect)       openvpn3_connect "$id"     || rc=1 ;;
        openvpn:disconnect)    openvpn3_disconnect "$id"  || rc=1 ;;
        tailscale:connect)     tailscale_up               || rc=1 ;;
        tailscale:disconnect)  tailscale_down             || rc=1 ;;
    esac
    if [[ $rc -ne 0 ]]; then
        echo "vpn: failed to ${action} $id" >&2
        return 1
    fi
    echo "vpn: $id ${action}ed"
}

vpn_usage() {
    cat <<EOF
Usage: vpn -l              List VPNs and their connection status
       vpn -c <name>       Connect a VPN
       vpn -d <name>       Disconnect a VPN
       vpn -R <iface|name> -N <display name>
                           Set a WireGuard display name (-N '' resets)
       vpn -h              Show this help

<name> is matched in this order (first hit wins):
  "tailscale"              Tailscale (tailscale up / down)
  WireGuard interface      .conf name in /etc/wireguard (wg-quick up / down)
  WireGuard display name   as set with -R/-N
  openvpn3 config name     as shown by 'openvpn3 configs-list'

The wofi menu (wofi-vpn) drives the same backends and display names, so the
two stay in sync. Display names file: $WIREGUARD_NAMES_FILE
EOF
}

# vpn_main "$@" — full CLI entrypoint: parse args, validate, dispatch.
vpn_main() {
    local mode="" target="" newname="" s_newname=0 opt
    local resolved backend iface
    local OPTIND=1

    while getopts ":lc:d:R:N:h" opt; do
        case "$opt" in
            l) [[ -n "$mode" ]] && { echo "vpn: only one of -l/-c/-d/-R allowed" >&2; return 2; }; mode="list" ;;
            c) [[ -n "$mode" ]] && { echo "vpn: only one of -l/-c/-d/-R allowed" >&2; return 2; }; mode="connect"; target="$OPTARG" ;;
            d) [[ -n "$mode" ]] && { echo "vpn: only one of -l/-c/-d/-R allowed" >&2; return 2; }; mode="disconnect"; target="$OPTARG" ;;
            R) [[ -n "$mode" ]] && { echo "vpn: only one of -l/-c/-d/-R allowed" >&2; return 2; }; mode="rename"; target="$OPTARG" ;;
            N) newname="$OPTARG"; s_newname=1 ;;
            h) vpn_usage; return 0 ;;
            \?) echo "vpn: unknown option -$OPTARG" >&2; vpn_usage >&2; return 2 ;;
            :)  echo "vpn: option -$OPTARG requires an argument" >&2; return 2 ;;
        esac
    done
    shift $((OPTIND - 1))

    case "$mode" in
        list)       vpn_list ;;
        connect)    vpn_toggle_cli connect "$target" ;;
        disconnect) vpn_toggle_cli disconnect "$target" ;;
        rename)
            (( s_newname )) || { echo "vpn: -R requires -N <display name> (use -N '' to reset)" >&2; return 2; }
            resolved="$(vpn_resolve "$target")" || {
                echo "vpn: no VPN named '$target' (see vpn -l)" >&2
                return 1
            }
            backend="${resolved%%$'\t'*}"
            iface="${resolved#*$'\t'}"
            if [[ "$backend" != "wireguard" ]]; then
                echo "vpn: display names are only supported for WireGuard entries" >&2
                return 1
            fi
            wireguard_set_name "$iface" "$newname"
            ;;
        "")
            if (( s_newname )); then
                echo "vpn: -N requires -R <iface>" >&2
                return 2
            fi
            vpn_usage
            ;;
    esac
}
