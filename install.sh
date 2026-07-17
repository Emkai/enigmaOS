#!/bin/bash
# Entrypoint: run every stage in stages/ in filename order.
# Usage: ./install.sh [--gpu=intel,nvidia] [--extras="embedded extras"] [--from=20]
set -euo pipefail

ENIGMA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$ENIGMA_ROOT/lib/common.sh"
source "$ENIGMA_ROOT/config.sh"

ENIGMA_FROM_STAGE=""

for arg in "$@"; do
    case "$arg" in
        --gpu=*)    GPU_VENDORS="${arg#*=}" ;;
        --extras=*) ENIGMA_EXTRAS="${arg#*=}" ;;
        --from=*)   ENIGMA_FROM_STAGE="${arg#*=}" ;;
        *) die "unknown flag: $arg" ;;
    esac
done

export ENIGMA_ROOT GPU_VENDORS CPU_VENDOR ENIGMA_EXTRAS

# Package/service failures accumulate in this report (see lib/common.sh) and
# are printed by the summary stage instead of killing the run. Start a full
# run with a clean slate; --from resumes keep earlier failures visible.
[[ -n "$ENIGMA_FROM_STAGE" ]] || : > "$ENIGMA_FAILURES"

# Long stages (AUR builds) outlive sudo's cached credentials, and a password
# prompt buried mid-build times out after 5 minutes and kills the run. Ask
# once up front and keep the timestamp fresh. No-op under NOPASSWD.
if ! sudo -n true 2>/dev/null; then
    log "sudo is needed for package installs — asking once up front."
    sudo -v || die "sudo authentication failed"
fi
# `sudo -n true` rather than `sudo -n -v`: any successful sudo refreshes the
# timestamp, and -v insists on (re)authentication under a mixed NOPASSWD +
# wheel-with-password sudoers (the firstboot setup), where it fails with -n
# and silently killed the keepalive.
( while sleep 60; do sudo -n true 2>/dev/null || exit; done ) &
sudo_keepalive=$!
# `|| true`: under set -e a failing command in an EXIT trap overrides the
# script's exit code — a dead keepalive here turned a fully successful run
# into "exit 1", which firstboot read as failure and kept autologin armed.
trap 'kill "$sudo_keepalive" 2>/dev/null || true' EXIT

for stage in "$ENIGMA_ROOT"/stages/*.sh; do
    name=$(basename "$stage")
    prefix="${name%%-*}"
    if [[ -n "$ENIGMA_FROM_STAGE" && "$prefix" < "$ENIGMA_FROM_STAGE" ]]; then
        continue
    fi
    log "=== $name ==="
    bash "$stage"
done
