# Hyprland

Window manager configuration.

## Installation

```sh
sudo pacman -S hyprland
```

## Link config

```sh
stow --adopt -t "$HOME" hyprland
```

## Autostart

Hyprland starts Ollama with `OLLAMA_IGPU_ENABLE=1` so `ollama-vulkan` can use the AMD integrated GPU.
