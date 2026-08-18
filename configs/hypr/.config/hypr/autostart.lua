local programs = require("programs")

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
hl.on("hyprland.start", function()
    hl.exec_cmd("hyprdynamicmonitors run")
    hl.exec_cmd("waybar & hyprpaper & " .. programs.terminal)
end)
