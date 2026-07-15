-- LSP configured via plugins/lspconfig.lua
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.scrolloff = 18
vim.opt.formatoptions:remove("o")

require('mini.diff').setup()
-- Floating, auto-fading notifications; also lets us update a message in place
-- (e.g. the async commit review transitions "Reviewing…" → result on one popup).
require('mini.notify').setup()
vim.diagnostic.config({ virtual_text = true })

require('oil').setup({
    default_file_explorer = false,
    float = {
        padding = 6,
        border = "rounded",
        win_options = {
            winblend = 0,
        },
        override = function(conf)
            return conf
        end,
    }
})

