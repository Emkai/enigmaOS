#!/bin/bash

# Open a Chromium session routed through a remote host via an SSH SOCKS5 tunnel.
# Uses a throwaway profile and forces DNS resolution through the proxy (no leak),
# then tears down the tunnel and deletes the profile on exit.
#
# Usage: proxy-browse.sh [-p PORT] [-l] <ssh-host>
#   <ssh-host>  Host alias from ~/.ssh/config (or user@host)
#   -p PORT     local SOCKS port (default: 1080)
#   -l          route loopback through the proxy so http://127.0.0.1:PORT
#               and localhost reach services bound to the remote's loopback

set -euo pipefail

port=1080
loopback=false

usage() {
    echo "Usage: $(basename "$0") [-p PORT] [-l] <ssh-host>" >&2
    exit 1
}

while getopts ":p:lh" opt; do
    case "$opt" in
        p) port="$OPTARG" ;;
        l) loopback=true ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

host="${1:-}"
[ -z "$host" ] && usage

command -v ssh >/dev/null || { echo "ssh not found" >&2; exit 1; }
command -v chromium >/dev/null || { echo "chromium not found" >&2; exit 1; }

profile_dir=$(mktemp -d /tmp/proxy-browse.XXXXXX)
ssh_pid=""

cleanup() {
    [ -n "$ssh_pid" ] && kill "$ssh_pid" 2>/dev/null || true
    rm -rf "$profile_dir"
}
trap cleanup EXIT INT TERM

echo "Starting SSH SOCKS5 tunnel on 127.0.0.1:$port via $host ..."
ssh -N -D "127.0.0.1:$port" "$host" &
ssh_pid=$!

# Wait for the tunnel to actually accept connections (abort if SSH dies first).
for _ in $(seq 1 20); do
    if ! kill -0 "$ssh_pid" 2>/dev/null; then
        echo "SSH tunnel failed to start." >&2
        exit 1
    fi
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
        exec 3>&- 3<&-
        break
    fi
    sleep 0.5
done

if ! (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    echo "Tunnel did not come up within timeout." >&2
    exit 1
fi
exec 3>&- 3<&-

echo "Tunnel up. Launching Chromium (temp profile, DNS via proxy)."
chromium_args=(
    --user-data-dir="$profile_dir"
    --proxy-server="socks5://127.0.0.1:$port"
    --host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE 127.0.0.1"
    --no-first-run
)
# Send loopback through the proxy too, so 127.0.0.1/localhost reach the
# remote's loopback instead of being bypassed to this machine.
$loopback && chromium_args+=(--proxy-bypass-list="<-loopback>")

chromium "${chromium_args[@]}"

echo "Chromium closed. Cleaning up."
