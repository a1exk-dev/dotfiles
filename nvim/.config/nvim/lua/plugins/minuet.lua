return {
  {
    "milanglacier/minuet-ai.nvim",
    lazy = false,

    config = function()
      require("minuet").setup({
        provider = "openai_fim_compatible",

        n_completions = 1,
        -- Minuet's context window is characters, not model tokens.
        context_window = 8000,
        request_timeout = 5,
        throttle = 1200,
        debounce = 500,

        virtualtext = {
          -- Equivalent to enabling auto virtual text globally.
          auto_trigger_ft = { "*" },

          -- Optional exclusions.
          auto_trigger_ignore_ft = {
            "markdown",
            "text",
            "help",
            "gitcommit",
          },

          keymap = {
            next = "<C-f>",
            prev = "<C-b>",
            accept = "<C-l>",
            accept_line = "<C-j>",
            accept_n_lines = "<C-k>",
            dismiss = "<C-e>",
          },

          show_on_completion_menu = false,
        },

        provider_options = {
          openai_fim_compatible = {
            api_key = "TERM",
            name = "Ollama",
            end_point = "http://localhost:11434/v1/completions",
            model = "qwen2.5-coder:1.5b-base-q4_K_M",

            optional = {
              max_tokens = 128,
              temperature = 0.1,
              top_p = 0.9,
              top_k = 20,
              stop = {
                "<|endoftext|>",
                "<|fim_prefix|>",
                "<|fim_suffix|>",
                "<|fim_middle|>",
              },
            },
          },
        },
      })
    end,
  },
}
