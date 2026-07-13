local dap = require("dap")
local ui = require("dapui")
local dap_virtual_text = require("nvim-dap-virtual-text")

dap_virtual_text.setup({})

dap.adapters.delve = function(callback, config)
    if config.mode == "remote" and config.request == "attach" then
        callback({
            type = "server",
            host = config.host or "127.0.0.1",
            port = config.port or "38697",
        })
    else
        callback({
            type = "server",
            port = "${port}",
            executable = {
                command = "dlv",
                args = { "dap", "-l", "127.0.0.1:${port}", "--log", "--log-output=dap" },
                detached = vim.fn.has("win32") == 0,
            },
        })
    end
end

local function get_arguments()
    local co = coroutine.running()
    if co then
        return coroutine.create(function()
            local args = {}
            vim.ui.input({ prompt = 'Enter command-line arguments: ' }, function(input)
                args = vim.split(input, " ")
            end)
            coroutine.resume(co, args)
        end)
    else
        local args = {}
        vim.ui.input({ prompt = 'Enter command-line arguments: ' }, function(input)
            args = vim.split(input, " ")
        end)
        return args
    end
end


dap.configurations.go = {
    {
        type = "delve",
        name = "Debug",
        request = "launch",
        program = "${file}",
        args = get_arguments,
    },
}

dap.adapters.js = {
    type = "server",
    host = "localhost",
    port = "${port}",
    executable = {
        command = "js-debug-adapter",
        args = { "${port}" },
    },
}

dap.adapters["chrome"] = {
    type = "server",
    host = "localhost",
    port = "${port}",
    executable = {
        command = "chrome-debug-adapter",
        args = { "${port}" },
    },
}

dap.configurations.typescript = {
    {
        type = "chrome",
        request = "attach",
        program = "${file}",
        debugServer = 45635,
        cwd = vim.fn.getcwd(),
        sourceMaps = true,
        protocol = "inspector",
        port = 9222,
        webRoot = "${workspaceFolder}",
    },
}

dap.configurations.chrome = {
    {
        type = "chrome",
        name = "Debug",
        request = "launch",
        program = "${file}",
    },
}

ui.setup()

dap.listeners.before.attach.dapui_config = function() ui.open() end

dap.listeners.before.launch.dapui_config = function() ui.open() end

dap.listeners.before.event_terminated.dapui_config = function() ui.close() end

dap.listeners.before.event_exited.dapui_config = function() ui.close() end

vim.fn.sign_define("DapBreakpoint", {
    text = ""
})

