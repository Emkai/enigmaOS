// qsmenu — a wofi-style dmenu replacement rendered by quickshell.
//
// One hidden PanelWindow that scripts drive over IPC:
//   qs -p <this dir> ipc call menu show <prompt> <options> <fifo> <lines> <password>
// The selection ("" when dismissed) is written to <fifo> and the window hides
// again. scripts/qs-main is the only intended caller.
//
// Colors mirror scripts/menu/style.css so both menu systems look alike.

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
    readonly property int inputHeight: 38
    readonly property color bgColor: "#131215"
    readonly property color fieldColor: "#22233a"
    readonly property color textColor: "#f8f8f2"
    readonly property color accentColor: "#33ccff"

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
        implicitWidth: 640
        implicitHeight: root.inputHeight + root.lines * root.rowHeight + 2

        onVisibleChanged: if (visible) searchInput.forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            color: root.bgColor

            Column {
                anchors.fill: parent
                anchors.margins: 1

                Rectangle {
                    width: parent.width
                    height: root.inputHeight
                    color: root.fieldColor

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: root.accentColor
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        visible: searchInput.text === ""
                        text: root.prompt
                        color: Qt.rgba(0.97, 0.97, 0.95, 0.5)
                        font.pixelSize: 15
                    }

                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.textColor
                        font.pixelSize: 15
                        echoMode: root.passwordMode ? TextInput.Password : TextInput.Normal
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

                ListView {
                    id: list
                    width: parent.width
                    height: root.lines * root.rowHeight
                    visible: root.lines > 0
                    clip: true
                    model: root.filtered

                    delegate: Rectangle {
                        id: row
                        required property int index
                        required property string modelData
                        width: list.width
                        height: root.rowHeight
                        color: index === root.selectedIndex ? root.fieldColor : "transparent"

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            text: row.modelData
                            color: root.textColor
                            font.pixelSize: 15
                            font.bold: row.index === root.selectedIndex
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
            }
        }
    }
}
