#!/bin/bash
# Webcam health check for the IPU6 MIPI camera behind an Intel IVSC (Dell XPS
# 14 9440). Walks the chain top to bottom so a regression shows where it breaks:
# kernel (sensor I2C device, IVSC drivers), media graph, libcamera inside
# WirePlumber, PipeWire camera node. Background: stages/15-camera-ivsc.sh,
# configs/wireplumber, configs/libcamera, configs/chromium.

echo "== sensor i2c client (expect i2c-OVTI02C1:00 bound to ov02c10)"
if [[ -e /sys/bus/i2c/devices/i2c-OVTI02C1:00 ]]; then
    echo "  present, driver: $(basename "$(readlink /sys/bus/i2c/devices/i2c-OVTI02C1:00/driver 2>/dev/null)" 2>/dev/null || echo UNBOUND)"
else
    echo "  MISSING (sensor never enumerated: check the IVSC drivers below and 'mei-csi probed without device fwnode' in dmesg)"
fi

echo "== IVSC drivers (expect ivsc_csi and ivsc_ace bound)"
for u in 92335fcf-3203-4472-af93-7b4453ac29da:csi 5db76cf6-0a68-4ed6-9b78-0361635e2447:ace; do
    d=/sys/bus/mei/devices/intel_vsc-${u%%:*}
    echo "  mei_${u##*:}: $(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null || echo UNBOUND)"
done

echo "== kernel messages"
journalctl -k -b --no-pager | grep -i -E 'ov02c10|ipu6.*(sensor|camera)|ivsc|mei-csi|mei_ace|int3472|ACPI (BIOS )?Error' | grep -v 'dummy regulator' | head -12

echo "== media graph (expect the sensor, 'Intel IVSC CSI', and the CSI2 receivers)"
media-ctl -p -d /dev/media0 2>/dev/null | grep -E '^- entity' | grep -v 'ISYS Capture' | sed 's/^- entity [0-9]*: /  /'

echo "== libcamera in WirePlumber (expect 'Adding camera'; debayer/FATAL lines mean the ISP path broke)"
journalctl --user -u wireplumber -b --no-pager | grep -i -E 'Adding camera|No sensor found|debayer|FATAL|dumped' | tail -5
echo "  softisp mode in wireplumber env: $(tr '\0' '\n' < /proc/$(pidof wireplumber | awk '{print $1}')/environ 2>/dev/null | grep LIBCAMERA_SOFTISP_MODE || echo 'unset (GPU/EGL default)')"

echo "== PipeWire camera nodes (expect exactly the libcamera 'Built-in Front Camera')"
pw-dump 2>/dev/null | python3 -c '
import json,sys
for o in json.load(sys.stdin):
    p=o.get("info",{}).get("props",{})
    if o.get("type")=="PipeWire:Interface:Node" and p.get("media.class","").startswith("Video/Source"):
        print(" ", o["id"], p.get("node.name"), "|", p.get("node.description"), "|", p.get("device.api"))'
