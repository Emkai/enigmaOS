-- See https://wiki.hypr.land/Configuring/Start/
-- monitors.lua is machine state written by hyprdynamicmonitors (gitignored),
-- absent on a fresh install until the daemon first runs — don't hard-fail
-- the whole config then; the daemon's post_apply hyprctl reload picks it up.
pcall(require, "monitors")
require("autostart")
require("env")
require("style")
require("input")
require("binds")
require("windows")
