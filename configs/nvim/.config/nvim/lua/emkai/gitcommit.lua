-- Auto-generate commit messages and lightly review commits via `claude`.
-- We run the git commands ourselves and feed their output straight to claude,
-- so it never needs tool permissions (reliable + fast in -p mode). MCP servers
-- are disabled so nothing heavy loads at startup.

local MODEL = "sonnet"       -- good balance of speed and message quality
local MAX_DIFF_BYTES = 60000 -- cap the payload so huge commits stay quick
local TIMEOUT_MS = 120000    -- per-attempt cap; cold starts + API latency add up
local MAX_ATTEMPTS = 3       -- retry transient failures (overload/rate-limit/network)
local RETRY_BASE_MS = 2000   -- backoff grows: 2s, 4s, ...

local function claude_available()
    return vim.fn.executable("claude") == 1
end

-- A short, human-readable reason for a failed claude run.
local function fail_detail(res)
    if res.code == 124 or res.signal == 15 then return "timed out" end
    local detail = vim.trim(res.stderr or "")
    if detail == "" then detail = "no output" end
    return ("exit %s: %s"):format(res.code, vim.split(detail, "\n")[1])
end

-- Run claude in print mode with MCP disabled, feeding `prompt` on stdin.
-- Retries transient failures (non-zero exit or empty output) with exponential
-- backoff; on_result fires once (on success or after the last try). opts.on_retry
-- (res, failed_attempt, next_attempt) fires before each retry so callers can
-- surface progress.
local function ask_claude(prompt, cwd, on_result, opts, _attempt)
    opts = opts or {}
    local attempt = _attempt or 1
    local cmd = {
        "claude", "-p",
        "--model", MODEL,
        "--mcp-config", '{"mcpServers":{}}',
        "--strict-mcp-config",
    }
    vim.system(cmd, { stdin = prompt, text = true, cwd = cwd, timeout = TIMEOUT_MS },
        function(res)
            vim.schedule(function()
                local ok = res.code == 0 and res.stdout and res.stdout ~= ""
                if ok or attempt >= MAX_ATTEMPTS then
                    on_result(res)
                else
                    if opts.on_retry then opts.on_retry(res, attempt, attempt + 1) end
                    vim.defer_fn(function()
                        ask_claude(prompt, cwd, on_result, opts, attempt + 1)
                    end, RETRY_BASE_MS * attempt)
                end
            end)
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

    -- Drive ONE notification through the whole lifecycle (running → retrying →
    -- done/failed) so it's always clear what state the review is in. `finish`
    -- writes the terminal state, then fades the popup after `linger` ms.
    local MiniNotify = require("mini.notify")
    local id = MiniNotify.add("Reviewing latest commit via claude…", "INFO")
    local function finish(msg, level, linger)
        MiniNotify.update(id, { msg = msg, level = level })
        vim.defer_fn(function() pcall(MiniNotify.remove, id) end, linger)
    end

    ask_claude(REVIEW_PROMPT .. truncate(show), cwd, function(res)
        if res.code ~= 0 or not res.stdout or res.stdout == "" then
            finish("claude review failed (" .. fail_detail(res) .. ")", "WARN", 8000)
            return
        end
        local issue = vim.trim(res.stdout):match("ISSUE:%s*(.+)")
        if issue then
            issue = vim.split(issue, "\n")[1]
            finish("Commit issue: " .. issue, "WARN", 10000)
            vim.fn.system({ "notify-send", "-u", "critical", "Commit Issue", issue })
        else
            finish("Commit review: OK — no issues found", "INFO", 4000)
        end
    end, {
        -- Show each retry in place, including why the previous attempt failed.
        on_retry = function(res, failed, next_attempt)
            MiniNotify.update(id, {
                msg = ("Review attempt %d failed (%s) — retrying %d/%d…")
                    :format(failed, fail_detail(res), next_attempt, MAX_ATTEMPTS),
                level = "WARN",
            })
        end,
    })
end

-- Public: manually review HEAD (the latest commit), resolving the repo root
-- from the current buffer. Bound to a keymap; the autocmd path stays automatic.
local M = {}

function M.review_latest()
    if not claude_available() then
        return vim.notify("claude CLI not found", vim.log.levels.ERROR)
    end
    review_commit(repo_root(0))
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
            -- Persistent notification (like the review): stays up while claude
            -- works, then updates in place to the result / retries.
            local MiniNotify = require("mini.notify")
            local id = MiniNotify.add("Generating commit message via claude…", "INFO")
            local function finish(msg, level, linger)
                MiniNotify.update(id, { msg = msg, level = level })
                vim.defer_fn(function() pcall(MiniNotify.remove, id) end, linger)
            end
            ask_claude(COMMIT_PROMPT .. truncate(diff), cwd, function(res)
                if not vim.api.nvim_buf_is_valid(buf) then
                    pcall(MiniNotify.remove, id)
                    return
                end
                if res.code ~= 0 or not res.stdout or res.stdout == "" then
                    finish("commit message failed (" .. fail_detail(res) .. ")", "WARN", 8000)
                    return
                end
                if not is_empty_message(buf) then
                    pcall(MiniNotify.remove, id) -- user typed their own; step aside
                    return
                end
                local lines = vim.split(clean_output(res.stdout), "\n", { plain = true })
                vim.api.nvim_buf_set_lines(buf, 0, 0, false, lines)
                finish("Commit message generated", "INFO", 3000)
            end, {
                -- Show each retry in place, including why the previous attempt failed.
                on_retry = function(res, failed, next_attempt)
                    MiniNotify.update(id, {
                        msg = ("Commit message attempt %d failed (%s) — retrying %d/%d…")
                            :format(failed, fail_detail(res), next_attempt, MAX_ATTEMPTS),
                        level = "WARN",
                    })
                end,
            })
        end

        if pre_sha ~= "" then
            -- NOTE: `once` fires once PER event, and wiping the commit buffer
            -- triggers both BufUnload and BufWipeout — so guard against the
            -- double dispatch to avoid reviewing twice. Both events are kept
            -- for coverage across commit flows (some unload, some wipe).
            local triggered = false
            vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
                buffer = buf,
                once = true,
                callback = function()
                    if triggered then return end
                    triggered = true
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

return M
