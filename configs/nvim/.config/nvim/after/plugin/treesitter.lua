require('nvim-treesitter').install({
    'c', 'bash', 'go', 'lua', 'vim', 'vimdoc', 'query',
    'markdown', 'markdown_inline', 'http',
})

vim.api.nvim_create_autocmd('FileType', {
    callback = function(args)
        pcall(vim.treesitter.start, args.buf)
    end,
})
