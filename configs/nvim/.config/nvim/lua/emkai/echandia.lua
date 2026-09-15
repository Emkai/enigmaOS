local M = {}

local SCRIPTS_DIR = vim.fn.expand("~/src/scripts/linux/work/echandia")

local BUILD_MODES = {
    bms = {
        { key = "local",        label = "Local only (no docker)" },
        { key = "local_docker", label = "Local + docker" },
        { key = "docker",       label = "Docker only" },
    },
    escu = {
        { key = "sil_local",  label = "SIL local (scons)" },
        { key = "sil_docker", label = "SIL docker image" },
        { key = "firmware",   label = "Firmware (armgccscons)" },
    },
    sil = {
        { key = "full_stack",    label = "Full stack: bms+escu+sil+tools + pin .env" },
        { key = "sil_and_tools", label = "SIL images + tools" },
        { key = "sil_images",    label = "SIL images only" },
        { key = "tools",         label = "Tools only (ebms/escu/scu generators)" },
        { key = "bundle",        label = "Release bundle (native arch, .env pins)" },
        { key = "bundle_local",  label = "Release bundle (fully local: deploy_sil + bundle)" },
    },
}

local function notify_err(msg)
    vim.notify(msg, vim.log.levels.ERROR)
end

function M.detect_repo()
    local cwd = vim.fn.getcwd()
    if vim.fn.isdirectory(cwd .. "/EBMS") == 1 then
        return "bms"
    elseif vim.fn.isdirectory(cwd .. "/EScu") == 1 then
        return "escu"
    elseif vim.fn.isdirectory(cwd .. "/sil/simulators") == 1 then
        return "sil"
    elseif vim.fn.isdirectory(cwd .. "/simulators") == 1
        and vim.fn.filereadable(cwd .. "/docker-compose.yml") == 1
    then
        return "sil"
    end
    return nil
end

function M.ensure_var(varname, prompt, default, cb)
    local val = vim.g[varname]
    if val and val ~= "" then
        cb(val)
        return
    end
    vim.ui.input({ prompt = prompt, default = default }, function(input)
        if not input or input == "" then
            return
        end
        vim.g[varname] = input
        cb(input)
    end)
end

-- Prompt for (or recall) several settings in order, then hand the collected
-- values to cb keyed by varname. Per step the semantics are ensure_var's: an
-- already-set global skips its prompt, an empty or cancelled input aborts the
-- rest of the chain.
function M.ensure_vars(specs, cb)
    local vals = {}
    local function step(i)
        local spec = specs[i]
        if not spec then
            cb(vals)
            return
        end
        M.ensure_var(spec[1], spec[2], spec[3], function(v)
            vals[spec[1]] = v
            step(i + 1)
        end)
    end
    step(1)
end

