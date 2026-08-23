# Starship

The `starship` Stow package owns one leaf target:

- `~/.config/starship.toml`, linked from `config/starship/.config/starship.toml`

The tracked config started as a byte-for-byte capture of Omarchy 4's `/usr/share/omarchy/config/starship.toml`. Its only intentional differences are the connected two-line frame, Git branch icon, and Git status markers described below. Keep packaged files under `/usr/share/omarchy/` read-only; they are comparison and recovery inputs.

The package does not own:

- `/usr/share/omarchy/config/starship.toml` or `/etc/skel/.config/starship.toml`
- The Starship executable or its Arch package lifecycle
- Starship cache, state, or XDG-state migration backups
- Bash initialization or `STARSHIP_CONFIG`
- Terminal configuration, terminal palettes, Omarchy themes, or generated theme state
- Archived Starship, Everforest, or theme-manager files

## Requirement and Bash initialization

The package requires the official Arch `starship` package. If it is missing, the Dotfiles wizard includes `omarchy pkg add starship` in the complete apply plan, asks for confirmation, installs and verifies it, and repeats the Stow simulation before linking the config.

The `bash` and `starship` Stow packages are independent. Omarchy's packaged Bash defaults continue to initialize Starship. The `starship` package supplies only `~/.config/starship.toml`; it does not add a prompt hook or set `STARSHIP_CONFIG`. Either Stow package can be applied or removed without the other.

## Prompt behavior

The prompt still uses a 200 ms command timeout, two directory components, the read-only lock, and Omarchy's existing module roster. It uses a connected two-line frame. The first line starts with `╭─ ` and shows the directory and Git context in their existing order. The second line starts with `╰─`, followed immediately by the existing success `❯` or error `✗` character. Typing starts after the character's existing trailing space. The frame uses terminal `cyan`; all other module spacing, glyphs, and text styles are unchanged.

## Git branch

Git repositories prefix the branch name with ` `, so a branch such as `baseline` renders as ` baseline`. The icon and branch name use the existing italic terminal `cyan` style. Prompts outside a Git repository do not show the icon.

## Git status

Compared with Omarchy's packaged baseline, the tracked config reports file counts for six Git states:

- Conflict: `${count} `
- Modified: `${count} `
- Untracked: `?${count} `
- Staged: `+${count} `
- Deleted: `✘${count} `
- Renamed: `»${count} `

Stash state is presence-only:

- Stash present: `\$ `

Branches with a configured upstream report commit distance when local and upstream refs differ:

- Ahead: `⇡${count} `
- Behind: `⇣${count} `
- Diverged: `⇕⇡${ahead_count}⇣${behind_count} `

A synchronized branch shows no upstream marker. Starship reads local refs only; prompt rendering does not fetch or contact a remote.

Starship replaces the count variables at runtime and treats `\$` as a literal dollar sign. Multiple stashes still render one `$ ` marker. File-state and stash markers render before upstream distance; colors are unchanged. No other archived setting is active.

## Apply

When `~/.config/starship.toml` is absent, start the Dotfiles wizard:

```bash
make
```

Choose `Apply Stow packages` and select `starship`. The wizard checks the supported Omarchy version, plans the official Arch requirement when needed, simulates the leaf link with `--no-folding`, asks for confirmation, applies the package, verifies the link, and runs the strict config validator.

The repository used `Migrate existing target` once, while `config/starship/.config/starship.toml` was empty. Before migration, the live file was a regular file inside the home directory and matched Omarchy's packaged baseline byte for byte. Migration backed it up to XDG state, moved it into the Stow package, linked it, and validated it.

At that checkpoint, the live file, backup, initial tracked source, and packaged baseline shared one byte count and digest. The backup remains unchanged. The current tracked config differs only by the connected two-line frame, Git branch icon, and Git status markers above.

In a normal clone, the tracked destination already exists. Do not use `Migrate existing target` or `stow --adopt` for a regular `~/.config/starship.toml`. Use the procedure below.

## Existing regular target

This procedure applies when a normal apply finds an unmanaged regular `~/.config/starship.toml`. It also applies after the optional baseline restoration described below. Run every command from the repository root.

First run:

```bash
make
```

Choose `Run structural checks`. Continue only if the supported and detected Omarchy versions match. Fix every structural error before continuing, except a missing declared Arch `starship` package, which the normal apply plan can install. Then choose `Package status`. The `starship` package must be `conflicting` only because `~/.config/starship.toml` is a regular file. Stop on an invalid state or another cause.

Check the complete Stow simulation:

```bash
repo_root=$(git rev-parse --show-toplevel)
stow --no-folding --simulate --verbose=2 \
	--dir "$repo_root/config" --target "$HOME" starship
```

