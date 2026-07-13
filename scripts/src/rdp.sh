#!/bin/bash

RDP_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rdp"
RDP_CONFIG_FILE="$RDP_CONFIG_DIR/connections.json"

rdp_init() {
    mkdir -p "$RDP_CONFIG_DIR"
    if [[ ! -f "$RDP_CONFIG_FILE" ]]; then
        echo '{"connections":[]}' > "$RDP_CONFIG_FILE"
        chmod 600 "$RDP_CONFIG_FILE"
    fi
}

# Machine-bound key: derived from /etc/machine-id + a static salt.
# No usable secret lives in the repo, and the config can't be decrypted on
# another machine. /etc/machine-id is world-readable, so this is "no plaintext
# at rest", not strong crypto.
rdp_enc_key() {
    printf '%s' "$(cat /etc/machine-id)rdp-v1-salt"
}

# plaintext (stdin) -> single-line base64 ciphertext (stdout)
rdp_encrypt() {
    local k
    k="$(rdp_enc_key)"
    _RDP_K="$k" openssl enc -aes-256-cbc -pbkdf2 -salt -a -A -pass env:_RDP_K
}

# base64 ciphertext (stdin) -> plaintext (stdout)
rdp_decrypt() {
    local k
    k="$(rdp_enc_key)"
    _RDP_K="$k" openssl enc -d -aes-256-cbc -pbkdf2 -a -A -pass env:_RDP_K
}

# Atomic write of a full JSON document, kept at mode 600.
rdp_save() {
    local json="$1" tmp
    tmp="$(mktemp)"
    printf '%s\n' "$json" > "$tmp"
    mv "$tmp" "$RDP_CONFIG_FILE"
    chmod 600 "$RDP_CONFIG_FILE"
}