-- Every remembered setting, in the order M.configure() walks them. `repos`
-- gates which repos see a step; `var`/`prompt` may be functions of the repo
-- (version and build mode are per-repo). Build mode is a vim.ui.select over
-- BUILD_MODES, everything else a free-text vim.ui.input.
local CONFIGS = {
    { kind = "build_mode", repos = { "bms", "escu", "sil" } },
    { var = "echandia_deploy_host", prompt = "Deploy host: ", default = "", repos = { "bms", "escu" } },
    { var = "echandia_deploy_arch", prompt = "Arch: ", default = "amd64", repos = { "bms", "escu" } },
    {
        var = function(repo) return "echandia_" .. repo .. "_version" end,
        prompt = function(repo) return "Deploy version (" .. repo .. "): " end,
        default = "99.99.99.01",
        repos = { "bms", "escu", "sil" },
    },
    {
        var = "echandia_sil_bundle_arch",
        prompt = "Bundle arch (amd64,arm64,win-amd64 | native | all): ",
        default = "all",
        repos = { "sil" },
    },
    {
        var = "echandia_sil_bundle_local_arch",
        prompt = "Local-bundle arch (amd64 | arm64 | native): ",
        default = "native",
        repos = { "sil" },
    },
    { var = "echandia_bms_scus", prompt = "SCU count: ", default = "1", repos = { "bms" } },
    { var = "echandia_sil_scus", prompt = "SCU count: ", default = "1", repos = { "sil" } },
    { var = "echandia_launch_docker", prompt = "Launch with docker: ", default = "false", repos = { "bms", "escu" } },
    { var = "echandia_launch_metrics", prompt = "Launch metrics stack: ", default = "false", repos = { "bms" } },
    { var = "echandia_launch_gen_config", prompt = "Generate config on launch: ", default = "false", repos = { "bms", "escu" } },
    { var = "echandia_sil_escu_hw", prompt = "EScu hardware type (-w, e.g. 10 = s05 | none): ", default = "none", repos = { "sil" } },
    { var = "echandia_sil_module_type", prompt = "Module type (23ah | 20ah | 26ah | 155ah): ", default = "23ah", repos = { "sil" } },
    { var = "echandia_sil_ch1", prompt = "CMUs on CAN channel 1 (0..28 | none): ", default = "none", repos = { "sil" } },
    { var = "echandia_sil_ch2", prompt = "CMUs on CAN channel 2 (0..28 | none): ", default = "none", repos = { "sil" } },
    { var = "echandia_sil_boxe", prompt = "Box mode subnet 10.10.10.0/24 (--boxe): ", default = "false", repos = { "sil" } },
    { var = "echandia_sil_password", prompt = "SIL password: ", default = "", repos = { "sil" } },
}

-- Walk every config relevant to the current repo, one prompt after another.
-- Enter keeps the shown value (current or default) and moves on; Esc on a
-- text prompt aborts the rest of the walk, Esc on the build-mode select just
-- skips it (cancel is the only way to keep the current mode in a select).
function M.configure()
    local repo = M.detect_repo()
    if not repo then
        notify_err("Not in a bms, escu, or sil repo")
        return
    end
    local steps = vim.tbl_filter(function(cfg)
        return vim.tbl_contains(cfg.repos, repo)
    end, CONFIGS)
    local i = 0
    local function next_step()
        i = i + 1
        local cfg = steps[i]
        if not cfg then
            return
        end
        if cfg.kind == "build_mode" then
            local varname = "echandia_" .. repo .. "_build_mode"
            local current = vim.g[varname]
            vim.ui.select(BUILD_MODES[repo], {
                prompt = "Build mode (" .. repo .. "):",
                format_item = function(item)
                    if item.key == current then
                        return item.label .. "  [current]"
                    end
                    return item.label
                end,
            }, function(choice)
                if choice then
                    vim.g[varname] = choice.key
                end
                next_step()
            end)
            return
        end
        local varname = type(cfg.var) == "function" and cfg.var(repo) or cfg.var
        local prompt = type(cfg.prompt) == "function" and cfg.prompt(repo) or cfg.prompt
        vim.ui.input(
            { prompt = prompt, default = vim.g[varname] or cfg.default },
            function(v)
                if v == nil then
                    return
                end
                if v ~= "" then
                    vim.g[varname] = v
                end
                next_step()
            end
        )
    end
    next_step()
end

function M.ensure_gen_config(cb)
    local cur = vim.g.echandia_launch_gen_config
    if cur and cur ~= "" then
        cb(cur)
        return
    end
    vim.ui.input(
        { prompt = "Generate config on launch: ", default = "false" },
        function(v)
            if not v or v == "" then
                return
            end
            vim.g.echandia_launch_gen_config = v
            cb(v)
        end
    )
end

function M.ensure_build_mode(repo, cb)
    local modes = BUILD_MODES[repo]
    if not modes then
        cb(nil)
        return
    end
    local varname = "echandia_" .. repo .. "_build_mode"
    local cur = vim.g[varname]
    if cur and cur ~= "" then
        cb(cur)
        return
    end
    vim.ui.select(modes, {
        prompt = "Build mode (" .. repo .. "):",
        format_item = function(item) return item.label end,
    }, function(choice)
        if not choice then
            return
        end
        vim.g[varname] = choice.key
        cb(choice.key)
    end)