The simulation is expected to return nonzero and name exactly one conflict, `~/.config/starship.toml`. Stop if it reports another conflict. If GNU Stow is missing, run `make`, choose `Prepare prerequisites`, and restart this procedure.

The following block accepts only a regular target that is not a symlink. It verifies the canonical home and repository boundaries, compares the target with the current packaged baseline, asks for explicit approval, creates and verifies a timestamped backup below the XDG state directory, rechecks the target, and removes only that approved file.

```bash
(
	set -euo pipefail

	repo_root=$(readlink -f -- "$(git rev-parse --show-toplevel)")
	target=$HOME/.config/starship.toml
	package_root=$repo_root/config/starship
	tracked=$package_root/.config/starship.toml
	packaged=/usr/share/omarchy/config/starship.toml
	state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}

	if [[ $state_home != /* ]]; then
		printf 'XDG_STATE_HOME must be an absolute path: %s\n' "$state_home" >&2
		exit 1
	fi
	if [[ ! -f $target || -L $target ]]; then
		printf 'Expected a regular file that is not a symlink: %s\n' "$target" >&2
		exit 1
	fi
	if [[ ! -d $package_root || ! -f $tracked || -L $tracked ]]; then
		printf 'Expected the tracked Starship source: %s\n' "$tracked" >&2
		exit 1
	fi
	if [[ ! -f $packaged ]]; then
		printf 'Packaged Omarchy Starship baseline is unavailable: %s\n' "$packaged" >&2
		exit 1
	fi

	home_root=$(readlink -f -- "$HOME")
	resolved_target=$(readlink -f -- "$target")
	resolved_package_root=$(readlink -f -- "$package_root")
	resolved_tracked=$(readlink -f -- "$tracked")
	if [[ $resolved_target != "$home_root/"* ]]; then
		printf 'Starship configuration resolves outside HOME: %s -> %s\n' \
			"$target" "$resolved_target" >&2
		exit 1
	fi
	if [[ $resolved_package_root != "$repo_root/"* ]] ||
		[[ $resolved_tracked != "$resolved_package_root/"* ]]; then
		printf 'Tracked Starship source resolves outside its package: %s -> %s\n' \
			"$tracked" "$resolved_tracked" >&2
		exit 1
	fi

	diff_status=0
	diff -u -- "$packaged" "$target" || diff_status=$?
	if ((diff_status > 1)); then
		exit "$diff_status"
	fi

	read -r -p "Type BACKUP to approve this file's backup and removal: " answer
	if [[ $answer != BACKUP ]]; then
		printf 'No changes made.\n'
		exit 0
	fi
	if [[ ! -f $target || -L $target ]] ||
		[[ $(readlink -f -- "$target") != "$resolved_target" ]]; then
		printf 'Starship configuration changed before backup; leaving it in place.\n' >&2
		exit 1
	fi

	timestamp=$(date -u +%Y%m%dT%H%M%S.%NZ)
	backup=$state_home/dotfiles/backups/starship/$timestamp/.config/starship.toml
	resolved_state_home=$(readlink -m -- "$state_home")
	resolved_backup=$(readlink -m -- "$backup")
	if [[ $resolved_backup != "$resolved_state_home/"* ]]; then
		printf 'Backup resolves outside XDG state: %s -> %s\n' \
			"$backup" "$resolved_backup" >&2
		exit 1
	fi
	if [[ -e $backup || -L $backup ]]; then
		printf 'Backup path already exists: %s\n' "$backup" >&2
		exit 1
	fi

	mkdir -p -- "${backup%/*}"
	cp --archive -- "$target" "$backup"
	if [[ ! -f $backup || -L $backup ]] ||
		[[ $(readlink -f -- "$backup") != "$resolved_backup" ]]; then
		printf 'Backup is not the expected contained regular file: %s\n' "$backup" >&2
		exit 1
	fi
	cmp -s -- "$target" "$backup"
	printf 'Verified backup: %s\n' "$backup"

	if [[ ! -f $target || -L $target ]] ||
		[[ $(readlink -f -- "$target") != "$resolved_target" ]]; then
		printf 'Starship configuration changed before removal; leaving it in place.\n' >&2
		exit 1
	fi
	if ! cmp -s -- "$target" "$backup"; then
		printf 'Starship configuration changed after backup; leaving it in place.\n' >&2
		exit 1
	fi

	rm -- "$target"
	printf 'Removed only: %s\n' "$target"
)
```

After the verified backup and removal, immediately run the normal wizard apply:

```bash
make
```

