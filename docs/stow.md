[Back to README](../README.md)

# Stow workflow

A Stow package manages one application or one closely related configuration concern. Packages use lowercase names and live under `config/<name>/`. Each package directory has the same relative paths as its targets below the user's home directory.

GNU Stow links tracked files into the home directory. It does not copy them.

Package operations disable Stow directory folding when they create links. New parent paths stay as ordinary directories, and each tracked file gets its own link. A link created by an older version can stay folded until you remove and reapply its package.

## Start the Dotfiles wizard

```bash
make
```

The Dotfiles wizard has these Stow actions:

- `Guided setup`
- `Package status`
- `Run structural checks`
- `Apply Stow packages`
- `Migrate existing target`
- `Remove Stow package`
- `Prepare prerequisites`
- `Manage screensaver effects`

The wizard uses Gum when it is available. Otherwise, it uses Bash prompts.

`Manage screensaver effects` opens the selector for an applied `screensaver-effects` package. If the wizard finds another personal clone of `omarchy.idle` or `omarchy.indicators`, it also shows `Migrate competing screensaver clones`.

## Guided setup

`Guided setup` runs these phases in order:

1. Prerequisite preparation
2. Pinned global skill installation
3. Application cleanup
4. Stow package application
5. Wallpaper library deployment
6. Optional shared Brave policy application

Prerequisite preparation verifies GNU Stow, ImageMagick through `magick`, Node.js 22.20.0 or newer, npm, and npx. If a prerequisite is missing or does not meet its version requirement, the wizard shows one plan and asks for confirmation. Guided setup stops before later phases if you decline the plan, if installation fails, or if verification fails. This guide covers the Stow phase. See [Application cleanup](cleanup.md), [Agent setup](agent-setup.md), and [Brave](brave.md) for the other guided phases.

```text
omarchy pkg add stow
omarchy pkg add imagemagick
omarchy install dev-env node
```

Omarchy manages the privilege prompts. The wizard verifies the tools after installation.

The Stow phase shows one package multi-select screen. No package is selected by default. An empty selection skips the Stow phase. An operational failure stops Guided setup and names the standalone wizard action for recovery.

After the Stow phase, phase 5 calls the same operation as `Apply wallpapers`. A declined plan, an empty unowned Wallpaper library, and an exact deployment no-op are successful skips. An operational failure stops Guided setup and directs you to `Apply wallpapers` for recovery.

Phase 6 calls the same apply operation as `Manage Brave policy`. It skips successfully when no supported browser is installed or you decline the plan. It succeeds if the active policy already matches the shared Brave policy exactly or if the apply completes. An operational failure stops Guided setup and directs you to `Manage Brave policy` for recovery.

## Ownership

Prefer Omarchy-supported user overrides. Track a complete configuration only when an override cannot express the required behavior and a human has reviewed the replacement scope.

Packages target the user's home directory. A system target or another location requires a separate decision.

The shared Brave policy is a copied system file, not a Stow package. It does not live below `config/` and has no `packages.json` entry. `Manage Brave policy` uses a separate preview, confirmation, backup, verification, recovery, and removal process for its root-owned system copy. See [Brave](brave.md).

The Wallpaper library is also outside Stow. Git tracks source assignments under `wallpapers/library/`; `Apply wallpapers` creates receipt-owned regular files under `~/.config/omarchy/backgrounds/`. The operation preserves unrelated backgrounds and Omarchy theme state.

The `screensaver-effects` package owns its allowlist, canonical plugin clone sources, launcher, runtime shim, and selector through Stow. Its lifecycle creates two complete live plugin-directory symlinks and manages only the `system.screensaver` entry that it inserted into the shared Omarchy menu extension. It does not own `shell.json`, the complete menu extension, Stay Awake state, lifecycle receipts, migration backups, diagnostics, preview state, or live plugin links through Stow.

Stop before adding machine-specific values, generated files, or sensitive data. Decide how to handle the concrete case first.

