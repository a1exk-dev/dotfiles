[Back to README](../README.md)

# btop

The `btop` Stow package owns one leaf target:

- `~/.config/btop/btop.conf`, linked from `config/btop/.config/btop/btop.conf`

The tracked file is a complete replacement for the active btop configuration. It contains all btop 1.4.7 settings, retains Omarchy 4 behavior, and selects the CPU sensor for the ASUS Zenbook S16 UM5606GA.

Keep `/usr/share/omarchy/config/btop/btop.conf` read-only.

The package does not own:

- `~/.config/btop/themes/current.theme`
- Omarchy theme state below `~/.local/state/omarchy/current/theme/`
- `~/.local/state/btop.log` or other btop runtime state
- Existing btop backups
- Dotfiles migration backups
- Files below `/usr/share/omarchy/`

See [Stow workflow](stow.md) for the shared Stow package lifecycle.

## Requirements

The package supports Omarchy 4 and btop 1.4.7.

It declares the official Arch `btop` package. If btop is missing, the Dotfiles wizard includes it in the complete Stow plan, installs it through Omarchy after confirmation, and verifies the installation.

The selected CPU sensor requires these readable paths:

- `/sys/class/thermal/thermal_zone1/device/path`
- `/sys/class/thermal/thermal_zone1/type`
- `/sys/class/thermal/thermal_zone1/temp`

They must report the ACPI path `\_TZ_.THRM`, the thermal type `acpitz`, and a numeric temperature. This layout matches the ASUS Zenbook S16 UM5606GA.

Before applying the package, run this read-only check:

```bash
(
	set -euo pipefail

	zone=/sys/class/thermal/thermal_zone1

	for file in device/path type temp; do
		if [[ ! -r "$zone/$file" ]]; then
			printf 'Required btop CPU sensor input is not readable: %s\n' \
				"$zone/$file" >&2
			exit 1
		fi
	done

	IFS= read -r identity < "$zone/device/path"
	IFS= read -r type < "$zone/type"
	IFS= read -r temp < "$zone/temp"

	if [[ $identity != '\_TZ_.THRM' ]]; then
		printf 'Expected ACPI THRM at thermal_zone1, found: %s\n' \
			"$identity" >&2
		exit 1
	fi
	if [[ $type != acpitz ]]; then
		printf 'Expected acpitz at thermal_zone1, found: %s\n' \
			"$type" >&2
		exit 1
	fi
	if [[ ! $temp =~ ^-?[0-9]+$ ]]; then
		printf 'Expected a numeric temperature at thermal_zone1, found: %s\n' \
			"$temp" >&2
		exit 1
	fi

	printf 'Verified btop CPU sensor mapping: thermal1/acpitz -> %s (%s, %s)\n' \
		"$identity" "$type" "$temp"
)
```

This check does not write any file. Stop if it fails.

## Configuration

The tracked file contains all 88 settings recognized by btop 1.4.7. Four values differ from the compiled defaults:

- `color_theme = "current"` retains Omarchy theme integration.
- `vim_keys = true` retains Omarchy's Vim-style controls.
- `cpu_sensor = "thermal1/acpitz"` selects this machine's ACPI THRM sensor.
- `shown_gpus = "nvidia amd intel"` retains Omarchy's GPU vendor selection.

All other values match the btop 1.4.7 compiled defaults.

The config retains the full four-box layout:

```ini
shown_boxes = "cpu mem net proc"
```

It also lets btop save settings when it exits:

```ini
save_config_on_exit = true
```

Omarchy continues to manage `~/.config/btop/themes/current.theme`. A theme change updates Omarchy theme state and tells btop to reload the theme. This Stow package does not track the theme files.

## CPU temperature

With `cpu_sensor = "Auto"`, btop reports that it cannot find a good CPU sensor and uses another detected sensor. On this machine, it selects the ACPI `TZ01` zone, which stays at 20 C.