Choose `Apply Stow packages` and select `starship`. Review the complete plan, including any Arch package install. The wizard repeats the simulation after an install, applies the leaf link, audits it, and runs the package validator. If apply fails, keep the verified backup and leave the tracked source unchanged.

Confirm the final link from the repository root:

```bash
(
	set -euo pipefail
	repo_root=$(readlink -f -- "$(git rev-parse --show-toplevel)")
	target=$HOME/.config/starship.toml
	tracked=$repo_root/config/starship/.config/starship.toml

	[[ -d $HOME/.config && ! -L $HOME/.config ]]
	[[ -L $target ]]
	[[ $(readlink -f -- "$target") == $(readlink -f -- "$tracked") ]]
)
```

Use `Package status` in the wizard to confirm that `starship` is `linked`.

## Strict validation

`Apply Stow packages` runs `starship print-config` against the active linked file. Each run uses a fresh isolated cache and a fixed session key. It fails when Starship returns nonzero or writes any byte to standard error. This matters because Starship 1.26.0 can report invalid TOML or values, fall back to defaults, and still return status 0.

An equivalent manual check is:

```bash
(
	set -euo pipefail
	work=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-starship-validator.XXXXXX")
	diagnostics=$work/stderr

	cleanup() {
		rm -rf -- "$work"
	}
	trap cleanup EXIT
	trap 'exit 1' HUP INT TERM

	export STARSHIP_CONFIG=$HOME/.config/starship.toml
	export STARSHIP_CACHE=$work/cache
	export STARSHIP_SESSION_KEY=dotfiles-starship-validation
	mkdir -p -- "$STARSHIP_CACHE"

	if ! starship print-config >/dev/null 2>"$diagnostics"; then
		cat -- "$diagnostics" >&2
		exit 1
	fi
	if [[ -s $diagnostics ]]; then
		cat -- "$diagnostics" >&2
		exit 1
	fi
)
```

## Controlled prompt tests

Computed-config validation does not prove prompt behavior or appearance. The focused suite runs real `starship prompt` and `starship module` commands in a fixed, isolated environment. It checks exact ANSI and glyph output for normal prompts, path handling, read-only directories, Git states, and one-file and multi-file counts. It checks the connected frame for success, failure, repository, deep-path, and read-only prompts. It also checks the branch icon in clean and dirty repositories. It checks synchronized, ahead, behind, diverged, and mixed file-state-plus-upstream branches using local Git refs. It verifies mixed staged and unstaged changes, mixed deleted and staged changes, and mixed renamed and deleted changes. It also checks one stash, multiple stashes, and mixed stash and rename state. Any Starship diagnostic fails the test.

The focused suite requires Starship 1.26.0:

```bash
bash tests/starship_test.sh
```

Run the complete suite with `make test`.

## Themes and named colors

The baseline uses named terminal `cyan`, not a fixed RGB value and not a tracked Omarchy theme value. Omarchy theme set, refresh, install, and switch operations change the terminal ANSI palette. The Starship config continues to emit `cyan`, while the terminal decides the displayed color from its current palette.

Theme operations remain outside this package and do not require a Starship config rewrite. The package does not track terminal palettes, theme files, or generated theme state.

## Omarchy updates and writes

After a normal Omarchy update, verify the active link, inspect any repository change, and compare the complete tracked replacement with the current packaged baseline:

```bash
readlink -f -- "$HOME/.config/starship.toml"
git diff -- config/starship/.config/starship.toml
diff -u -- \
	/usr/share/omarchy/config/starship.toml \
	config/starship/.config/starship.toml
```

The expected diff is limited to the global prompt `format`, the Git branch `symbol` and `format`, the Git status `format` and `up_to_date`, and the seven Git status marker settings above. Stop and investigate any other difference.

Review relevant new Omarchy migrations and hooks before accepting update-related behavior. Decide which packaged changes belong in the tracked replacement, then repeat strict validation and the focused prompt tests. When the repository changes its supported Omarchy target, also audit the new migration behavior and repeat the complete package lifecycle checks.

`omarchy refresh config starship.toml`, `omarchy reinstall configs`, and `omarchy reinstall` can follow the active Stow link and overwrite `config/starship/.config/starship.toml`. Do not use the focused refresh command as a local reset while the link exists. Never edit `/usr/share/omarchy/`.

Treat any write through the link as a proposed Git change. Inspect the diff, compare it with the current packaged baseline, decide what to keep, verify that the live link still resolves to the tracked source, and rerun strict validation and controlled prompt tests.

