# Tmux

## TPM Installation

TPM requires git. Install it with:

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

After launching tmux, press `prefix + I` to fetch plugins.

## Config

- `tmux/.tmux.conf` - Main configuration
- Stow: `stow --adopt -t "$HOME" tmux`

## Notes

- Prefix is `Ctrl+a`.
- Reload config with `prefix + r`.
- Status bar uses Everforest palette values from root `ReadMe.md`.
- Session shortcuts:
  - `prefix + S` - Create new named session (prompt)
  - `prefix + X` - Kill current session (confirm)