rdp_valid_name() {
    local name="$1"
    if [[ -z "$name" ]] || ! [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "rdp: invalid name '$name' (expected [A-Za-z0-9_-]+)" >&2
        return 2
    fi
    if ! [[ "$name" =~ [A-Za-z] ]]; then
        echo "rdp: name '$name' must contain a letter (so it can't be confused with an index)" >&2
        return 2
    fi
}

rdp_exists() {
    local name="$1" n
    n=$(jq -r --arg n "$name" '[.connections[] | select(.name == $n)] | length' "$RDP_CONFIG_FILE")
    [[ "$n" -gt 0 ]]
}

rdp_get() {
    local name="$1" field="$2"
    jq -r --arg n "$name" --arg f "$field" \
        '.connections[] | select(.name == $n) | .[$f] // ""' "$RDP_CONFIG_FILE"
}

# Connection names, one per line (for menus / scripting).
rdp_names() {
    jq -r '.connections[].name' "$RDP_CONFIG_FILE"
}

# Resolve a name or 1-based index to a connection name. Echoes the name on
# success; prints an error and returns 2 if it doesn't exist.
rdp_resolve() {
    local target="$1" name
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        if (( target < 1 )); then
            echo "rdp: index must be >= 1 (got '$target')" >&2
            return 2
        fi
        name=$(jq -r --argjson i "$target" '.connections[$i - 1].name // ""' "$RDP_CONFIG_FILE")
        if [[ -z "$name" ]]; then
            echo "rdp: no connection at index $target" >&2
            return 2
        fi
    else
        if ! rdp_exists "$target"; then
            echo "rdp: no connection named '$target'" >&2
            return 2
        fi
        name="$target"
    fi
    printf '%s\n' "$name"
}

rdp_list() {
    local count
    count=$(jq '.connections | length' "$RDP_CONFIG_FILE")
    if [[ "$count" -eq 0 ]]; then
        echo "(no connections — create one with 'rdp -n')"
        return 0
    fi
    jq -r '.connections | to_entries[]
        | "\(.key + 1): \(.value.name)  (\(.value.user)@\(.value.server))"
          + (if .value.domain != "" then "  d:\(.value.domain)" else "" end)
          + (if (.value.proxy // "") != "" then "  y:\(.value.proxy)" else "" end)
          + (if .value.extra  != "" then "  x:\(.value.extra)"  else "" end)' \
        "$RDP_CONFIG_FILE"
}

# rdp_new <name> <server> <domain> <user> <password> <extra> <proxy>
# Prompts for any missing required field (name, server, user). Password is
# stored AES-encrypted, or left empty (prompted at connect time) if absent.
rdp_new() {
    local name="$1" server="$2" domain="$3" user="$4" password="$5" extra="$6" proxy="$7"
    local enc="" json

    [[ -z "$name" ]] && read -rp "Name: " name
    rdp_valid_name "$name" || return $?
    if rdp_exists "$name"; then
        echo "rdp: connection '$name' already exists (use -E to edit)" >&2
        return 2
    fi
    [[ -z "$server" ]] && read -rp "Server (/v:): " server
    [[ -z "$user" ]] && read -rp "Username (/u:): " user
    if [[ -z "$server" || -z "$user" ]]; then
        echo "rdp: server and user are required" >&2
        return 2
    fi

    [[ -n "$password" ]] && enc="$(printf '%s' "$password" | rdp_encrypt)"

    json="$(jq --arg name "$name" --arg server "$server" --arg domain "$domain" \
               --arg user "$user" --arg password "$enc" --arg extra "$extra" \
               --arg proxy "$proxy" \
        '.connections += [{name:$name, server:$server, domain:$domain, user:$user, password:$password, extra:$extra, proxy:$proxy}]' \
        "$RDP_CONFIG_FILE")"
    rdp_save "$json"
    echo "rdp: added '$name'"
}

# rdp_edit <target> <s_name> <name> <s_server> <server> <s_domain> <domain>
#          <s_user> <user> <s_pass> <pass> <s_extra> <extra> <s_proxy> <proxy>
# Each s_* is 1 when that field flag was given; only those fields change.
rdp_edit() {
    local target="$1"
    local s_name="$2" v_name="$3" s_server="$4" v_server="$5" s_domain="$6" v_domain="$7"
    local s_user="$8" v_user="$9" s_pass="${10}" v_pass="${11}" s_extra="${12}" v_extra="${13}"
    local s_proxy="${14}" v_proxy="${15}"
    local name json enc

    name="$(rdp_resolve "$target")" || return $?
    json="$(cat "$RDP_CONFIG_FILE")"

    # Field updates select by the current name; the rename (if any) is applied
    # last so these selectors stay valid.
    if [[ "$s_server" == 1 ]]; then
        json="$(printf '%s' "$json" | jq --arg n "$name" --arg v "$v_server" \
            '(.connections[] | select(.name == $n) | .server) = $v')"
    fi
    if [[ "$s_domain" == 1 ]]; then
        json="$(printf '%s' "$json" | jq --arg n "$name" --arg v "$v_domain" \
            '(.connections[] | select(.name == $n) | .domain) = $v')"
    fi
    if [[ "$s_user" == 1 ]]; then
        json="$(printf '%s' "$json" | jq --arg n "$name" --arg v "$v_user" \
            '(.connections[] | select(.name == $n) | .user) = $v')"
    fi
    if [[ "$s_extra" == 1 ]]; then
        json="$(printf '%s' "$json" | jq --arg n "$name" --arg v "$v_extra" \
            '(.connections[] | select(.name == $n) | .extra) = $v')"
    fi
    if [[ "$s_proxy" == 1 ]]; then
        json="$(printf '%s' "$json" | jq --arg n "$name" --arg v "$v_proxy" \
            '(.connections[] | select(.name == $n) | .proxy) = $v')"
    fi
    if [[ "$s_pass" == 1 ]]; then
        enc=""
        [[ -n "$v_pass" ]] && enc="$(printf '%s' "$v_pass" | rdp_encrypt)"
        json="$(printf '%s' "$json" | jq --arg n "$name" --arg v "$enc" \
            '(.connections[] | select(.name == $n) | .password) = $v')"
    fi
    if [[ "$s_name" == 1 ]]; then
        rdp_valid_name "$v_name" || return $?
        if [[ "$v_name" != "$name" ]] && rdp_exists "$v_name"; then
            echo "rdp: connection '$v_name' already exists" >&2
            return 2
        fi
        json="$(printf '%s' "$json" | jq --arg n "$name" --arg v "$v_name" \
            '(.connections[] | select(.name == $n) | .name) = $v')"
    fi

    rdp_save "$json"
    echo "rdp: updated '$name'"
}

# rdp_show <target> — print a connection's stored config in a readable form.
# The password is never printed (it's encrypted at rest and the whole point of
# this script is to keep it off ps/stdout); we only note whether one is stored.
rdp_show() {
    local target="$1" name server domain user enc extra proxy
    name="$(rdp_resolve "$target")" || return $?
    server="$(rdp_get "$name" server)"
    domain="$(rdp_get "$name" domain)"
    user="$(rdp_get "$name" user)"
    enc="$(rdp_get "$name" password)"
    extra="$(rdp_get "$name" extra)"
    proxy="$(rdp_get "$name" proxy)"

    printf 'name:     %s\n' "$name"
    printf 'server:   %s\n' "$server"
    printf 'domain:   %s\n' "${domain:-(none)}"
    printf 'user:     %s\n' "$user"
    if [[ -n "$enc" ]]; then
        printf 'password: %s\n' "(stored, encrypted)"
    else
        printf 'password: %s\n' "(none — prompted at connect)"
    fi
    printf 'proxy:    %s\n' "${proxy:-(none)}"
    printf 'extra:    %s\n' "${extra:-(none)}"
}

rdp_remove() {
    local target="$1" name reply json
    name="$(rdp_resolve "$target")" || return $?
    if [[ -n "${RDP_YES:-}" ]]; then
        reply=y
    else
        read -rp "Delete connection '$name'? [y/N] " reply
    fi
    if [[ ! "$reply" =~ ^[yY]$ ]]; then
        echo "aborted"
        return 0
    fi
    json="$(jq --arg n "$name" '.connections |= map(select(.name != $n))' "$RDP_CONFIG_FILE")"
    rdp_save "$json"
    echo "rdp: removed '$name'"
}

# Find a free local port for the SSH SOCKS tunnel. A /dev/tcp connect that
# fails means nothing is listening there.
rdp_free_port() {
    local p
    for p in {24580..24680}; do
        if ! (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

# Build the xfreerdp3 invocation and connect. The password is fed via
# /from-stdin (never /p:) so it never appears in ps/proc. If the connection
# has a proxy, a URL (socks5://, http://) is handed to xfreerdp3 as-is, while
# an SSH destination ([user@]host[:port] or ssh://...) gets a SOCKS tunnel
# (ssh -D) opened first and torn down after. Set RDP_DRYRUN=1 to print the
# commands instead of launching.
rdp_connect() {
    local target="$1" name server domain user enc password="" extra proxy
    name="$(rdp_resolve "$target")" || return $?
    server="$(rdp_get "$name" server)"
    domain="$(rdp_get "$name" domain)"
    user="$(rdp_get "$name" user)"
    enc="$(rdp_get "$name" password)"
    extra="$(rdp_get "$name" extra)"
    proxy="$(rdp_get "$name" proxy)"

    # RDP_PASSWORD lets a front-end (e.g. the wofi menu) supply an
    # already-decrypted password to a detached, TTY-less launch.
    if [[ -n "${RDP_PASSWORD:-}" ]]; then
        password="$RDP_PASSWORD"
    else
        [[ -n "$enc" ]] && password="$(printf '%s' "$enc" | rdp_decrypt)"
        if [[ -z "$password" ]]; then
            read -rsp "Password for '$name': " password
            echo
        fi
    fi

    local proxy_url="" tunnel_cmd=() ssh_dest=""
    if [[ -n "$proxy" ]]; then
        if [[ "$proxy" == *://* && "$proxy" != ssh://* ]]; then
            proxy_url="$proxy"
        else
            local ssh_port="" lport
            ssh_dest="${proxy#ssh://}"
            if [[ "$ssh_dest" =~ ^(.+):([0-9]+)$ ]]; then
                ssh_dest="${BASH_REMATCH[1]}"
                ssh_port="${BASH_REMATCH[2]}"
            fi
            lport="$(rdp_free_port)" || {
                echo "rdp: no free local port for the SSH tunnel" >&2
                return 1
            }
            tunnel_cmd=(ssh -N -D "127.0.0.1:$lport" -o ExitOnForwardFailure=yes)
            [[ -n "$ssh_port" ]] && tunnel_cmd+=(-p "$ssh_port")
            tunnel_cmd+=("$ssh_dest")
            proxy_url="socks5://127.0.0.1:$lport"
        fi
    fi

    local args=(/v:"$server")
    [[ -n "$domain" ]] && args+=(/d:"$domain")
    args+=(/u:"$user" /from-stdin)
    [[ -n "$proxy_url" ]] && args+=(/proxy:"$proxy_url")
    if [[ -n "$extra" ]]; then
        local ex
        read -ra ex <<< "$extra"
        args+=("${ex[@]}")
    fi

    if [[ -n "${RDP_DRYRUN:-}" ]]; then
        if (( ${#tunnel_cmd[@]} )); then
            printf 'tunnel:'
            printf ' %q' "${tunnel_cmd[@]}"
            printf '\n'
        fi
        printf 'xfreerdp3'
        printf ' %q' "${args[@]}"
        printf '   (password via stdin)\n'
        return 0
    fi

    local tunnel_pid=""
    if (( ${#tunnel_cmd[@]} )); then
        # stdout to /dev/null so a captured fd can't outlive us; stderr stays
        # visible for auth errors. ssh prompts (password/hostkey) go via
        # /dev/tty, so an interactive run can still answer them.
        "${tunnel_cmd[@]}" >/dev/null &
        tunnel_pid=$!
        # Belt and braces: kill the tunnel if we exit any way other than the
        # explicit cleanup below (Ctrl-C, set -e, ...).
        trap "kill $tunnel_pid 2>/dev/null" EXIT

        # Wait for the SOCKS port to accept connections. Generous timeout so
        # interactive ssh auth has time; bail immediately if ssh gives up.
        local i ok=""
        for ((i = 0; i < 300; i++)); do
            if ! kill -0 "$tunnel_pid" 2>/dev/null; then
                echo "rdp: SSH tunnel via '$ssh_dest' failed" >&2
                trap - EXIT
                return 1
            fi
            if (exec 3<>"/dev/tcp/127.0.0.1/$lport") 2>/dev/null; then
                ok=1
                break
            fi
            sleep 0.2
        done
        if [[ -z "$ok" ]]; then
            echo "rdp: SSH tunnel via '$ssh_dest' did not come up in time" >&2
            kill "$tunnel_pid" 2>/dev/null
            trap - EXIT
            return 1
        fi
    fi

    local rc=0
    printf '%s\n' "$password" | xfreerdp3 "${args[@]}" || rc=$?
    if [[ -n "$tunnel_pid" ]]; then
        kill "$tunnel_pid" 2>/dev/null
        trap - EXIT
    fi
    return "$rc"
}

rdp_usage() {
    cat <<EOF
Usage: rdp -l                       List stored connections
       rdp -e <name|index>          Connect to a stored connection
       rdp -P <name|index>          Print a stored connection's config (password masked)
       rdp -n [field flags]         Create a connection (missing required fields are prompted)
       rdp -E <name|index> [flags]  Edit a connection (only the given fields change)
       rdp -r <name|index>          Remove a connection (asks for confirmation)
       rdp -h                       Show this help

Field flags (for -n and -E):
  -N name     Connection name (must contain a letter; never purely numeric)
  -s server   Server/host        -> /v:
  -d domain   Domain             -> /d:
  -u user     Username           -> /u:
  -p pass     Password (stored AES-encrypted, machine-bound key)
  -y proxy    Proxy to connect through:
                socks5://host:port, http://host:port  -> passed to /proxy: as-is
                [user@]host[:port] or ssh://...       -> SSH SOCKS tunnel (ssh -D)
                                                         opened first, closed after
  -x "extra"  Extra xfreerdp3 args appended verbatim (e.g. "/dynamic-resolution")

Connections may be referenced by name or by the 1-based index shown in 'rdp -l'.
Passwords are encrypted at rest and passed to xfreerdp3 via /from-stdin
(so they never appear in the process list). Config file is kept at mode 600.
SSH-tunnel proxies need non-interactive auth (key/agent) when launched from
the wofi menu, since that runs detached from any terminal.

Config: $RDP_CONFIG_FILE
EOF
}

# rdp_main "$@" — full CLI entrypoint: parse args, validate, dispatch.
rdp_main() {
    rdp_init

    local mode="" target="" opt
    local name="" server="" domain="" user="" password="" extra="" proxy=""
    local s_name=0 s_server=0 s_domain=0 s_user=0 s_pass=0 s_extra=0 s_proxy=0
    local OPTIND=1

    while getopts ":lnN:s:d:u:p:x:y:e:r:E:P:h" opt; do
        case "$opt" in
            l) [[ -n "$mode" ]] && { echo "rdp: only one of -l/-n/-e/-r/-E/-P allowed" >&2; return 2; }; mode="list" ;;
            n) [[ -n "$mode" ]] && { echo "rdp: only one of -l/-n/-e/-r/-E/-P allowed" >&2; return 2; }; mode="new" ;;
            e) [[ -n "$mode" ]] && { echo "rdp: only one of -l/-n/-e/-r/-E/-P allowed" >&2; return 2; }; mode="connect"; target="$OPTARG" ;;
            r) [[ -n "$mode" ]] && { echo "rdp: only one of -l/-n/-e/-r/-E/-P allowed" >&2; return 2; }; mode="remove"; target="$OPTARG" ;;
            E) [[ -n "$mode" ]] && { echo "rdp: only one of -l/-n/-e/-r/-E/-P allowed" >&2; return 2; }; mode="edit"; target="$OPTARG" ;;
            P) [[ -n "$mode" ]] && { echo "rdp: only one of -l/-n/-e/-r/-E/-P allowed" >&2; return 2; }; mode="show"; target="$OPTARG" ;;
            N) name="$OPTARG"; s_name=1 ;;
            s) server="$OPTARG"; s_server=1 ;;
            d) domain="$OPTARG"; s_domain=1 ;;
            u) user="$OPTARG"; s_user=1 ;;
            p) password="$OPTARG"; s_pass=1 ;;
            y) proxy="$OPTARG"; s_proxy=1 ;;
            x) extra="$OPTARG"; s_extra=1 ;;
            h) rdp_usage; return 0 ;;
            \?) echo "rdp: unknown option -$OPTARG" >&2; rdp_usage >&2; return 2 ;;
            :)  echo "rdp: option -$OPTARG requires an argument" >&2; return 2 ;;
        esac
    done
    shift $((OPTIND - 1))

    case "$mode" in
        list)    rdp_list ;;
        connect) rdp_connect "$target" ;;
        show)    rdp_show "$target" ;;
        remove)  rdp_remove "$target" ;;
        new)     rdp_new "$name" "$server" "$domain" "$user" "$password" "$extra" "$proxy" ;;
        edit)    rdp_edit "$target" \
                     "$s_name" "$name" "$s_server" "$server" "$s_domain" "$domain" \
                     "$s_user" "$user" "$s_pass" "$password" "$s_extra" "$extra" \
                     "$s_proxy" "$proxy" ;;
        "")
            if (( s_name || s_server || s_domain || s_user || s_pass || s_extra || s_proxy )); then
                echo "rdp: field flags require -n (new) or -E (edit)" >&2
                rdp_usage >&2
                return 2
            fi
            rdp_usage
            ;;
    esac
}