end

function M.bump_version(varname)
    local v = vim.g[varname]
    if not v then
        return
    end
    local a, b, c, d = v:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then
        vim.notify(
            string.format("echandia: could not parse version %q for bump", v),
            vim.log.levels.WARN
        )
        return
    end
    local new_v = string.format("%s.%s.%s.%0" .. #d .. "d", a, b, c, tonumber(d) + 1)
    vim.g[varname] = new_v
    vim.notify(string.format("%s: %s -> %s", varname, v, new_v))
end

function M.run_in_float(cmd, on_success)
    local buf = vim.api.nvim_create_buf(false, true)
    local ui = vim.api.nvim_list_uis()[1] or { width = vim.o.columns, height = vim.o.lines }
    local width = math.floor(ui.width * 0.8)
    local height = math.floor(ui.height * 0.8)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((ui.height - height) / 2),
        col = math.floor((ui.width - width) / 2),
        style = "minimal",
        border = "rounded",
    })
    vim.fn.termopen(cmd, {
        on_exit = function(_, code)
            if code == 0 and on_success then
                vim.schedule(on_success)
            end
        end,
    })
    local opts = { buffer = buf, silent = true, nowait = true }
    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end
    -- Normal mode only: the launched command may read stdin (sudo password
    -- prompt), so every key must pass through while in terminal mode. Nvim
    -- drops to normal mode when the process exits, where q/Esc close as
    -- before; mid-run it's <C-\><C-n> then q.
    vim.keymap.set("n", "q", close, opts)
    vim.keymap.set("n", "<Esc>", close, opts)
    vim.cmd("startinsert")
end

function M.deploy()
    local repo = M.detect_repo()
    if repo ~= "bms" and repo ~= "escu" then
        notify_err("Deploy: not in a bms or escu repo")
        return
    end
    local cwd = vim.fn.getcwd()
    local version_var = "echandia_" .. repo .. "_version"

    M.ensure_var("echandia_deploy_host", "Deploy host: ", "", function(host)
        local function run_with_version(arch, deploy_type)
            M.ensure_var(version_var, "Version (" .. repo .. "): ", "99.99.99.01", function(version)
                local cmd
                if repo == "bms" then
                    cmd = string.format(
                        "%s/deploy_bms.sh %s -s %s -a %s -v %s -l",
                        SCRIPTS_DIR,
                        vim.fn.shellescape(host),
                        vim.fn.shellescape(cwd .. "/EBMS"),
                        vim.fn.shellescape(arch),
                        vim.fn.shellescape(version)
                    )
                else
                    cmd = string.format(
                        "%s/deploy_escu.sh %s -s %s -v %s -t %s",
                        SCRIPTS_DIR,
                        vim.fn.shellescape(host),
                        vim.fn.shellescape(cwd),
                        vim.fn.shellescape(version),
                        vim.fn.shellescape(deploy_type)
                    )
                    if arch then
                        cmd = cmd .. " -a " .. vim.fn.shellescape(arch)
                    end
                end
                M.run_in_float(cmd, function()
                    M.bump_version(version_var)
                end)
            end)
        end

        if repo == "bms" then
            M.ensure_var("echandia_deploy_arch", "Arch: ", "amd64", function(arch)
                run_with_version(arch, nil)
            end)
        else
            -- Deploy artifact follows the build mode: firmware ships the
            -- production binary, either sil mode ships the SIL docker image
            -- (deploy always builds what it ships, so sil_local still
            -- deploys the image).
            M.ensure_build_mode("escu", function(mode)
                if mode == "firmware" then
                    run_with_version(nil, "fw")
                else
                    M.ensure_var("echandia_deploy_arch", "Arch: ", "amd64", function(arch)
                        run_with_version(arch, "sil")
                    end)
                end
            end)
        end
    end)
end

