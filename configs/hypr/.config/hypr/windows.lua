-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/ for more
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/ for workspace rules

-- Ignore maximize requests from apps. You'll probably like this.
hl.window_rule({
    name = "windowrule-1",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Satty (screenshot annotation): float, centered on the monitor it opens on
-- — which is the focused monitor, i.e. where the region was just selected
hl.window_rule({
    name = "satty-float-center",
    match = { class = "^(com\\.gabm\\.satty)$" },
    float = true,
    center = true,
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    name = "windowrule-2",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})
