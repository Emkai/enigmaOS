-- Single external Samsung LS27D60xU + laptop panel: monitor on the left,
-- laptop on the right (matches physical desk layout). Same setup at home
-- (HK2Y700227) and at the Echandia lab standing desk (HK2Y400056); only one
-- unit is ever connected, the rule for the absent one is inert.
hl.monitor({ output = "desc:Samsung Electric Company LS27D60xU HK2Y700227", mode = "2560x1440@59.95", position = "0x0", scale = 1 })
hl.monitor({ output = "desc:Samsung Electric Company LS27D60xU HK2Y400056", mode = "2560x1440@59.95", position = "0x0", scale = 1 })
hl.monitor({ output = "eDP-1", mode = "preferred", position = "2560x0", scale = 2 })
