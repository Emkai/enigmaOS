-- Uppfinnovation, two-monitor desk: laptop panel off, two AOC U27V4G6B 4K side
-- by side at 60Hz, scale 1.5 (2560x1440 logical each).
-- Matched by description (includes serial) so left/right stay fixed regardless
-- of which DP-* connector each lands on.
hl.monitor({ output = "eDP-1", disabled = true })
hl.monitor({ output = "desc:AOC U27V4G6B VDRNBHA000683", mode = "3840x2160@59.99", position = "0x0", scale = 1.5 })
hl.monitor({ output = "desc:AOC U27V4G6B VDRNBHA000660", mode = "3840x2160@59.99", position = "2560x0", scale = 1.5 })
