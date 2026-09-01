[Back to README](../README.md)

# Tmux

The `tmux` Stow package owns three leaf targets:

- `~/.config/tmux/tmux.conf`, linked from `config/tmux/.config/tmux/tmux.conf`
- `~/.local/libexec/dotfiles/tmux-starter`, linked from `config/tmux/.local/libexec/dotfiles/tmux-starter`
- `~/.local/libexec/dotfiles/tmux-stop-orphaned-nvim`, linked from `config/tmux/.local/libexec/dotfiles/tmux-stop-orphaned-nvim`

The tracked configuration is a complete replacement based on `/usr/share/omarchy/config/tmux/tmux.conf`. The packaged Omarchy file stays read-only. The active configuration does not source a drop-in or a second baseline copy.

The package owns the configuration and helper sources. Tmux owns its server, sessions, panes, logs, and other runtime state; the user systemd manager owns each transient cleanup service.

## Requirements

The package requires the official Arch `tmux`, `fzf`, and `less` packages. The generated keybinding-help popup runs `less -R`. The Dotfiles wizard lists anything missing in the Stow plan and installs it through Omarchy after confirmation.

Orphaned Neovim cleanup also requires `systemd-run`, a running user systemd manager, and util-linux pidfd support through `getino --pidfs` and `kill PID:inode`.

The `bash` Stow package depends on `tmux`, so selecting `bash` includes both packages.

## Configuration

The primary prefix is `C-a`, and the secondary prefix is `C-Space`. `C-b` is not a prefix. In the table below, `prefix` means either configured prefix.

| Input | Result |
| --- | --- |
| `prefix + C-a` | Send the primary prefix to a nested tmux client |
| `prefix + q` | Reload `~/.config/tmux/tmux.conf` |
| `prefix + r` | Rename the current window |
| `prefix + ?` | Show generated tmux key help |
| `prefix + %` | Split horizontally in the current pane directory |
| `prefix + \|` | Split horizontally in the current pane directory |
| `prefix + "` | Split vertically in the current pane directory |
| `M-h` | Focus the pane to the left |
| `M-j` | Focus the pane below |
| `M-k` | Focus the pane above |
| `M-l` | Focus the pane to the right |

The `M-h/j/k/l` bindings do not require a prefix. Omarchy also provides Alt-arrow window and session navigation, Ctrl-Alt-arrow pane navigation, pane resizing, window controls, session controls, copy mode, and direct terminal clipboard behavior. Each custom binding has a description in Omarchy's generated help.

Each pane keeps 50,000 lines of history. The configuration also uses one-based window and pane indexes, automatic window renumbering, mouse support, vi copy mode, focus events, extended terminal keys, clipboard terminal features, aggressive pane resizing, and Omarchy's session-switching behavior when a session is destroyed.

Window names follow the active pane command, such as `nvim`, `bash`, or `btop`. The outer terminal title stays in `host:window-name` form. A session named `0` is not renamed to `main`.

The one-line status bar stays at the top. It shows:

- The session name
- Native `#I:#W` window entries
- Conditional `COPY`, `PREFIX`, and `ZOOM` labels
- The active pane path

The path replaces the home directory with `~`. Values up to 32 columns remain exact. Only longer values gain a leading ASCII `...`; tmux keeps the newest suffix within the same 32-column budget. The status bar omits the pane title and hostname. It uses the named terminal colors `default`, `black`, `blue`, and `brightblack`, without tmux-specific theme variables, icon glyphs, or hard-coded theme RGB values.

The configuration does not load TPM, tmux-resurrect, tmux-continuum, snapshots, automatic restore, or a persistence service.

## Starter

In an interactive Bash shell, run `tmux` without arguments to open the starter. Tmux commands with arguments run `/usr/bin/tmux` normally. Use `command tmux` to bypass the Bash wrapper.

Omarchy's `t` alias attaches to an existing session or creates `Work`.

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

After a confirmed kill, the starter refreshes the session list. A declined kill changes nothing. The starter refuses to run inside tmux.

The Bash wrapper reports a missing or non-executable private helper. The starter reports a missing or non-executable `/usr/bin/tmux` or `/usr/bin/fzf`.

