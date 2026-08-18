STT_BIN="$HOME/.local/share/pipx/venvs/whisper-ctranslate2/bin/whisper-ctranslate2"
STT_MODEL="${STT_MODEL:-small}"

# Run whisper-ctranslate2 once for the given device. Writes <outdir>/<base>.txt
# on success; on failure (e.g. CUDA libs missing when exec'd outside a shell
# that sources ~/.bashrc) it prints a traceback but still exits 0 and leaves
# no output file, so callers must check for the file rather than the exit code.
stt_transcribe() {
    local audio="$1" device="$2" outdir="$3"
    "$STT_BIN" --model "$STT_MODEL" --device "$device" \
        --output_format txt --output_dir "$outdir" "$audio" \
        >/dev/null 2>>"$outdir/stderr.log"
}

# stt_main <audio-file> — prints the transcription to stdout.
stt_main() {
    local audio="${1-}"
    if [[ -z "$audio" || ! -f "$audio" ]]; then
        echo "usage: stt <audio-file>" >&2
        return 1
    fi

    local outdir base txt
    outdir="$(mktemp -d)"
    trap 'rm -rf "$outdir"' RETURN
    base="$(basename "$audio")"
    txt="$outdir/${base%.*}.txt"

    stt_transcribe "$audio" auto "$outdir"
    if [[ ! -f "$txt" ]]; then
        stt_transcribe "$audio" cpu "$outdir"
    fi

    if [[ ! -f "$txt" ]]; then
        cat "$outdir/stderr.log" >&2
        return 1
    fi

    cat "$txt"
}
