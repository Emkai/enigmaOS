-- Auto-generate commit messages and lightly review commits via `claude`.
-- We run the git commands ourselves and feed their output straight to claude,
-- so it never needs tool permissions (reliable + fast in -p mode). MCP servers
-- are disabled so nothing heavy loads at startup.

local MODEL = "sonnet"       -- good balance of speed and message quality
local MAX_DIFF_BYTES = 60000 -- cap the payload so huge commits stay quick

local function claude_available()
    return vim.fn.executable("claude") == 1
end

-- Run claude in print mode with MCP disabled, feeding `prompt` on stdin.
local function ask_claude(prompt, cwd, on_result)
    local cmd = {
        "claude", "-p",
        "--model", MODEL,
        "--mcp-config", '{"mcpServers":{}}',
        "--strict-mcp-config",
    }
    vim.system(cmd, { stdin = prompt, text = true, cwd = cwd, timeout = 60000 },
        function(res)
            vim.schedule(function() on_result(res) end)
        end)
end

-- Synchronous git call; returns stdout string, or nil on failure.
local function git_output(cwd, args)
    local cmd = { "git", "-C", cwd }
    vim.list_extend(cmd, args)
    local res = vim.system(cmd, { text = true }):wait()
    if res.code ~= 0 then return nil end
    return res.stdout or ""
end

-- Resolve the repo root from the commit buffer, not nvim's cwd.
local function repo_root(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    local dir = (name ~= "" and vim.fs.dirname(name)) or vim.fn.getcwd()
    local top = git_output(dir, { "rev-parse", "--show-toplevel" })
    if top and vim.trim(top) ~= "" then return vim.trim(top) end
    return vim.fn.getcwd()
end

local function is_empty_message(buf)
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if l:match("^#") then break end
        if l:match("%S") then return false end
    end
    return true
end

local function truncate(text)
    if #text <= MAX_DIFF_BYTES then return text end
    return text:sub(1, MAX_DIFF_BYTES) .. "\n\n[diff truncated]\n"
end

local function clean_output(out)
    out = out:gsub("\n+$", "")
    out = out:gsub("^```[%w]*\n", ""):gsub("\n```$", "")
    return vim.trim(out)
end

local COMMIT_PROMPT = [[Write a git commit message for the staged diff below.
Base your answer ONLY on this diff; do not run any commands.
Output ONLY the raw commit message: a concise imperative subject line
(~72 chars), optionally a blank line and a short body explaining the why.
No backticks, no preamble, no quotes.

STAGED DIFF:
]]

local REVIEW_PROMPT = [[Review the git commit shown below (metadata + diff).
Base your answer ONLY on this; do not run any commands.
Flag ONLY serious issues:
- Bugs, logic errors, broken or obviously incomplete code
- Committed secrets: API keys, tokens, passwords, .env files
- Unsafe patterns: hardcoded credentials, injection-prone code
- Clear mistakes: leftover debug prints, large commented-out blocks, wrong/binary files
IGNORE formatting, style, naming, missing comments, refactoring opinions.
Be CONSERVATIVE — false positives are worse than silence.
Reply with ONE line only:
- `OK` if no real issues
- `ISSUE: <under 120 chars>` otherwise

COMMIT:
]]

local function review_commit(cwd)
    if not claude_available() then return end
    local show = git_output(cwd, { "show", "HEAD", "--stat", "--patch" })
    if not show or show == "" then return end
    vim.notify("Reviewing commit via claude...")
    ask_claude(REVIEW_PROMPT .. truncate(show), cwd, function(res)
        if res.code ~= 0 or not res.stdout or res.stdout == "" then
            vim.notify("claude review failed: " .. (res.stderr or "no output"),
                vim.log.levels.WARN)
            return
        end
        local issue = vim.trim(res.stdout):match("ISSUE:%s*(.+)")
        if issue then
            issue = vim.split(issue, "\n")[1]
            vim.notify("Commit Issue: " .. issue, vim.log.levels.WARN)
            vim.fn.system({ "notify-send", "-u", "critical", "Commit Issue", issue })
        else
            vim.notify("Commit review: OK")
        end
    end)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = "gitcommit",
    callback = function(ev)
        local buf = ev.buf
        if not claude_available() then return end

        local cwd = repo_root(buf)
        local pre_sha = vim.trim(git_output(cwd, { "rev-parse", "HEAD" }) or "")

        local diff = git_output(cwd, { "diff", "--cached" })
        if diff and diff ~= "" and not vim.b[buf].claude_commit_generated
            and is_empty_message(buf) then
            vim.b[buf].claude_commit_generated = true
            vim.notify("Generating commit message via claude...")
            ask_claude(COMMIT_PROMPT .. truncate(diff), cwd, function(res)
                if not vim.api.nvim_buf_is_valid(buf) then return end
                if res.code ~= 0 or not res.stdout or res.stdout == "" then
                    vim.notify("claude failed: " .. (res.stderr or "no output"),
                        vim.log.levels.WARN)
                    return
                end
                if not is_empty_message(buf) then return end
                local lines = vim.split(clean_output(res.stdout), "\n", { plain = true })
                vim.api.nvim_buf_set_lines(buf, 0, 0, false, lines)
            end)
        end

        if pre_sha ~= "" then
            vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
                buffer = buf,
                once = true,
                callback = function()
                    vim.defer_fn(function()
                        local post = vim.trim(git_output(cwd, { "rev-parse", "HEAD" }) or "")
                        if post ~= "" and post ~= pre_sha then
                            review_commit(cwd)
                        end
                    end, 1000)
                end,
            })
        end
    end,
})
