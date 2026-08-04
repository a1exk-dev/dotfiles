# Tmux

## TPM Installation

TPM requires git. Install it with:

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

After launching tmux, press `prefix + I` to fetch plugins.

The configured plugins include Resurrect and Continuum. Continuum saves tmux
state every 15 minutes and restores it automatically when a new tmux server
starts.

## Config

- `tmux/.tmux.conf` - Main configuration
- `tmux/.local/bin/tmux-session` - Interactive session picker
- Stow: `stow --adopt -t "$HOME" tmux`

## Session Picker Installation

Install `tmux`, `fzf`, `zsh`, and GNU Stow with the system package manager.
Then run these commands from the repository root:

```sh
stow --adopt -t "$HOME" tmux
stow --adopt -t "$HOME" zsh
source ~/.zshrc
```

The first Stow command links the picker to `~/.local/bin/tmux-session`. The
second installs the Zsh wrapper that sends a bare `tmux` command to the picker.
Verify the installation with:

```sh
command -v tmux-session
tmux
```

With no running tmux server, the launcher starts a `main` session directly so
Continuum can restore saved state automatically; `fzf` is not shown or required
for this cold start. Once the server is running, the launcher opens the `fzf`
picker to select a live or restored session or create a new one. When run from
inside tmux, the picker switches the current client instead of nesting tmux.
Commands with arguments, such as `tmux ls`, continue to call tmux normally.

## Notes

- Prefix is `Ctrl+a`.
- Reload config with `prefix + r`.
- Save session state manually with `prefix + Ctrl+s`.
- Restore session state manually with `prefix + Ctrl+r`.
- Continuum automatically saves every 15 minutes and restores on tmux startup.
- Status bar uses Everforest palette values from root `ReadMe.md`.
- Session shortcuts:
  - `prefix + S` - Create new named session (prompt)
  - `prefix + X` - Kill current session (confirm)
