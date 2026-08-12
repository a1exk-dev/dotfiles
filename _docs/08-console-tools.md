# Console Tools

Unified installation for console tools on Arch Linux.

## Installation

```sh
sudo pacman -S --needed zsh git stow fzf zoxide tmux starship ghostty thefuck
```

## Link configs

From the dotfiles repo root, run:

```sh
stow --adopt -t "$HOME" zsh
stow --no-folding -t "$HOME" theme-tools
dotfiles-theme install
```

The theme install safely restows the managed tmux, Ghostty, and OpenCode packages and generates Starship's active config. Do not separately Stow the old Starship theme file. See [Theme management](21-theme.md).

## Features

### Aliases

- `ll` - `ls -la`
- `~` - `cd ~`
- `..` - `cd ..`
- `...` - `cd ../..`
- `....` - `cd ../../..`
- `fuck` - Correct the previous command
- `z <dir>` - Jump to directory
- `zi` - Interactive directory selection

### Tools

- **zoxide** - Smarter `cd` command
- **thefuck** - Fix command typos
- **starship** - Cross-shell prompt
- **fzf** - Fuzzy finder (Ctrl+R for history, Ctrl+T for files)
