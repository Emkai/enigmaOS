-- Create a GitHub PR toward origin/main from the current branch.
--
-- Company policy: every PR must map to a monday.com ticket, so the PR title
-- MUST carry the ticket code — tasks use `TSWENG-<n>`, bugs use `BSWENG-<n>`
-- (e.g. "TSWENG-1061 System_HMI update from 3.0 db name issue"). We enforce
-- that the code prefixes the title before the PR is ever created.
--
-- The ticket is resolved one of two ways (we ask at run time):
--   * picked live from monday.com — via the connected monday MCP, reached
--     through the `claude` CLI with only the monday tools allowed; or
--   * typed in by hand.
-- Title + body are drafted by `claude` (MCP disabled, like gitcommit.lua) from
-- the branch's commits and diff, then the ticket code is guaranteed on the
-- title. Nothing is created without a final confirmation.

local M = {}

local MODEL = "sonnet"        -- fast, good enough for a PR blurb
local MAX_DIFF_BYTES = 60000  -- cap the payload so big branches stay quick
local BASE = "main"           -- PRs always target origin/main
local TASK_PREFIX = "TSWENG"  -- task ticket code prefix
local BUG_PREFIX = "BSWENG"   -- bug ticket code prefix
-- A ticket code (TSWENG-123 / BSWENG-123); both share the "SWENG" stem.
local KEY_CLASS = "[TB]SWENG%-%d+"

local function claude_available() return vim.fn.executable("claude") == 1 end
local function gh_available() return vim.fn.executable("gh") == 1 end

-- Synchronous git call; returns stdout string (may be ""), or nil on failure.
local function git(cwd, args)
    local cmd = { "git", "-C", cwd }
    vim.list_extend(cmd, args)
    local res = vim.system(cmd, { text = true }):wait()
    if res.code ~= 0 then return nil end
    return res.stdout or ""
end

-- Resolve the repo root from the current buffer, not nvim's cwd.
local function repo_root()
    local name = vim.api.nvim_buf_get_name(0)
    local dir = (name ~= "" and vim.fs.dirname(name)) or vim.fn.getcwd()
    local top = git(dir, { "rev-parse", "--show-toplevel" })
    if top and vim.trim(top) ~= "" then return vim.trim(top) end
    return vim.fn.getcwd()
end

local function current_branch(cwd)
    local out = git(cwd, { "branch", "--show-current" })
    return out and vim.trim(out) or ""
end

-- Prefer origin/main as the diff base; fall back to local main if unfetched.
local function base_ref(cwd)
    if git(cwd, { "rev-parse", "--verify", "--quiet", "origin/" .. BASE }) then
        return "origin/" .. BASE
    end
    return BASE
end

local function truncate(text)
    if #text <= MAX_DIFF_BYTES then return text end
    return text:sub(1, MAX_DIFF_BYTES) .. "\n\n[diff truncated]\n"
end

-- Decode the single JSON object the prompts demand (same tolerance as
-- gitcommit.lua: chatter/code fences around the braces get cut away).
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

-- Turn user/monday input into a canonical ticket code, or nil if unusable.
--   "TSWENG-1061" / "bsweng-176"  -> "TSWENG-1061" / "BSWENG-176"
--   "1061" (+ prefix)            -> "<prefix>-1061"
local function normalize_key(input, prefix)
    if not input then return nil end
    input = vim.trim(tostring(input)):upper()
    if input == "" then return nil end
    local full = input:match(KEY_CLASS)
    if full then return full end
    local num = input:match("^%d+$")
    if num and prefix then return prefix .. "-" .. num end
    return nil
end

-- Guarantee the title starts with the ticket code (strip any stray code first).
local function enforce_key(title, key)
    if title:match("^" .. vim.pesc(key)) then return title end
    title = title:gsub("^%[?" .. KEY_CLASS .. "%]?%s*", "")
    return key .. " " .. vim.trim(title)
end

