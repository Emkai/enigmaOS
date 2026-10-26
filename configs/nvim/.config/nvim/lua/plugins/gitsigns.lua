return {
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    opts = {
        current_line_blame = true,
        preview_config = { border = 'rounded' },
    },
    keys = {
        { '<leader>gb', '<cmd>Gitsigns toggle_current_line_blame<cr>', desc = 'Toggle inline blame' },
        { '<leader>gB', '<cmd>Gitsigns blame_line full=true<cr>', desc = 'Blame popup' },
    },
}
