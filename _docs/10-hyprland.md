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

## Idle policy

Hypridle uses total idle time for every listener:

| Action | Battery | External power |
| --- | ---: | ---: |
| Monitor dim | 2m 30s | 5m |
| Keyboard backlight off | 2m 30s | 2m 30s |
| Session lock | 5m | 1h |
| Screen DPMS off | 5m 30s | 30m |
| Suspend | 15m | 2h |

Monitor and keyboard brightness and screen DPMS are restored on activity. Suspend runs `systemctl suspend`.
The later external-power schedule is unconditional, so it remains a fallback if the power source changes during an idle period.

## Lua configuration scope

Hyprland 0.55 and later use Lua for `hyprland.lua`, but the companion tools still use Hyprlang configuration files:

| Tool | Repository config | Native format |
| --- | --- | --- |
| Hyprpaper | `hyprland/.config/hypr/hyprpaper.conf` | Hyprlang |
| Hyprlock | `hyprland/.config/hypr/hyprlock.conf` | Hyprlang |
| Hypridle | `hypridle/.config/hypr/hypridle.conf` | Hyprlang |

Keep these files as `.conf`. Their `--config` options can accept an arbitrary filename, but each tool still passes the selected file to its Hyprlang parser; a `.lua` suffix does not enable Lua syntax.

Sources: [Hyprland configuration](https://wiki.hypr.land/Configuring/Start/), [hyprpaper](https://wiki.hypr.land/Hypr-Ecosystem/hyprpaper/), [hyprlock](https://wiki.hypr.land/Hypr-Ecosystem/hyprlock/), and [hypridle](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/).

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

## Suspend and hibernate display corruption

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

If artifacts are visible on the physical display but absent from a screenshot, disable scatter/gather display buffers to target the hardware scanout path:

```text
amdgpu.sg_display=0
```

Add the parameter to the active boot-loader entry and reboot. Rebuilding the initramfs is unnecessary when AMDGPU is not embedded in it.

For hibernation-only corruption on Krackan-family AMD GPUs, check the kernel journal for `MES failed to respond` and `failed to unmap legacy queue`. If those errors occur, remove the `kms` hook from `/etc/mkinitcpio.conf` so AMDGPU is not initialized before the hibernation image is restored, then rebuild the initramfs:

```sh
sudo mkinitcpio -P
```

This workaround takes effect after reboot and may remove the graphical Plymouth phase during early boot.

For systemd-boot, edit the `options` line in the active entry under `/boot/loader/entries/`, not `/boot/loader/loader.conf`, then reboot. Use `bootctl status` to identify the active entry. Verify that the parameter is active:

```sh
cat /proc/cmdline
cat /sys/module/amdgpu/parameters/dcdebugmask
cat /sys/module/amdgpu/parameters/sg_display
```

The module parameters should report `512` for `0x200`, `1536` for `0x600`, or `1040` for `0x410`, and `0` for `sg_display`.