-- Run claude in print mode, feeding `prompt` on stdin.
--   mode "off"    : no MCP servers (fast, offline drafting)
--   mode "monday" : keep the user's connected servers, allow only monday tools
local function ask_claude(prompt, cwd, mode, on_result)
    local cmd = { "claude", "-p", "--model", MODEL }
    if mode == "monday" then
        vim.list_extend(cmd, { "--allowedTools", "mcp__claude_ai_monday_com" })
    else
        vim.list_extend(cmd, { "--mcp-config", '{"mcpServers":{}}', "--strict-mcp-config" })
    end
    vim.system(cmd, { stdin = prompt, text = true, cwd = cwd, timeout = 120000 },
        function(res)
            vim.schedule(function() on_result(res) end)
        end)
end

-- Ask claude (with monday tools) for a JSON list of the user's open tickets.
local MONDAY_PROMPT = [[Use the monday.com tools to find my open (not-done) tasks and bugs.
Respond with ONLY this JSON object — no prose, no code fences, nothing else:
{"tickets": [{"key":"TSWENG-1061","name":"short item name","type":"task"}, ...]}
Rules:
- up to 25 tickets; tasks use the key prefix TSWENG-, bugs use BSWENG-.
- the ticket code is usually in the item name or an ID/text column; if an item
  has no such code, set "key" to its numeric monday item id.
- prefer items assigned to me that are still in progress.
If you cannot reach monday, return {"tickets": []}.]]

-- Prompt for type + number when the user opts to type the ticket in.
local function enter_manually(cb)
    vim.ui.select({ "task  (" .. TASK_PREFIX .. "-)", "bug   (" .. BUG_PREFIX .. "-)" },
        { prompt = "Ticket type:" }, function(choice)
            if not choice then return end
            local prefix = choice:match("^task") and TASK_PREFIX or BUG_PREFIX
            vim.ui.input({ prompt = prefix .. "- number (or full code): " }, function(input)
                local key = normalize_key(input, prefix)
                if not key then
                    return vim.notify("Invalid ticket — expected e.g. " .. prefix .. "-1061",
                        vim.log.levels.ERROR)
                end
                cb(key)
            end)
        end)
end

-- Fetch tickets from monday and let the user pick; fall back to manual entry.
local function pick_from_monday(cwd, cb)
    vim.notify("Fetching monday tickets via claude…")
    ask_claude(MONDAY_PROMPT, cwd, "monday", function(res)
        local items
        if res.code == 0 and res.stdout and res.stdout ~= "" then
            local obj = decode_json_object(res.stdout)
            if obj and type(obj.tickets) == "table" then items = obj.tickets end
        end
        if not items or #items == 0 then
            vim.notify("No monday tickets found — enter manually", vim.log.levels.WARN)
            return enter_manually(cb)
        end
        local labels = {}
        for _, it in ipairs(items) do
            table.insert(labels, string.format("[%s] %s  %s",
                it.type or "?", it.key or "?", it.name or ""))
        end
        table.insert(labels, "— enter manually —")
        vim.ui.select(labels, { prompt = "Select monday ticket:" }, function(_, idx)
            if not idx then return end
            if idx > #items then return enter_manually(cb) end
            local it = items[idx]
            local key = normalize_key(it.key, (it.type == "bug") and BUG_PREFIX or TASK_PREFIX)
            if not key then
                vim.notify("Selected item has no valid code — enter manually", vim.log.levels.WARN)
                return enter_manually(cb)
            end
            cb(key)
        end)
    end)
end

local function build_pr_prompt(key, base, log, diff)
    return table.concat({
        "Draft a GitHub pull request for the branch changes below.",
        "Base your answer ONLY on the commits and diff; do not run any commands.",
        "Respond with ONLY this JSON object — no prose, no code fences, nothing else:",
        '{"title": "<concise imperative PR subject, under 72 chars, WITHOUT the ticket code>",',
        ' "body": "<short markdown body: a one-line summary, then a \'## Changes\' bullet list>"}',
        "Use \\n for newlines inside the body string.",
        "",
        "Ticket: " .. key,
        "",
        "COMMITS (" .. base .. "..HEAD):",
        log,
        "",
        "DIFF:",
        truncate(diff),
    }, "\n")
end

