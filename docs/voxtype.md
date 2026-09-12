# Voxtype GPU acceleration

Voxtype selects CPU or GPU acceleration through its installed executable variant. The setting is not stored in `~/.config/voxtype/config.toml`.

## Check support

```bash
voxtype setup gpu --status
```

The status must list a detected GPU, an installed GPU backend, and its required runtime. For AMD, Intel, and NVIDIA GPUs, Voxtype can use its Vulkan Whisper variant when the Vulkan driver and runtime are available.

## Enable GPU acceleration

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

## Return to CPU acceleration

```bash
sudo voxtype setup gpu --disable
systemctl --user restart voxtype
voxtype info accel
```

Options such as `whisper.flash_attention`, `whisper.gpu_device`, and `whisper.gpu_isolation` tune GPU operation after the switch. They do not enable the GPU backend.
