# Neovim

LazyVim-based configuration with Everforest theme.

## Config

- `nvim/.config/nvim/init.lua` - Entry point
- `nvim/.config/nvim/lua/config/lazy.lua` - Plugin manager setup
- `nvim/.config/nvim/lua/config/options.lua` - Editor options
- `nvim/.config/nvim/lua/config/keymaps.lua` - Custom keymaps
- `nvim/.config/nvim/lua/config/autocmds.lua` - Custom autocommands
- `nvim/.config/nvim/lua/plugins/` - Plugin specs
- Stow: `stow --adopt -t "$HOME" nvim`

## Plugins

- **everforest** - Color scheme (hard background)
- **minuet-ai** - AI code completion via local Ollama
- **snacks.nvim** - Explorer with hidden/ignored file support
- **nvim-lspconfig** - lua_ls with Hyprland stubs

## Notes

- Relative numbers are disabled.
- `VimResume` triggers `checktime` to reload externally changed files.
