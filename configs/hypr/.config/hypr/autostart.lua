local programs = require("programs")

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
hl.on("hyprland.start", function()
    hl.exec_cmd("hyprdynamicmonitors run")
    hl.exec_cmd("hyprpaper & " .. programs.terminal)
    -- waybar is parked for now in favor of the quickshell bar (Bar.qml);
    -- its config/scripts are kept, just not autostarted. Re-add
    -- "waybar & " above (or run scripts/re_waybar) to bring it back.
    -- quickshell menu daemon (scripts/qs-main starts it on demand too)
    hl.exec_cmd("qs -p ~/.config/quickshell/qsmenu -d")
end)
