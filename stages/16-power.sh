#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

log "Installing TLP profile config (AC defaults to balanced; profiles switchable from the bar)"
sudo install -Dm644 "$ENIGMA_ROOT/system/tlp/50-enigma.conf" /etc/tlp.d/50-enigma.conf
command -v tlp > /dev/null && sudo tlp start > /dev/null

log "Letting wheel change fan mode, CPU preference and turbo from the bar"
sudo install -m644 "$ENIGMA_ROOT/system/power/enigma-power-writable.conf" /etc/tmpfiles.d/enigma-power-writable.conf
sudo systemd-tmpfiles --create /etc/tmpfiles.d/enigma-power-writable.conf

# Intel RAPL energy counters are root-only since CVE-2020-8694 (Platypus);
# the bar reads them for per-component power draw.
if [[ -d /sys/class/powercap/intel-rapl:0 ]]; then
    log "Making Intel RAPL power meters readable for the bar"
    sudo install -m644 "$ENIGMA_ROOT/system/power/90-rapl-readable.rules" /etc/udev/rules.d/90-rapl-readable.rules
    sudo udevadm control --reload
    sudo chmod 0444 /sys/class/powercap/intel-rapl:*/energy_uj
fi