## Package status

Choose `Package status` to inspect all packages in the package catalog. The wizard reports each package as linked, absent, conflicting, or invalid.

This action does not require GNU Stow.

For `screensaver-effects`, Package status also reports the lifecycle as `active`, `inactive`, `drifted`, `conflicting`, or `recovery-required`. Use the printed standalone action before another mutation when the lifecycle is not active or inactive.

## Structural checks

Choose `Run structural checks` to validate:

- The package catalog and package directories
- Package documentation links
- Package dependencies
- Package prerequisites and validator executables
- Package-specific Arch requirements
- The application cleanup profile
- The skill manifest and required global skill commands
- The canonical shared Brave policy source
- ImageMagick and the Wallpaper library
- GNU Stow availability
- The complete screensaver package inventory, copied Omarchy plugin baselines, host seams, allowlist, effect mappings, executable modes, and lifecycle ownership boundaries

`Run structural checks` can run without GNU Stow, but it reports a structural error if GNU Stow is missing. It does not require an installed browser. It requires Node.js and npx. Brave source validation does not require a deployed policy or privilege and does not change system or user files.

## Apply Stow packages

Choose `Apply Stow packages`. The wizard shows one multi-select screen with no packages selected by default.

For a nonempty selection, the wizard:

1. Validates the package catalog.
2. Reports the supported and detected Omarchy versions.
3. Checks GNU Stow.
4. Resolves package dependencies.
5. Checks package prerequisites, validator executables, and Arch package requirements.
6. Simulates all Stow operations.
7. Shows the complete plan in dependency order, including missing Arch packages.
8. Asks for confirmation.
9. Installs and verifies missing Arch packages.
10. If it installed an Arch package, repeats all Stow simulations.
11. Applies and verifies each package in dependency order.

The plan identifies selected packages and required dependencies. Existing normal files cause a conflict. The wizard does not replace them and does not use `stow --adopt`.

Package-specific Arch requirements are part of the Stow plan and use the same confirmation. The wizard installs missing packages with `omarchy pkg add`, verifies them, and repeats the Stow simulation before it changes links.

After Stow links and validators pass for `screensaver-effects`, the package lifecycle publishes both complete live plugin links. It performs one plugin rescan when needed, preserves the existing Indicators position and options, enables the idle clone, and adds the managed System-menu action. An exact repeated Apply is a no-op. Another idle or Indicators clone blocks normal Apply and directs recovery to `Migrate competing screensaver clones`.

An empty selection or a declined plan makes no changes.

## Pre-existing tmux configuration

The `tmux` package contains the complete tracked configuration at `config/tmux/.config/tmux/tmux.conf`. A pre-existing `~/.config/tmux/tmux.conf` is recovery data, not a source to import into the package.

A normal apply reports the existing file as a conflict and leaves it unchanged. `Migrate existing target` also refuses it because the package destination already exists. Do not use `stow --adopt`.

Run this preflight from the repository root before the backup and removal block:

```bash
make
```

Choose `Run structural checks`. It may report one or more of `tmux`, `fzf`, and `less` as missing declared Arch packages for `tmux`. Record each missing package as a planned wizard install under `Apply Stow packages`. Continue only if those are the only structural errors and the supported and detected Omarchy versions match. Any other structural error or Omarchy version mismatch stops this procedure.

Run the wizard again:

```bash
make
```

Choose `Package status`. It must report no `conflicting` or `invalid` package except `tmux`, which is expected to be `conflicting` only because `~/.config/tmux/tmux.conf` is an existing regular file. Stop on any other unexpected package state.

Then print the current requirement plan and run the complete Stow simulation from the repository root:

```bash
(
	for package in tmux fzf less; do
		if omarchy pkg present "$package"; then
			printf '%s: installed\n' "$package"
		else
			printf '%s: will install during Apply Stow packages\n' "$package"
		fi
	done

	if ! command -v stow >/dev/null 2>&1; then
		printf '%s\n' 'GNU Stow is missing. Run make, choose Prepare prerequisites, then restart this preflight.' >&2
		exit 1
	fi

	stow --no-folding --simulate --verbose=2 --dir "$PWD/config" --target "$HOME" tmux
)
```

