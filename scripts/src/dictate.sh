DICTATE_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
DICTATE_PIDFILE="$DICTATE_RUNTIME_DIR/dictate.pid"
DICTATE_WAV="$DICTATE_RUNTIME_DIR/dictate.wav"

dictate_start() {
    rm -f "$DICTATE_WAV"
    pw-record "$DICTATE_WAV" &
    echo $! > "$DICTATE_PIDFILE"
    notify-send -t 2000 "Dictation" "Recording... press again to stop"
}

# dictate_stop <script_dir>
dictate_stop() {
    local script_dir="$1" pid text

    pid="$(<"$DICTATE_PIDFILE")"
    rm -f "$DICTATE_PIDFILE"
    kill -INT "$pid" 2>/dev/null || true

    # Wait for pw-record to flush and close the wav before transcribing it.
    for _ in {1..15}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done

    notify-send -t 2000 "Dictation" "Transcribing..."

    text="$("$script_dir/stt" "$DICTATE_WAV")"
    if [[ -n "$text" ]]; then
        wtype -- "$text"
    else
        notify-send -u critical "Dictation" "No text transcribed"
    fi
}

# dictate_main <script_dir>
dictate_main() {
    local script_dir="$1"
    if [[ -f "$DICTATE_PIDFILE" ]]; then
        dictate_stop "$script_dir"
    else
        dictate_start
    fi
}
