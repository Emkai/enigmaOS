ASKVOICE_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
ASKVOICE_PIDFILE="$ASKVOICE_RUNTIME_DIR/ask-voice.pid"
ASKVOICE_WAV="$ASKVOICE_RUNTIME_DIR/ask-voice.wav"
ASKVOICE_ANSWER="$ASKVOICE_RUNTIME_DIR/ask-voice-answer.txt"

askvoice_start() {
    rm -f "$ASKVOICE_WAV"
    pw-record "$ASKVOICE_WAV" &
    echo $! > "$ASKVOICE_PIDFILE"
    notify-send -t 2000 "Ask" "Recording... press again to stop"
}

# askvoice_show <text> — floating popup in the middle of the screen,
# closes on Enter/Esc (see scripts/ask-voice-popup and the "ask-voice-popup"
# window rule in configs/hypr/.config/hypr/windows.lua).
askvoice_show() {
    local script_dir="$1" text="$2"
    printf '%s\n' "$text" > "$ASKVOICE_ANSWER"
    kitty --class ask-voice-popup -e "$script_dir/ask-voice-popup" "$ASKVOICE_ANSWER" &
    disown
}

# askvoice_stop <script_dir>
askvoice_stop() {
    local script_dir="$1" pid text answer

    pid="$(<"$ASKVOICE_PIDFILE")"
    rm -f "$ASKVOICE_PIDFILE"
    kill -INT "$pid" 2>/dev/null || true

    # Wait for pw-record to flush and close the wav before transcribing it.
    for _ in {1..15}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done

    notify-send -t 2000 "Ask" "Transcribing..."

    text="$("$script_dir/stt" "$ASKVOICE_WAV")"
    if [[ -z "$text" ]]; then
        notify-send -u critical "Ask" "No text transcribed"
        return 0
    fi

    notify-send -t 3000 "Ask" "Asking..."
    answer="$("$script_dir/ask" -n -M "$text")"
    askvoice_show "$script_dir" "$answer"
}

# askvoice_main <script_dir>
askvoice_main() {
    local script_dir="$1"
    if [[ -f "$ASKVOICE_PIDFILE" ]]; then
        askvoice_stop "$script_dir"
    else
        askvoice_start
    fi
}
