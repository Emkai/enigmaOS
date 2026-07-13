#!/bin/bash
# User-editable defaults for install.sh. Values here can be overridden by
# environment variables or the matching install.sh flag (--gpu, --extras).

# Comma-separated: intel,nvidia,amd,nouveau — or "auto" to detect via lspci.
# Hybrid setups (e.g. Intel iGPU + NVIDIA dGPU) are supported: list both.
GPU_VENDORS="${GPU_VENDORS:-auto}"

# intel|amd|auto
CPU_VENDOR="${CPU_VENDOR:-auto}"

# Space-separated optional/ tier names to install, e.g. "embedded extras".
# Leave empty to install only the core desktop.
ENIGMA_EXTRAS="${ENIGMA_EXTRAS:-}"