function M.build()
    local repo = M.detect_repo()
    if not repo then
        notify_err("Not in a bms, escu, or sil repo")
        return
    end
    local cwd = vim.fn.getcwd()

    if repo == "bms" then
        M.ensure_build_mode("bms", function(mode)
            local version_var = "echandia_bms_version"
            M.ensure_var("echandia_deploy_arch", "Arch: ", "amd64", function(arch)
                M.ensure_var(version_var, "Version (bms): ", "99.99.99.01", function(version)
                    local mode_flag
                    if mode == "local_docker" then
                        mode_flag = " -l"
                    elseif mode == "local" then
                        mode_flag = " --no-docker"
                    else
                        mode_flag = ""
                    end
                    local cmd = string.format(
                        "%s/build_bms.sh -s %s -a %s -v %s%s",
                        SCRIPTS_DIR,
                        vim.fn.shellescape(cwd .. "/EBMS"),
                        vim.fn.shellescape(arch),
                        vim.fn.shellescape(version),
                        mode_flag
                    )
                    M.run_in_float(cmd)
                end)
            end)
        end)
    elseif repo == "sil" then
        M.ensure_build_mode("sil", function(mode)
            local sil_dir = M.detect_sil_dir()
            local workspace = M.detect_workspace_root()
            local function run(version)
                -- Release bundle: sil-<version>-<arch>.tar.gz via the sil repo's
                -- own scripts/build-bundles.sh (bundle_sil.sh wrapper); output
                -- lands in <workspace>/sil/build/. The password is prompted each
                -- time and never persisted, matching launch_sil; a remembered
                -- SCU count is forwarded when set. The arch set is remembered in
                -- echandia_sil_bundle_arch — bundle_local always builds native
                -- (locally-built images only exist for the host arch), so it
                -- skips the arch prompt.
                if mode == "bundle" or mode == "bundle_local" then
                    if not workspace then
                        notify_err("Not in a feature workspace (need bms/, escu/, sil/ siblings)")
                        return
                    end
                    local function run_bundle(arch)
                        vim.ui.input({ prompt = "Bundle password: " }, function(pw)
                            if not pw or pw == "" then
                                return
                            end
                            local cmd = string.format(
                                "%s/bundle_sil.sh -s %s -v %s -P %s -a %s",
                                SCRIPTS_DIR,
                                vim.fn.shellescape(workspace),
                                vim.fn.shellescape(version),
                                vim.fn.shellescape(pw),
                                vim.fn.shellescape(arch)
                            )
                            local scus = vim.g.echandia_sil_scus
                            if scus and scus ~= "" then
                                cmd = cmd .. " -n " .. vim.fn.shellescape(tostring(scus))
                            end
                            if mode == "bundle_local" then
                                cmd = cmd .. " -l"
                            end
                            M.run_in_float(cmd)
                        end)
                    end
                    if mode == "bundle_local" then
                        -- Local images hold one platform per tag, so exactly one
                        -- arch; cross arches build under QEMU (deploy_sil -a).
                        M.ensure_var(
                            "echandia_sil_bundle_local_arch",
                            "Bundle arch (amd64 | arm64 | native): ",
                            "native",
                            run_bundle
                        )
                    else
                        M.ensure_var(
                            "echandia_sil_bundle_arch",
                            "Bundle arch (amd64,arm64,win-amd64 | native | all): ",
                            "all",
                            run_bundle
                        )
                    end
                    return
                end
                -- Full stack: build bms+escu+sil+tools images and pin
                -- <workspace>/sil/.env to the locally-built images (deploy_sil.sh).
                if mode == "full_stack" then
                    if not workspace then
                        notify_err("Not in a feature workspace (need bms/, escu/, sil/ siblings)")
                        return
                    end
                    M.run_in_float(string.format(
                        "%s/deploy_sil.sh -s %s -v %s -l",
                        SCRIPTS_DIR,
                        vim.fn.shellescape(workspace),
                        vim.fn.shellescape(version)
                    ))
                    return
                end
                local parts = {}
                if mode == "sil_images" or mode == "sil_and_tools" then
                    if not sil_dir then
                        notify_err("No sil dir (need sil/simulators or simulators/)")
                        return
                    end
                    table.insert(parts, string.format(
                        "%s/build_sil.sh -s %s -v %s",
                        SCRIPTS_DIR,
                        vim.fn.shellescape(sil_dir),
                        vim.fn.shellescape(version)
                    ))
                end
                if mode == "tools" or mode == "sil_and_tools" then
                    if not workspace then
                        notify_err("Not in a feature workspace (need bms/, escu/, sil/ siblings)")
                        return
                    end
                    table.insert(parts, string.format(
                        "%s/build_sil_tools.sh -s %s",
                        SCRIPTS_DIR,
                        vim.fn.shellescape(workspace)
                    ))
                end
                M.run_in_float(table.concat(parts, " && "))
            end
            if mode == "tools" then
                run(nil) -- build_sil_tools takes no version
            else
                M.ensure_var("echandia_sil_version", "Version (sil): ", "99.99.99.01", run)
            end
        end)
    else
        M.ensure_build_mode("escu", function(mode)
            if mode == "sil_docker" then
                M.ensure_var("echandia_deploy_arch", "Arch: ", "amd64", function(arch)
                    M.ensure_var("echandia_escu_version", "Version (escu): ", "99.99.99.01", function(version)
                        local cmd = string.format(
                            "%s/build_escu.sh -s %s -d -v %s -a %s",
                            SCRIPTS_DIR,
                            vim.fn.shellescape(cwd),
                            vim.fn.shellescape(version),
                            vim.fn.shellescape(arch)
                        )
                        M.run_in_float(cmd)
                    end)
                end)
            elseif mode == "sil_local" then
                local cmd = string.format(
                    "%s/build_escu.sh -s %s --sil-local",
                    SCRIPTS_DIR,
                    vim.fn.shellescape(cwd)
                )
                M.run_in_float(cmd)
            else
                local cmd = string.format(
                    "%s/build_escu.sh -s %s",
                    SCRIPTS_DIR,
                    vim.fn.shellescape(cwd)
                )
                M.run_in_float(cmd)
            end
        end)
    end
