#!/usr/bin/env bash
# Temporarily serve iso/out/ over HTTP so another machine on the LAN can
# fetch the newest ISO (e.g. to re-image a USB or update install media
# without walking a stick back and forth).
#
#   ./iso/serve-iso.sh [port]     # default port 8000, Ctrl-C to stop
set -euo pipefail

ISO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${1:-8000}"

c_red=$'\033[1;31m'; c_cyn=$'\033[1;36m'; c_rst=$'\033[0m'
die() { printf '%s[serve-iso] ERROR:%s %s\n' "$c_red" "$c_rst" "$*" >&2; exit 1; }

command -v python3 >/dev/null || die "python3 is required to serve the ISO."

NEWEST="$(ls -t "$ISO_DIR"/out/*.iso 2>/dev/null | head -1 || true)"
[[ -n "$NEWEST" ]] || die "no ISO found in iso/out/ — run build-iso.sh first."

# best-effort LAN address; fall back to listing everything we have
LAN_IP="$(ip -4 route get 1 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="src") print $(i+1); exit}')"
[[ -n "$LAN_IP" ]] || LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -n "$LAN_IP" ]] || LAN_IP="<this-machine-ip>"

echo "Serving $ISO_DIR/out on port $PORT (Ctrl-C to stop)"
echo
echo "Newest ISO: $(basename "$NEWEST") ($(du -h "$NEWEST" | cut -f1))"
printf '  %s http://%s:%s/%s %s\n' "$c_cyn" "$LAN_IP" "$PORT" "$(basename "$NEWEST")" "$c_rst"
echo
echo "From the target machine:"
echo "  curl -O http://$LAN_IP:$PORT/$(basename "$NEWEST")"
echo

exec python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$ISO_DIR/out"
