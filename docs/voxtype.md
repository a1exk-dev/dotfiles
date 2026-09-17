[Back to README](../README.md)

# Voxtype

The `voxtype` Stow package tracks two configuration profiles:

- `~/.config/dotfiles/voxtype/pc.toml`, linked from `config/voxtype/.config/dotfiles/voxtype/pc.toml`
- `~/.config/dotfiles/voxtype/laptop.toml`, linked from `config/voxtype/.config/dotfiles/voxtype/laptop.toml`

Each profile is a complete replacement for `~/.config/voxtype/config.toml`. They begin as copies of one another and diverge as each machine needs.

Applying the package does not change the active configuration. `Select Voxtype profile` does that: it points `~/.config/voxtype/config.toml` at one profile and owns that link alone.

The package does not own:

- The Voxtype installation or its CPU and GPU executable variants
- Voxtype models and runtime state
- `~/.config/voxtype/config.toml.bak` and other files Voxtype writes beside the link
- Hyprland keybindings that call `voxtype record toggle`

See [Stow workflow](stow.md) for the shared Stow package lifecycle.

## Requirements

Voxtype is not an Arch package in this repository, so the package declares no Arch requirement and installs nothing. Install Voxtype first; the package declares the `/usr/bin/voxtype` prerequisite, and both validators parse a tracked profile with `voxtype -c <profile> config get engine`.

## Apply

Start the Dotfiles wizard:

```bash
make
```

Choose `Apply Stow packages` and select `voxtype`. The package is optional and is never selected by default.

Then choose `Select Voxtype profile` and pick `pc` or `laptop`. You can also run `bin/dotfiles --action voxtype-profile`, or `make voxtype` for the selector alone. The action reports the current selection, backs up an existing `~/.config/voxtype/config.toml` under the XDG state backup tree, links the chosen profile, verifies the link, and has Voxtype parse it. Restart the daemon afterwards:

```bash
systemctl --user restart voxtype
```

## Edit a profile

Edit the tracked file in the repository. Because the active config is a link, the change is live at once, so restart the daemon to pick it up.

`voxtype config set` and the `voxtype configure` TUI write through the link into the tracked profile. Review the result as a proposed Git change:

```bash
git diff -- config/voxtype
```

## Verification

```bash
target=$HOME/.config/voxtype/config.toml

[[ -L $target ]]
readlink -f -- "$target"
voxtype config get engine
```

The resolved path must name the profile you selected, and the last command must print its engine.

Run the focused tests with:

```bash
bash tests/voxtype_test.sh
```

## Removal

Choose `Remove Stow package` and select `voxtype`. Removal unlinks the profiles and leaves `~/.config/voxtype/config.toml` as a broken link to the profile it pointed at. Delete that link, or put your own regular file there. Voxtype itself, its models and its state stay in place.

## GPU acceleration

Voxtype selects CPU or GPU acceleration through its installed executable variant. The setting is not stored in `~/.config/voxtype/config.toml`.

Run `make voxtype-gpu` to enable the GPU variant, restart the user daemon and print the acceleration report. It asks for your sudo password. The sections below cover the same steps one command at a time.

### Check support

```bash
voxtype setup gpu --status
```

The status must list a detected GPU, an installed GPU backend, and its required runtime. For AMD, Intel, and NVIDIA GPUs, Voxtype can use its Vulkan Whisper variant when the Vulkan driver and runtime are available.

### Enable GPU acceleration

```bash
sudo voxtype setup gpu --enable
```

Restart the user service if the running daemon still reports the CPU variant:

```bash
systemctl --user restart voxtype
```

Verify the active backend:

```bash
voxtype setup gpu --status
voxtype info accel
```

The status should report the Vulkan variant as active, and the acceleration report should no longer say `cpu-only`.

### Return to CPU acceleration

```bash
sudo voxtype setup gpu --disable
systemctl --user restart voxtype
voxtype info accel
```

Options such as `whisper.flash_attention`, `whisper.gpu_device`, and `whisper.gpu_isolation` tune GPU operation after the switch. They do not enable the GPU backend.
