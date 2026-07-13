return {
    "ggml-org/llama.vim",
    init = function()
        vim.g.llama_config = {
            endpoint_fim = "http://127.0.0.1:8080/infill",
            endpoint_inst = "http://127.0.0.1:8080/v1/chat/completions",
            model_fim = "ggml-org/Qwen2.5-Coder-3B-Q8_0-GGUF:Q8_0",
            model_inst = "ggml-org/Qwen2.5-Coder-3B-Q8_0-GGUF:Q8_0",
            keymap_fim_trigger = "<C-g>",
            keymap_fim_accept_full = "<C-a>",
            keymap_fim_accept_line = "<S-Tab>",
            keymap_fim_accept_word = "<C-j>",
        }
        vim.api.nvim_create_autocmd("VimEnter", {
            once = true,
            callback = function()
                local toggle = require("emkai.llama_toggle")
                toggle.apply(toggle.is_enabled())
            end,
        })
    end,
}
