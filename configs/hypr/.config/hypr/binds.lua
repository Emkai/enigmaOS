local programs = require("programs")

-- See https://wiki.hypr.land/Configuring/Basics/Binds/ for more
local mainMod = "SUPER" -- Sets "Windows" key as main modifier

hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(programs.terminal))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(programs.browser))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(programs.music))
hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + escape", hl.dsp.exit())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(programs.fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float())
hl.bind(mainMod .. " + S", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(programs.menu))
-- hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("cat ~/.config/hypr/help/tmux $dmenu"))
-- hl.bind(mainMod .. " + SHIFT + K", hl.dsp.exec_cmd("ls ~/ | $dmenu"))
hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd("~/src/enigmaOS/scripts/wofi-main"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo()) -- dwindle
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
-- hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) -- dwindle
hl.bind(mainMod .. " + Y", hl.dsp.exec_cmd("/usr/bin/chromium --profile-directory=Default --app=http://youtube.com"))
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd("/usr/bin/chromium --profile-directory=Default --app=http://github.com"))

-- hyprshot: plain region shot to file; +SHIFT pipes into satty for annotation
hl.bind(mainMod .. " + CTRL + K", hl.dsp.exec_cmd('hyprshot -m region -o ~/Pictures/screenshots && notify-send "Screenshot taken"'))
hl.bind(mainMod .. " + CTRL + SHIFT + K", hl.dsp.exec_cmd("hyprshot -m region --raw | satty --filename - --output-filename ~/Pictures/screenshots/%Y-%m-%d-%H%M%S_satty.png --early-exit --copy-command wl-copy"))
hl.bind(mainMod .. " + CTRL + V", hl.dsp.exec_cmd("~/src/enigmaOS/scripts/screen-recording.sh"))

-- Dictation: press to start recording, press again to transcribe and type
-- the result into whatever window has focus.
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("~/src/enigmaOS/scripts/dictate"))

-- Move focus with mainMod + hjkl (intentionally inverted j/k, kept as-is)
hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "down" }))

hl.bind(mainMod .. " + SHIFT + k", hl.dsp.window.swap({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + k", hl.dsp.window.move({ x = 0, y = -50, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + j", hl.dsp.window.swap({ direction = "down" }))
hl.bind(mainMod .. " + SHIFT + j", hl.dsp.window.move({ x = 0, y = 50, relative = true }), { repeating = true })

hl.bind(mainMod .. " + SHIFT + h", hl.dsp.window.swap({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + h", hl.dsp.window.move({ x = -50, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + l", hl.dsp.window.swap({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + l", hl.dsp.window.move({ x = 50, y = 0, relative = true }), { repeating = true })

-- Change keyboard layout
hl.bind(mainMod .. " + CTRL + SPACE", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
-- hl.bind(mainMod .. " + CTRL + S", hl.dsp.workspace.toggle_special("magic"))
-- hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
