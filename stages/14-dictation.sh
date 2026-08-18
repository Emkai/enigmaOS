#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

# Only relevant if the dictation extras tier was selected — it installs pipx
# (packages/optional/dictation.txt, stage 12). whisper-ctranslate2 isn't a
# pacman/AUR package, so it's pipx-installed here instead.
[[ " $ENIGMA_EXTRAS " == *" dictation "* ]] || exit 0

dictation_pkgs="$ENIGMA_ROOT/packages/optional/dictation.txt"

if ! command -v pipx &>/dev/null; then
    warn "pipx not found — did packages/optional/dictation.txt install? Skipping whisper-ctranslate2."
    record_failure "whisper-ctranslate2" "$dictation_pkgs"
    exit 0
fi

if pipx list --short 2>/dev/null | grep -q '^whisper-ctranslate2 '; then
    log "whisper-ctranslate2 already installed via pipx"
else
    log "pipx install whisper-ctranslate2 (faster-whisper + friends — several minutes, mostly silent)"
    if ! pipx install whisper-ctranslate2; then
        warn "pipx install whisper-ctranslate2 failed"
        record_failure "whisper-ctranslate2" "$dictation_pkgs"
        exit 0
    fi
fi

# whisper-ctranslate2 does NOT pull in CUDA libs on its own — without this,
# faster-whisper detects the NVIDIA GPU, tries to use it, and dies with
# "Library libcublas.so.12 is not found" (scripts/stt falls back to CPU when
# that happens, but it's a slow, avoidable stumble on every run). These are
# injected straight into the pipx venv rather than a system-wide CUDA
# install, since Arch's `cuda` package has moved past v12 and ships
# libcublas.so.13 — a version faster-whisper doesn't expect.
if command -v lspci &>/dev/null && lspci -k 2>/dev/null | grep -qi 'VGA.*NVIDIA\|3D.*NVIDIA'; then
    log "NVIDIA GPU detected — injecting CUDA libs (nvidia-cublas-cu12, nvidia-cudnn-cu12) into the whisper-ctranslate2 venv"
    if ! pipx inject whisper-ctranslate2 nvidia-cublas-cu12 nvidia-cudnn-cu12; then
        warn "pipx inject nvidia-cublas-cu12/nvidia-cudnn-cu12 failed — dictation will fall back to CPU"
        record_failure "whisper-ctranslate2-cuda" "$dictation_pkgs"
    fi
else
    log "No NVIDIA GPU detected — skipping CUDA libs, dictation will run on CPU"
fi
