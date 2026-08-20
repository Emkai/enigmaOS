// qsmenu — quickshell-rendered menus, styled by Theme.qml.
//
// Menu.qml: wofi-style dmenu window that scripts drive over IPC:
//   qs -p <this dir> ipc call menu open <prompt> <options> <fifo> <lines> <password>
// The selection ("" when dismissed) is written to <fifo> and the window hides
// again. scripts/qs-main is the only intended caller.
//
// Drun.qml: application launcher, toggled via:
//   qs -p <this dir> ipc call drun toggle
// (bound to super+alt+space through scripts/qs-drun).

import Quickshell

ShellRoot {
    Menu {}
    Drun {}
}