The tracked config selects:

```ini
cpu_sensor = "thermal1/acpitz"
```

On this machine, `thermal1/acpitz` maps to Linux thermal zone 1 and the ACPI path `\_TZ_.THRM`. Linux associates this zone with processor cooling devices.

THRM is a processor-associated ACPI thermal proxy, not a native AMD CPU package-temperature sensor. This machine does not expose a `k10temp` hwmon device. Do not treat the THRM reading as the true CPU package temperature.

Thermal-zone numbers and meanings are machine-specific. Do not apply this package to another machine unless its sensor mapping meets the requirements above.

## Before link changes

Exit every running btop process before you apply, replace, or remove this package.

Because `save_config_on_exit = true`, a running process can write its old settings through a new Stow link. It can also recreate `~/.config/btop/btop.conf` after removal.

## Apply

Complete the read-only hardware check in [Requirements](#requirements), then start the Dotfiles wizard:

```bash
make
```

Choose `Apply Stow packages` and select `btop`.

The package is optional and is never selected by default. This also applies to the Stow package phase in `Guided setup`.

The wizard checks the supported Omarchy version, plans the official Arch `btop` requirement, and simulates the leaf link. It then shows the complete plan and asks for confirmation. If it installs btop, it verifies the installation and repeats the Stow simulation before changing any links.

Stow creates the link before the package validators run. The wizard audits the link, then runs the config and hardware validators. The hardware validator is not a pre-link gate.

If the hardware validator rejects the machine, apply fails during verification and leaves the `btop` package linked. Run `make`, choose `Remove Stow package`, and select `btop` to remove the link.

## Existing config and migration

A normal clone already contains:

```text
config/btop/.config/btop/btop.conf
```

If `~/.config/btop/btop.conf` is an unmanaged regular file, a normal apply reports a conflict and leaves the file unchanged.

`Migrate existing target` also refuses this target because the Stow package destination already exists. Do not use `stow --adopt`.

The procedure below replaces only that existing regular file. Run every command from the repository root.

First, exit every running btop process and complete the read-only hardware check in [Requirements](#requirements). Stop if the hardware check fails.

Start the Dotfiles wizard:

```bash
make
```

Choose `Run structural checks`. Continue only if the supported and detected Omarchy versions match. Fix every structural error before continuing, except a missing declared Arch `btop` package, which the normal apply plan can install. If GNU Stow is missing, run `make`, choose `Prepare prerequisites`, and restart this procedure before the direct simulation.

Start the wizard again:

```bash
make
```

Choose `Package status`. The `btop` package must be `conflicting` only because `~/.config/btop/btop.conf` is an unmanaged regular file. No package can be `invalid`, and no other package can have an unexpected conflict. Stop if the status has another result.

Run the complete Stow simulation:

```bash
repo_root=$(readlink -f -- "$(git rev-parse --show-toplevel)")
stow --no-folding --simulate --verbose=2 \
	--dir "$repo_root/config" --target "$HOME" btop
```

The simulation is expected to return nonzero. It must identify exactly one conflicting target, `.config/btop/btop.conf`, and abort all operations. Stow can name the same target during planning and again in its conflict summary. Stop if it names another target or does not abort because of the expected conflict.

The following block checks the canonical home and repository boundaries before it changes the live file. It accepts only a regular target that is not a symlink and a regular tracked source inside the `btop` Stow package. It prints the live config and its difference from the tracked config for inspection. After approval, it creates and byte-verifies a timestamped XDG-state backup, checks both files again, and removes only the approved live file.

```bash
(
	set -euo pipefail

	repo_root=$(readlink -f -- "$(git rev-parse --show-toplevel)")
	home_root=$(readlink -f -- "$HOME")
	target=$HOME/.config/btop/btop.conf
	package_root=$repo_root/config/btop
	tracked=$package_root/.config/btop/btop.conf
	state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}

	if [[ $state_home != /* ]]; then
		printf 'XDG_STATE_HOME must be an absolute path: %s\n' \
			"$state_home" >&2
		exit 1
	fi
	if [[ ! -d $home_root || ! -d $repo_root ]]; then
		printf 'Expected canonical home and repository directories.\n' >&2
		exit 1
	fi
	if [[ ! -d $package_root || -L $package_root ]]; then
		printf 'Expected the btop package directory: %s\n' \
			"$package_root" >&2
		exit 1
	fi
	if [[ ! -f $target || -L $target ]]; then
		printf 'Expected a regular file that is not a symlink: %s\n' \
			"$target" >&2
		exit 1
	fi
	if [[ ! -f $tracked || -L $tracked ]]; then
		printf 'Expected the tracked btop source: %s\n' \
			"$tracked" >&2
		exit 1
	fi

	resolved_package_root=$(readlink -f -- "$package_root")
	resolved_target=$(readlink -f -- "$target")
	resolved_tracked=$(readlink -f -- "$tracked")

	if [[ $resolved_package_root != "$repo_root/config/btop" ]]; then
		printf 'btop package resolves outside the expected repository path: %s -> %s\n' \
			"$package_root" "$resolved_package_root" >&2
		exit 1
	fi
	if [[ $resolved_target != "$home_root/"* ]]; then
		printf 'btop configuration resolves outside HOME: %s -> %s\n' \
			"$target" "$resolved_target" >&2
		exit 1
	fi
	if [[ $resolved_tracked != "$resolved_package_root/"* ]]; then
		printf 'Tracked btop source resolves outside its package: %s -> %s\n' \
			"$tracked" "$resolved_tracked" >&2
		exit 1
	fi

	printf 'Canonical HOME: %s\n' "$home_root"
	printf 'Canonical repository: %s\n' "$repo_root"
	printf 'Verified live target: %s -> %s\n' "$target" "$resolved_target"
	printf 'Verified tracked source: %s -> %s\n' "$tracked" "$resolved_tracked"

	target_identity=$(stat -c '%d:%i' -- "$target")
	tracked_identity=$(stat -c '%d:%i' -- "$tracked")

	if ! target_digest=$(sha256sum -- "$target"); then
		printf 'Failed to calculate btop configuration digest at inspection: %s\n' \
			"$target" >&2
		exit 1
	fi
	if ! tracked_digest=$(sha256sum -- "$tracked"); then
		printf 'Failed to calculate tracked btop source digest at inspection: %s\n' \
			"$tracked" >&2
		exit 1
	fi

	printf '\nExisting btop config:\n'
	cat -- "$target"

	printf '\nDifference from the tracked btop config:\n'
	diff_status=0
	diff -u -- "$tracked" "$target" || diff_status=$?
	if ((diff_status > 1)); then
		exit "$diff_status"
	fi

	read -r -p "Type BACKUP after you inspect this file and approve its backup and removal: " answer
	if [[ $answer != BACKUP ]]; then
		printf 'No changes made.\n'
		exit 0
	fi

	if [[ ! -f $target || -L $target ]] ||
		[[ $(readlink -f -- "$target") != "$resolved_target" ]] ||
		[[ $(stat -c '%d:%i' -- "$target") != "$target_identity" ]]; then
		printf 'btop configuration changed before backup; leaving it in place.\n' >&2
		exit 1
	fi
	if ! current_target_digest=$(sha256sum -- "$target"); then
		printf 'Failed to calculate btop configuration digest before backup: %s\n' \
			"$target" >&2
		exit 1
	fi
	if [[ "$current_target_digest" != "$target_digest" ]]; then
		printf 'btop configuration content changed before backup; leaving it in place.\n' >&2
		exit 1
	fi

	if [[ ! -f $tracked || -L $tracked ]] ||
		[[ $(readlink -f -- "$tracked") != "$resolved_tracked" ]] ||
		[[ $(stat -c '%d:%i' -- "$tracked") != "$tracked_identity" ]]; then
		printf 'Tracked btop source changed before backup; leaving the live file in place.\n' >&2
		exit 1
	fi
	if ! current_tracked_digest=$(sha256sum -- "$tracked"); then
		printf 'Failed to calculate tracked btop source digest before backup: %s\n' \
			"$tracked" >&2
		exit 1
	fi
	if [[ "$current_tracked_digest" != "$tracked_digest" ]]; then
		printf 'Tracked btop source content changed before backup; leaving the live file in place.\n' >&2
		exit 1
	fi

	timestamp=$(date -u +%Y%m%dT%H%M%S.%NZ)
	backup=$state_home/dotfiles/backups/btop/$timestamp/.config/btop/btop.conf
	resolved_state_home=$(readlink -m -- "$state_home")
	resolved_backup=$(readlink -m -- "$backup")

	if [[ $resolved_backup != "$resolved_state_home/"* ]]; then
		printf 'Backup resolves outside XDG state: %s -> %s\n' \
			"$backup" "$resolved_backup" >&2
		exit 1
	fi
	if [[ $resolved_backup == "$repo_root" ||
		$resolved_backup == "$repo_root/"* ]]; then
		printf 'Backup resolves inside the Git repository: %s -> %s\n' \
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
		printf 'Backup is not the expected contained regular file: %s\n' \
			"$backup" >&2
		exit 1
	fi
	if ! cmp -s -- "$target" "$backup"; then
		printf 'Backup does not match the btop configuration: %s\n' \
			"$backup" >&2
		exit 1
	fi
	printf 'Verified backup: %s\n' "$backup"

	if [[ ! -f $target || -L $target ]] ||
		[[ $(readlink -f -- "$target") != "$resolved_target" ]] ||
		[[ $(stat -c '%d:%i' -- "$target") != "$target_identity" ]]; then
		printf 'btop configuration changed before removal; leaving it in place.\n' >&2
		exit 1
	fi
	if ! current_target_digest=$(sha256sum -- "$target"); then
		printf 'Failed to calculate btop configuration digest before removal: %s\n' \
			"$target" >&2
		exit 1
	fi
	if [[ "$current_target_digest" != "$target_digest" ]]; then
		printf 'btop configuration content changed before removal; leaving it in place.\n' >&2
		exit 1
	fi

	if [[ ! -f $tracked || -L $tracked ]] ||
		[[ $(readlink -f -- "$tracked") != "$resolved_tracked" ]] ||
		[[ $(stat -c '%d:%i' -- "$tracked") != "$tracked_identity" ]]; then
		printf 'Tracked btop source changed before removal; leaving the live file in place.\n' >&2
		exit 1
	fi
	if ! current_tracked_digest=$(sha256sum -- "$tracked"); then
		printf 'Failed to calculate tracked btop source digest before removal: %s\n' \
			"$tracked" >&2
		exit 1
	fi
	if [[ "$current_tracked_digest" != "$tracked_digest" ]]; then
		printf 'Tracked btop source content changed before removal; leaving the live file in place.\n' >&2
		exit 1
	fi

	if ! cmp -s -- "$target" "$backup"; then
		printf 'btop configuration changed after backup; leaving it in place.\n' >&2
		exit 1
	fi

	rm -- "$target"
	if [[ -e $target || -L $target ]]; then
		printf 'Failed to remove only the approved btop configuration: %s\n' \
			"$target" >&2
		exit 1
	fi

	printf 'Removed only: %s\n' "$target"
	printf 'Retained verified backup: %s\n' "$backup"
)
```

After the verified backup and removal, immediately start the Dotfiles wizard:

```bash
make
```

Choose `Apply Stow packages` and select `btop`. Review and confirm the complete plan. The wizard repeats the Stow simulation, applies and audits the leaf link, then runs the config and hardware validators.

If apply fails, keep the verified backup and follow the recovery instructions from the wizard. If the hardware validator fails, the package remains linked until you remove it with `Remove Stow package`.

## Verification

Choose `Package status` in the Dotfiles wizard. It must report `btop` as `linked`.

From the repository root, verify the leaf link and btop version:

```bash
repo_root=$(git rev-parse --show-toplevel)
target=$HOME/.config/btop/btop.conf
source=$repo_root/config/btop/.config/btop/btop.conf

[[ -L $target ]]
[[ $(readlink -f -- "$target") == $(readlink -f -- "$source") ]]
btop --version
```

The version command must report btop 1.4.7.

Check the selected thermal zone:

```bash
zone=/sys/class/thermal/thermal_zone1
cat -- "$zone/device/path"
cat -- "$zone/type"
cat -- "$zone/temp"
```

The first two commands must print:

```text
\_TZ_.THRM
acpitz
```

The temperature must be an integer in millidegrees Celsius.

Start btop. Confirm that its CPU sensor is `thermal1/acpitz` and that the displayed temperature follows THRM instead of the static TZ01 reading.

The focused test suite requires btop 1.4.7 because it compares the tracked config with `btop --default-config`:

```bash
bash tests/btop_test.sh
```

Run the complete test suite with:

```bash
make test
```

## Config writes and Omarchy updates

Because `save_config_on_exit = true`, btop can rewrite the complete config when it exits. The active config is a Stow link, so the write changes this tracked source:

```text
config/btop/.config/btop/btop.conf
```

Review the Git diff after changing btop options or finding an unexpected config write:

```bash
git diff -- config/btop/.config/btop/btop.conf
```

Treat the diff as a proposed Git change. Decide which settings to keep, then run the package validators and focused tests again.

Omarchy refresh, migration, update, and reinstall operations can also follow the Stow link and overwrite the tracked source. Compare any resulting change with the packaged Omarchy baseline:

```bash
diff -u -- \
	/usr/share/omarchy/config/btop/btop.conf \
	config/btop/.config/btop/btop.conf || true
```

Omarchy 4's packaged file uses an older btop schema. The expected semantic difference is the selected CPU sensor. The tracked file also contains the settings added by btop 1.4.7.

Do not use this command as a local reset while the Stow package is linked:

```bash
omarchy refresh config btop/btop.conf
```

Before running `omarchy reinstall configs` or `omarchy reinstall`, remove the `btop` Stow package. Keep it linked only if you explicitly accept that Omarchy can overwrite the tracked source.

## Removal

Exit every running btop process, then start the Dotfiles wizard:

```bash
make
```

Choose `Remove Stow package` and select `btop`.

The wizard simulates the unlink operation, shows the managed link and cleanup notes, and asks for confirmation. It then removes the leaf link and verifies that the managed target is absent.

Removal leaves:

- `config/btop/.config/btop/btop.conf` in the Dotfiles repository
- The official Arch `btop` package
- btop themes below `~/.config/btop/themes/`
- `~/.local/state/btop.log` and other btop runtime state
- Existing btop backups
- Dotfiles migration backups below the XDG state backup tree

The Dotfiles wizard reports the optional baseline restoration command but does not run it.

## Restore the Omarchy baseline

Restore the baseline only after removing the `btop` Stow package.

First confirm that the Stow link and live path are absent:

```bash
target=$HOME/.config/btop/btop.conf

[[ ! -e $target && ! -L $target ]]
omarchy refresh config btop/btop.conf
[[ -f $target && ! -L $target ]]
```

This command creates an unmanaged regular copy of the current Omarchy baseline.

The restored baseline uses automatic CPU sensor selection. On this machine, that restores the static TZ01 reading.

A later Stow package apply reports the restored regular file as a conflict. Follow [Existing config and migration](#existing-config-and-migration) before applying the package again.
