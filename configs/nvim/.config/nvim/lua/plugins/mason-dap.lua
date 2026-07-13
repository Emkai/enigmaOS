return {
    "mfussenegger/nvim-dap",
    dependencies = {
        {
            'mason-org/mason.nvim',
            opts = {},
        },
        {
            "jay-babu/mason-nvim-dap.nvim",
            opts = {
                ensure_installed = {
                    'delve',
                    'js',
                    'chrome'
                },
                automatic_installation=true
            },
            handlers = {
                function(config)
                    print("Config: %s", config.name)
                    require("mason-nvim-dap").default_setup(config)
                end,
            },
            dependencies = {
                'mason-org/mason.nvim',
            }
        },
        "rcarriga/nvim-dap-ui",
        "nvim-neotest/nvim-nio",
        "theHamsta/nvim-dap-virtual-text"
    }

}
