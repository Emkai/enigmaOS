#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

detect_gpu_vendors() {
    local v=()
    lspci -k 2>/dev/null | grep -qi 'VGA.*Intel\|3D.*Intel'   && v+=(intel)
    lspci -k 2>/dev/null | grep -qi 'VGA.*NVIDIA\|3D.*NVIDIA' && v+=(nvidia)
    lspci -k 2>/dev/null | grep -qiE 'VGA.*(AMD|ATI)'         && v+=(amd)
    echo "${v[@]}"
}

detect_cpu_vendor() {
    grep -qi 'GenuineIntel' /proc/cpuinfo && echo intel || echo amd
}

gpu_vendors="$GPU_VENDORS"
if [[ "$gpu_vendors" == "auto" ]]; then
    gpu_vendors=$(detect_gpu_vendors | tr ' ' ',')
    log "Auto-detected GPU vendor(s): ${gpu_vendors:-none}"
fi

cpu_vendor="$CPU_VENDOR"
if [[ "$cpu_vendor" == "auto" ]]; then
    cpu_vendor=$(detect_cpu_vendor)
    log "Auto-detected CPU vendor: $cpu_vendor"
fi

IFS=',' read -ra vendors <<< "$gpu_vendors"
for v in "${vendors[@]}"; do
    [[ -n "$v" ]] || continue
    f="$ENIGMA_ROOT/packages/gpu/$v.txt"
    [[ -f "$f" ]] || { log "No gpu package list for '$v', skipping"; continue; }
    pacman_install "$f"
done

if [[ -n "$cpu_vendor" ]]; then
    f="$ENIGMA_ROOT/packages/cpu/$cpu_vendor.txt"
    [[ -f "$f" ]] && pacman_install "$f"
fi
