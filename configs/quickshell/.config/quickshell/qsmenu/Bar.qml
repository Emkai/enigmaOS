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
    readonly property color dueLate: "#e2707a" // deadline already gone
    readonly property color dueSoon: "#d9a55c" // deadline lands today

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
    property string netKind: "none" // "ethernet" | "wifi" | "none"
    property var netWiredList: []
    property var netVpnList: []
    property var netWifiDevList: []
    property var netWifiList: []
    property string wifiExpandedSsid: ""
    property bool wifiExpandedNeedsPassword: false
    property bool wifiShowPassword: false

    Process {
        id: netProc
        command: ["bash", "-c", `
            conn_type=$(nmcli -t -f type,state,connection dev status 2>/dev/null | grep -E '^(wifi|ethernet):connected:' | head -n1 | cut -d: -f1)
            printf 'TYPE\\t%s\\n' "\${conn_type:-none}"
            nmcli -t -f type,state,device dev status 2>/dev/null | grep '^ethernet:connected:' | cut -d: -f3 | while read -r dev; do
                gw=$(ip -4 route list default dev "$dev" 2>/dev/null | awk '/via/{print $3; exit}')
                printf 'ETH\\t%s\\t%s\\n' "$dev" "\${gw:-?}"
                # One line per address; the kernel flags DHCP-leased addresses
                # "dynamic" (finite lease lifetime), statics are permanent.
                ip -4 -o addr show dev "$dev" scope global 2>/dev/null | awk '{
                    kind = "static"
                    for (i = 5; i <= NF; i++) if ($i == "dynamic") kind = "dhcp"
                    print "ETHADDR\\t" $2 "\\t" $4 "\\t" kind
                }'
            done
            nmcli -t -f type,state,device,connection dev status 2>/dev/null | grep '^wifi:connected:' | while IFS=: read -r _ _ dev conn; do
                ip4=$(ip -4 addr show "$dev" 2>/dev/null | awk '/inet /{print $2; exit}')
                gw=$(ip -4 route list default dev "$dev" 2>/dev/null | awk '/via/{print $3; exit}')
                printf 'WIFIDEV\\t%s\\t%s\\t%s\\t%s\\n' "$dev" "\${ip4:-?}" "\${gw:-?}" "$conn"
            done
            # VPN tunnels: wireguard interfaces plus tun (tailscale/openvpn)
            for t in wireguard tun; do
                ip -o link show type "$t" up 2>/dev/null | awk -F': ' '{print $2}'
            done | while read -r dev; do
                ip4=$(ip -4 addr show "$dev" 2>/dev/null | awk '/inet /{print $2; exit}')
                routes=$(ip -4 route list dev "$dev" 2>/dev/null | awk '{print $1}' | paste -sd ',' - | sed 's/,/, /g')
                printf 'VPN\\t%s\\t%s\\t%s\\n' "$dev" "\${ip4:-?}" "\${routes:--}"
            done
            nmcli -t -f active,ssid,signal,security dev wifi 2>/dev/null | while IFS=: read -r active ssid signal sec; do
                [[ -z "$ssid" ]] && continue
                printf 'WIFI\\t%s\\t%s\\t%s\\t%s\\n' "$active" "$ssid" "$signal" "\${sec:-open}"
            done
            nmcli -t -f name,type connection show 2>/dev/null | awk -F: '$2=="802-11-wireless"{print "SAVED\\t"$1}'
        `]
        stdout: StdioCollector {
            id: netCollector
            onStreamFinished: {
                let kind = "none";
                const wired = [];
                const vpn = [];
                const wifiDevs = [];
                const wifi = [];
                const saved = new Set();
                for (const line of netCollector.text.split("\n")) {
                    const p = line.split("\t");
                    if (p[0] === "SAVED") saved.add(p[1]);
                }
                for (const line of netCollector.text.split("\n")) {
                    const p = line.split("\t");
                    if (p[0] === "TYPE") kind = p[1];
                    else if (p[0] === "ETH") wired.push({ dev: p[1], gw: p[2], addrs: [] });
                    else if (p[0] === "ETHADDR") {
                        const w = wired.find(x => x.dev === p[1]);
                        if (w) w.addrs.push({ cidr: p[2], kind: p[3] });
                    }
                    else if (p[0] === "VPN") vpn.push({ dev: p[1], ip4: p[2], routes: p[3] });
                    else if (p[0] === "WIFIDEV") wifiDevs.push({ dev: p[1], ip4: p[2], gw: p[3], conn: p[4] });
                    else if (p[0] === "WIFI") wifi.push({ active: p[1] === "yes", ssid: p[2], signal: p[3], security: p[4], saved: saved.has(p[2]) });
                }
                root.netKind = kind;
                root.netWiredList = wired;
                root.netVpnList = vpn;
                root.netWifiDevList = wifiDevs;
                root.netWifiList = wifi.filter(w => w.active).concat(wifi.filter(w => !w.active));
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
        // Held open regardless of the pointer — set by a dropdown the user is
        // typing into, which would otherwise vanish the moment the pointer
        // drifted off it (see the todo dropdown's composer).
        property bool pinned: false
        Timer { id: closeTimer; interval: 150; onTriggered: if (!parent.hovering && !parent.pinned) parent.open = false }
        onPinnedChanged: if (!pinned && !hovering) closeTimer.restart()
        function enter() { hovering = true; open = true; }
        function leave() { hovering = false; closeTimer.restart(); }
    }

    // ---- Reusable dropdown popup window ----
    //
    // Width follows the content: the widest row's natural (un-elided) width,
    // clamped to [minWidth, maxWidth]. See naturalWidth() for how rows are
    // measured. A row that should widen the popup around it (device names,
    // SSIDs) sets an explicit implicitWidth built from its texts' implicitWidth
    // and fixed-width status columns — never from its own width, which follows
    // the popup and would loop, and never from a value that changes while the
    // popup is open (volume %, signal %), which would make it jitter.
    component Dropdown: PanelWindow {
        id: dd
        required property var barScreen
        required property var hover // HoverState driving this dropdown's open/close
        property int minWidth: 220
        property int maxWidth: Math.min(720, Math.round(screenWidth * 0.6))
        property string align: "right" // "left" | "right" | "center"
        // Dropdowns open on hover, so they don't grab keyboard focus by default
        // (that would steal it from whatever app the user is typing in just from
        // glancing at the bar). Set true only while a dropdown has an actual text
        // input the user asked to type into (e.g. the wifi password field).
        property bool wantsKeyboard: false
        default property alias content: col.data
        // barScreen is briefly null while a monitor is being unplugged; don't
        // spam TypeErrors from the size/position bindings during that window.
        readonly property int screenWidth: barScreen ? barScreen.width : 0

        screen: barScreen
        visible: hover.open
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qsbar-dropdown"
        WlrLayershell.keyboardFocus: wantsKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors {
            top: true
            left: align !== "right"
            right: align === "right"
        }
        margins.top: root.dropdownTopMargin
        margins.left: align === "center" ? Math.round((screenWidth - implicitWidth) / 2) : 12
        margins.right: 12
        implicitWidth: Math.max(minWidth, Math.min(maxWidth, contentWidth + 2 * col.x))
        implicitHeight: col.implicitHeight + 20

        // Natural width of an item tree. Positioners (Row/Column/Grid/Flow) can't
        // report one: their implicitWidth is read-only and tracks their children's
        // *actual* widths, which already follow the popup — reading it would be
        // circular. So a Row sums its children, a Column takes its widest, and a
        // Grid/Flow is skipped (its cells are sized from the popup). Wrapping text
        // is skipped too: it adapts to the popup rather than sizing it. Anything
        // else reports its implicitWidth: a Text's is its full unelided width, an
        // Item's/Rectangle's is 0 unless set explicitly.
        function naturalWidth(item) {
            if (!item.visible)
                return 0;
            if (item instanceof Grid || item instanceof Flow)
                return 0;
            if (item instanceof Text && item.wrapMode !== Text.NoWrap)
                return 0;
            if (item instanceof Row) {
                let w = 0, n = 0;
                for (let i = 0; i < item.children.length; i++) {
                    if (!item.children[i].visible)
                        continue;
                    w += naturalWidth(item.children[i]);
                    n++;
                }
                return w + Math.max(0, n - 1) * item.spacing + item.leftPadding + item.rightPadding;
            }
            if (item instanceof Column) {
                let w = 0;
                for (let i = 0; i < item.children.length; i++)
                    w = Math.max(w, naturalWidth(item.children[i]));
                return w + item.leftPadding + item.rightPadding;
            }
            return item.implicitWidth;
        }

        readonly property int contentWidth: {
            let w = 0;
            for (let i = 0; i < col.children.length; i++)
                w = Math.max(w, naturalWidth(col.children[i]));
            return Math.ceil(w);
        }

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
        readonly property int contentInset: 8 // horizontal padding around content
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
            anchors.leftMargin: btn.contentInset
            anchors.rightMargin: btn.contentInset
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.clicked()
        }
    }

    // ---- Todo dropdown state ----
    //
    // Shared across screens, like the wifi expander above: only one todo
    // dropdown is ever hovered at a time. Either flag pulls compositor keyboard
    // focus to the open dropdown, and (with something actually typed) pins it
    // open, so editing doesn't end the moment the pointer drifts off.
    property bool todoComposing: false  // the new-task row wants the keyboard
    property string todoExpandedId: ""  // task whose editor is open, at most one
    readonly property int todoDueWidth: 96 // fixed deadline column: an ageing label ("fri" -> "2d late") must not resize the popup
    readonly property int todoNoteWidth: 14
    readonly property int todoIndent: 30 // left inset shared by every expanded editor

    function todoDueColor(tone, done) {
        if (done)
            return root.textFaint;
        if (tone === "overdue")
            return root.dueLate;
        if (tone === "today")
            return root.dueSoon;
        if (tone === "soon")
            return root.textDefault;
        if (tone === "later")
            return root.textDim;
        return root.textFaint;
    }

    function todoDismiss() {
        root.todoComposing = false;
        root.todoExpandedId = "";
    }

    // "-" / ":" between the picker's cells.
    component DueSep: Text {
        color: root.textDimmer
        font.family: Theme.fontFamily
        font.pixelSize: 12
        height: 22
        verticalAlignment: Text.AlignVCenter
    }

    // ---- One numeric cell of the deadline picker ----
    //
    // Type into it, wheel over it, or use up/down. It reports edits rather than
    // writing them back itself: DueFields owns the arithmetic, because a day or
    // month only means something against the rest of the date.
    component DueField: Rectangle {
        id: cell
        property int digits: 2
        property int value: -1 // -1 = unset, shown as dashes
        property Item nextFocus: null
        readonly property alias focusItem: input
        signal stepped(int delta)
        signal typed(int v)

        width: 8 + cell.digits * 9
        height: 22
        radius: 3
        color: "transparent"
        border.width: 1
        border.color: input.activeFocus ? root.accent : (cellHover.hovered ? root.textDimmer : root.hairline)

        // Pushed in whenever the owner recalculates, including right after an
        // edit of our own — a plain binding on `text` would be dropped the
        // moment the user typed, and the clamped result would never show.
        function sync() {
            input.text = cell.value < 0 ? "" : String(cell.value).padStart(cell.digits, "0");
        }
        onValueChanged: cell.sync()
        Component.onCompleted: cell.sync()

        HoverHandler { id: cellHover }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.margins: 3
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            color: root.textDefault
            font.family: Theme.fontFamily
            font.pixelSize: 12
            maximumLength: cell.digits
            validator: IntValidator { bottom: 0; top: 9999 }
            clip: true
            KeyNavigation.tab: cell.nextFocus
            Keys.onUpPressed: cell.stepped(1)
            Keys.onDownPressed: cell.stepped(-1)
            onEditingFinished: cell.typed(input.text === "" ? -1 : Number(input.text))
        }

        Text {
            anchors.centerIn: parent
            text: "-".repeat(cell.digits)
            color: root.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 12
            visible: input.text === "" && !input.activeFocus
        }

        // Wheel only: NoButton lets presses fall through to the TextInput below.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => cell.stepped(wheel.angleDelta.y > 0 ? 1 : -1)
        }
    }

    // ---- Deadline picker: year, month, day, hour, minute ----
    //
    // Holds the parts rather than a string so a half-filled date is a legal
    // intermediate state; `stamp` is "" until the date is complete, and carries
    // the time only once an hour is set. Date parts do real calendar arithmetic
    // (31 jan + 1 month is 28 feb, not 3 mar); time parts deliberately don't
    // carry into the date, so nudging an hour can never move the day.
    component DueFields: Row {
        id: df
        property int yr: -1
        property int mo: -1
        property int dy: -1
        property int hh: -1 // -1 = whole day, no time
        property int mi: 0
        property Item tabTarget: null
        readonly property alias firstFocus: cellYear.focusItem

        readonly property bool hasDate: df.yr > 0 && df.mo > 0 && df.dy > 0
        readonly property string stamp: !df.hasDate ? ""
            : df.yr + "-" + root.pad2(df.mo) + "-" + root.pad2(df.dy)
                + (df.hh < 0 ? "" : "T" + root.pad2(df.hh) + ":" + root.pad2(df.mi))

        spacing: 3

        function load(s) {
            const d = TodoStore.dueDate(s);
            if (!d) {
                df.clear();
                return;
            }
            df.yr = d.getFullYear();
            df.mo = d.getMonth() + 1;
            df.dy = d.getDate();
            const timed = TodoStore.dueHasTime(s);
            df.hh = timed ? d.getHours() : -1;
            df.mi = timed ? d.getMinutes() : 0;
        }

        function clear() {
            df.yr = -1;
            df.mo = -1;
            df.dy = -1;
            df.hh = -1;
            df.mi = 0;
        }

        function today() {
            const n = new Date();
            df.yr = n.getFullYear();
            df.mo = n.getMonth() + 1;
            df.dy = n.getDate();
        }

        function _daysInMonth(y, m) { return new Date(y, m, 0).getDate(); }

        function _setDate(d) {
            df.yr = d.getFullYear();
            df.mo = d.getMonth() + 1;
            df.dy = d.getDate();
        }

        // Keeps the day legal after the month or year moves under it.
        function _clampDay() {
            df.dy = Math.min(df.dy, df._daysInMonth(df.yr, df.mo));
        }

        function step(part, delta) {
            if (!df.hasDate)
                df.today(); // nothing to step from yet; start from today
            if (part === "h" || part === "mi") {
                if (df.hh < 0) {
                    df.hh = 0;
                    df.mi = 0;
                }
                if (part === "h")
                    df.hh = Math.max(0, Math.min(23, df.hh + delta));
                else
                    df.mi = (df.mi + delta * 5 + 60) % 60;
                return;
            }
            if (part === "y") {
                df.yr = Math.max(1, df.yr + delta);
                df._clampDay();
            } else if (part === "mo") {
                const keep = df.dy;
                const m = new Date(df.yr, df.mo - 1 + delta, 1);
                df.yr = m.getFullYear();
                df.mo = m.getMonth() + 1;
                df.dy = Math.min(keep, df._daysInMonth(df.yr, df.mo));
            } else {
                df._setDate(new Date(df.yr, df.mo - 1, df.dy + delta));
            }
        }

        function commit(part, v) {
            if (v < 0) {
                // Emptying any date cell drops the deadline; emptying a time cell
                // just takes the clock off it.
                if (part === "h" || part === "mi")
                    df.hh = -1;
                else
                    df.clear();
                return;
            }
            if (part === "h" || part === "mi") {
                if (!df.hasDate)
                    df.today();
                if (df.hh < 0)
                    df.hh = 0;
                if (part === "h")
                    df.hh = Math.min(23, v);
                else
                    df.mi = Math.min(59, v);
                return;
            }
            if (part === "y")
                df.yr = v;
            else if (part === "mo")
                df.mo = Math.max(1, Math.min(12, v));
            else
                df.dy = Math.max(1, v);
            // A cell can be filled before its neighbours; assume this month/year
            // so a lone day still produces a usable date.
            const n = new Date();
            if (df.yr < 0) df.yr = n.getFullYear();
            if (df.mo < 0) df.mo = n.getMonth() + 1;
            if (df.dy < 0) df.dy = n.getDate();
            df._clampDay();
        }

        DueField {
            id: cellYear
            digits: 4
            value: df.yr
            nextFocus: cellMonth.focusItem
            onStepped: function (d) { df.step("y", d); }
            onTyped: function (v) { df.commit("y", v); }
        }
        DueSep { text: "-" }
        DueField {
            id: cellMonth
            value: df.mo
            nextFocus: cellDay.focusItem
            onStepped: function (d) { df.step("mo", d); }
            onTyped: function (v) { df.commit("mo", v); }
        }
        DueSep { text: "-" }
        DueField {
            id: cellDay
            value: df.dy
            nextFocus: cellHour.focusItem
            onStepped: function (d) { df.step("d", d); }
            onTyped: function (v) { df.commit("d", v); }
        }
        Item { width: 8; height: 1 }
        DueField {
            id: cellHour
            value: df.hh
            nextFocus: cellMinute.focusItem
            onStepped: function (d) { df.step("h", d); }
            onTyped: function (v) { df.commit("h", v); }
        }
        DueSep { text: ":" }
        DueField {
            id: cellMinute
            value: df.hh < 0 ? -1 : df.mi
            nextFocus: df.tabTarget
            onStepped: function (d) { df.step("mi", d); }
            onTyped: function (v) { df.commit("mi", v); }
        }
        Item { width: 4; height: 1 }
        MenuButton {
            width: 52
            implicitHeight: 22
            discrete: true
            onClicked: df.hasDate ? df.clear() : df.today()
            Text {
                anchors.centerIn: parent
                text: df.hasDate ? "clear" : "today"
                color: root.textDimmer
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
        }
    }

    // ---- One task in the todo dropdown ----
    //
    // The line itself is checkbox / title / notes mark / deadline / delete.
    // Hovering reveals the description underneath; clicking anywhere that isn't
    // the checkbox or the delete mark opens the editor below the row, where both
    // the deadline and the description are changed and committed together.
    component TodoRow: Column {
        id: trow
        required property var modelData
        readonly property bool expanded: root.todoExpandedId === trow.modelData.id
        width: parent.width
        spacing: 0

        function apply() {
            TodoStore.edit(trow.modelData.id, dueFields.stamp, descInput.text);
            root.todoExpandedId = "";
        }

        // Every mutation re-sorts the list and so rebuilds these delegates; a row
        // rebuilt mid-edit comes up already expanded and never sees the
        // visibility change, hence the prime runs from both places.
        function prime() {
            dueFields.load(trow.modelData.due);
            descInput.text = trow.modelData.desc;
            descInput.cursorPosition = descInput.length;
            descInput.forceActiveFocus();
        }

        Rectangle {
            width: parent.width
            height: 24
            radius: 3
            color: rowHover.hovered || trow.expanded ? root.hoverBg : "transparent"
            // Widens the popup around the task text (see Dropdown.naturalWidth);
            // the deadline is a fixed column so its changing label can't.
            implicitWidth: 6 + box.implicitWidth + 8 + title.implicitWidth + 6 + root.todoNoteWidth
                + 6 + root.todoDueWidth + 6 + 16 + 6

            // HoverHandler, not MouseArea: the checkbox/delete MouseAreas stack on
            // top and would take hover tracking away from a MouseArea here.
            HoverHandler { id: rowHover }

            // Declared first so it sits under the checkbox and delete targets,
            // which keep their own clicks.
            MouseArea {
                anchors.fill: parent
                onClicked: root.todoExpandedId = trow.expanded ? "" : trow.modelData.id
            }

            Text {
                id: box
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: trow.modelData.done ? "\uf046" : "\uf096"
                color: boxMa.containsMouse ? root.accent : (trow.modelData.done ? root.textFaint : root.textDim)
                font.family: Theme.fontFamily
                font.pixelSize: 14
                MouseArea {
                    id: boxMa
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    onClicked: TodoStore.toggle(trow.modelData.id)
                }
            }

            Text {
                id: title
                anchors.left: box.right
                anchors.leftMargin: 8
                anchors.right: note.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: trow.modelData.text
                elide: Text.ElideRight
                color: trow.modelData.done ? root.textFaint : root.textDefault
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.strikeout: trow.modelData.done
            }

            // Marks a task that carries notes. Purely an indicator now — the row
            // click is what opens them.
            Text {
                id: note
                width: root.todoNoteWidth
                anchors.right: dueText.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "\uf036"
                visible: trow.modelData.desc !== ""
                color: trow.modelData.done ? root.textFaint : root.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Text {
                id: dueText
                width: root.todoDueWidth
                anchors.right: del.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: trow.modelData.due !== "" ? TodoStore.dueLabel(trow.modelData.due, TodoStore.now)
                    : (rowHover.hovered ? "set due" : "\uf073")
                color: trow.modelData.due !== "" ? root.todoDueColor(TodoStore.dueTone(trow.modelData.due, TodoStore.now), trow.modelData.done)
                    : root.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            Text {
                id: del
                width: 16
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "\uf00d"
                color: delMa.containsMouse ? root.dueLate : root.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 12
                visible: rowHover.hovered || trow.expanded
                MouseArea {
                    id: delMa
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    onClicked: {
                        if (trow.expanded)
                            root.todoExpandedId = "";
                        TodoStore.remove(trow.modelData.id);
                    }
                }
            }
        }

        // Hover preview of the notes. Only grows downwards, so the row line the
        // pointer is on never moves out from under it.
        Row {
            width: parent.width
            visible: !trow.expanded && rowHover.hovered && trow.modelData.desc !== ""
            leftPadding: root.todoIndent
            rightPadding: 8
            bottomPadding: 4

            Text {
                width: parent.width - parent.leftPadding - parent.rightPadding
                text: trow.modelData.desc
                wrapMode: Text.Wrap
                color: root.textDimmer
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
        }

        Column {
            id: editPanel
            width: parent.width
            visible: trow.expanded
            spacing: 6
            leftPadding: root.todoIndent
            rightPadding: 8
            topPadding: 4
            bottomPadding: 6
            onVisibleChanged: if (visible) trow.prime()
            Component.onCompleted: if (visible) trow.prime()

            DueFields {
                id: dueFields
                tabTarget: descInput
            }

            Rectangle {
                width: editPanel.width - editPanel.leftPadding - editPanel.rightPadding
                // Grows with the text, but always offers a couple of lines to
                // start writing in.
                height: Math.max(52, descInput.implicitHeight + 16)
                radius: 3
                color: "transparent"
                border.width: 1
                border.color: descInput.activeFocus ? root.accent : root.hairline

                TextEdit {
                    id: descInput
                    anchors.fill: parent
                    anchors.margins: 8
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    color: root.textDefault
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    // BeforeItem, or TextEdit swallows tab as a character.
                    KeyNavigation.priority: KeyNavigation.BeforeItem
                    KeyNavigation.tab: dueFields.firstFocus
                    Keys.onEscapePressed: root.todoExpandedId = ""
                    // Enter belongs to the text here, so ctrl+enter is what saves.
                    Keys.onReturnPressed: event => {
                        if (event.modifiers & Qt.ControlModifier)
                            trow.apply();
                        else
                            event.accepted = false;
                    }
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.top: parent.top
                    anchors.topMargin: 8
                    text: "description (optional)"
                    color: root.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    visible: descInput.text === ""
                }
            }

            Row {
                spacing: 6

                MenuButton {
                    width: 48
                    implicitHeight: 22
                    onClicked: trow.apply()
                    Text { anchors.centerIn: parent; text: "save"; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 12 }
                }

                MenuButton {
                    width: 56
                    implicitHeight: 22
                    discrete: true
                    onClicked: root.todoExpandedId = ""
                    Text { anchors.centerIn: parent; text: "cancel"; color: root.textDimmer; font.family: Theme.fontFamily; font.pixelSize: 12 }
                }

                Text {
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 6
                    text: "ctrl+enter"
                    color: root.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }
    }


    property var powerConfirm: null

    function powerConfirmAccept() {
        const cmd = root.powerConfirm.cmd;
        root.powerConfirm = null;
        Quickshell.execDetached(cmd);
    }

    PanelWindow {
        visible: root.powerConfirm !== null
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qsbar-confirm"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"
        implicitWidth: 380
        implicitHeight: 150

        onVisibleChanged: if (visible) confirmBox.forceActiveFocus()

        Rectangle {
            id: confirmBox
            anchors.fill: parent
            color: root.bg
            border.width: 1
            border.color: root.accent
            focus: true
            Keys.onReturnPressed: root.powerConfirmAccept()
            Keys.onEnterPressed: root.powerConfirmAccept()
            Keys.onEscapePressed: root.powerConfirm = null

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 32
                text: root.powerConfirm ? root.powerConfirm.name + "?" : ""
                color: root.textBright
                font.family: Theme.fontFamily
                font.pixelSize: 20
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 24
                spacing: 16
                MenuButton {
                    width: 140
                    implicitHeight: 32
                    onClicked: root.powerConfirm = null
                    Text {
                        anchors.centerIn: parent
                        text: "cancel  esc"; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 14
                    }
                }
                MenuButton {
                    width: 140
                    implicitHeight: 32
                    border.color: root.accent
                    onClicked: root.powerConfirmAccept()
                    Text {
                        anchors.centerIn: parent
                        text: "ok  enter"; color: root.accent; font.family: Theme.fontFamily; font.pixelSize: 14
                    }
                }
            }
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

            HoverState {
                id: hsTodo
                // Pinned only while there is something to lose: a deadline being
                // edited or a half-typed task. An empty composer closes on
                // pointer-out like every other dropdown, so it can't strand
                // itself open after the user wanders off.
                pinned: root.todoExpandedId !== ""
                    || (root.todoComposing && (newTaskInput.text !== "" || newDescInput.text !== ""
                        || newDue.hasDate))
            }
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
                color: "transparent"

                // ---------------- LEFT ----------------
                Row {
                    id: leftRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    // Todo
                    Rectangle {
                        width: todoRow.implicitWidth + 18
                        height: root.barHeight
                        color: hsTodo.open ? root.hoverBg : "transparent"

                        Row {
                            id: todoRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: "\uf0ae"
                                color: TodoStore.overdueCount > 0 ? root.dueLate
                                    : (TodoStore.openCount > 0 ? root.accent : root.textDimmer)
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                            }
                            Text {
                                text: TodoStore.openCount
                                visible: TodoStore.openCount > 0
                                color: TodoStore.overdueCount > 0 ? root.dueLate : root.textDefault
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: hsTodo.enter()
                            onExited: hsTodo.leave()
                            // Hover just shows the list; clicking holds it open and
                            // drops the cursor in the composer, clicking again lets go.
                            onClicked: {
                                if (root.todoComposing || root.todoExpandedId !== "") {
                                    todoDropdown.dismiss();
                                } else {
                                    hsTodo.enter();
                                    root.todoComposing = true;
                                    todoDropdown.focusComposer();
                                }
                            }
                        }
                    }

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
                    minWidth: 236

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

                Dropdown {
                    id: todoDropdown
                    barScreen: barWin.screen
                    hover: hsTodo
                    align: "left"
                    minWidth: 380
                    // Gated on being open: todoComposing is shared by every screen's
                    // dropdown, and an off-screen window must never hold the
                    // compositor's keyboard grab.
                    wantsKeyboard: hsTodo.open && (root.todoComposing || root.todoExpandedId !== "")

                    onVisibleChanged: {
                        if (visible)
                            return;
                        root.todoDismiss();
                        newTaskInput.focus = false;
                        newDescInput.focus = false;
                    }

                    // The composer can only take focus once the popup is mapped,
                    // so a click on the bar icon hands off through a tick.
                    function focusComposer() { composerFocusTimer.restart(); }

                    function dismiss() {
                        root.todoDismiss();
                        newTaskInput.focus = false;
                        newDescInput.focus = false;
                        hsTodo.open = false;
                    }

                    Timer { id: composerFocusTimer; interval: 40; onTriggered: newTaskInput.forceActiveFocus() }

                    Item {
                        width: parent.width
                        height: 16

                        SectionLabel {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "TODO"
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (TodoStore.openCount === 0)
                                    return TodoStore.tasks.length === 0 ? "" : "all done";
                                let s = TodoStore.openCount + " open";
                                if (TodoStore.overdueCount > 0)
                                    s += " · " + TodoStore.overdueCount + " late";
                                else if (TodoStore.dueTodayCount > 0)
                                    s += " · " + TodoStore.dueTodayCount + " today";
                                return s;
                            }
                            color: TodoStore.overdueCount > 0 ? root.dueLate : root.textDimmer
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }

                    Text {
                        visible: TodoStore.tasks.length === 0
                        text: "nothing on the list"
                        color: root.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        topPadding: 4
                        bottomPadding: 2
                    }

                    Repeater {
                        model: TodoStore.openTasks
                        delegate: TodoRow {}
                    }

                    Item {
                        width: parent.width
                        height: 18
                        visible: TodoStore.doneTasks.length > 0

                        SectionLabel {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            text: "DONE"
                        }
                        MenuButton {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            width: 56
                            implicitHeight: 18
                            discrete: true
                            onClicked: TodoStore.clearDone()
                            Text { anchors.centerIn: parent; text: "clear"; color: root.textDimmer; font.family: Theme.fontFamily; font.pixelSize: 11 }
                        }
                    }

                    Repeater {
                        model: TodoStore.doneTasks
                        delegate: TodoRow {}
                    }

                    Item { width: parent.width; height: 4 }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.hairline
                    }

                    Row {
                        id: composer
                        width: parent.width
                        spacing: 6
                        topPadding: 4

                        Rectangle {
                            width: composer.width - addBtn.width - composer.spacing
                            height: 24
                            radius: 3
                            color: "transparent"
                            border.width: 1
                            border.color: newTaskInput.activeFocus ? root.accent : root.hairline

                            TextInput {
                                id: newTaskInput
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: root.textDefault
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                clip: true
                                // Scene focus alone isn't enough: wantsKeyboard follows
                                // todoComposing, and that is what actually gets the
                                // compositor to route keys here.
                                onActiveFocusChanged: if (activeFocus) root.todoComposing = true
                                KeyNavigation.tab: newDescInput
                                Keys.onReturnPressed: addBtn.clicked()
                                Keys.onEscapePressed: todoDropdown.dismiss()
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: "new task"
                                color: root.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                visible: newTaskInput.text === ""
                            }
                        }

                        MenuButton {
                            id: addBtn
                            width: 44
                            implicitHeight: 24
                            onClicked: {
                                if (newTaskInput.text.trim() === "") {
                                    newTaskInput.forceActiveFocus();
                                    return;
                                }
                                TodoStore.add(newTaskInput.text, newDue.stamp, newDescInput.text);
                                newTaskInput.text = "";
                                newDescInput.text = "";
                                newDue.clear();
                                newTaskInput.forceActiveFocus();
                            }
                            Text { anchors.centerIn: parent; text: "add"; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        }
                    }

                    // Deadline and notes for the new task, both optional. Only in
                    // the way once the composer has the keyboard.
                    Row {
                        width: parent.width
                        visible: root.todoComposing
                        spacing: 8
                        topPadding: 2

                        Text {
                            height: 22
                            verticalAlignment: Text.AlignVCenter
                            text: "due"
                            color: root.textDimmer
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }

                        DueFields {
                            id: newDue
                            tabTarget: newTaskInput
                        }
                    }

                    Rectangle {
                        width: parent.width
                        visible: root.todoComposing
                        height: Math.max(40, newDescInput.implicitHeight + 16)
                        radius: 3
                        color: "transparent"
                        border.width: 1
                        border.color: newDescInput.activeFocus ? root.accent : root.hairline

                        TextEdit {
                            id: newDescInput
                            anchors.fill: parent
                            anchors.margins: 8
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            color: root.textDefault
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            onActiveFocusChanged: if (activeFocus) root.todoComposing = true
                            // BeforeItem, or TextEdit swallows tab as a character.
                            KeyNavigation.priority: KeyNavigation.BeforeItem
                            KeyNavigation.tab: newDue.firstFocus
                            Keys.onEscapePressed: todoDropdown.dismiss()
                            // Enter belongs to the text here, so ctrl+enter adds.
                            Keys.onReturnPressed: event => {
                                if (event.modifiers & Qt.ControlModifier)
                                    addBtn.clicked();
                                else
                                    event.accepted = false;
                            }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            text: "description (optional)"
                            color: root.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            visible: newDescInput.text === ""
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
                    minWidth: 260

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
                    minWidth: 260

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
                            text: root.netKind === "ethernet" ? "" : ""
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
                    minWidth: 300

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
                    id: volDropdown
                    barScreen: barWin.screen
                    hover: hsVol
                    align: "right"
                    minWidth: 292

                    readonly property var appStreams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink && n.audio)
                    function appName(n) {
                        return n.properties && n.properties["application.name"] ? n.properties["application.name"] : n.name;
                    }
                    // One name column shared by all application rows so their sliders
                    // line up, sized to the longest name (monospace font, so the
                    // longest by character count is the widest) and capped so one
                    // absurd name can't eat the whole popup.
                    TextMetrics {
                        id: appNameMetrics
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        text: volDropdown.appStreams.map(n => volDropdown.appName(n)).reduce((a, b) => b.length > a.length ? b : a, "")
                    }
                    readonly property int appNameColWidth: Math.min(Math.ceil(appNameMetrics.advanceWidth) + 1, 240)

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
                            // Full device name + status column: the popup widens to fit.
                            implicitWidth: sinkName.implicitWidth + 8 + activeLabel.width + 2 * contentInset
                            discrete: true
                            onClicked: Pipewire.preferredDefaultAudioSink = modelData
                            Text {
                                id: sinkName
                                anchors.left: parent.left
                                anchors.right: activeLabel.left
                                anchors.rightMargin: 8
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
                        model: volDropdown.appStreams
                        delegate: Item {
                            id: appRow
                            required property var modelData
                            x: 8
                            width: parent.width - 16
                            height: appName.implicitHeight
                            // Name column + room for a usable slider; the % column is
                            // fixed-width so a changing volume can't resize the popup.
                            implicitWidth: 16 + volDropdown.appNameColWidth + 8 + 80 + 8 + appPct.width
                            Text {
                                id: appName
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: volDropdown.appNameColWidth
                                text: volDropdown.appName(appRow.modelData)
                                color: root.textDefault
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Item {
                                anchors.left: appName.right
                                anchors.leftMargin: 8
                                anchors.right: appPct.left
                                anchors.rightMargin: 8
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
                                id: appPct
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
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
                            text: "pavucontrol"
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
                    minWidth: 248

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
                            // Full device name + status column: the popup widens to fit.
                            implicitWidth: btName.implicitWidth + 8 + statusLabel.width + 2 * contentInset
                            discrete: true
                            onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                            Text {
                                id: btName
                                anchors.left: parent.left
                                anchors.right: statusLabel.left
                                anchors.rightMargin: 8
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
                                text: "qs-bluetooth"
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
                    minWidth: 380
                    wantsKeyboard: root.wifiExpandedSsid !== "" && root.wifiExpandedNeedsPassword

                    Repeater {
                        model: root.netWiredList
                        delegate: Column {
                            required property var modelData
                            required property int index
                            width: parent.width
                            spacing: 4
                            SectionLabel { text: "WIRED · " + modelData.dev; topPadding: index > 0 ? 6 : 0 }
                            Repeater {
                                model: modelData.addrs
                                delegate: Row {
                                    required property var modelData
                                    width: parent.width
                                    Text { text: modelData.kind; color: root.textDim; font.family: Theme.fontFamily; font.pixelSize: 13; width: parent.width - 150 }
                                    Text { text: modelData.cidr; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13; width: 150; horizontalAlignment: Text.AlignRight }
                                }
                            }
                            Text {
                                visible: modelData.addrs.length === 0
                                text: "no ipv4 address"
                                color: root.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }
                            Row {
                                width: parent.width
                                Text { text: "gateway"; color: root.textDim; font.family: Theme.fontFamily; font.pixelSize: 13; width: parent.width - 120 }
                                Text { text: modelData.gw; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13; width: 120; horizontalAlignment: Text.AlignRight }
                            }
                        }
                    }

                    SectionLabel { text: "WI-FI"; topPadding: 6 }
                    Timer { id: wifiRefreshTimer; interval: 2500; onTriggered: netProc.running = true }
                    Repeater {
                        model: root.netWifiList
                        delegate: Column {
                            id: wifiRow
                            required property var modelData
                            readonly property bool expanded: root.wifiExpandedSsid === modelData.ssid
                            // Interface details for the connected network: match the NM
                            // connection name to the SSID, fall back to the first wifi device.
                            readonly property var devInfo: modelData.active
                                ? (root.netWifiDevList.find(d => d.conn === modelData.ssid) || root.netWifiDevList[0] || null)
                                : null
                            width: parent.width
                            spacing: 0

                            MenuButton {
                                width: parent.width
                                // Full SSID + status columns: the popup widens to fit.
                                implicitWidth: ssidText.implicitWidth + 8 + securityLabel.width + signalLabel.width + 2 * contentInset
                                discrete: true
                                // The connected network's actions are always shown below it,
                                // so its row is a plain label: no hover chrome, no click.
                                enabled: !modelData.active
                                opacity: 1
                                onClicked: {
                                    root.wifiExpandedSsid = wifiRow.expanded ? "" : modelData.ssid;
                                    root.wifiExpandedNeedsPassword = !modelData.saved;
                                    root.wifiShowPassword = false;
                                }
                                Text {
                                    id: ssidText
                                    anchors.left: parent.left
                                    anchors.right: securityLabel.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (modelData.active ? "● " : "") + modelData.ssid
                                    color: modelData.active ? root.accent : root.textDefault
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: securityLabel
                                    anchors.right: signalLabel.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.active ? "connected" : modelData.security
                                    color: modelData.active ? root.accent : root.textDimmer
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    width: 62
                                    horizontalAlignment: Text.AlignRight
                                }
                                Text {
                                    id: signalLabel
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.signal + "%"
                                    color: root.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    width: 40
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            Column {
                                width: parent.width
                                visible: wifiRow.devInfo !== null
                                spacing: 4
                                topPadding: 2
                                bottomPadding: 4
                                // Match MenuButton's 8px content inset on the right so the
                                // values line up with the signal column; indent deeper on
                                // the left to read as nested under the connection row.
                                leftPadding: 16
                                rightPadding: 8
                                Row {
                                    width: parent.width - parent.leftPadding - parent.rightPadding
                                    Text { text: "ipv4 · " + (wifiRow.devInfo ? wifiRow.devInfo.dev : ""); color: root.textDim; font.family: Theme.fontFamily; font.pixelSize: 13; width: parent.width - 140 }
                                    Text { text: wifiRow.devInfo ? wifiRow.devInfo.ip4 : ""; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13; width: 140; horizontalAlignment: Text.AlignRight }
                                }
                                Row {
                                    width: parent.width - parent.leftPadding - parent.rightPadding
                                    Text { text: "gateway"; color: root.textDim; font.family: Theme.fontFamily; font.pixelSize: 13; width: parent.width - 140 }
                                    Text { text: wifiRow.devInfo ? wifiRow.devInfo.gw : ""; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13; width: 140; horizontalAlignment: Text.AlignRight }
                                }
                                Row {
                                    spacing: 6
                                    MenuButton {
                                        width: 72
                                        onClicked: {
                                            Quickshell.execDetached([root.repoScripts + "/qs-wifi", "--disconnect"]);
                                            wifiRefreshTimer.restart();
                                        }
                                        Text { anchors.centerIn: parent; text: "disconnect"; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 12 }
                                    }
                                    MenuButton {
                                        width: 56
                                        visible: modelData.saved
                                        onClicked: {
                                            Quickshell.execDetached([root.repoScripts + "/qs-wifi", "--forget", modelData.ssid]);
                                            wifiRefreshTimer.restart();
                                        }
                                        Text { anchors.centerIn: parent; text: "forget"; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 12 }
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                visible: wifiRow.expanded
                                topPadding: 4
                                bottomPadding: 6
                                spacing: 6
                                onVisibleChanged: if (visible && !modelData.saved) pwInput.forceActiveFocus()

                                Rectangle {
                                    width: parent.width
                                    height: 24
                                    radius: 3
                                    visible: !modelData.saved
                                    color: "transparent"
                                    border.width: 1
                                    border.color: pwInput.activeFocus ? root.accent : root.hairline

                                    TextInput {
                                        id: pwInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: root.textDefault
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        clip: true
                                        echoMode: root.wifiShowPassword ? TextInput.Normal : TextInput.Password
                                        passwordCharacter: "•"
                                        Keys.onReturnPressed: connectBtn.clicked()
                                        Keys.onEscapePressed: root.wifiExpandedSsid = ""
                                    }
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "password"
                                        color: root.textFaint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        visible: pwInput.text === "" && !pwInput.activeFocus
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: 6

                                    MenuButton {
                                        width: 44
                                        discrete: true
                                        visible: !modelData.saved
                                        onClicked: root.wifiShowPassword = !root.wifiShowPassword
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.wifiShowPassword ? "hide" : "show"
                                            color: root.textDimmer
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                        }
                                    }
                                    MenuButton {
                                        id: connectBtn
                                        width: 72
                                        onClicked: {
                                            if (modelData.active) {
                                                Quickshell.execDetached([root.repoScripts + "/qs-wifi", "--disconnect"]);
                                            } else {
                                                Quickshell.execDetached([root.repoScripts + "/qs-wifi", "--connect", modelData.ssid, pwInput.text]);
                                            }
                                            root.wifiExpandedSsid = "";
                                            wifiRefreshTimer.restart();
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.active ? "disconnect" : "connect"
                                            color: root.textDefault
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                        }
                                    }
                                    MenuButton {
                                        width: 56
                                        visible: modelData.saved
                                        onClicked: {
                                            Quickshell.execDetached([root.repoScripts + "/qs-wifi", "--forget", modelData.ssid]);
                                            root.wifiExpandedSsid = "";
                                            wifiRefreshTimer.restart();
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "forget"
                                            color: root.textDefault
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Repeater {
                        model: root.netVpnList
                        delegate: Column {
                            required property var modelData
                            width: parent.width
                            spacing: 4
                            SectionLabel { text: "VPN · " + modelData.dev; topPadding: 6 }
                            Row {
                                width: parent.width
                                Text { text: "ipv4"; color: root.textDim; font.family: Theme.fontFamily; font.pixelSize: 13; width: parent.width - 120 }
                                Text { text: modelData.ip4; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13; width: 120; horizontalAlignment: Text.AlignRight }
                            }
                            Row {
                                width: parent.width
                                Text { text: "routes"; color: root.textDim; font.family: Theme.fontFamily; font.pixelSize: 13; width: 60 }
                                Text { text: modelData.routes; color: root.textDefault; font.family: Theme.fontFamily; font.pixelSize: 13; width: parent.width - 60; horizontalAlignment: Text.AlignRight; wrapMode: Text.Wrap }
                            }
                        }
                    }

                    Item { width: 1; height: 4 }
                    Row {
                        spacing: 8
                        MenuButton {
                            width: nmtuiText.implicitWidth + 16
                            onClicked: Quickshell.execDetached(["kitty", "--class", "nmtui-popup", "-e", "nmtui"])
                            Text {
                                id: nmtuiText
                                anchors.centerIn: parent
                                text: "nmtui"
                                color: root.textDimmer
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }
                        MenuButton {
                            width: qsWifiText.implicitWidth + 16
                            onClicked: Quickshell.execDetached([root.repoScripts + "/qs-wifi"])
                            Text {
                                id: qsWifiText
                                anchors.centerIn: parent
                                text: "qs-wifi"
                                color: root.textDimmer
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }
                    }
                }

                Dropdown {
                    barScreen: barWin.screen
                    hover: hsPow
                    align: "right"
                    minWidth: 216

                    SectionLabel { text: "POWER" }

                    Repeater {
                        model: [
                            { name: "lock", key: "l", cmd: ["hyprlock"] },
                            { name: "suspend", key: "s", cmd: ["systemctl", "suspend"], confirm: true },
                            { name: "log out", key: "e", cmd: ["hyprctl", "dispatch", "exit"], confirm: true },
                            { name: "reboot", key: "r", cmd: ["systemctl", "reboot"], confirm: true },
                            { name: "power off", key: "p", cmd: ["systemctl", "poweroff"], confirm: true }
                        ]
                        delegate: MenuButton {
                            required property var modelData
                            width: parent.width
                            onClicked: {
                                if (!modelData.confirm)
                                    return Quickshell.execDetached(modelData.cmd);
                                hsPow.open = false;
                                root.powerConfirm = modelData;
                            }
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
