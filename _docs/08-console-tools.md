# Console Tools

Unified installation for console tools on Arch Linux.

## Installation

```sh
sudo pacman -S --needed zsh git stow fzf zoxide tmux starship ghostty thefuck
```

## Link configs

From the dotfiles repo root, run:

```sh
stow --adopt -t "$HOME" zsh starship tmux ghostty
```

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
