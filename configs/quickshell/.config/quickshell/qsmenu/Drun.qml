// Application launcher (drun) — quickshell-native, driven by the compositor
// bind via `qs -p <this dir> ipc call drun toggle` (see scripts/qs-drun).
// Lists desktop applications through Quickshell's DesktopEntries and launches
// the selection with DesktopEntry.execute().

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property var apps: []
    property var filtered: []
    property int selectedIndex: 0
    property bool shown: false

    readonly property int rowHeight: 36
    readonly property int maxRows: 12

    // Same subsequence matching as Menu.qml's wofi -M fuzzy equivalent.
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

    function loadApps() {
        apps = [...DesktopEntries.applications.values]
            .filter(a => !a.noDisplay)
            .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
    }

    // Rank: name prefix < name substring < fuzzy over name+comment+keywords.
    function refilter() {
        const q = searchInput.text.toLowerCase();
        if (q === "") {
            filtered = apps.slice();
        } else {
            const ranked = [];
            for (let i = 0; i < apps.length; i++) {
                const a = apps[i];
                const name = a.name.toLowerCase();
                let rank;
                if (name.startsWith(q))
                    rank = 0;
                else if (name.includes(q))
                    rank = 1;
                else if (fuzzyMatch(q, a.name + " " + a.comment + " " + a.keywords.join(" ")))
                    rank = 2;
                else
                    continue;
                ranked.push({ rank: rank, order: i, app: a });
            }
            ranked.sort((x, y) => x.rank - y.rank || x.order - y.order);
            filtered = ranked.map(r => r.app);
        }
        selectedIndex = 0;
    }

    function launch() {
        if (filtered.length === 0)
            return;
        filtered[Math.min(selectedIndex, filtered.length - 1)].execute();
        shown = false;
    }

    function moveSelection(delta) {
        if (filtered.length === 0)
            return;
        selectedIndex = Math.max(0, Math.min(filtered.length - 1, selectedIndex + delta));
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    // The desktop-entry scan is asynchronous: a toggle right after daemon
    // start (cold start via scripts/qs-drun) can race it and see no apps.
    // Refresh the open window whenever the scan adds or removes entries.
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            if (root.shown) {
                root.loadApps();
                root.refilter();
            }
        }
    }

    IpcHandler {
        target: "drun"

        function toggle(): void {
            if (root.shown) {
                root.shown = false;
                return;
            }
            root.loadApps();
            searchInput.text = "";
            root.refilter();
            root.shown = true;
        }

        function hide(): void {
            root.shown = false;
        }

        function state(): string {
            return JSON.stringify({
                shown: root.shown,
                apps: root.apps.length,
                filtered: root.filtered.length,
                selected: root.filtered.length > 0 ? root.filtered[root.selectedIndex].name : ""
            });
        }
    }

    PanelWindow {
        id: win
        visible: root.shown
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qsdrun"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"
        implicitWidth: 720
        implicitHeight: Theme.headerHeight + root.maxRows * root.rowHeight + Theme.footerHeight + 2

        onVisibleChanged: if (visible) searchInput.forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            color: Theme.bgColor
            border.width: 1
            border.color: Theme.borderColor

            // ---- Header: run · filter input · match counter ----
            Item {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: Theme.headerHeight

                Text {
                    id: promptLabel
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    text: "run"
                    color: Theme.accentColor
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                }

                Text {
                    id: counter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    text: root.filtered.length + "/" + root.apps.length
                    color: Theme.mutedColor
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: promptLabel.right
                    anchors.leftMargin: 12
                    visible: searchInput.text === ""
                    text: "type to filter"
                    color: Theme.mutedColor
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                }

                TextInput {
                    id: searchInput
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: promptLabel.right
                    anchors.leftMargin: 12
                    anchors.right: counter.left
                    anchors.rightMargin: 12
                    color: Theme.brightColor
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    clip: true

                    onTextChanged: root.refilter()

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Escape:
                            root.shown = false;
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
                            root.launch();
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
                color: Theme.lineColor
            }

            // ---- Application list ----
            ListView {
                id: list
                anchors.top: headerLine.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                height: root.maxRows * root.rowHeight
                clip: true
                model: root.filtered

                delegate: Rectangle {
                    id: row
                    required property int index
                    required property var modelData
                    readonly property bool selected: index === root.selectedIndex
                    readonly property string iconSource: modelData.icon !== "" ? Quickshell.iconPath(modelData.icon, true) : ""
                    width: list.width
                    height: root.rowHeight
                    color: selected ? Theme.selectedBgColor : "transparent"

                    Rectangle { // selection accent bar
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        color: Theme.accentColor
                        visible: row.selected
                    }

                    Image {
                        id: icon
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        width: 22
                        height: 22
                        sourceSize: Qt.size(44, 44)
                        asynchronous: true
                        source: row.iconSource
                        visible: row.iconSource !== ""
                    }

                    Text {
                        id: nameText
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 52
                        text: row.modelData.name
                        color: row.selected ? Theme.brightColor : Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: row.selected
                    }

                    Text { // description, like the reference launcher
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: nameText.right
                        anchors.leftMargin: 12
                        anchors.right: categoryText.left
                        anchors.rightMargin: 12
                        text: row.modelData.comment
                        color: Theme.mutedColor
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Text {
                        id: categoryText
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        text: row.modelData.categories.length > 0 ? row.modelData.categories[0].toLowerCase() : ""
                        color: Theme.mutedColor
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selectedIndex = row.index;
                            root.launch();
                        }
                    }
                }
            }

            // ---- Footer: key hints · selected command ----
            Rectangle {
                anchors.bottom: footer.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                height: 1
                color: Theme.lineColor
            }

            Item {
                id: footer
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: Theme.footerHeight

                Text {
                    id: hints
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    text: "↑↓ select  ·  ↵ launch  ·  esc dismiss"
                    color: Theme.mutedColor
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }

                Text { // Exec of the selection, field codes (%U etc.) stripped
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.left: hints.right
                    anchors.leftMargin: 20
                    horizontalAlignment: Text.AlignRight
                    text: root.filtered.length > 0
                        ? root.filtered[Math.min(root.selectedIndex, root.filtered.length - 1)].execString.replace(/\S*=%[a-zA-Z]/g, "").replace(/%[a-zA-Z]/g, "").trim()
                        : ""
                    color: Theme.accentColor
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideLeft
                }
            }
        }
    }
}
