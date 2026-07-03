# Hyprland

Window manager configuration.

## Installation

```sh
sudo pacman -S --needed hyprland hypridle hyprlock
```
yay -S wlogout

## Link config

```sh
stow -t "$HOME" hyprland
stow -t "$HOME" hypridle 
stow -t "$HOME" wlogout 
```

systemctl --user enable --now hypridle.service

## Autostart

Hyprland starts Ollama with `OLLAMA_IGPU_ENABLE=1` so `ollama-vulkan` can use the AMD integrated GPU.

Hyprland also starts `~/.config/hypr/scripts/edp-refresh-rate.sh` to keep the laptop display at `120 Hz` when external power is online and `60 Hz` on battery.
