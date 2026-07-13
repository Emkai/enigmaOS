vim.g.mapleader = " "

local wk = require("which-key")

-- Vim keybinds
wk.add({
  { "<leader>p", group = "Search and Files" }, -- group
})
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex, { desc = "vim Ex, file explorer" })
vim.keymap.set("n", "<A-n>", "<cmd>cnext<CR>", { desc = "next quickfix item" })
vim.keymap.set("n", "<A-p>", "<cmd>cprev<CR>", { desc = "previous quickfix item" })

vim.keymap.set("n", "<A-k>", "<cmd>bnext<CR>", { desc = "next buffer" })
vim.keymap.set("n", "<A-j>", "<cmd>bprev<CR>", { desc = "previous buffer" })
vim.keymap.set("n", "<A-w>", "<cmd>bdelete<CR>", { desc = "previous buffer" })

-- workspace diagnostics
vim.api.nvim_set_keymap("n", "<leader>x", "", {
	desc = "workspace diagnostics",
	noremap = true,
	callback = function()
		for _, client in ipairs(vim.lsp.get_clients()) do
			require("workspace-diagnostics").populate_workspace_diagnostics(client, 0)
		end
		vim.diagnostic.setqflist()
	end,
})

-- Oil keybinds
vim.keymap.set("n", "<leader>po", "<CMD>Oil --float<CR>", { desc = "Open oil parent directory" })

-- Rest client keybinds
wk.add({
  { "<leader>r", group = "Run" }, -- group
})
vim.keymap.set("n", "<leader>rr", "<CMD>Rest run<CR>", { desc = "Rest client" })

-- Telescope keybinds
local builtin = require("telescope.builtin")
local default_opts = { noremap = true, silent = true }
vim.keymap.set("n", "<leader>pf", builtin.find_files, { desc = "Telescope find files" })
vim.keymap.set("n", "<leader>pg", builtin.live_grep, { desc = "Telescope live grep" })
vim.keymap.set("v", "<leader>pg", "y<ESC>:Telescope live_grep default_text=<c-r>0<CR>", default_opts)
vim.keymap.set("n", "<leader>ph", builtin.help_tags, { desc = "Telescope help tags" })

-- Lsp keybinds
vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if not client then
			return
		end
		vim.keymap.set("n", "<leader>f", function()
			vim.lsp.buf.format()
		end, { desc = "Format current buffer" })
		vim.keymap.set(
			"n",
			"gD",
			vim.lsp.buf.declaration,
			{ noremap = true, silent = true, desc = "Go to declaration" }
		)
		vim.keymap.set(
			"n",
			"gd",
			"<cmd>Telescope lsp_definitions<CR>",
			{ noremap = true, silent = true, desc = "Go to definition" }
		)
		vim.keymap.set(
			"n",
			"gi",
			"<cmd>Telescope lsp_implementations<CR>",
			{ noremap = true, silent = true, desc = "Go to definition" }
		)
		vim.keymap.set(
			"n",
			"gr",
			"<cmd>Telescope lsp_references<CR>",
			{ noremap = true, silent = true, desc = "Go to definition" }
		)
		vim.keymap.set("n", "gn", vim.lsp.buf.rename, { noremap = true, silent = true, desc = "Rename" })
		vim.keymap.set("n", "gk", vim.lsp.buf.hover, { noremap = true, silent = true, desc = "Rename" })
		vim.keymap.set(
			"n",
			"gu",
			"<cmd>Telescope diagnostics<CR>",
			{ noremap = true, silent = true, desc = "Diangostics" }
		)
		--vim.keymap.set("n", "grr", vim.lsp.buf.find, { noremap = true, silent = true, desc = 'Go to declaration' })
	end,
})

-- csv keybinds
vim.api.nvim_create_autocmd("FileType", {
	pattern = "csv",
        desc = "csv",
	callback = function()
		vim.keymap.set("n", "<leader>f", "<cmd>RainbowAlign<CR>", { desc = "Open csv" })
	end,
})

-- Git
wk.add({
  { "<leader>g", group = "Git" }, -- group
})

vim.keymap.set("n", "<leader>gg", function()
	vim.cmd("tab Git")
end, { noremap = true, silent = true, desc = "Open Git" })
vim.keymap.set("n", "<leader>gd", function()
	vim.cmd("tab Git diff")
end, { noremap = true, silent = true, desc = "Open Git diff" })
vim.keymap.set("n", "<leader>gi", function()
	require("mini.diff").toggle_overlay(0)
end, { desc = "Toggle git diff overlay" })
vim.keymap.set("n", "<leader>gp", function()
	require("emkai.gitpr").create_pr()
end, { noremap = true, silent = true, desc = "Create PR (monday ticket) → origin/main" })

-- Debugger
wk.add({
  { "<leader>b", group = "Debugger" }, -- group
})

local dap = require("dap")
vim.keymap.set("n", "<leader>bb", function()
	dap.toggle_breakpoint()
end, { desc = "Debugger breakpoint" })
vim.keymap.set("n", "<leader>bs", function()
	dap.continue()
end, { desc = "Debugger start" })
vim.keymap.set("n", "<F5>", function()
	dap.continue()
end, { desc = "Debugger continue/start" })
vim.keymap.set("n", "<F6>", function()
	dap.step_into()
end, { desc = "Debugger step into" })
vim.keymap.set("n", "<F7>", function()
	dap.step_over()
end, { desc = "Debugger step over" })
vim.keymap.set("n", "<F8>", function()
	dap.step_out()
end, { desc = "Debugger step out" })

-- Echandia (bms/escu/sil) scripts — only the commands that apply to the detected
-- repo are bound (see echandia.keymaps). Nothing is bound outside those repos.
local echandia = require("emkai.echandia")
local echandia_repo = echandia.detect_repo()
if echandia_repo then
  wk.add({
    { "<leader>e", group = "Echandia" },
  })
  for _, k in ipairs(echandia.keymaps) do
    if vim.tbl_contains(k.repos, echandia_repo) then
      vim.keymap.set("n", "<leader>" .. k.lhs, k.fn, { desc = k.desc })
    end
  end
end

-- llama systemd service
wk.add({
  { "<leader>l", group = "llama" },
  { "<leader>ll", group = "llama" },
})
vim.keymap.set("n", "<leader>llm", function()
	local active = vim.fn.system("systemctl is-active llama.service"):gsub("%s+", "")
	local action = active == "active" and "stop" or "start"
	vim.cmd("split | terminal sudo systemctl " .. action .. " llama.service")
	vim.cmd("startinsert")
end, { desc = "Toggle llama systemd service" })
vim.keymap.set("n", "<leader>llt", function()
	require("emkai.llama_toggle").toggle()
end, { desc = "Toggle llama.vim plugin (all nvim instances)" })
vim.keymap.set("n", "<leader>lls", function()
	require("emkai.llama_toggle").status()
end, { desc = "Show llama.vim plugin status" })
