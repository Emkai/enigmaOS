// qsmenu — a wofi-style dmenu replacement rendered by quickshell.
//
// One hidden PanelWindow that scripts drive over IPC:
//   qs -p <this dir> ipc call menu open <prompt> <options> <fifo> <lines> <password>
// The selection ("" when dismissed) is written to <fifo> and the window hides
// again. scripts/qs-main is the only intended caller.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property string prompt: ""
    property var allOptions: []
    property var filtered: []
    property int selectedIndex: 0
    property int lines: 0
    property bool passwordMode: false
    property string outPath: ""
    property bool shown: false

    readonly property int rowHeight: 32
    readonly property int headerHeight: 44
    readonly property int footerHeight: 34
    // The window grows/shrinks with the filtered list; `lines` (wofi's -L) caps it.
    readonly property int visibleRows: Math.min(filtered.length, lines)
    readonly property string fontFamily: "CaskaydiaMono Nerd Font"

    readonly property color bgColor: "#0b0e14"
    readonly property color borderColor: "#8ba7c9"
    readonly property color accentColor: "#5c9fd8"
    readonly property color textColor: "#c3cbd8"
    readonly property color brightColor: "#e8eef6"
    readonly property color mutedColor: "#5c687a"
    readonly property color selectedBgColor: "#111a28"
    readonly property color lineColor: "#1c2432"

    // wofi -M fuzzy equivalent: query chars must appear in order, case-insensitive
    function fuzzyMatch(query, entry) {
        const q = query.toLowerCase();
        const s = entry.toLowerCase();
        let qi = 0;
        for (let si = 0; si < s.length && qi < q.length; si++) {
            if (s[si] === q[qi])
                qi++;
        }
        return qi === q.length;
    }

    function refilter() {
        const q = searchInput.text;
        filtered = q === "" ? allOptions.slice() : allOptions.filter(o => fuzzyMatch(q, o));
        selectedIndex = 0;
    }

    function writeResult(result, path) {
        // The write blocks until the script side opens the fifo for reading;
        // the timeout reaps the writer if that reader is already gone.
        Quickshell.execDetached(["timeout", "5", "bash", "-c", "printf '%s\\n' \"$0\" > \"$1\"", result, path]);
    }

    function finish(result) {
        if (outPath !== "")
            writeResult(result, outPath);
        outPath = "";
        shown = false;
    }

    function activate() {
        if (!shown)
            return;
        if (filtered.length > 0)
            finish(filtered[Math.min(selectedIndex, filtered.length - 1)]);
        else
            finish(searchInput.text); // no match: return the typed text, like wofi without --require-match
    }

    function moveSelection(delta) {
        if (filtered.length === 0)
            return;
        selectedIndex = Math.max(0, Math.min(filtered.length - 1, selectedIndex + delta));
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    IpcHandler {
        target: "menu"

        // Named "open" because "show" would collide with the `qs ipc show`
        // subcommand, whose fallthrough parsing hijacks the call.
        function open(prompt: string, options: string, out: string, lines: int, password: bool): void {
            if (root.outPath !== "") // a previous caller is still waiting: release it
                root.writeResult("", root.outPath);
            root.prompt = prompt;
            root.allOptions = options === "" ? [] : options.split("\n").filter(o => o !== "");
            root.lines = lines;
            root.passwordMode = password;
            root.outPath = out;
            searchInput.text = "";
            root.refilter();
            root.shown = true;
        }

        function hide(): void {
            root.finish("");
        }

        function accept(): void { // activate the current selection (also used for scripted tests)
            root.activate();
        }

        function echo(s: string): string { // liveness probe for qs-main
            return s;
        }

        function state(): string {
            return JSON.stringify({
                shown: root.shown,
                prompt: root.prompt,
                options: root.allOptions.length,
                filtered: root.filtered.length,
                lines: root.lines
            });
        }
    }

    PanelWindow {
        id: win
        visible: root.shown
        // Unanchored layer surface: the compositor centers it on the focused monitor.
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qsmenu"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"
        implicitWidth: 720
        implicitHeight: root.headerHeight + root.visibleRows * root.rowHeight + root.footerHeight + 2

        onVisibleChanged: if (visible) searchInput.forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            color: root.bgColor
            border.width: 1
            border.color: root.borderColor

            // ---- Header: prompt · filter input · match counter ----
            Item {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: root.headerHeight

                Text {
                    id: promptLabel
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    text: root.prompt
                    color: root.accentColor
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                }

                Text {
                    id: counter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    visible: root.allOptions.length > 0
                    text: root.filtered.length + "/" + root.allOptions.length
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 12
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: promptLabel.right
                    anchors.leftMargin: 12
                    visible: searchInput.text === ""
                    text: root.allOptions.length > 0 ? "type to filter" : ""
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 14
                }

                TextInput {
                    id: searchInput
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: promptLabel.right
                    anchors.leftMargin: 12
                    anchors.right: counter.visible ? counter.left : parent.right
                    anchors.rightMargin: 12
                    color: root.brightColor
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    echoMode: root.passwordMode ? TextInput.Password : TextInput.Normal
                    passwordCharacter: "•"
                    clip: true

                    onTextChanged: root.refilter()

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Escape:
                            root.finish("");
                            break;
                        case Qt.Key_Down:
                        case Qt.Key_Tab:
                            root.moveSelection(1);
                            break;
                        case Qt.Key_Up:
                        case Qt.Key_Backtab:
                            root.moveSelection(-1);
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.activate();
                            break;
                        default:
                            return;
                        }
                        event.accepted = true;
                    }
                }
            }

            Rectangle {
                id: headerLine
                anchors.top: header.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                height: 1
                color: root.lineColor
                visible: root.visibleRows > 0
            }

            // ---- Option list ----
            ListView {
                id: list
                anchors.top: headerLine.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                height: root.visibleRows * root.rowHeight
                visible: root.visibleRows > 0
                clip: true
                model: root.filtered

                delegate: Rectangle {
                    id: row
                    required property int index
                    required property string modelData
                    readonly property bool selected: index === root.selectedIndex
                    readonly property bool isDivider: /^-{3,}$/.test(modelData)
                    width: list.width
                    height: root.rowHeight
                    color: selected ? root.selectedBgColor : "transparent"

                    Rectangle { // selection accent bar
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        color: root.accentColor
                        visible: row.selected
                    }

                    Rectangle { // dividers ("---------") render as a real separator line
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        height: 1
                        color: root.lineColor
                        visible: row.isDivider
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        visible: !row.isDivider
                        text: row.modelData
                        color: row.selected ? root.brightColor : root.textColor
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        font.bold: row.selected
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selectedIndex = row.index;
                            root.activate();
                        }
                    }
                }
            }

            // ---- Footer: key hints ----
            Rectangle {
                anchors.bottom: footer.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                height: 1
                color: root.lineColor
            }

            Item {
                id: footer
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: root.footerHeight

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    text: root.allOptions.length > 0
                        ? "↑↓ select  ·  ↵ choose  ·  esc dismiss"
                        : "↵ confirm  ·  esc dismiss"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 12
                }
            }
        }
    }
}
