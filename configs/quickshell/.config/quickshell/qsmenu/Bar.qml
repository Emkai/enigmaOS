// Bar.qml — native quickshell top bar, styled after the "Custom Arch dmenu
// launcher" design (claude.ai/design). waybar is parked (removed from
// autostart, config kept) while this bar is evaluated as its replacement;
// barTopMargin is 0 so this bar sits flush at the top. Bump it back up to
// waybar's old height (18) if waybar is re-enabled alongside it.
//
// Data sources are native Quickshell services where available (Hyprland
// workspaces/keyboard, Pipewire volume, UPower battery, Bluez, NetworkManager
// via Quickshell.Networking) and fall back to the project's existing
// scripts/src/vpn.sh / nmcli one-liners for things those services don't
// expose (VPN interface details, link/gateway/dns info).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import Quickshell.Networking

Scope {
    id: root

    readonly property int barHeight: 34
    readonly property int barTopMargin: 0 // waybar is parked; bump to 18 if it's re-enabled alongside this bar
    readonly property int dropdownTopMargin: barTopMargin + barHeight

    readonly property color bg: "#000000"
    readonly property color textBright: "#f2f5f8"
    readonly property color textDefault: "#c7cdd6"
    readonly property color textDim: "#98a1ac"
    readonly property color textDimmer: "#6b7480"
    readonly property color textFaint: "#545c68"
    readonly property color hairline: "#232b36"
    readonly property color accent: Theme.accentColor
    readonly property color hoverBg: Qt.rgba(accent.r, accent.g, accent.b, 0.10)

    readonly property string repoScripts: Quickshell.env("HOME") + "/src/enigmaOS/scripts"

    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    function pad2(n) { return String(n).padStart(2, "0"); }

    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y0) / 86400000 + 1) / 7);
    }

    readonly property var monthNames: ["January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"]

    function calendarCells(d) {
        const first = new Date(d.getFullYear(), d.getMonth(), 1);
        const lead = (first.getDay() + 6) % 7;
        const days = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
        const cells = [];
        for (let i = 0; i < lead; i++)
            cells.push({ t: "", today: false });
        for (let day = 1; day <= days; day++)
            cells.push({ t: String(day), today: day === d.getDate() });
        return cells;
    }

    // ---- CPU usage: delta over /proc/stat every 2s ----
    property var _prevCpuSample: null
    property real cpuPct: 0

    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: cpuStatProc.running = true }

    Process {
        id: cpuStatProc
        command: ["sh", "-c", "head -n1 /proc/stat"]
        stdout: StdioCollector {
            id: cpuStatCollector
            onStreamFinished: {
                const parts = cpuStatCollector.text.trim().split(/\s+/).slice(1).map(Number);
                if (parts.length < 5)
                    return;
                const idle = parts[3] + parts[4];
                const total = parts.reduce((a, b) => a + b, 0);
                if (root._prevCpuSample) {
                    const dIdle = idle - root._prevCpuSample.idle;
                    const dTotal = total - root._prevCpuSample.total;
                    if (dTotal > 0)
                        root.cpuPct = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)));
                }
                root._prevCpuSample = { idle: idle, total: total };
            }
        }
    }

    // ---- RAM usage: MemTotal - MemAvailable, every 2s ----
    property real ramGiB: 0

    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: memInfoProc.running = true }

    Process {
        id: memInfoProc
        command: ["sh", "-c", "grep -E 'MemTotal|MemAvailable' /proc/meminfo"]
        stdout: StdioCollector {
            id: memInfoCollector
            onStreamFinished: {
                let total = 0, avail = 0;
                for (const line of memInfoCollector.text.split("\n")) {
                    const m = line.match(/(\d+)/);
                    if (!m) continue;
                    if (line.startsWith("MemTotal")) total = Number(m[1]);
                    else if (line.startsWith("MemAvailable")) avail = Number(m[1]);
                }
                root.ramGiB = (total - avail) / 1048576;
            }
        }
    }

    // ---- Top processes (fetched only while their dropdown is open) ----
    property var topCpuList: []
    property var topRamList: []

    Process {
        id: topCpuProc
        command: ["bash", "-c", "ps -eo pcpu=,comm= | sort -rn -k1 | head -n 10"]
        stdout: StdioCollector {
            id: topCpuCollector
            onStreamFinished: {
                const out = [];
                for (const line of topCpuCollector.text.split("\n")) {
                    const t = line.trim();
                    if (!t) continue;
                    const sp = t.indexOf(" ");
                    if (sp < 0) continue;
                    out.push({ name: t.slice(sp + 1).trim(), pct: t.slice(0, sp) + "%" });
                }
                root.topCpuList = out;
            }
        }
    }

    Process {
        id: topRamProc
        command: ["bash", "-c", "ps -eo rss=,comm= | awk '{a[$2]+=$1} END{for(n in a) printf \"%d %s\\n\", a[n], n}' | sort -rn -k1 | head -n 10"]
        stdout: StdioCollector {
            id: topRamCollector
            onStreamFinished: {
                const out = [];
                for (const line of topRamCollector.text.split("\n")) {
                    const t = line.trim();
                    if (!t) continue;
                    const sp = t.indexOf(" ");
                    if (sp < 0) continue;
                    const kib = Number(t.slice(0, sp));
                    const mib = kib / 1024;
                    out.push({ name: t.slice(sp + 1).trim(), v: mib >= 1024 ? (mib / 1024).toFixed(1) + " GiB" : Math.round(mib) + " MiB" });
                }
                root.topRamList = out;
            }
        }
    }

    // ---- VPN status (wireguard/tailscale/openvpn), via scripts/src/vpn.sh ----
    property var vpnEntries: []

    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: vpnProc.running = true }

    Process {
        id: vpnProc
        command: ["bash", "-c", `
            source "${root.repoScripts}/src/vpn.sh" 2>/dev/null
            if wireguard_connected 2>/dev/null; then
                ip -4 addr show type wireguard 2>/dev/null | awk '
                    /^[0-9]+:/ { iface = $2; sub(/:$/, "", iface) }
                    /inet /    { print "WG\\t" iface "\\t" $2 }
                '
            fi
            if tailscale_connected 2>/dev/null; then
                ip=$(tailscale ip -4 2>/dev/null | head -1)
                printf 'TS\\ttailscale\\t%s\\n' "\${ip:-connected}"
            fi
            if openvpn_connected 2>/dev/null; then
                printf 'OVPN\\topenvpn3\\tactive\\n'
            fi
        `]
        stdout: StdioCollector {
            id: vpnCollector
            onStreamFinished: {
                const out = [];
                for (const line of vpnCollector.text.split("\n")) {
                    const parts = line.split("\t");
                    if (parts.length < 3) continue;
                    out.push({ kind: parts[0], iface: parts[1], detail: parts[2] });
                }
                root.vpnEntries = out;
            }
        }
    }

    // ---- Network details (ip/gateway/link + wifi list), via nmcli/ip ----
    property string netKind: "none" // "wired" | "wifi" | "none"
    property var netWired: null
    property var netWifiList: []

    Process {
        id: netProc
        command: ["bash", "-c", `
            conn_type=$(nmcli -t -f type,state,connection dev status 2>/dev/null | grep -E '^(wifi|ethernet):connected:' | head -n1 | cut -d: -f1)
            printf 'TYPE\\t%s\\n' "\${conn_type:-none}"
            if [[ "$conn_type" == "ethernet" ]]; then
                dev=$(nmcli -t -f type,state,device dev status | grep '^ethernet:connected:' | head -n1 | cut -d: -f3)
                ip4=$(ip -4 addr show "$dev" 2>/dev/null | awk '/inet /{print $2; exit}')
                gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
                printf 'ETH\\t%s\\t%s\\t%s\\n' "$dev" "\${ip4:-?}" "\${gw:-?}"
            fi
            nmcli -t -f active,ssid,signal,security dev wifi 2>/dev/null | while IFS=: read -r active ssid signal sec; do
                [[ -z "$ssid" ]] && continue
                printf 'WIFI\\t%s\\t%s\\t%s\\t%s\\n' "$active" "$ssid" "$signal" "\${sec:-open}"
            done
        `]
        stdout: StdioCollector {
            id: netCollector
            onStreamFinished: {
                let kind = "none", wired = null;
                const wifi = [];
                for (const line of netCollector.text.split("\n")) {
                    const p = line.split("\t");
                    if (p[0] === "TYPE") kind = p[1];
                    else if (p[0] === "ETH") wired = { dev: p[1], ip4: p[2], gw: p[3] };
                    else if (p[0] === "WIFI") wifi.push({ active: p[1] === "yes", ssid: p[2], signal: p[3], security: p[4] });
                }
                root.netKind = kind;
                root.netWired = wired;
                root.netWifiList = wifi;
            }
        }
    }

    // ---- Keyboard layout: hyprctl devices -j, refreshed on activelayout events ----
    property string kbLayout: "??"

    function refreshKeyboard() { kbDevicesProc.running = true; }

    Process {
        id: kbDevicesProc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            id: kbDevicesCollector
            onStreamFinished: {
                try {
                    const d = JSON.parse(kbDevicesCollector.text);
                    const kb = d.keyboards.find(k => k.main) || d.keyboards[0];
                    if (kb && kb.layout) {
                        const layouts = kb.layout.split(",");
                        root.kbLayout = (layouts[kb.active_layout_index] || layouts[0] || "??").trim().toUpperCase();
                    }
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: refreshKeyboard()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout")
                root.refreshKeyboard();
        }
    }

    // ---- Pipewire: keep default sink/source and every node's audio bound ----
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].concat(Pipewire.nodes.values)
    }

    function volumePct() {
        const sink = Pipewire.defaultAudioSink;
        return sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0;
    }

    // ---- Reusable hover/open state for a bar segment + its dropdown ----
    component HoverState: Item {
        property bool open: false
        property bool hovering: false
        Timer { id: closeTimer; interval: 150; onTriggered: if (!parent.hovering) parent.open = false }
        function enter() { hovering = true; open = true; }
        function leave() { hovering = false; closeTimer.restart(); }
    }

    // ---- Reusable dropdown popup window ----
    component Dropdown: PanelWindow {
        id: dd
        required property var barScreen
        required property var hover // HoverState driving this dropdown's open/close
        property int popupWidth: 260
        property string align: "right" // "left" | "right" | "center"
        default property alias content: col.data

        screen: barScreen
        visible: hover.open
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qsbar-dropdown"
        anchors {
            top: true
            left: align !== "right"
            right: align === "right"
        }
        margins.top: root.dropdownTopMargin
        margins.left: align === "center" ? Math.round((barScreen.width - popupWidth) / 2) : 12
        margins.right: 12
        implicitWidth: popupWidth
        implicitHeight: col.implicitHeight + 20

        // HoverHandler (not MouseArea) so it keeps tracking hover even when the
        // pointer is over a child MouseArea (e.g. MenuButton) stacked above it —
        // MouseArea hover is exclusive to the topmost hoverEnabled item and would
        // otherwise report a false exit, closing the dropdown while hovering a button.
        HoverHandler {
            onHoveredChanged: hovered ? dd.hover.enter() : dd.hover.leave()
        }

        Rectangle {
            anchors.fill: parent
            color: root.bg
            border.width: 1
            border.color: root.hairline

            Column {
                id: col
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 4
            }
        }
    }

    component SectionLabel: Text {
        color: root.textDimmer
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.letterSpacing: 1
    }

    // Bordered, hover-highlighted click target for dropdown rows/links.
    component MenuButton: Rectangle {
        id: btn
        default property alias content: inner.data
        // Discrete: no visible border/fill at rest, looks like plain text —
        // only shows the button chrome on hover.
        property bool discrete: false
        signal clicked()
        implicitHeight: 22
        height: implicitHeight
        opacity: enabled ? 1 : 0.4
        radius: 3
        border.width: 1
        border.color: ma.containsMouse ? root.accent : (discrete ? "transparent" : root.hairline)
        color: ma.containsMouse ? root.hoverBg : "transparent"

        Item {
            id: inner
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.clicked()
        }
    }


    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWin
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            margins.top: root.barTopMargin
            implicitHeight: root.barHeight
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.barHeight
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "qsbar"
            color: "transparent"

            HoverState { id: hsClock }
            HoverState { id: hsCpu }
            HoverState { id: hsRam }
            HoverState { id: hsVpn }
            HoverState { id: hsVol }
            HoverState { id: hsBt }
            HoverState { id: hsNet }
            HoverState { id: hsPow }

            // ---- Workspaces (native Hyprland IPC, filtered to this monitor) ----
            property var wsList: []
            property bool isFocusedMonitor: Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === barWin.screen.name
            function refreshWorkspaces() {
                const mine = Hyprland.workspaces.values.filter(w => w.monitor && w.monitor.name === barWin.screen.name);
                mine.sort((a, b) => a.id - b.id);
                barWin.wsList = mine;
            }
            Component.onCompleted: barWin.refreshWorkspaces()
            Connections {
                target: Hyprland.workspaces
                function onValuesChanged() { barWin.refreshWorkspaces(); }
            }
            Connections {
                target: Hyprland
                function onFocusedWorkspaceChanged() { barWin.refreshWorkspaces(); }
                function onFocusedMonitorChanged() { barWin.refreshWorkspaces(); }
            }

            Rectangle {
                anchors.fill: parent
                color: root.bg

                // ---------------- LEFT ----------------
                Row {
                    id: leftRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        text: root.isoWeek(root.now)
                        color: root.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        leftPadding: 10
                        rightPadding: 8
                        verticalAlignment: Text.AlignVCenter
                        height: root.barHeight
                    }

                    Rectangle {
                        width: clockText.implicitWidth + 20
                        height: root.barHeight
                        color: hsClock.open ? root.hoverBg : "transparent"

                        Text {
                            id: clockText
                            anchors.centerIn: parent
                            text: root.pad2(root.now.getHours()) + ":" + root.pad2(root.now.getMinutes())
                            color: root.textBright
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: hsClock.enter()
                            onExited: hsClock.leave()
                        }
                    }
                }

                Dropdown {
                    barScreen: barWin.screen
                    hover: hsClock
                    align: "left"
                    popupWidth: 236

                    Row {
                        width: parent.width
                        Text {
                            text: root.monthNames[root.now.getMonth()] + " " + root.now.getFullYear()
                            color: root.textBright
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        Item { width: parent.width - 140; height: 1 }
                        Text {
                            text: "w" + root.isoWeek(root.now)
                            color: root.textDimmer
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }

                    Grid {
                        columns: 7
                        spacing: 2
                        width: parent.width

                        Repeater {
                            model: ["m", "t", "w", "t", "f", "s", "s"]
                            delegate: Text {
                                required property string modelData
                                text: modelData
                                width: (parent.width - 12) / 7
                                height: 24
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: root.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }

                        Repeater {
                            model: root.calendarCells(root.now)
                            delegate: Rectangle {
                                required property var modelData
                                width: (parent.width - 12) / 7
                                height: 24
                                color: modelData.today ? root.accent : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.t
                                    color: modelData.today ? "#ffffff" : root.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }

                // ---------------- CENTER ----------------
                Row {
                    id: centerRow
                    anchors.centerIn: parent
                    spacing: 0

                    Rectangle {
                        width: cpuText.implicitWidth + 20
                        height: root.barHeight
                        color: hsCpu.open ? root.hoverBg : "transparent"
                        Text {
                            id: cpuText
                            anchors.centerIn: parent
                            text: Math.round(root.cpuPct) + "%"
                            color: root.textBright
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: { hsCpu.enter(); topCpuProc.running = true; }
                            onExited: hsCpu.leave()
                        }
                    }

                    Row {
                        spacing: 2
                        leftPadding: 12
                        rightPadding: 12
                        anchors.verticalCenter: parent.verticalCenter

                        Repeater {
                            model: barWin.wsList
                            delegate: Rectangle {
                                id: wsDelegate
                                required property var modelData
                                width: 22
                                height: 20
                                color: modelData.active
                                    ? (barWin.isFocusedMonitor ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35))
                                    : (wsMa.containsMouse ? root.hoverBg : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: wsDelegate.modelData.id
                                    color: "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    id: wsMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: wsDelegate.modelData.activate()
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: ramText.implicitWidth + 24
                        height: root.barHeight
                        color: hsRam.open ? root.hoverBg : "transparent"
                        Text {
                            id: ramText
                            anchors.centerIn: parent
                            text: root.ramGiB.toFixed(1) + " GiB"
                            color: root.textBright
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: { hsRam.enter(); topRamProc.running = true; }
                            onExited: hsRam.leave()
                        }
                    }
                }

                Dropdown {
                    barScreen: barWin.screen
                    hover: hsCpu
                    align: "center"
                    popupWidth: 260

                    SectionLabel { text: "CPU BY PROCESS" }
                    Repeater {
                        model: root.topCpuList
                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            Text { text: modelData.name; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width - 50 }
                            Text { text: modelData.pct; color: root.textDim; font.family: Theme.fontFamily; font.pixelSize: 13; width: 50; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }

                Dropdown {
                    barScreen: barWin.screen
                    hover: hsRam
                    align: "center"
                    popupWidth: 260

                    SectionLabel { text: "MEMORY BY PROCESS" }
                    Repeater {
                        model: root.topRamList
                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            Text { text: modelData.name; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width - 60 }
                            Text { text: modelData.v; color: root.textDim; font.family: Theme.fontFamily; font.pixelSize: 13; width: 60; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }

                // ---------------- RIGHT ----------------
                Row {
                    id: rightRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // VPN
                    Rectangle {
                        width: vpnRow.implicitWidth + 14
                        height: root.barHeight
                        color: hsVpn.open ? root.hoverBg : "transparent"
                        Row {
                            id: vpnRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text { text: ""; color: root.accent; font.family: Theme.fontFamily; font.pixelSize: 13; visible: root.vpnEntries.length > 0 }
                            Repeater {
                                model: root.vpnEntries
                                delegate: Text {
                                    required property var modelData
                                    text: modelData.kind === "WG" ? "W" : modelData.kind === "TS" ? "T" : "O"
                                    color: root.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: hsVpn.enter()
                            onExited: hsVpn.leave()
                            onClicked: Quickshell.execDetached([root.repoScripts + "/qs-vpn"])
                        }
                    }

                    // Keyboard layout
                    Rectangle {
                        width: kbText.implicitWidth + 16
                        height: root.barHeight
                        color: kbMa.containsMouse ? root.hoverBg : "transparent"
                        Text {
                            id: kbText
                            anchors.centerIn: parent
                            text: root.kbLayout
                            color: root.textBright
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: kbMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"]);
                                refreshKbTimer.start();
                            }
                        }
                        Timer { id: refreshKbTimer; interval: 150; onTriggered: root.refreshKeyboard() }
                    }

                    // Volume
                    Rectangle {
                        width: volRow.implicitWidth + 16
                        height: root.barHeight
                        color: hsVol.open ? root.hoverBg : "transparent"
                        Row {
                            id: volRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted ? "" : ""
                                color: root.textDefault
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                            }
                            Text { text: root.volumePct() + "%"; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: hsVol.enter()
                            onExited: hsVol.leave()
                            onClicked: if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
                                Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted
                            onWheel: wheel => {
                                const sink = Pipewire.defaultAudioSink;
                                if (!sink || !sink.audio) return;
                                const delta = wheel.angleDelta.y > 0 ? 0.02 : -0.02;
                                sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta));
                            }
                        }
                    }

                    // Bluetooth
                    Rectangle {
                        width: 34
                        height: root.barHeight
                        color: hsBt.open ? root.hoverBg : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: ""
                            color: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? root.accent : root.textDimmer
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: hsBt.enter()
                            onExited: hsBt.leave()
                        }
                    }

                    // Network
                    Rectangle {
                        width: 34
                        height: root.barHeight
                        color: hsNet.open ? root.hoverBg : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: root.netKind === "wired" ? "" : ""
                            color: root.textDefault
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: { hsNet.enter(); netProc.running = true; }
                            onExited: hsNet.leave()
                        }
                    }

                    // Battery / power
                    Rectangle {
                        width: powRow.implicitWidth + 18
                        height: root.barHeight
                        color: hsPow.open ? root.hoverBg : "transparent"
                        Row {
                            id: powRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: UPower.displayDevice && UPower.displayDevice.state === UPowerDeviceState.Charging ? "󰂄" : "󰁹"
                                color: root.textDefault
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                            }
                            Text {
                                text: UPower.displayDevice ? Math.round(UPower.displayDevice.percentage * 100) + "%" : "?"
                                color: root.textDefault
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: hsPow.enter()
                            onExited: hsPow.leave()
                        }
                    }
                }

                Dropdown {
                    barScreen: barWin.screen
                    hover: hsVpn
                    align: "right"
                    popupWidth: 300

                    SectionLabel { text: "VPN INTERFACES" }
                    Repeater {
                        model: root.vpnEntries
                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            Text { text: modelData.iface; color: root.textBright; font.family: Theme.fontFamily; font.pixelSize: 13; width: parent.width * 0.4 }
                            Text { text: modelData.detail; color: root.textDim; font.family: Theme.fontFamily; font.pixelSize: 13; width: parent.width * 0.6; horizontalAlignment: Text.AlignRight }
                        }
                    }
                    Text {
                        visible: root.vpnEntries.length === 0
                        text: "no active VPN connections"
                        color: root.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                }

                Dropdown {
                    barScreen: barWin.screen
                    hover: hsVol
                    align: "right"
                    popupWidth: 292

                    Item {
                        width: parent.width
                        height: 22
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "OUTPUT"; color: root.textDimmer; font.family: Theme.fontFamily; font.pixelSize: 12; font.letterSpacing: 1
                        }
                        MenuButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: muteText.implicitWidth + 16
                            onClicked: if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
                                Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted
                            Text {
                                id: muteText
                                anchors.centerIn: parent
                                text: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted) ? "MUTED" : "MUTE"
                                color: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted) ? root.accent : root.textDimmer
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 18

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: "#161a1f"
                            border.width: 1
                            border.color: volMa.containsMouse ? root.accent : root.hairline
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: height / 2
                            width: Math.max(height, parent.width * root.volumePct() / 100)
                            color: volMa.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent
                        }

                        MouseArea {
                            id: volMa
                            anchors.fill: parent
                            hoverEnabled: true
                            function setFromX(x) {
                                if (!Pipewire.defaultAudioSink || !Pipewire.defaultAudioSink.audio) return;
                                const pct = Math.max(0, Math.min(1, x / width));
                                Pipewire.defaultAudioSink.audio.volume = pct;
                                Pipewire.defaultAudioSink.audio.muted = false;
                            }
                            onPressed: mouse => setFromX(mouse.x)
                            onPositionChanged: mouse => { if (pressed) setFromX(mouse.x); }
                        }
                    }

                    SectionLabel { text: "OUTPUT DEVICE"; topPadding: 4 }
                    Repeater {
                        model: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)
                        delegate: MenuButton {
                            required property var modelData
                            width: parent.width
                            discrete: true
                            onClicked: Pipewire.preferredDefaultAudioSink = modelData
                            Text {
                                anchors.left: parent.left
                                anchors.right: activeLabel.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.description || modelData.name
                                color: modelData === Pipewire.defaultAudioSink ? root.textBright : root.textDefault
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Text {
                                id: activeLabel
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData === Pipewire.defaultAudioSink ? "ACTIVE" : ""
                                color: root.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                width: 60
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }

                    SectionLabel { text: "APPLICATIONS"; topPadding: 8 }
                    Repeater {
                        model: Pipewire.nodes.values.filter(n => n.isStream && n.isSink && n.audio)
                        delegate: Row {
                            required property var modelData
                            x: 8
                            width: parent.width - 16
                            spacing: 8
                            Text {
                                text: modelData.properties && modelData.properties["application.name"] ? modelData.properties["application.name"] : modelData.name
                                color: root.textDefault
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                width: 84
                                elide: Text.ElideRight
                            }
                            Item {
                                width: parent.width - 84 - 8 - 34
                                height: 10
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: "#161a1f"
                                    border.width: 1
                                    border.color: appVolMa.containsMouse ? root.accent : root.hairline
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    radius: height / 2
                                    width: Math.max(height, parent.width * modelData.audio.volume)
                                    color: appVolMa.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent
                                }

                                MouseArea {
                                    id: appVolMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    function setFromX(x) {
                                        modelData.audio.volume = Math.max(0, Math.min(1, x / width));
                                    }
                                    onPressed: mouse => setFromX(mouse.x)
                                    onPositionChanged: mouse => { if (pressed) setFromX(mouse.x); }
                                }
                            }
                            Text {
                                text: Math.round(modelData.audio.volume * 100) + "%"
                                color: root.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                width: 34
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }

                    Item { width: 1; height: 4 }
                    MenuButton {
                        width: pavuText.implicitWidth + 16
                        onClicked: Quickshell.execDetached(["pavucontrol"])
                        Text {
                            id: pavuText
                            anchors.centerIn: parent
                            text: "pavucontrol · wpctl"
                            color: root.textDimmer
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                }

                Dropdown {
                    barScreen: barWin.screen
                    hover: hsBt
                    align: "right"
                    popupWidth: 248

                    MenuButton {
                        width: parent.width
                        onClicked: if (Bluetooth.defaultAdapter)
                            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "BLUETOOTH · " + (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? "ON" : "OFF")
                            color: root.textDimmer
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.letterSpacing: 1
                        }
                    }
                    Repeater {
                        model: Bluetooth.devices.values.filter(d => d.paired || d.connected)
                        delegate: MenuButton {
                            required property var modelData
                            width: parent.width
                            discrete: true
                            onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                            Text {
                                anchors.left: parent.left
                                anchors.right: statusLabel.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name || modelData.deviceName
                                color: modelData.connected ? root.textBright : root.textDefault
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Text {
                                id: statusLabel
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.connected ? "CONNECTED" : "PAIRED"
                                color: modelData.connected ? root.accent : root.textDimmer
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                width: 90
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                    Item { width: 1; height: 4 }
                    Row {
                        spacing: 8
                        MenuButton {
                            width: btctlText.implicitWidth + 16
                            onClicked: Quickshell.execDetached([root.repoScripts + "/qs-bluetooth"])
                            Text {
                                id: btctlText
                                anchors.centerIn: parent
                                text: "bluetoothctl"
                                color: root.textDimmer
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }
                        MenuButton {
                            width: btScanText.implicitWidth + 16
                            enabled: !(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering)
                            onClicked: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = true
                            Text {
                                id: btScanText
                                anchors.centerIn: parent
                                text: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering) ? "scanning…" : "scan"
                                color: root.textDimmer
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }
                    }
                }

                Dropdown {
                    barScreen: barWin.screen
                    hover: hsNet
                    align: "right"
                    popupWidth: 300

                    Column {
                        width: parent.width
                        visible: root.netWired !== null
                        spacing: 4
                        SectionLabel { text: "WIRED · " + (root.netWired ? root.netWired.dev : "") }
                        Row {
                            width: parent.width
                            Text { text: "ipv4"; color: root.textDim; font.family: Theme.fontFamily; font.pixelSize: 13; width: parent.width - 120 }
                            Text { text: root.netWired ? root.netWired.ip4 : ""; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13; width: 120; horizontalAlignment: Text.AlignRight }
                        }
                        Row {
                            width: parent.width
                            Text { text: "gateway"; color: root.textDim; font.family: Theme.fontFamily; font.pixelSize: 13; width: parent.width - 120 }
                            Text { text: root.netWired ? root.netWired.gw : ""; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13; width: 120; horizontalAlignment: Text.AlignRight }
                        }
                    }

                    SectionLabel { text: "WI-FI"; topPadding: 6 }
                    Repeater {
                        model: root.netWifiList
                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            spacing: 8
                            Text {
                                text: modelData.ssid
                                color: modelData.active ? root.textBright : root.textDefault
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                width: parent.width - 106
                            }
                            Text {
                                text: modelData.security
                                color: root.textDimmer
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                width: 50
                            }
                            Text {
                                text: modelData.signal + "%"
                                color: root.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                width: 40
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                    Item { width: 1; height: 4 }
                    MenuButton {
                        width: wifiLinkText.implicitWidth + 16
                        onClicked: Quickshell.execDetached([root.repoScripts + "/qs-wifi"])
                        Text {
                            id: wifiLinkText
                            anchors.centerIn: parent
                            text: "nmtui / qs-wifi"
                            color: root.textDimmer
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                }

                Dropdown {
                    barScreen: barWin.screen
                    hover: hsPow
                    align: "right"
                    popupWidth: 216

                    Text {
                        text: UPower.displayDevice
                            ? (UPower.displayDevice.state === UPowerDeviceState.Charging ? "charging" : "discharging")
                            : ""
                        color: root.textDefault
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                    SectionLabel { text: "POWER"; topPadding: 8 }

                    Repeater {
                        model: [
                            { name: "lock", key: "l", cmd: ["hyprlock"] },
                            { name: "suspend", key: "s", cmd: ["systemctl", "suspend"] },
                            { name: "log out", key: "e", cmd: ["hyprctl", "dispatch", "exit"] },
                            { name: "reboot", key: "r", cmd: ["systemctl", "reboot"] },
                            { name: "power off", key: "p", cmd: ["systemctl", "poweroff"] }
                        ]
                        delegate: MenuButton {
                            required property var modelData
                            width: parent.width
                            onClicked: Quickshell.execDetached(modelData.cmd)
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.key; color: root.textFaint; font.family: Theme.fontFamily; font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }
    }
}
