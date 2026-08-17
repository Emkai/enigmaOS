-- Work dock: laptop panel off, two Dell P2723DE side by side at 60Hz.
-- Matched by description (includes serial) so left/right stay fixed regardless
-- of which DP-* connector each lands on.
hl.monitor({ output = "eDP-1", disabled = true })
hl.monitor({ output = "desc:Dell Inc. DELL P2723DE JWSDH14", mode = "2560x1440@59.95", position = "0x0", scale = 1 })
hl.monitor({ output = "desc:Dell Inc. DELL P2723DE 466F714", mode = "2560x1440@59.95", position = "2560x0", scale = 1 })
