# Neovim

LazyVim-based configuration with Everforest theme.

## Config

- `nvim/.config/nvim/init.lua` - Entry point
- `nvim/.config/nvim/lua/config/lazy.lua` - Plugin manager setup
- `nvim/.config/nvim/lua/config/options.lua` - Editor options
- `nvim/.config/nvim/lua/config/keymaps.lua` - Custom keymaps
- `nvim/.config/nvim/lua/config/autocmds.lua` - Custom autocommands
- `nvim/.config/nvim/lua/config/theme.lua` - Active bundle selector loader
- `nvim/.config/nvim/lua/plugins/` - Plugin specs

Neovim files on this machine are intentionally not Stowed or adopted by the theme manager. The plugin config reads the generated selector from `${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-theme/current/.config/nvim/theme.lua`. Install and switch the shared theme as described in [Theme management](21-theme.md), then reload Neovim manually.

## Plugins

- **everforest** - Colorscheme and background selected by the active bundle
- **minuet-ai** - AI code completion via local Ollama
- **snacks.nvim** - Explorer with hidden/ignored file support
- **nvim-lspconfig** - lua_ls with Hyprland stubs

## Notes

- Relative numbers are disabled.
- `VimResume` triggers `checktime` to reload externally changed files.