end

-- Locate the sil dir whether we're at the workspace root (sil/simulators) or
-- inside the sil worktree itself (simulators/). Used by build and launch.
function M.detect_sil_dir()
    local cwd = vim.fn.getcwd()
    if vim.fn.isdirectory(cwd .. "/sil/simulators") == 1 then
        return cwd .. "/sil"
    end
    if vim.fn.isdirectory(cwd .. "/simulators") == 1 then
        return cwd
    end
    return nil
end

-- Find the feature workspace root (a dir containing bms/, escu/, sil/ siblings).
-- Looks at cwd, then cwd/.. — so this works whether you're at the workspace
-- root or inside one of the sibling repos.
function M.detect_workspace_root()
    local cwd = vim.fn.getcwd()
    local function has_all(dir)
        return vim.fn.isdirectory(dir .. "/bms") == 1
            and vim.fn.isdirectory(dir .. "/escu") == 1
            and vim.fn.isdirectory(dir .. "/sil") == 1
    end
    if has_all(cwd) then
        return cwd
    end
    local parent = vim.fn.fnamemodify(cwd, ":h")
    if parent ~= cwd and has_all(parent) then
        return parent
    end
    return nil
end

-- Publish dirs are reused between builds for speed, but stale files survive in
-- them (the publish copy is timestamp-based). Run this when switching arch or
-- when a deployed container crashes loading a native lib.
function M.clean()
    local repo = M.detect_repo()
    if repo ~= "bms" then
        notify_err("Clean: not in a bms repo")
        return
    end
    local cwd = vim.fn.getcwd()
    local cmd = string.format(
        "%s/clean_bms.sh -s %s",
        SCRIPTS_DIR,
        vim.fn.shellescape(cwd .. "/EBMS")
    )
    M.run_in_float(cmd)
