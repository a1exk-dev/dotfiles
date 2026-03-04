# Zsh

## Installation

Install dependencies:

```sh
sudo dnf install -y zsh git starship thefuck fzf zoxide
```

Install `stow` if it is not already present.

## Link config after installing Zsh

From the dotfiles repo root, run:

```sh
stow --adopt -t "$HOME" zsh
```

This links `~/.zshrc` to `zsh/.zshrc`.

## Plugin manager

Zinit bootstraps itself automatically on first shell start and installs the plugins below. It is cloned to:

- `~/.local/share/zinit/zinit.git`

## Enabled plugins

- `zsh-users/zsh-autosuggestions`
- `zsh-users/zsh-syntax-highlighting`
- `zsh-users/zsh-completions`
- `Aloxaf/fzf-tab`
- `ajeetdsouza/zoxide`

## Optional integrations

If installed, fzf keybindings and completion are sourced from:

- `/usr/share/fzf/shell/key-bindings.zsh`
- `/usr/share/fzf/shell/completion.zsh`
