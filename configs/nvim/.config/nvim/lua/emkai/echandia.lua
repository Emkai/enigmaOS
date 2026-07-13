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

function M.set_target()
    vim.ui.input(
        { prompt = "Deploy host: ", default = vim.g.echandia_deploy_host or "" },
        function(host)
            if not host or host == "" then
                return
            end
            vim.g.echandia_deploy_host = host
            vim.ui.input(
                { prompt = "Arch: ", default = vim.g.echandia_deploy_arch or "amd64" },
                function(arch)
                    if not arch or arch == "" then
                        return
                    end
                    vim.g.echandia_deploy_arch = arch
                end
            )
        end
    )
end

function M.set_version()
    local repo = M.detect_repo()
    if not repo then
        notify_err("Not in a bms, escu, or sil repo")
        return
    end
    local varname = "echandia_" .. repo .. "_version"
    vim.ui.input(
        { prompt = "Deploy version (" .. repo .. "): ", default = vim.g[varname] or "99.99.99.01" },
        function(v)
            if not v or v == "" then
                return
            end
            vim.g[varname] = v
        end
    )
end

function M.set_launch_docker()
    vim.ui.input(
        { prompt = "Launch with docker: ", default = vim.g.echandia_launch_docker or "false" },
        function(v)
            if not v or v == "" then
                return
            end
            vim.g.echandia_launch_docker = v
        end
    )
end

function M.set_launch_gen_config()
    vim.ui.input(
        { prompt = "Generate config on launch: ", default = vim.g.echandia_launch_gen_config or "false" },
        function(v)
            if not v or v == "" then
                return
            end
            vim.g.echandia_launch_gen_config = v
        end
    )
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

function M.set_build_mode()
    local repo = M.detect_repo()
    if not repo then
        notify_err("Not in a bms, escu, or sil repo")
        return
    end
    local modes = BUILD_MODES[repo]
    if not modes then
        vim.notify("No build mode choice for " .. repo, vim.log.levels.INFO)
        return
    end
    local varname = "echandia_" .. repo .. "_build_mode"
    vim.ui.select(modes, {
        prompt = "Build mode (" .. repo .. "):",
        format_item = function(item) return item.label end,
    }, function(choice)
        if not choice then
            return
        end
        vim.g[varname] = choice.key
        vim.notify(varname .. " = " .. choice.key)
    end)
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
    vim.keymap.set({ "n", "t" }, "q", close, opts)
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
        local function run_with_version(arch)
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
                        "%s/deploy_escu.sh %s -s %s -v %s",
                        SCRIPTS_DIR,
                        vim.fn.shellescape(host),
                        vim.fn.shellescape(cwd),
                        vim.fn.shellescape(version)
                    )
                end
                M.run_in_float(cmd, function()
                    M.bump_version(version_var)
                end)
            end)
        end

        if repo == "bms" then
            M.ensure_var("echandia_deploy_arch", "Arch: ", "amd64", function(arch)
                run_with_version(arch)
            end)
        else
            run_with_version(nil)
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
                M.ensure_var("echandia_escu_version", "Version (escu): ", "99.99.99.01", function(version)
                    local cmd = string.format(
                        "%s/build_escu.sh -s %s -d -v %s",
                        SCRIPTS_DIR,
                        vim.fn.shellescape(cwd),
                        vim.fn.shellescape(version)
                    )
                    M.run_in_float(cmd)
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
-- and starts the compose stack). The password is prompted each time and is not
-- persisted in a vim global; the SCU count is remembered like echandia_bms_scus.
function M.launch_sil()
    local sil_dir = M.detect_sil_dir()
    if not sil_dir then
        notify_err("Launch SIL: no sil dir found (need sil/simulators or simulators/)")
        return
    end
    M.ensure_var("echandia_sil_scus", "SCU count: ", "1", function(scus)
        vim.ui.input({ prompt = "SIL password: " }, function(pw)
            if not pw or pw == "" then
                return
            end
            local cmd = string.format(
                "cd %s && ./setup.sh -s %s --password %s",
                vim.fn.shellescape(sil_dir),
                vim.fn.shellescape(tostring(scus)),
                vim.fn.shellescape(pw)
            )
            M.run_in_float(cmd)
        end)
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
            cmd = string.format("%s/launch_bms.sh -s %s -m", SCRIPTS_DIR, vim.fn.shellescape(cwd .. "/EBMS"))
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
-- deploy_sil) is a `eb` build mode instead.
M.keymaps = {
    { lhs = "eb", fn = M.build,                 repos = { "bms", "escu", "sil" }, desc = "Echandia build" },
    { lhs = "eB", fn = M.set_build_mode,        repos = { "bms", "escu", "sil" }, desc = "Echandia set build mode" },
    { lhs = "ed", fn = M.deploy,                repos = { "bms", "escu" },        desc = "Echandia deploy" },
    { lhs = "el", fn = M.launch,                repos = { "bms", "escu", "sil" }, desc = "Echandia launch" },
    { lhs = "eg", fn = M.generate_embedded,     repos = { "bms", "escu" },        desc = "Echandia generate embedded" },
    { lhs = "en", fn = M.generate_nswag,        repos = { "bms" },                desc = "Echandia generate nswag (bms)" },
    { lhs = "et", fn = M.set_target,            repos = { "bms", "escu" },        desc = "Echandia set deploy target (host + arch)" },
    { lhs = "ev", fn = M.set_version,           repos = { "bms", "escu", "sil" }, desc = "Echandia set deploy version" },
    { lhs = "ep", fn = M.set_launch_docker,     repos = { "bms", "escu" },        desc = "Echandia set use docker for launch" },
    { lhs = "eG", fn = M.set_launch_gen_config, repos = { "bms", "escu" },        desc = "Echandia set gen-config on launch" },
}

return M
