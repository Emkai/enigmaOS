local M = {}

local function state_file()
  local dir = vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state")
  return dir .. "/nvim/llama_enabled"
end

function M.is_enabled()
  return vim.uv.fs_stat(state_file()) ~= nil
end

function M.apply(enabled)
  pcall(vim.cmd, enabled and "LlamaEnable" or "LlamaDisable")
end

function M.status()
  vim.notify("llama.vim: " .. (M.is_enabled() and "enabled" or "disabled"))
end

local function set_sentinel(enabled)
  local path = state_file()
  if enabled then
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local f = io.open(path, "w")
    if f then f:close() end
  else
    os.remove(path)
  end
end

local function other_sockets()
  local runtime = vim.env.XDG_RUNTIME_DIR or ("/run/user/" .. vim.fn.getuid())
  local own = vim.v.servername
  local socks = {}
  for _, sock in ipairs(vim.fn.glob(runtime .. "/nvim.*.0", true, true)) do
    if sock ~= own then table.insert(socks, sock) end
  end
  return socks
end

function M.toggle()
  local enabled = not M.is_enabled()
  set_sentinel(enabled)
  M.apply(enabled)

  local cmd = enabled and "LlamaEnable" or "LlamaDisable"
  local socks = other_sockets()
  for _, sock in ipairs(socks) do
    vim.system({ "nvim", "--server", sock, "--remote-send",
      ("<C-\\><C-N>:%s<CR>"):format(cmd) }, { detach = true })
  end

  vim.notify(
    ("llama.vim: %s (this + %d other instance%s)"):format(
      enabled and "enabled" or "disabled",
      #socks,
      #socks == 1 and "" or "s"
    )
  )
end

return M