## Orphaned Neovim cleanup

When a tmux pane exits or is killed, or a window is removed, tmux submits the cleanup helper to a collected transient user service. On a final-session exit, tmux keeps its empty server running until that submission succeeds, then stops the server.

After a short grace period, the helper stops only an `nvim --embed` process in a `tmux-spawn-*.scope` whose standard streams all refer to deleted terminals. It sends `TERM` through the process's pidfd identity, waits one second, and sends `KILL` only if the same process still qualifies. Active Neovim processes and other processes are left unchanged.

## Apply

Start the Dotfiles wizard:

```bash
make
```

Choose `Apply Stow packages`. Selecting `bash` includes the `tmux` dependency. Selecting `tmux` by itself links the complete configuration and both private helpers. The bare-command wrapper belongs to Bash.

If a pre-existing `~/.config/tmux/tmux.conf` is a regular file, follow [Pre-existing tmux configuration](stow.md#pre-existing-tmux-configuration) before applying the package. Do not use `Migrate existing target` or `stow --adopt` for this file because the package contains the complete tracked configuration.

Applying the package does not reload an existing server. Reload it deliberately with the prefix and `q` binding that the running server currently recognizes, or start a new server.

## Validation

`Apply Stow packages` checks both helpers' syntax and executable mode:

```bash
sh -n ~/.local/libexec/dotfiles/tmux-starter
test -x ~/.local/libexec/dotfiles/tmux-starter
bash -n ~/.local/libexec/dotfiles/tmux-stop-orphaned-nvim
test -x ~/.local/libexec/dotfiles/tmux-stop-orphaned-nvim
```

The configuration validator creates a temporary tmux socket, loads the complete configuration there, and removes the isolated server and socket directory afterward. It does not load the candidate configuration into the default tmux server.

An equivalent manual check is:

```bash
(
	set -euo pipefail
	socket_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tmux-validator.XXXXXX")
	socket=$socket_dir/socket

	cleanup() {
		TMUX= tmux -S "$socket" kill-server >/dev/null 2>&1 || true
		rm -rf -- "$socket_dir"
	}
	trap cleanup EXIT
	trap 'exit 1' HUP INT TERM

	TMUX= tmux -S "$socket" -f /dev/null \
		new-session -d -s dotfiles-validator \; \
		source-file "$HOME/.config/tmux/tmux.conf"
)
```

Every tmux command in this check names the temporary socket with `-S`. Use `Package status` in the Dotfiles wizard to confirm that all three package targets are linked.

## Omarchy writes and updates

Keep `/usr/share/omarchy/` read-only. After an Omarchy update, check the active link, review any Git change, and compare the tracked replacement with the current packaged baseline:

```bash
readlink -f -- "$HOME/.config/tmux/tmux.conf"
git diff -- config/tmux/.config/tmux/tmux.conf
diff -u -- \
	/usr/share/omarchy/config/tmux/tmux.conf \
	config/tmux/.config/tmux/tmux.conf || true
```

`omarchy refresh tmux`, Omarchy migrations, hooks, and reinstall operations can write through or replace the Stow link. Treat the result as a proposed repository change. Review the diff, keep useful baseline changes deliberately, restore the documented customizations, Restow if the link was replaced, and run package validation.

Do not use `omarchy refresh tmux` as a local reset while the package is linked. Before `omarchy reinstall configs`, unlink affected Stow packages unless overwriting their tracked sources has been explicitly accepted.

## Removal

The wizard blocks `tmux` package removal while the linked `bash` package depends on it. Remove `bash` first if you want to unlink tmux.

Removing `bash` leaves the `tmux` package linked. Removing `tmux` unlinks the configuration and both helpers. It leaves `~/.config/tmux/tmux.conf` absent and keeps the tracked sources in the repository.

Removal leaves the Arch `tmux`, `fzf`, and `less` packages, migration backups, servers, sessions, panes, logs, and other runtime state untouched. The cleanup report names this restoration command without running it:

```bash
omarchy refresh tmux
```

Run that command after removal only when you want an unmanaged copy of the current Omarchy baseline.
