#!/bin/bash
set -euo pipefail

ENIGMA_ROOT="${ENIGMA_ROOT:?ENIGMA_ROOT not set - run via install.sh}"
source "$ENIGMA_ROOT/lib/common.sh"

# Intel IPU6 MIPI webcam behind an MEI-based IVSC (Dell XPS 14 9440 and other
# Meteor Lake laptops): make intel_ipu6 load only after the IVSC's MEI CSI
# client device exists.
#
# Why: the camera sensor's ACPI _DEP names the IVSC, and Linux only creates the
# sensor's I2C device once the IVSC driver (mei_ace) clears that dependency.
# mei_ace in turn needs mei_csi, which refuses to probe unless the IPU bridge
# has handed it a fwnode. The bridge does that during intel_ipu6's probe, and
# it is supposed to defer until the MEI CSI client exists. Since the bridge
# grew fallbacks for Intel's newer CVS controllers (kernels 6.1x+), that
# deferral is defeated: the fallback accepts the generic platform device the
# ACPI core creates for the IVSC node, so an IPU probe that runs before mei_vsc
# has bound "succeeds" and attaches the fwnode to the wrong device. The real
# CSI client then probes without it ("mei-csi probed without device fwnode!"),
# mei_ace stays deferred forever, and the sensor never enumerates: no
# /dev/v4l-subdev for it, libcamera reports "No sensor found for /dev/media0".
# Diagnosed 2026-09-07 on kernel 7.2.2; Fedora 6.14 (pre-fallback) works.
#
# The bridge keeps its state on the IPU's ACPI node, so this cannot be redone
# at runtime; ordering the probe is the only stock-kernel fix. Blacklisting the
# PCI alias plus a udev rule keyed on the MEI CSI client's add event gives
# exactly that order. With the client present, the bridge's first lookup finds
# it and links it properly. Machines without an MEI-based IVSC skip this stage:
# there the blacklist would only prevent the camera from ever loading.

ivsc_hids=(INTC1059 INTC1095 INTC100A INTC10CF) # TGL/ADL/RPL/MTL IVSC (drivers/acpi/scan.c honor list)
have_ivsc=0
for hid in "${ivsc_hids[@]}"; do
    compgen -G "/sys/bus/acpi/devices/$hid:*" > /dev/null && have_ivsc=1 && break
done

if [[ $have_ivsc -eq 0 ]]; then
    log "No MEI-based IVSC camera controller found, skipping IPU6 load-order workaround"
    exit 0
fi

log "IVSC camera controller present: installing IPU6 load-order workaround"
sudo install -m644 "$ENIGMA_ROOT/system/camera/ipu6-after-ivsc.conf" /etc/modprobe.d/ipu6-after-ivsc.conf
sudo install -m644 "$ENIGMA_ROOT/system/camera/90-ipu6-after-ivsc.rules" /etc/udev/rules.d/90-ipu6-after-ivsc.rules
sudo udevadm control --reload
log "Takes effect on the next boot (intel_ipu6 is already loaded on a running system)"