-- Pull {title, body} out of the drafting reply; nil title means unusable.
local function parse_pr_draft(out)
    local obj = decode_json_object(out)
    if not obj or type(obj.title) ~= "string" or vim.trim(obj.title) == "" then
        return nil
    end
    local body = type(obj.body) == "string" and vim.trim(obj.body) or ""
    return vim.trim(obj.title), body
end

-- Push the branch, then open the PR; copy the resulting URL to the clipboard.
local function do_create(cwd, branch, base, key, title, body)
    vim.notify("Pushing " .. branch .. " → origin…")
    vim.system({ "git", "push", "-u", "origin", branch }, { text = true, cwd = cwd },
        function(pres)
            vim.schedule(function()
                if pres.code ~= 0 then
                    return vim.notify("git push failed: " .. (pres.stderr or ""),
                        vim.log.levels.ERROR)
                end
                local base_branch = base:gsub("^origin/", "")
                vim.notify("Creating PR via gh…")
                vim.system({ "gh", "pr", "create",
                    "--base", base_branch, "--head", branch,
                    "--title", title, "--body", body },
                    { text = true, cwd = cwd }, function(cres)
                        vim.schedule(function()
                            if cres.code ~= 0 then
                                return vim.notify("gh pr create failed: " .. (cres.stderr or ""),
                                    vim.log.levels.ERROR)
                            end
                            local url = vim.trim(cres.stdout or "")
                            vim.fn.setreg("+", url)
                            vim.notify("PR created (URL copied): " .. url)
                        end)
                    end)
            end)
        end)
end

local function confirm_and_create(cwd, branch, base, key, title, body)
    if body == "" then body = "_No description._" end
    body = body .. "\n\nRelates to " .. key
    vim.ui.select({ "Create PR", "Cancel" },
        { prompt = "Create PR: " .. title }, function(choice)
            if choice ~= "Create PR" then
                return vim.notify("PR creation cancelled")
            end
            do_create(cwd, branch, base, key, title, body)
        end)
end

-- With a ticket code in hand, draft the title/body and confirm.
local function after_ticket(cwd, branch, key)
    local base = base_ref(cwd)
    local log = vim.trim(git(cwd, { "log", "--format=%s%n%b%n---", base .. "..HEAD" }) or "")
    local diff = git(cwd, { "diff", base .. "...HEAD" }) or ""
    if log == "" and diff == "" then
        return vim.notify("No commits ahead of " .. base .. " — nothing to PR",
            vim.log.levels.ERROR)
    end
    if not claude_available() then
        -- No drafting available: fall back to a code-only title.
        return confirm_and_create(cwd, branch, base, key, key, "")
    end
    vim.notify("Drafting PR title & body via claude…")
    ask_claude(build_pr_prompt(key, base, log, diff), cwd, "off", function(res)
        if res.code ~= 0 or not res.stdout or res.stdout == "" then
            return vim.notify("claude failed: " .. (res.stderr or "no output"),
                vim.log.levels.ERROR)
        end
        local title, body = parse_pr_draft(res.stdout)
        if not title then
            return vim.notify("claude reply was not the requested {title, body} JSON",
                vim.log.levels.ERROR)
        end
        confirm_and_create(cwd, branch, base, key, enforce_key(title, key), body)
    end)
end

function M.create_pr()
    if not gh_available() then
        return vim.notify("gh CLI not found", vim.log.levels.ERROR)
    end
    local cwd = repo_root()
    local branch = current_branch(cwd)
    if branch == "" then
        return vim.notify("Detached HEAD — checkout a branch first", vim.log.levels.ERROR)
    end
    if branch == BASE or branch == "master" then
        return vim.notify("On " .. branch .. " — create a feature branch first",
            vim.log.levels.ERROR)
    end

    vim.ui.select({ "Pick from monday.com", "Enter manually" },
        { prompt = "Monday ticket source for this PR:" }, function(choice)
            if not choice then return end
            local cb = function(key) after_ticket(cwd, branch, key) end
            if choice == "Pick from monday.com" then
                pick_from_monday(cwd, cb)
            else
                enter_manually(cb)
            end
        end)
end

return M