Before `omarchy reinstall configs` or `omarchy reinstall`, remove the `starship` Stow package unless you explicitly accept that the config-writing phase can overwrite the repository source. If an unlinked reinstall creates a regular live file, use [Existing regular target](#existing-regular-target) to reapply the package safely.

## Removal and retained data

Start `make`, choose `Remove Stow package`, and select `starship`. The wizard simulates the unlink, asks for confirmation, removes only the leaf link, verifies that `~/.config/starship.toml` is absent rather than dangling, and prints the cleanup notes. It does not run a refresh command or create a replacement config.

Removal retains:

- `config/starship/.config/starship.toml` in the repository
- The official Arch `starship` package
- Starship cache and state
- Every XDG-state migration or recovery backup
- Bash initialization, shells, terminal configuration, and Omarchy theme state

## Optional baseline restoration

After removal, you can restore an unmanaged copy of the current Omarchy baseline. This is optional and must run only while the Stow link and live path are absent:

```bash
(
	set -euo pipefail
	target=$HOME/.config/starship.toml
	packaged=/usr/share/omarchy/config/starship.toml

	if [[ -e $target || -L $target ]]; then
		printf 'Refusing to refresh an existing Starship path: %s\n' "$target" >&2
		exit 1
	fi
	if [[ ! -f $packaged ]]; then
		printf 'Packaged Omarchy Starship baseline is unavailable: %s\n' "$packaged" >&2
		exit 1
	fi

	omarchy refresh config starship.toml

	if [[ ! -f $target || -L $target ]]; then
		printf 'Expected refresh to create a regular file: %s\n' "$target" >&2
		exit 1
	fi
	home_root=$(readlink -f -- "$HOME")
	resolved_target=$(readlink -f -- "$target")
	if [[ $resolved_target != "$home_root/"* ]]; then
		printf 'Restored Starship configuration resolves outside HOME: %s -> %s\n' \
			"$target" "$resolved_target" >&2
		exit 1
	fi
	cmp -s -- "$packaged" "$target"
	printf 'Verified unmanaged Omarchy baseline: %s\n' "$target"
)
```

The restored path is a regular file, so a later apply reports a conflict. To reapply, follow [Existing regular target](#existing-regular-target) in full. That procedure compares and backs up the restored file before removing only the approved target and returning to the normal wizard apply. Do not use `Migrate existing target`, `stow --adopt`, or `omarchy refresh config starship.toml` while the Stow link exists.

## Clone relocation

Before moving the repository, use `Remove Stow package` from the old clone when possible. If the clone has already moved, inspect `~/.config/starship.toml`. Remove it as a stale link only after proving that it is a symlink to the exact source in the old clone. A regular file must instead use [Existing regular target](#existing-regular-target).

For an already stale link, set the old clone path and run:

```bash
old_clone=/absolute/path/to/old/dotfiles
(
	set -euo pipefail
	target=$HOME/.config/starship.toml
	old_root=$(readlink -m -- "$old_clone")
	expected=$(readlink -m -- "$old_root/config/starship/.config/starship.toml")

	resolve_live_link() {
		local value
		[[ -L $target ]] || return 1
		value=$(readlink -- "$target") || return 1
		if [[ $value == /* ]]; then
			readlink -m -- "$value"
		else
			readlink -m -- "${target%/*}/$value"
		fi
	}

	resolved_link=$(resolve_live_link) || {
		printf 'Expected a Starship symlink: %s\n' "$target" >&2
		exit 1
	}
	if [[ $resolved_link != "$expected" ]]; then
		printf 'Link does not point to the expected old source: %s -> %s\n' \
			"$target" "$resolved_link" >&2
		exit 1
	fi

	read -r -p "Type UNLINK to remove only this stale link: " answer
	if [[ $answer != UNLINK ]]; then
		printf 'No changes made.\n'
		exit 0
	fi

	current_link=$(resolve_live_link) || {
		printf 'Starship path changed before removal; leaving it in place.\n' >&2
		exit 1
	}
	if [[ $current_link != "$expected" ]]; then
		printf 'Starship link target changed before removal: %s -> %s\n' \
			"$target" "$current_link" >&2
		exit 1
	fi

	rm -- "$target"
	printf 'Removed only stale link: %s\n' "$target"
)
```

From the new repository root, start the wizard:

```bash
make
```

Choose `Apply Stow packages` and select `starship`. Review the simulation and complete plan. The normal `--no-folding` lifecycle Restows the package from the new clone and runs its link audit and validator. Then repeat the canonical link check and use `Package status` to confirm that `starship` is `linked`. The live link must resolve to `config/starship/.config/starship.toml` in the new clone.

## Further changes

The baseline checkpoint passed before Git counts were added. Review one further archived capability or presentation change at a time. Implement and test that change before selecting another.
