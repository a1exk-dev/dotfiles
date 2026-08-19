# Tmux

The `tmux` Stow package owns only `~/.local/libexec/dotfiles/tmux-starter`. This private executable is not on `PATH`. The package does not manage `.tmux.conf`, the tmux server, sessions, logs, or other tmux state.

## Requirements

The package requires the official Arch `tmux` and `fzf` packages. The Dotfiles wizard lists anything missing in the Stow plan and installs it through Omarchy after confirmation.

The `bash` Stow package depends on `tmux`, so selecting `bash` includes both packages.

## Starter

In an interactive Bash shell, run `tmux` without arguments to open the starter. Tmux commands with arguments run `/usr/bin/tmux` normally. Use `command tmux` to bypass the Bash wrapper.

Omarchy's `t` alias remains unchanged.

| Input | Result |
| --- | --- |
| Type text | Filter the session list |
| Up or Down | Select a session |
| Enter | Open the selected session |
| Ctrl-N | Ask for a new session name |
| Ctrl-X | Ask before killing the selected session |
| Esc | Exit without changing any session |

Enter and Ctrl-X target the selected session by its exact tmux session ID. The displayed name is not parsed as a command target.

The new-session prompt uses `Work` when the name is empty. Another valid name is preserved, including spaces. If that name already exists, tmux attaches to it. A new session starts in the current directory.

After a confirmed kill, the starter refreshes the session list. A declined kill changes nothing.

The starter refuses to run inside tmux.

The Bash wrapper reports a missing or non-executable private helper. The starter reports a missing or non-executable `/usr/bin/tmux` or `/usr/bin/fzf`.

## Apply

Start the Dotfiles wizard:

```bash
make
```

Choose `Apply Stow packages`. Selecting `bash` includes the `tmux` dependency. Selecting `tmux` by itself installs only the private starter and its Arch requirements; the bare-command wrapper belongs to Bash.

See [Stow workflow](stow.md) for shared planning, confirmation, and conflict handling.

## Validation

Check the private script with:

```bash
sh -n ~/.local/libexec/dotfiles/tmux-starter
test -x ~/.local/libexec/dotfiles/tmux-starter
```

Use `Package status` in the Dotfiles wizard to confirm that `tmux` is linked.

## Removal

The wizard blocks `tmux` package removal while the linked `bash` package depends on it. Remove `bash` first if you want to unlink the private starter.

Removing `bash` leaves the `tmux` package linked. Removing `tmux` leaves the Arch `tmux` and `fzf` packages installed. It does not stop the tmux server or delete sessions, logs, or other tmux state.
