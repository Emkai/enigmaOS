#!/bin/bash

RCLONE_SYNC_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rclone-sync"
RCLONE_SYNC_PAIRS="$RCLONE_SYNC_CONFIG_DIR/pairs"
RCLONE_SYNC_AUTO="$RCLONE_SYNC_CONFIG_DIR/auto"
RCLONE_SYNC_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/rclone-sync"
RCLONE_SYNC_ROOT="${RCLONE_SYNC_ROOT:-$HOME/SharePoint}"
RCLONE_SYNC_UNIT="rclone-sync"
RCLONE_SYNC_INTERVAL="${RCLONE_SYNC_INTERVAL:-15min}"
RCLONE_SYNC_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rclone-sync"

rclone_remotes() {
    rclone listremotes 2>/dev/null | sed 's/:$//'
}

rclone_remote_dirs() {
    rclone lsf --dirs-only --max-depth 1 "$1:" 2>/dev/null | sed 's:/$::'
}

rclone_pairs() {
    [[ -f "$RCLONE_SYNC_PAIRS" ]] && grep -v '^\s*$' "$RCLONE_SYNC_PAIRS" | cut -f1
}

rclone_pair_add() {
    mkdir -p "$RCLONE_SYNC_CONFIG_DIR"
    rclone_pairs | grep -qxF "$1" && return 0
    if [[ -n "${2:-}" ]]; then
        printf '%s\t%s\n' "$1" "$(realpath -m "$2")" >> "$RCLONE_SYNC_PAIRS"
    else
        printf '%s\n' "$1" >> "$RCLONE_SYNC_PAIRS"
    fi
}

rclone_pair_remove() {
    local tmp
    [[ -f "$RCLONE_SYNC_PAIRS" ]] || return 0
    tmp="$(mktemp)"
    awk -F'\t' -v p="$1" '$1 != p' "$RCLONE_SYNC_PAIRS" > "$tmp"
    mv "$tmp" "$RCLONE_SYNC_PAIRS"
    rm -rf "${RCLONE_SYNC_STATE:?}/$(rclone_pair_id "$1")"
}

rclone_pair_id() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

rclone_pair_local() {
    local remote="${1%%:*}" path="${1#*:}" custom
    custom="$(awk -F'\t' -v p="$1" '$1 == p && $2 != "" { print $2; exit }' "$RCLONE_SYNC_PAIRS" 2>/dev/null)"
    if [[ -n "$custom" ]]; then
        printf '%s' "$custom"
    else
        printf '%s/%s/%s' "$RCLONE_SYNC_ROOT" "$remote" "$path"
    fi
}

rclone_pair_status() {
    local f="$RCLONE_SYNC_STATE/$(rclone_pair_id "$1")/status"
    [[ -f "$f" ]] && cat "$f" || printf 'never synced'
}

rclone_pair_log() {
    printf '%s/%s/log' "$RCLONE_SYNC_STATE" "$(rclone_pair_id "$1")"
}

rclone_sync_pair() {
    local pair="$1" local_dir workdir resync=() rc
    local_dir="$(rclone_pair_local "$pair")"
    workdir="$RCLONE_SYNC_STATE/$(rclone_pair_id "$pair")"
    mkdir -p "$local_dir" "$workdir"
    compgen -G "$workdir/*.lst" >/dev/null || resync=(--resync --resync-mode newer)

    printf 'syncing since %(%H:%M)T' -1 > "$workdir/status"
    rclone bisync "$pair" "$local_dir" "${resync[@]}" \
        --workdir "$workdir" \
        --compare modtime \
        --create-empty-src-dirs \
        --exclude '~*.lck' --exclude '~$*' --exclude '.~lock.*#' \
        --resilient --recover --max-lock 5m \
        --conflict-resolve newer --conflict-loser num \
        --log-file "$workdir/log" --log-level INFO
    rc=$?

    if (( rc == 0 )); then
        printf 'ok %(%Y-%m-%d %H:%M)T' -1 > "$workdir/status"
    else
        printf 'failed %(%Y-%m-%d %H:%M)T' -1 > "$workdir/status"
        notify-send -u critical "rclone" "Sync failed: $pair"
    fi
    return "$rc"
}

rclone_sync_all() {
    local pair rc=0
    exec {lock}>"${XDG_RUNTIME_DIR:-/tmp}/rclone-sync.lock"
    flock -n "$lock" || { echo "rclone-sync: already running" >&2; return 1; }
    while IFS= read -r pair; do
        rclone_sync_pair "$pair" || rc=1
    done < <(rclone_pairs)
    return "$rc"
}

rclone_syncing() {
    systemctl --user is-active --quiet "$RCLONE_SYNC_UNIT.service" \
        || ! flock -n "${XDG_RUNTIME_DIR:-/tmp}/rclone-sync.lock" true
}

rclone_sync_now() {
    rclone_syncing && return 0
    if rclone_auto_enabled; then
        systemctl --user start --no-block "$RCLONE_SYNC_UNIT.service"
    else
        setsid -f "$RCLONE_SYNC_BIN" sync >/dev/null 2>&1
    fi
}

rclone_auto_enabled() {
    systemctl --user is-active --quiet "$RCLONE_SYNC_UNIT.timer"
}

rclone_auto_start() {
    mkdir -p "$RCLONE_SYNC_CONFIG_DIR"
    touch "$RCLONE_SYNC_AUTO"
    rclone_auto_enabled && return 0
    systemctl --user reset-failed "$RCLONE_SYNC_UNIT.service" "$RCLONE_SYNC_UNIT.timer" 2>/dev/null
    systemd-run --user --quiet --unit "$RCLONE_SYNC_UNIT" \
        --on-active=10s --on-unit-inactive="$RCLONE_SYNC_INTERVAL" \
        "$RCLONE_SYNC_BIN" sync
}

rclone_auto_stop() {
    rm -f "$RCLONE_SYNC_AUTO"
    systemctl --user stop "$RCLONE_SYNC_UNIT.timer" 2>/dev/null
}

rclone_auto_restore() {
    [[ -f "$RCLONE_SYNC_AUTO" ]] && rclone_auto_start
    return 0
}

rclone_usage() {
    cat <<EOF
Usage: rclone-sync <command>
  sync       two-way sync every pair now
  start      sync every $RCLONE_SYNC_INTERVAL in the background
  stop       stop background sync
  restore    start background sync if it was on (login hook)
  status     show pairs and their last result
  add <remote:path> [local dir] | remove <remote:path>
Pairs sync to [local dir], or $RCLONE_SYNC_ROOT/<remote>/<path> when omitted.
EOF
}

rclone_main() {
    local pair
    case "${1:-}" in
        sync)    rclone_sync_all ;;
        start)   rclone_auto_start ;;
        stop)    rclone_auto_stop ;;
        restore) rclone_auto_restore ;;
        add)     [[ -n "${2:-}" ]] || { rclone_usage >&2; return 2; }; rclone_pair_add "$2" "${3:-}" ;;
        remove)  [[ -n "${2:-}" ]] || { rclone_usage >&2; return 2; }; rclone_pair_remove "$2" ;;
        status)
            rclone_auto_enabled && echo "auto: on" || echo "auto: off"
            while IFS= read -r pair; do
                printf '%s\t%s\n' "$pair" "$(rclone_pair_status "$pair")"
            done < <(rclone_pairs)
            ;;
        -h|--help|"") rclone_usage ;;
        *) rclone_usage >&2; return 2 ;;
    esac
}
