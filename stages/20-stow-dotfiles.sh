#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

configs_dir="$ENIGMA_ROOT/configs"
dry_run_log=$(mktemp)
trap 'rm -f "$dry_run_log"' EXIT

if ! (cd "$configs_dir" && stow --target="$HOME" --no --verbose */) >"$dry_run_log" 2>&1; then
    if grep -qi 'existing target' "$dry_run_log"; then
        cat "$dry_run_log" >&2
        die "stow conflicts detected — back up/remove the listed pre-existing dotfiles, then re-run this stage."
    fi
    cat "$dry_run_log" >&2
    die "stow dry-run failed for an unexpected reason, see output above."
fi

"$ENIGMA_ROOT/scripts/re_cfg_stow"
