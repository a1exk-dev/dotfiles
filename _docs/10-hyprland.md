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

## Russian input

The input configuration provides US English and Russian keyboard layouts. Press `Super+Space` to switch every connected keyboard to the next layout.

Generate the Russian UTF-8 locale without changing the system's default English locale:

```sh
sudoedit /etc/locale.gen
```

Uncomment `ru_RU.UTF-8 UTF-8`, then generate the enabled locales:

```sh
sudo locale-gen
```

## Autostart

Hyprland starts Ollama with `OLLAMA_IGPU_ENABLE=1` so `ollama-vulkan` can use the AMD integrated GPU.

Hyprland also starts `~/.config/hypr/scripts/edp-refresh-rate.sh` to keep the laptop display at `120 Hz` when external power is online and `60 Hz` on battery.

Hyprland 0.55 Lua configurations require `hyprctl eval` for runtime monitor changes. The legacy `hyprctl keyword monitor` command does not apply the requested mode.

## Suspend display corruption

On the ASUS Zenbook S16 UM5606GA, AMD PSR2 selective update can cause full-screen noise or display corruption after resuming from `s2idle`. Start with this kernel parameter to disable PSR2 selective update while retaining legacy PSR:

```text
amdgpu.dcdebugmask=0x200
```

If artifacts persist, change the parameter from `0x200` to `0x600` to also disable AMD Panel Replay:

```text
amdgpu.dcdebugmask=0x600
```

If artifacts still persist, replace `0x600` with `0x410` to disable legacy PSR as well as PSR selective update and Panel Replay:

```text
amdgpu.dcdebugmask=0x410
```

Disabling all PSR modes can increase panel power consumption.

For systemd-boot, edit the `options` line in the active entry under `/boot/loader/entries/`, not `/boot/loader/loader.conf`, then reboot. Use `bootctl status` to identify the active entry. Verify that the parameter is active:

```sh
cat /proc/cmdline
cat /sys/module/amdgpu/parameters/dcdebugmask
```

The module parameter should report `512` for `0x200`, `1536` for `0x600`, or `1040` for `0x410`.
