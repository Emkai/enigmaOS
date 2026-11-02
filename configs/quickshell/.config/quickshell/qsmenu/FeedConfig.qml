import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: cfg

    readonly property color cardBg: "#141619"
    readonly property color cardBorder: "#262a31"
    readonly property color track: "#23272e"
    readonly property color accent: Theme.accentColor
    readonly property color textDefault: "#c7cdd6"
    readonly property color textDim: "#98a1ac"
    readonly property color textFaint: "#545c68"
    readonly property color danger: "#e2707a"

    ListModel { id: cats }

    IpcHandler {
        target: "feeds"
        function setup(): void { FeedStore.configOpen = !FeedStore.configOpen; }
    }

    Connections {
        target: FeedStore
        function onConfigOpenChanged() {
            if (FeedStore.configOpen)
                cfg.load(FeedStore.editableConfig());
        }
    }

    function load(list) {
        cats.clear();
        for (const c of list)
            cats.append(c);
    }

    function addCategory() {
        cats.append({ name: "", counter: true, markRead: "off", clear: "off", feeds: [{ url: "", name: "" }] });
    }

    function validDuration(v) { return /^\s*(\d+\s*[mhdw]|off)?\s*$/i.test(v); }

    function save() {
        const list = [];
        for (let i = 0; i < cats.count; i++) {
            const c = cats.get(i);
            const feeds = [];
            for (let j = 0; j < c.feeds.count; j++)
                feeds.push({ url: c.feeds.get(j).url, name: c.feeds.get(j).name });
            list.push({ name: c.name, counter: c.counter, markRead: c.markRead, clear: c.clear, feeds: feeds });
        }
        FeedStore.writeConfig(list);
        FeedStore.refresh();
        FeedStore.configOpen = false;
    }

    component Label: Text {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: cfg.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }

    component Field: Rectangle {
        id: fld
        property alias text: input.text
        property string placeholder
        property bool invalid: false
        signal edited(string value)
        height: 28
        radius: 2
        color: "#000000"
        border.width: 1
        border.color: invalid ? cfg.danger : (input.activeFocus ? cfg.accent : cfg.cardBorder)

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            color: cfg.textDefault
            font.family: Theme.fontFamily
            font.pixelSize: 13
            clip: true
            selectByMouse: true
            onTextEdited: fld.edited(text)
            Keys.onEscapePressed: FeedStore.configOpen = false
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: fld.placeholder
            color: cfg.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }
    }

    component Button: Rectangle {
        id: btn
        property string label
        property color textColor: cfg.textDefault
        property bool primary: false
        signal clicked()
        width: btnText.implicitWidth + 24
        height: 28
        radius: 2
        color: primary ? (ma.containsMouse ? Qt.lighter(cfg.accent, 1.15) : cfg.accent)
            : (ma.containsMouse ? Qt.rgba(cfg.accent.r, cfg.accent.g, cfg.accent.b, 0.10) : "transparent")
        border.width: 1
        border.color: primary ? "transparent" : (ma.containsMouse ? cfg.accent : cfg.cardBorder)
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? "#ffffff" : btn.textColor
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: btn.clicked() }
    }

    component Toggle: Rectangle {
        id: tg
        property bool checked: false
        signal toggled()
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: 34
        height: 18
        radius: 9
        color: checked ? cfg.accent : cfg.track
        Rectangle {
            x: tg.checked ? tg.width - width - 2 : 2
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: "#f2f5f8"
            Behavior on x { NumberAnimation { duration: 120 } }
        }
        MouseArea { anchors.fill: parent; onClicked: tg.toggled() }
    }

    PanelWindow {
        visible: FeedStore.configOpen
        implicitWidth: 720
        implicitHeight: Math.min(list.implicitHeight + 128, 760)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qsfeedcfg"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Shortcut { sequence: "Ctrl+S"; onActivated: cfg.save() }
        Shortcut { sequence: "Escape"; onActivated: FeedStore.configOpen = false }

        Rectangle {
            anchors.fill: parent
            color: cfg.cardBg
            radius: 2
            border.width: 1
            border.color: cfg.cardBorder

            Text {
                id: title
                x: 20
                y: 18
                text: "FEED SETUP"
                color: cfg.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.letterSpacing: 1.5
            }

            Flickable {
                id: flick
                x: 20
                anchors.top: title.bottom
                anchors.topMargin: 14
                anchors.bottom: footer.top
                anchors.bottomMargin: 14
                width: parent.width - 40
                contentHeight: list.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: list
                    width: flick.width
                    spacing: 10

                    Repeater {
                        model: cats
                        delegate: Rectangle {
                            id: card
                            required property int index
                            required property var model
                            width: list.width
                            implicitHeight: cardCol.implicitHeight + 24
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.025)
                            border.width: 1
                            border.color: cfg.cardBorder

                            Column {
                                id: cardCol
                                x: 12
                                y: 12
                                width: parent.width - 24
                                spacing: 6

                                Row {
                                    spacing: 8
                                    height: 28
                                    Field {
                                        width: 170
                                        text: card.model.name
                                        placeholder: "category"
                                        onEdited: v => cats.setProperty(card.index, "name", v)
                                    }
                                    Label { text: "in bar"; leftPadding: 6 }
                                    Toggle {
                                        checked: card.model.counter
                                        onToggled: cats.setProperty(card.index, "counter", !checked)
                                    }
                                    Label { text: "read after"; leftPadding: 10 }
                                    Field {
                                        width: 56
                                        text: card.model.markRead
                                        invalid: !cfg.validDuration(text)
                                        onEdited: v => cats.setProperty(card.index, "markRead", v)
                                    }
                                    Label { text: "clear after"; leftPadding: 4 }
                                    Field {
                                        width: 56
                                        text: card.model.clear
                                        invalid: !cfg.validDuration(text)
                                        onEdited: v => cats.setProperty(card.index, "clear", v)
                                    }
                                }

                                Repeater {
                                    model: card.model.feeds
                                    delegate: Row {
                                        id: feedRow
                                        required property int index
                                        required property string url
                                        required property string name
                                        spacing: 6
                                        Field {
                                            width: cardCol.width - 200 - 28 - 2 * feedRow.spacing
                                            text: feedRow.url
                                            placeholder: "https://example.com/feed.xml"
                                            onEdited: v => card.model.feeds.setProperty(feedRow.index, "url", v)
                                        }
                                        Field {
                                            width: 200
                                            text: feedRow.name
                                            placeholder: "name (optional)"
                                            onEdited: v => card.model.feeds.setProperty(feedRow.index, "name", v)
                                        }
                                        Button {
                                            width: 28
                                            label: ""
                                            textColor: cfg.textFaint
                                            onClicked: card.model.feeds.remove(feedRow.index)
                                        }
                                    }
                                }

                                Item {
                                    width: parent.width
                                    height: 28
                                    Button {
                                        label: "+ feed"
                                        onClicked: card.model.feeds.append({ url: "", name: "" })
                                    }
                                    Button {
                                        anchors.right: parent.right
                                        label: "remove category"
                                        textColor: cfg.danger
                                        onClicked: cats.remove(card.index)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Row {
                id: footer
                x: 20
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                width: parent.width - 40
                spacing: 8
                Button { id: catBtn; label: "+ category"; onClicked: cfg.addCategory() }
                Item { width: footer.width - 3 * footer.spacing - catBtn.width - cancelBtn.width - saveBtn.width; height: 1 }
                Button { id: cancelBtn; label: "Cancel"; onClicked: FeedStore.configOpen = false }
                Button { id: saveBtn; label: "Save  ctrl+s"; primary: true; onClicked: cfg.save() }
            }
        }
    }
}
