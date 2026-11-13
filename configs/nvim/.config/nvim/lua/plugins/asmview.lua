return {
    "Emkai/asmview.nvim",
    cmd = { "AsmView", "AsmCompare", "AsmSource" },
    keys = {
        { "<leader>aa", function() require("asmview").toggle() end, desc = "toggle assembly view" },
        { "<leader>ac", function() require("asmview").compare() end, desc = "toggle assembly compare pane" },
        { "<leader>as", function() require("asmview").source() end, desc = "pick assembly source for pane" },
        { "<leader>ae", function() require("asmview").ask() end, desc = "AI explain highlighted assembly" },
    },
    opts = {
        sources = {
            firmware = { object = function(path) return path and (path:gsub("application_sil", "application")) end },
            sil = {},
            compile = { build = true },
        },
        panes = { "firmware", "compile" },
    },
}
