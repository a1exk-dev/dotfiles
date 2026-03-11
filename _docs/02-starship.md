# Starship

## Installation

```sh
sudo dnf install -y starship
```

## Configure preset

After initial setup, select a preset:

```sh
starship preset gruvbox-rainbow -o ~/.config/starship.toml
```

## Link config

From the dotfiles repo root, run:

```sh
stow --adopt -t "$HOME" starship
```
