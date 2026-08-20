// Shared design tokens for the qsmenu windows (Menu.qml, Drun.qml).
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property string fontFamily: "CaskaydiaMono Nerd Font"

    readonly property color bgColor: "#0b0e14"
    readonly property color borderColor: "#8ba7c9"
    readonly property color accentColor: "#5c9fd8"
    readonly property color textColor: "#c3cbd8"
    readonly property color brightColor: "#e8eef6"
    readonly property color mutedColor: "#5c687a"
    readonly property color selectedBgColor: "#111a28"
    readonly property color lineColor: "#1c2432"

    readonly property int headerHeight: 44
    readonly property int footerHeight: 34
}
