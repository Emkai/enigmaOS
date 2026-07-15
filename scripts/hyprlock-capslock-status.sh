#!/bin/bash

# Outputs a warning line for hyprlock's password label when caps lock is on
# any keyboard. hyprlock has no native conditional text for this (only a
# color-changing ring via capslock_color), so this is polled via cmd[update:].

if hyprctl devices -j 2>/dev/null | grep -q '"capsLock": true'; then
    echo "Caps Lock is active"
fi
