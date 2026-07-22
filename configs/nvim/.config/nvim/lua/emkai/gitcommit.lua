-- Auto-generate commit messages and lightly review commits via `claude`.
-- We run the git commands ourselves and feed their output straight to claude,
-- so it never needs tool permissions (reliable + fast in -p mode). MCP servers
-- are disabled so nothing heavy loads at startup.

local MODEL = "sonnet"       -- good balance of speed and message quality
local MAX_DIFF_BYTES = 60000 -- cap the payload so huge commits stay quick
-- A real review call measured ~90s (claude -p startup + sonnet inference over a
-- ~30KB prompt), so 120s left almost no headroom: a busier API or a bigger diff
-- would cross it and get SIGTERM'd (seen as exit 143). Give ~2x the observed time.
local TIMEOUT_MS = 240000    -- per-attempt cap
local MAX_ATTEMPTS = 3       -- retry transient failures (overload/rate-limit/network)
local RETRY_BASE_MS = 2000   -- backoff grows: 2s, 4s, ...
local LOG_FILE = vim.fn.stdpath("cache") .. "/gitcommit-claude.log"

local function claude_available()
    return vim.fn.executable("claude") == 1
end

-- Append one diagnostic line to the log so failures are always explainable
-- after the fact (the notification is transient; this is not).
local function log_line(msg)
    local f = io.open(LOG_FILE, "a")
    if not f then return end
    f:write(("[%s] %s\n"):format(os.date("%Y-%m-%d %H:%M:%S"), msg))
    f:close()
end

-- A short, human-readable reason for a failed claude run. `elapsed_s` (optional)
-- lets timeouts report how long they ran before being killed.
local function fail_detail(res, elapsed_s)
    -- vim.system's timeout kills with SIGTERM; depending on platform that shows
    -- up as signal 15/9 or exit 143/137 (128 + signal). 124 = coreutils timeout.
    if res.code == 124 or res.code == 143 or res.code == 137
        or res.signal == 15 or res.signal == 9 then
        return elapsed_s and ("timed out after %ds"):format(elapsed_s) or "timed out"
    end
    if res.parse_failed then
        return "reply was not the requested JSON"
    end
    local detail = vim.trim(res.stderr or "")
    if detail == "" then detail = vim.trim(res.stdout or "") end
    if detail == "" then detail = "no output" end
    return ("exit %s: %s"):format(res.code, vim.split(detail, "\n")[1])
end

