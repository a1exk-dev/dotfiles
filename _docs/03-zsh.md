# Zsh

The zsh configuration is `zsh/.zshrc`.

From the repository root, Stow it with:

```sh
stow --adopt -t "$HOME" zsh
```

Zsh points Starship at `${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml`. That compatibility path is generated and bridged by [`dotfiles-theme`](21-theme.md); the theme manager does not Stow or adopt Zsh.

The `tradingview` function applies the X11 compatibility flag described in [TradingView](20-tradingview.md).