Each runtime package prints either `installed` or `will install during Apply Stow packages`. A planned install does not stop this preflight. GNU Stow must be present for the simulation. If GNU Stow is missing, run `make`, choose `Prepare prerequisites`, and restart this preflight before backup or removal.

The Stow simulation is expected to return nonzero. Its output must show exactly one conflict: `~/.config/tmux/tmux.conf`. Every other target in the `tmux` package must already be linked to its tracked source or otherwise be conflict-free. Any additional Stow conflict stops this procedure before backup or removal.

The complete direct-migration plan is to inspect and back up the live file, verify the backup, remove only that file, and immediately choose `Apply Stow packages` for `tmux`. After removal clears the known Stow conflict, the wizard simulates the package and shows the complete plan. The plan must show that the wizard will install and verify every requirement marked `will install during Apply Stow packages`, repeat the simulation after any installation, apply the package with `--no-folding`, and verify all three links and the validators. Continue only after reviewing this full plan and deciding to apply it immediately. This procedure applies only to the tmux target described here.

The following tmux-specific preparation accepts only a regular file that is not a symlink and resolves inside the user's home directory. It shows the file and its difference from the packaged Omarchy baseline, requires explicit confirmation, writes and verifies a timestamped XDG-state backup, rechecks the source, and removes only the active file.

```bash
(
	set -euo pipefail

	target=$HOME/.config/tmux/tmux.conf
	state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
	packaged=/usr/share/omarchy/config/tmux/tmux.conf

	if [[ $state_home != /* ]]; then
		printf 'XDG_STATE_HOME must be an absolute path: %s\n' "$state_home" >&2
		exit 1
	fi
	if [[ ! -f $target || -L $target ]]; then
		printf 'Expected a regular file that is not a symlink: %s\n' "$target" >&2
		exit 1
	fi
	if [[ ! -f $packaged ]]; then
		printf 'Packaged Omarchy tmux baseline is unavailable: %s\n' "$packaged" >&2
		exit 1
	fi

	home_root=$(readlink -f -- "$HOME")
	resolved_target=$(readlink -f -- "$target")
	if [[ $resolved_target != "$home_root/"* ]]; then
		printf 'Tmux configuration resolves outside HOME: %s -> %s\n' \
			"$target" "$resolved_target" >&2
		exit 1
	fi

	cat -- "$target"
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

	timestamp=$(date -u +%Y%m%dT%H%M%S.%NZ)
	backup=$state_home/dotfiles/backups/tmux/$timestamp/.config/tmux/tmux.conf
	mkdir -p -- "${backup%/*}"
	cp --archive -- "$target" "$backup"
	cmp -s -- "$target" "$backup"
	printf 'Verified backup: %s\n' "$backup"

	if [[ ! -f $target || -L $target ]] ||
		[[ $(readlink -f -- "$target") != "$resolved_target" ]]; then
		printf 'Tmux configuration changed before removal; leaving it in place.\n' >&2
		exit 1
	fi
	cmp -s -- "$target" "$backup"
	rm -- "$target"
	printf 'Removed only: %s\n' "$target"
)
```

After the verified backup and removal, run the existing wizard and choose `Apply Stow packages`, then select `tmux`:

```bash
make
```

The package operation plans the official Arch requirements, simulates the leaf links, asks for confirmation, applies them, and runs the package validators. Its Stow operations use these forms from the repository root:

```bash
stow --no-folding --simulate --verbose=2 --dir "$PWD/config" --target "$HOME" tmux
stow --no-folding --verbose=2 --dir "$PWD/config" --target "$HOME" tmux
```