end

function M.generate_embedded()
    local repo = M.detect_repo()
    if repo ~= "bms" and repo ~= "escu" then
        notify_err("Generate embedded: not in a bms or escu repo")
        return
    end
    local cwd = vim.fn.getcwd()

    local function abs(path)
        return (vim.fn.fnamemodify(path, ":p"):gsub("/$", ""))
    end

    local function run(bms_src, firmware_dir)
        local cmd = string.format(
            "%s/generate_embedded.sh -s %s -o %s",
            SCRIPTS_DIR,
            vim.fn.shellescape(bms_src),
            vim.fn.shellescape(firmware_dir)
        )
        M.run_in_float(cmd)
    end

    if repo == "bms" then
        M.ensure_var(
            "echandia_escu_dir",
            "Escu dir (containing EScu/): ",
            vim.g.echandia_escu_dir or abs(cwd .. "/../escu"),
            function(escu_dir)
                run(cwd .. "/EBMS", escu_dir)
            end
        )
    else
        M.ensure_var(
            "echandia_bms_src_dir",
            "BMS source dir (containing EBMS.Tools.EmbeddedCodeGenerator): ",
            vim.g.echandia_bms_src_dir or abs(cwd .. "/../bms/EBMS"),
            function(bms_src)
                run(bms_src, cwd)
            end
        )
    end
end

function M.generate_nswag()
    local repo = M.detect_repo()
    if repo ~= "bms" then
        notify_err("Not in a bms repo")
        return
    end
    local cwd = vim.fn.getcwd()
    local cmd = string.format(
        "%s/generate_nswag.sh -s %s",
        SCRIPTS_DIR,
        vim.fn.shellescape(cwd)
    )
    M.run_in_float(cmd)
end

-- Bring up the SIL stack via the sil repo's own setup.sh (regenerates configs
-- and starts the compose stack). Every setting, the password included, is
-- prompted once and remembered (change them later via the `es` config walk).
-- The password lives in a plain vim global for the nvim session only: vim.g is
-- not written to shada, so it never reaches disk, but it is readable from any
-- Lua in this instance and shown in the clear when `es` re-prompts it.
-- Hardware type "none" (the default) or empty omits -w; any other value is
-- passed as `-w <type>` (e.g. 10 = s05). Module type is always passed as
-- `--module-type <v>`
-- (23ah/20ah/26ah/155ah, or an enum name/value); the BMU type is deliberately
-- not set here — setup.sh derives it from the module type (155ah -> Wise LMU
-- V2, Toshiba -> BMU2G). ch1/ch2 are the CMU counts per CAN channel (0..28),
-- forwarded to the EBMS generator as `--ch1 N`/`--ch2 N`; "none" omits them and
-- leaves the generator's own defaults. Box mode ("true") adds `--boxe`, moving
-- the whole stack to 10.10.10.0/24 so it can't collide with a 10.20.x bench
-- network; it's opt-in since the default addressing is the production-shaped one.
function M.launch_sil()
    local sil_dir = M.detect_sil_dir()
    if not sil_dir then
        notify_err("Launch SIL: no sil dir found (need sil/simulators or simulators/)")
        return
    end
    M.ensure_vars({
        { "echandia_sil_scus",        "SCU count: ",                                     "1" },
        { "echandia_sil_escu_hw",     "EScu hardware type (-w, e.g. 10 = s05 | none): ", "none" },
        { "echandia_sil_module_type", "Module type (23ah | 20ah | 26ah | 155ah): ",      "23ah" },
        { "echandia_sil_ch1",         "CMUs on CAN channel 1 (0..28 | none): ",          "none" },
        { "echandia_sil_ch2",         "CMUs on CAN channel 2 (0..28 | none): ",          "none" },
        { "echandia_sil_boxe",        "Box mode subnet 10.10.10.0/24 (--boxe): ",        "false" },
        { "echandia_sil_password",    "SIL password: ",                                  "" },
    }, function(vals)
        local cmd = string.format(
            "cd %s && ./setup.sh -s %s --password %s --module-type %s",
            vim.fn.shellescape(sil_dir),
            vim.fn.shellescape(tostring(vals.echandia_sil_scus)),
            vim.fn.shellescape(vals.echandia_sil_password),
            vim.fn.shellescape(vals.echandia_sil_module_type)
        )
        local hw = vals.echandia_sil_escu_hw
        if hw ~= "none" and hw ~= "" then
            cmd = cmd .. " -w " .. vim.fn.shellescape(hw)
        end
        local ch1 = vals.echandia_sil_ch1
        if ch1 ~= "none" and ch1 ~= "" then
            cmd = cmd .. " --ch1 " .. vim.fn.shellescape(ch1)
        end
        local ch2 = vals.echandia_sil_ch2
        if ch2 ~= "none" and ch2 ~= "" then
            cmd = cmd .. " --ch2 " .. vim.fn.shellescape(ch2)
        end
        if vals.echandia_sil_boxe == "true" then
            cmd = cmd .. " --boxe"
        end
        M.run_in_float(cmd)
    end)
