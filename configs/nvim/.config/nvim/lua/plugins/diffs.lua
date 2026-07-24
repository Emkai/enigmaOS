-- Treesitter syntax highlighting inside unified diff hunks
-- (:Git diff, inline = diffs in :G status). Side-by-side :Gdiffsplit
-- already gets normal per-buffer highlighting without this.
return {
    'barrettruth/diffs.nvim',
    init = function()
        vim.g.diffs = {
            integrations = {
                fugitive = true,
                neogit = true,
                neojj = true,
                gitsigns = true,
            },
        }
    end,
    config = function()
        -- With a transparent colorscheme (tokyonight transparent=true),
        -- diffs.nvim recomputes its highlight groups right after the first
        -- render and the cache invalidation drops the pending treesitter
        -- pass for the initially visible hunks, leaving them without
        -- language colors. Repaint shortly after a diff buffer opens to
        -- reapply the lost layer.
        vim.api.nvim_create_autocmd('FileType', {
            pattern = { 'git', 'diff', 'fugitive' },
            group = vim.api.nvim_create_augroup('diffs_transparent_repaint', {}),
            callback = function()
                vim.defer_fn(function()
                    pcall(require('diffs.runtime').invalidate_attached)
                    vim.cmd('redraw!')
                end, 200)
            end,
        })
    end,
}
