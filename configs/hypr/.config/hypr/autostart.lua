local programs = require("programs")

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
hl.on("hyprland.start", function()
    hl.exec_cmd("pavlucontrol")
    -- Monitor switching is handled by the hyprdynamicmonitors daemon
    -- (see ~/.config/hyprdynamicmonitors/config.toml).
    -- Old script-based watcher kept on disk for rollback: uncomment to revert.
    -- hl.exec_cmd("~/src/enigmaOS/scripts/monitor-watcher.sh")
    hl.exec_cmd("hyprdynamicmonitors run")
    hl.exec_cmd("waybar & hyprpaper & " .. programs.terminal)
end)