end

function M.launch()
    local repo = M.detect_repo()
    if not repo then
        notify_err("Not in a bms, escu, or sil repo")
        return
    end
    if repo == "sil" then
        M.launch_sil()
        return
    end
    local cwd = vim.fn.getcwd()
    M.ensure_gen_config(function(gen_config)
        local cmd
        local use_docker = vim.g.echandia_launch_docker == "true"
        local gen = gen_config == "true"
        if repo == "bms" then
            cmd = string.format("%s/launch_bms.sh -s %s", SCRIPTS_DIR, vim.fn.shellescape(cwd .. "/EBMS"))
            -- Metrics stack (Victoria Metrics + OTel + Grafana) is docker-only
            -- and launch_bms.sh aborts if docker is down, so it's opt-in.
            if vim.g.echandia_launch_metrics == "true" then
                cmd = cmd .. " -m"
            end
            if gen then
                cmd = cmd .. " -g"
                local scus = vim.g.echandia_bms_scus
                if scus and scus ~= "" then
                    cmd = cmd .. " -n " .. vim.fn.shellescape(tostring(scus))
                end
            end
        else
            cmd = string.format(
                "%s/launch_escu.sh -s %s -t %s",
                SCRIPTS_DIR,
                vim.fn.shellescape(cwd),
                vim.fn.shellescape(cwd .. "/../sil")
            )
            if gen then
                cmd = cmd .. " -i"
            end
        end
        if use_docker then
            cmd = cmd .. " -d"
        end

        M.run_in_float(cmd)
    end)
end

-- Single source of truth for which command is bound in which repo. remap.lua
-- iterates this and binds only the entries whose `repos` include the detected
-- repo, so commands never show where they don't apply. SIL has no remote deploy
-- target, so `ed`/deploy is bms/escu only; the full-stack build (formerly
-- deploy_sil) is a `eb` build mode instead. All remembered settings live
-- behind one `es` walk (see CONFIGS) instead of a keymap per setting.
M.keymaps = {
    { lhs = "eb", fn = M.build,             repos = { "bms", "escu", "sil" }, desc = "Echandia build" },
    { lhs = "ec", fn = M.clean,             repos = { "bms" },                desc = "Echandia clean publish output (bms)" },
    { lhs = "ed", fn = M.deploy,            repos = { "bms", "escu" },        desc = "Echandia deploy" },
    { lhs = "el", fn = M.launch,            repos = { "bms", "escu", "sil" }, desc = "Echandia launch" },
    { lhs = "eg", fn = M.generate_embedded, repos = { "bms", "escu" },        desc = "Echandia generate embedded" },
    { lhs = "en", fn = M.generate_nswag,    repos = { "bms" },                desc = "Echandia generate nswag (bms)" },
    { lhs = "es", fn = M.configure,         repos = { "bms", "escu", "sil" }, desc = "Echandia settings (walk all configs)" },
}

return M