-- Run claude in print mode with MCP disabled, feeding `prompt` on stdin.
-- Retries transient failures (non-zero exit, empty output, or — when opts.parse
-- is given — output that doesn't parse) with exponential backoff; on_result
-- fires once (on success or after the last try). opts.parse(stdout) must return
-- the extracted value or nil; the value lands in res.parsed. opts.on_retry
-- (res, failed_attempt, next_attempt) fires before each retry so callers can
-- surface progress. opts.label tags the operation in the log. Every attempt's
-- outcome (timing, exit/signal, stderr) is written to LOG_FILE and res.elapsed_s
-- is set so callers can report it.
local function ask_claude(prompt, cwd, on_result, opts, _attempt)
    opts = opts or {}
    local attempt = _attempt or 1
    local label = opts.label or "claude"
    local cmd = {
        "claude", "-p",
        "--model", MODEL,
        "--mcp-config", '{"mcpServers":{}}',
        "--strict-mcp-config",
    }
    local uv = vim.uv or vim.loop
    local start = uv.hrtime()
    vim.system(cmd, { stdin = prompt, text = true, cwd = cwd, timeout = TIMEOUT_MS },
        function(res)
            res.elapsed_s = math.floor((uv.hrtime() - start) / 1e9 + 0.5)
            vim.schedule(function()
                local ok = res.code == 0 and res.stdout and res.stdout ~= ""
                if ok and opts.parse then
                    res.parsed = opts.parse(res.stdout)
                    if res.parsed == nil then
                        ok = false
                        res.parse_failed = true
                    end
                end
                local stderr = vim.trim(res.stderr or "")
                local extra = stderr ~= "" and ("\n  stderr: " .. stderr:sub(1, 800)) or ""
                if res.parse_failed then
                    extra = extra .. "\n  unparseable stdout: "
                        .. vim.trim(res.stdout):sub(1, 800)
                end
                log_line(("%s attempt %d/%d: %s in %ds (exit=%s signal=%s)%s"):format(
                    label, attempt, MAX_ATTEMPTS,
                    ok and "OK" or "FAIL", res.elapsed_s, res.code, res.signal or 0,
                    extra))
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

-- Decode the single JSON object the prompts demand. The model occasionally
-- wraps it in prose or code fences anyway — the point of asking for JSON is
-- that such chatter lands OUTSIDE the braces, so we can cut it away instead
-- of it leaking into the commit message. Try the whole (trimmed) output
-- first, then the first balanced {...}, then greedily first-{ to last-}.
local function decode_json_object(out)
    out = vim.trim(out)
    for _, cand in ipairs({ out, out:match("%b{}"), out:match("(%{.*%})") }) do
        if cand then
            local ok, obj = pcall(vim.json.decode, cand)
            if ok and type(obj) == "table" then return obj end
        end
    end
    return nil
end

-- opts.parse for commit-message calls: {message = "..."} or nil.
local function parse_commit(out)
    local obj = decode_json_object(out)
    if not obj or type(obj.message) ~= "string" or vim.trim(obj.message) == "" then
        return nil
    end
    return { message = vim.trim(obj.message) }
end

-- opts.parse for review calls: {ok = bool, issue = "..."} or nil.
-- A "not ok" verdict without an issue text is malformed → nil (retries).
local function parse_review(out)
    local obj = decode_json_object(out)
    if not obj or type(obj.ok) ~= "boolean" then return nil end
    local issue = type(obj.issue) == "string" and vim.trim(obj.issue) or ""
    if not obj.ok and issue == "" then return nil end
    return { ok = obj.ok, issue = issue }
end

local COMMIT_PROMPT = [[Write a git commit message for the staged diff below.
Base your answer ONLY on this diff; do not run any commands.
Respond with ONLY this JSON object — no prose, no code fences, nothing else:
{"message": "<the commit message>"}
The message: a concise imperative subject line (~72 chars), optionally
followed by a blank line and a short body explaining the why. Use \n for
newlines inside the JSON string.

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
Respond with ONLY one of these JSON objects — no prose, no code fences:
{"ok": true}                                 if no real issues
{"ok": false, "issue": "<under 120 chars>"}  otherwise

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
        if not res.parsed then
            finish("claude review failed (" .. fail_detail(res, res.elapsed_s)
                .. ") — :ClaudeCommitLog for details", "WARN", 10000)
            return
        end
        if not res.parsed.ok then
            local issue = vim.split(res.parsed.issue, "\n")[1]
            finish("Commit issue: " .. issue, "WARN", 10000)
            vim.fn.system({ "notify-send", "-u", "critical", "Commit Issue", issue })
        else
            finish("Commit review: OK — no issues found", "INFO", 4000)
        end
    end, {
        label = "review",
        parse = parse_review,
        -- Show each retry in place, including why the previous attempt failed.
        on_retry = function(res, failed, next_attempt)
            MiniNotify.update(id, {
                msg = ("Review attempt %d failed (%s) — retrying %d/%d…")
                    :format(failed, fail_detail(res, res.elapsed_s), next_attempt, MAX_ATTEMPTS),
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

-- Open the per-attempt diagnostic log (timing, exit/signal, stderr).
function M.open_log()
    if vim.fn.filereadable(LOG_FILE) == 0 then
        return vim.notify("No claude commit log yet: " .. LOG_FILE, vim.log.levels.INFO)
    end
    vim.cmd("tabedit " .. vim.fn.fnameescape(LOG_FILE))
    vim.cmd("normal! G")
end

vim.api.nvim_create_user_command("ClaudeCommitLog", M.open_log,
    { desc = "Open the claude commit/review diagnostic log" })

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
                if not res.parsed then
                    finish("commit message failed (" .. fail_detail(res, res.elapsed_s)
                        .. ") — :ClaudeCommitLog for details", "WARN", 10000)
                    return
                end
                if not is_empty_message(buf) then
                    pcall(MiniNotify.remove, id) -- user typed their own; step aside
                    return
                end
                local lines = vim.split(res.parsed.message, "\n", { plain = true })
                vim.api.nvim_buf_set_lines(buf, 0, 0, false, lines)
                finish("Commit message generated", "INFO", 3000)
            end, {
                label = "commit-msg",
                parse = parse_commit,
                -- Show each retry in place, including why the previous attempt failed.
                on_retry = function(res, failed, next_attempt)
                    MiniNotify.update(id, {
                        msg = ("Commit message attempt %d failed (%s) — retrying %d/%d…")
                            :format(failed, fail_detail(res, res.elapsed_s), next_attempt, MAX_ATTEMPTS),
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
