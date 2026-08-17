-- Home dock: laptop panel off, two ASUS VG27A side by side at 144Hz.
-- Matched by description (includes serial) so left/right stay fixed regardless
-- of which DP-* connector each lands on.
hl.monitor({ output = "eDP-1", disabled = true })
hl.monitor({ output = "desc:ASUSTek COMPUTER INC VG27A LCLMQS143396", mode = "2560x1440@143.97", position = "0x0", scale = 1 })
hl.monitor({ output = "desc:ASUSTek COMPUTER INC VG27A LCLMQS143398", mode = "2560x1440@143.97", position = "2560x0", scale = 1 })