If Omarchy installs a missing Arch package, the wizard repeats the simulation before it changes links. A failure after removal leaves the verified backup available for recovery. Do not move the old live contents into the tracked tmux package.

## Migrate an existing target

Choose `Migrate existing target`, select a package, and enter the `Home-relative target path`.

Do not use generic target migration for `screensaver-effects`. When competing idle or Indicators clones are present, use `Migrate competing screensaver clones`. This operation records the prior activation state, stores complete clone backups below the lifecycle XDG state directory, and restores the prior state if migration fails.

Migration accepts one existing regular file below the user's home directory. Inspect the file for credentials, account data, machine-specific values, and generated content before approval.

The wizard:

1. Confirms that the target resolves inside the user's home directory.
2. Confirms that the package destination resolves inside the selected package.
3. Resolves dependencies and checks prerequisites, validators, Arch package requirements, and GNU Stow.
4. Simulates the selected package and all required dependencies.
5. Shows the complete migration plan, including missing Arch packages, and asks for approval.
6. Asks if the file was inspected for sensitive and machine-specific content.
7. Installs and verifies missing Arch packages.
8. If it installed an Arch package, repeats the Stow simulation for the selected package and all required dependencies.
9. Applies required dependency packages before it changes the selected target.
10. Checks the selected target, package destination, and path containment again.
11. Creates a timestamped backup below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/<package>/`.
12. Moves the approved file into the selected package without replacing package content.
13. Simulates the selected package again.
14. Applies the selected package and verifies its links and validators.

Migration installs and verifies missing Arch packages before it applies dependency links, creates a backup, or moves the selected target. If installation fails, the selected target stays unchanged.

Migration does not use `stow --adopt`. If a failure occurs after the backup or move, the wizard prints the backup path and recovery commands. A dependency failure can leave an earlier dependency linked, but it leaves the selected migration target unchanged and does not create its backup.

## Remove a Stow package

Choose `Remove Stow package` and select one package.

The wizard blocks removal when another linked package depends on the selected package. It names each dependent package.

For an allowed removal, the wizard:

1. Simulates the unlink operation.
2. Shows the package links and cleanup notes.
3. Asks for confirmation.
4. Unlinks the package.
5. Verifies that all managed targets are gone.

Removing a Stow package leaves its Arch packages installed. The cleanup notes list the retained packages.

Removing `screensaver-effects` deactivates its lifecycle before Stow unlinks the package. It restores the prior idle and Indicators state, removes only an unchanged receipt-owned System-menu entry, and removes both live plugin links. Receipts, migration backups, diagnostics, successfully migrated old clones, and the `ttfx`, `jq`, and `socat` packages remain.

Removal does not delete generated files, application state, migration backups, or other paths in the package cleanup notes.

## Package catalog

The root `packages.json` file stores each package's:

- Name and description
- Path below `config/`
- Prerequisites
- Arch packages installed through Omarchy
- Dependencies
- Validation commands
- Optional documentation link
- Cleanup notes

The wizard applies dependencies before dependent packages. A linked dependent blocks removal of a package that it requires.

## Verification and recovery

An Omarchy version mismatch requires separate confirmation before most mutations. The `screensaver-effects` lifecycle is the exception. It reports supported and detected Omarchy and `ttfx` versions, warns on a mismatch, and continues when source, command, ownership, mapping, and lifecycle validation pass.

Successful application or migration means that each expected target points to its tracked source, each validator passes, and each declared Arch package is installed. Successful removal means that all managed targets are unlinked.

A package batch stops on the first failed package. Packages that passed verification earlier in the batch stay applied. Follow the printed recovery instructions. Then run `make` and choose the named standalone action.

If the repository moves, repair or remove links from the old path and apply the affected packages again.

## Package-specific installers

A package may include a Bash installer when setup needs more than a documented command. The installer must resolve the repository without assuming a clone path, preview its actions, request confirmation, tolerate repeated execution, and verify the result.

When elevated privileges are required, call the supported Omarchy command and let Omarchy manage the prompt.
