--remove this if dont want transparent
require("tokyonight").setup({
    transparent = true,
    styles = {
        sidebars = "transparent",
        floats = "transparent",
    },
})
vim.cmd[[colorscheme tokyonight]]
vim.opt.signcolumn = "yes"
vim.opt.number=true
vim.opt.relativenumber=true



