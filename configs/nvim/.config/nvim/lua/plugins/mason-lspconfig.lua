return {
    'mason-org/mason-lspconfig.nvim',
    opts = {
        ensure_installed = {
            'lua_ls',
            'gopls',
            'angularls',
            'ts_ls',
            'html',
            'cssls',
            'csharp_ls',
            'clangd',
            'tailwindcss',
            'templ',
            'pyright',
            'jsonls',
            'dockerls',
            'bashls',
        }
    },
    dependencies = {
        {
            'mason-org/mason.nvim',
            opts = {},
        },
        'neovim/nvim-lspconfig'
    }
}
