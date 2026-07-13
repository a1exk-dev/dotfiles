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

Hyprland 0.55 Lua configurations require `hyprctl eval` for runtime monitor changes. The legacy `hyprctl keyword monitor` command does not apply the requested mode.

## Suspend display corruption

On the ASUS Zenbook S16 UM5606GA, AMD PSR2 selective update can cause full-screen noise or display corruption after resuming from `s2idle`. Add this kernel parameter to the boot loader options to disable PSR2 selective update while retaining legacy PSR:

```text
amdgpu.dcdebugmask=0x200
```

For systemd-boot, append it to the `options` line in the active entry under `/boot/loader/entries/`, then reboot. Verify that it is active:

```sh
cat /proc/cmdline
cat /sys/module/amdgpu/parameters/dcdebugmask
```

The module parameter should report `512`, the decimal representation of `0x200`. If corruption persists, try `amdgpu.dcdebugmask=0x600` to also disable Panel Replay.
