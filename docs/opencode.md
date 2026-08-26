[Back to README](../README.md)

# OpenCode

The `opencode` Stow package owns the complete global OpenCode runtime and TUI settings. It owns exactly two leaf managed targets:

- `~/.config/opencode/opencode.json`, linked to the tracked source at `config/opencode/.config/opencode/opencode.json`
- `~/.config/opencode/tui.json`, linked to the tracked source at `config/opencode/.config/opencode/tui.json`

`~/.config/opencode/` stays an ordinary directory. OpenCode can create excluded sibling files in this directory.

The package uses native OpenCode. It declares no external plugin and no global LSP policy.

## Requirements

The package supports Omarchy 4. It requires the `opencode` command from Omarchy's Mise flow. The package does not install an Arch package, install or update a Mise tool, or run `opencode upgrade`.

Check the requirement before you apply or migrate the package:

```bash
omarchy version
command -v mise
command -v opencode
mise current opencode
opencode --version
```

The Omarchy major version must be 4. Mise must report an active OpenCode installation. If the OpenCode wrapper is absent, restore it through Omarchy. Then run the checks again:

```bash
omarchy-mise-install opencode
opencode --version
```

The package contract was verified with OpenCode 1.18.23. The Mise wrapper can update OpenCode without a change to this Stow package. Run the package validator after an OpenCode update.

## Settings

The `opencode.json` tracked source contains this complete object:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false
}
```

The `tui.json` tracked source contains this complete object:

```json
{
  "$schema": "https://opencode.ai/tui.json",
  "theme": "system"
}
```

Neither object has a `plugin` field or a global `lsp` field. Built-in language server integrations stay disabled unless another OpenCode configuration layer enables them. This package does not select, install, update, validate, or remove language servers or external plugins. Another OpenCode layer can own them.

## Native skills

OpenCode uses native Agent Skills. The Dotfiles wizard installs global skills below `~/.agents/skills/` in a separate operation. The `opencode` Stow package does not own or require those files.

After installing or updating global skills, restart OpenCode. In the TUI:

- Use `/skills` to list available skills.
- Use `/<skill-name>` to invoke a skill directly.

The package does not add the deprecated `opencode-skills` plugin. It does not add a command bridge or Claude-style top-level skill listing.

## Ownership boundary

The Stow package does not own these generated files and directories:

- `opencode.json.tui-migration.bak`
- `.gitignore`, `package.json`, `package-lock.json`, and `bun.lock`
- `node_modules/`, generated themes, and downloaded dependencies
- Global `plugin/` and `plugins/` directories

It also excludes provider and MCP credentials, account data, databases, sessions, prompt history, model choices, logs, snapshots, tool output, repository mirrors, worktrees, plans, locks, plugin metadata, caches, downloaded binaries, language servers, toolchains, and temporary files. OpenCode owns this data below its XDG data, state, and cache roots.

The package also excludes the Mise-managed executable, the Omarchy wrapper and packaged baseline, global skill sources, and XDG state backups.

## Competing settings

Other OpenCode layers can supplement or override the two managed targets. Check these layers before migration and reapplication:

- Global `config.json`, `opencode.jsonc`, `tui.jsonc`, `plugin/`, and `plugins/` paths
- `~/.opencode/` and custom OpenCode config paths
- Relevant `OPENCODE_*` environment variables
- Remote and account configuration
- Managed settings below `/etc/opencode/`
- Project `opencode.json`, `tui.json`, `.opencode/`, `.agents/`, and `.claude/` content

Resolve an unexpected global conflict before you continue. Keep project settings when their precedence is intentional.

## Apply without existing targets

Quit every OpenCode TUI, server, desktop sidecar, and other process that can read or write settings. Keep OpenCode stopped until both managed targets are linked and the package validator passes.

Start the Dotfiles wizard:

```bash
make
```

Choose `Apply Stow packages` and select `opencode`. The wizard checks Omarchy and OpenCode, simulates two leaf links with `--no-folding`, asks for confirmation, links both managed targets, and runs the package validator.

Use [Verification](#verification), then restart OpenCode once.

## Existing regular settings

Use this procedure only when both managed targets are regular files and are not symlinks. The procedure backs up and removes the pair before it starts the normal `Apply Stow packages` operation. Do not use `Migrate existing target` or `stow --adopt`. Both tracked sources already exist, and `Migrate existing target` handles one target at a time.

The procedure does not adopt either managed target. Each managed target must match its tracked source byte for byte. Stop for human review if a file differs.

### Stop and inspect

Quit every OpenCode process. Keep OpenCode stopped during preflight, backup, removal, apply, validation, and recovery.

Inspect both managed targets in a local editor. Check for credentials, tokens, account identifiers, provider or MCP secrets, machine-specific values, generated content, and plugin settings. Do not print sensitive content to a terminal log. Stop if either file contains data that must not enter Git.

Inspect the layers in [Competing settings](#competing-settings). Review the values of relevant `OPENCODE_*` variables without printing secrets.

### Preflight

From the repository root, start the wizard and choose `Run structural checks`:

```bash
make
```

Continue only when the supported and detected Omarchy major versions are 4 and all structural checks pass. If OpenCode is absent, run `omarchy-mise-install opencode`. Verify it with `mise current opencode` and `opencode --version`, then repeat the structural checks.

Start the wizard again and choose `Package status`. The `opencode` package must be `conflicting` only because these managed targets are regular files:

```text
~/.config/opencode/opencode.json
~/.config/opencode/tui.json
```

No package can be `invalid`. Stop if another package has an unexpected conflict.

Run the raw Stow simulation from the repository root:

```bash
repo_root=$(readlink -f -- "$(git rev-parse --show-toplevel)")
stow --no-folding --simulate --verbose=2 \
	--dir "$repo_root/config" --target "$HOME" opencode
```

The simulation must return nonzero. It must identify exactly two distinct conflicts: `.config/opencode/opencode.json` and `.config/opencode/tui.json`. Stow can print a target during planning and again in the conflict summary. Count distinct target names, not output lines. Stop if one of these conflicts is absent or if another conflict exists. Do not use `Apply Stow packages` while the regular files are present. Apply will stop at the conflicts.

### Back up, apply, and recover as one pair

The following block checks canonical ownership paths and compares both managed targets with their tracked sources. It then creates one timestamped XDG state backup. The block verifies both backup copies before it writes `SHA256SUMS`. It flushes and validates this manifest before it removes either managed target.

The block then starts the normal wizard. Choose `Apply Stow packages` and select only `opencode`. The migration is complete only when both managed targets link to their tracked sources and the package validator passes. A command failure, a declined plan, an empty selection, or a catchable interruption removes verified package links and restores both regular files from the XDG state backup.

```bash
(
	set -Eeuo pipefail

	repo_root=$(readlink -f -- "$(git rev-parse --show-toplevel)")
	home_root=$(readlink -f -- "$HOME")
	package_root=$repo_root/config/opencode
	config_root=$HOME/.config/opencode
	state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
	targets=(
		"$config_root/opencode.json"
		"$config_root/tui.json"
	)
	sources=(
		"$package_root/.config/opencode/opencode.json"
		"$package_root/.config/opencode/tui.json"
	)
	relatives=(
		.config/opencode/opencode.json
		.config/opencode/tui.json
	)
	resolved_targets=()
	resolved_sources=()
	identities=()
	digests=()
	metadata=()
	backups=()
	backup_digests=()
	backup_root=
	manifest=
	recovery_armed=0
	migration_complete=0

	digest_file() {
		local output
		output=$(sha256sum -- "$1") || return 1
		printf '%s\n' "${output%% *}"
	}

	resolve_link() {
		local target=$1 value
		[[ -L $target ]] || return 1
		value=$(readlink -- "$target") || return 1
		if [[ $value == /* ]]; then
			readlink -m -- "$value"
		else
			readlink -m -- "${target%/*}/$value"
		fi
	}

	pair_is_unchanged() {
		local i
		for i in 0 1; do
			[[ -f ${targets[$i]} && ! -L ${targets[$i]} ]] || return 1
			[[ -f ${sources[$i]} && ! -L ${sources[$i]} ]] || return 1
			[[ $(readlink -f -- "${targets[$i]}") == "${resolved_targets[$i]}" ]] || return 1
			[[ $(readlink -f -- "${sources[$i]}") == "${resolved_sources[$i]}" ]] || return 1
			[[ $(stat -c '%d:%i' -- "${targets[$i]}") == "${identities[$i]}" ]] || return 1
			[[ $(digest_file "${targets[$i]}") == "${digests[$i]}" ]] || return 1
			cmp -s -- "${targets[$i]}" "${sources[$i]}" || return 1
		done
	}

	verify_manifest() {
		local root=$1 manifest_file=$1/SHA256SUMS i line digest
		local -a lines=()

		[[ -d $root && ! -L $root ]] || return 1
		[[ -f $manifest_file && ! -L $manifest_file ]] || return 1
		[[ $(readlink -f -- "$manifest_file") == "$(readlink -f -- "$root")/SHA256SUMS" ]] || return 1
		mapfile -t lines <"$manifest_file" || return 1
		[[ ${#lines[@]} -eq 2 ]] || return 1

		for i in 0 1; do
			[[ -f $root/${relatives[$i]} && ! -L $root/${relatives[$i]} ]] || return 1
			line=${lines[$i]}
			digest=${line%% *}
			[[ ${#digest} -eq 64 && $digest != *[!0-9a-f]* ]] || return 1
			[[ $line == "$digest  ${relatives[$i]}" ]] || return 1
		done

		(
			cd -- "$root" || exit 1
			sha256sum --check --strict --quiet -- SHA256SUMS
		)
	}

	recover_pair() {
		local i current temp
		local -a temps=()

		printf '%s\n' 'Migration incomplete; restoring both managed targets as regular files.' >&2

		for i in 0 1; do
			if [[ ! -f ${backups[$i]} || -L ${backups[$i]} ]] ||
				[[ $(digest_file "${backups[$i]}") != "${backup_digests[$i]}" ]]; then
				printf 'Verified backup is unavailable or changed: %s\n' "${backups[$i]}" >&2
				return 1
			fi

			if [[ -L ${targets[$i]} ]]; then
				current=$(resolve_link "${targets[$i]}") || return 1
				if [[ $current != "${resolved_sources[$i]}" ]]; then
					printf 'Refusing to remove an unrelated link: %s -> %s\n' \
						"${targets[$i]}" "$current" >&2
					return 1
				fi
			elif [[ -f ${targets[$i]} && ! -L ${targets[$i]} ]] &&
				cmp -s -- "${backups[$i]}" "${targets[$i]}"; then
				printf 'Already restored from the paired backup: %s\n' \
					"${targets[$i]}" >&2
			elif [[ -e ${targets[$i]} ]]; then
				printf 'Refusing to replace an unexpected path during recovery: %s\n' \
					"${targets[$i]}" >&2
				return 1
			fi
		done

		for i in 0 1; do
			if [[ -L ${targets[$i]} ]]; then
				rm -- "${targets[$i]}" || return 1
			fi
		done

		for i in 0 1; do
			if [[ ! -e ${targets[$i]} && ! -L ${targets[$i]} ]]; then
				temp=${targets[$i]}.dotfiles-restore.$BASHPID.$i
				[[ ! -e $temp && ! -L $temp ]] || return 1
				cp --archive -- "${backups[$i]}" "$temp" || return 1
				cmp -s -- "${backups[$i]}" "$temp" || return 1
				temps[$i]=$temp
			elif [[ ! -f ${targets[$i]} || -L ${targets[$i]} ]] ||
				! cmp -s -- "${backups[$i]}" "${targets[$i]}"; then
				return 1
			fi
		done

		for i in 0 1; do
			if [[ -n ${temps[$i]-} ]]; then
				[[ ! -e ${targets[$i]} && ! -L ${targets[$i]} ]] || return 1
			fi
		done
		for i in 0 1; do
			if [[ -n ${temps[$i]-} ]]; then
				mv --no-clobber --no-target-directory -- \
					"${temps[$i]}" "${targets[$i]}" || return 1
			fi
		done

		for i in 0 1; do
			[[ -f ${targets[$i]} && ! -L ${targets[$i]} ]] || return 1
			cmp -s -- "${backups[$i]}" "${targets[$i]}" || return 1
		done
	}

	finish() {
		local status=$?
		trap - EXIT HUP INT TERM

		if ((migration_complete)); then
			exit "$status"
		fi
		if ((recovery_armed)); then
			if recover_pair; then
				printf 'Restored both files from: %s\n' "$backup_root" >&2
			else
				printf 'Automatic paired recovery failed. Keep OpenCode stopped and use the recovery procedure with: %s\n' \
					"$backup_root" >&2
				status=1
			fi
		fi
		exit "$status"
	}

	trap finish EXIT
	trap 'exit 129' HUP
	trap 'exit 130' INT
	trap 'exit 143' TERM

	if [[ $state_home != /* ]]; then
		printf 'XDG_STATE_HOME must be an absolute path: %s\n' "$state_home" >&2
		exit 1
	fi
	if [[ ! -d $package_root || -L $package_root ]] ||
		[[ $(readlink -f -- "$package_root") != "$repo_root/config/opencode" ]]; then
		printf 'Expected the canonical OpenCode package: %s\n' "$package_root" >&2
		exit 1
	fi
	if [[ ! -d $config_root || -L $config_root ]] ||
		[[ $(readlink -f -- "$config_root") != "$home_root/.config/opencode" ]]; then
		printf 'Expected an ordinary OpenCode config directory below HOME: %s\n' \
			"$config_root" >&2
		exit 1
	fi
	command -v opencode >/dev/null 2>&1 || {
		printf '%s\n' 'OpenCode is missing; restore the Omarchy Mise wrapper and restart preflight.' >&2
		exit 1
	}

	for i in 0 1; do
		if [[ ! -f ${targets[$i]} || -L ${targets[$i]} ]]; then
			printf 'Expected the managed target to be a regular file: %s\n' "${targets[$i]}" >&2
			exit 1
		fi
		if [[ ! -f ${sources[$i]} || -L ${sources[$i]} ]]; then
			printf 'Expected a regular tracked source: %s\n' "${sources[$i]}" >&2
			exit 1
		fi

		resolved_targets[$i]=$(readlink -f -- "${targets[$i]}")
		resolved_sources[$i]=$(readlink -f -- "${sources[$i]}")
		if [[ ${resolved_targets[$i]} != "$home_root/"* ]]; then
			printf 'Managed target resolves outside HOME: %s -> %s\n' \
				"${targets[$i]}" "${resolved_targets[$i]}" >&2
			exit 1
		fi
		if [[ ${resolved_sources[$i]} != "$package_root/"* ]]; then
			printf 'Tracked setting resolves outside its package: %s -> %s\n' \
				"${sources[$i]}" "${resolved_sources[$i]}" >&2
			exit 1
		fi
		if ! cmp -s -- "${targets[$i]}" "${sources[$i]}"; then
			printf 'Managed target differs from the approved tracked source: %s\n' \
				"${targets[$i]}" >&2
			exit 1
		fi

		identities[$i]=$(stat -c '%d:%i' -- "${targets[$i]}")
		digests[$i]=$(digest_file "${targets[$i]}")
		metadata[$i]=$(stat -c '%f:%u:%g:%s:%y' -- "${targets[$i]}")
	done

	read -r -p 'Type MIGRATE after inspecting both files and completing preflight: ' answer
	if [[ $answer != MIGRATE ]]; then
		printf '%s\n' 'No changes made.'
		exit 0
	fi
	pair_is_unchanged || {
		printf '%s\n' 'A managed target or tracked source changed before backup; nothing was removed.' >&2
		exit 1
	}

	timestamp=$(date -u +%Y%m%dT%H%M%S.%NZ)
	backup_root=$state_home/dotfiles/backups/opencode/$timestamp
	resolved_state_home=$(readlink -m -- "$state_home")
	resolved_backup_root=$(readlink -m -- "$backup_root")
	if [[ $resolved_backup_root != "$resolved_state_home/"* ]] ||
		[[ $resolved_backup_root == "$repo_root" || $resolved_backup_root == "$repo_root/"* ]]; then
		printf 'Backup root is outside XDG state or inside Git: %s -> %s\n' \
			"$backup_root" "$resolved_backup_root" >&2
		exit 1
	fi
	if [[ -e $backup_root || -L $backup_root ]]; then
		printf 'Backup root already exists: %s\n' "$backup_root" >&2
		exit 1
	fi

	for i in 0 1; do
		backups[$i]=$backup_root/${relatives[$i]}
		mkdir -p -- "${backups[$i]%/*}"
		cp --archive -- "${targets[$i]}" "${backups[$i]}"
	done

	for i in 0 1; do
		expected_backup=$(readlink -m -- "${backups[$i]}")
		if [[ ! -f ${backups[$i]} || -L ${backups[$i]} ]] ||
			[[ $(readlink -f -- "${backups[$i]}") != "$expected_backup" ]] ||
			[[ $expected_backup != "$resolved_backup_root/"* ]]; then
			printf 'Backup is not the expected contained regular file: %s\n' \
				"${backups[$i]}" >&2
			exit 1
		fi
		cmp -s -- "${targets[$i]}" "${backups[$i]}"
		if [[ $(stat -c '%f:%u:%g:%s:%y' -- "${backups[$i]}") != "${metadata[$i]}" ]]; then
			printf 'Backup metadata differs from its managed target: %s\n' \
				"${backups[$i]}" >&2
			exit 1
		fi
		backup_digests[$i]=$(digest_file "${backups[$i]}")
	done

	pair_is_unchanged || {
		printf '%s\n' 'A managed target or tracked source changed after backup; nothing was removed.' >&2
		exit 1
	}
	for i in 0 1; do
		cmp -s -- "${targets[$i]}" "${backups[$i]}"
	done

	manifest=$backup_root/SHA256SUMS
	manifest_tmp=$backup_root/.SHA256SUMS.tmp
	if [[ -e $manifest || -L $manifest || -e $manifest_tmp || -L $manifest_tmp ]]; then
		printf 'Checksum manifest path already exists below the new backup root: %s\n' \
			"$backup_root" >&2
		exit 1
	fi
	(
		set -o noclobber
		printf '%s  %s\n' \
			"${backup_digests[0]}" "${relatives[0]}" \
			"${backup_digests[1]}" "${relatives[1]}" >"$manifest_tmp"
	)
	if [[ ! -f $manifest_tmp || -L $manifest_tmp ]]; then
		printf 'Checksum manifest staging file is not a regular file: %s\n' \
			"$manifest_tmp" >&2
		exit 1
	fi
	mv --no-clobber --no-target-directory -- "$manifest_tmp" "$manifest"
	if [[ -e $manifest_tmp || -L $manifest_tmp ]]; then
		printf 'Checksum manifest was not installed safely: %s\n' "$manifest" >&2
		exit 1
	fi
	sync --file-system -- "$backup_root"

	pair_is_unchanged || {
		printf '%s\n' 'The managed targets or tracked sources changed before removal.' >&2
		exit 1
	}
	if ! verify_manifest "$backup_root"; then
		printf 'Checksum manifest validation failed: %s\n' "$manifest" >&2
		exit 1
	fi

	printf 'Verified both backups and checksum manifest: %s\n' "$backup_root"
	recovery_armed=1
	rm -- "${targets[0]}" "${targets[1]}"
	for i in 0 1; do
		[[ ! -e ${targets[$i]} && ! -L ${targets[$i]} ]]
	done

	printf '%s\n' \
		'Choose Apply Stow packages, select only opencode, and confirm its normal plan.' \
		'A failure, decline, empty selection, or interruption will restore both files.'
	cd -- "$repo_root"
	make

	for i in 0 1; do
		if [[ ! -L ${targets[$i]} ]] ||
			[[ $(resolve_link "${targets[$i]}") != "${resolved_sources[$i]}" ]] ||
			! cmp -s -- "${targets[$i]}" "${sources[$i]}"; then
			printf 'Apply did not produce the expected verified link: %s\n' \
				"${targets[$i]}" >&2
			exit 1
		fi
	done

	if ! bash lib/dotfiles/opencode-validator.sh \
		"${targets[0]}" "${targets[1]}"; then
		printf '%s\n' 'OpenCode package validation failed.' >&2
		exit 1
	fi

	migration_complete=1
	printf 'Migration complete; retained verified backup: %s\n' "$backup_root"
)
```

Do not start OpenCode until the block prints `Migration complete`. The recovery trap handles `HUP`, `INT`, and `TERM`. Use [Recovery after an incomplete migration](#recovery-after-an-incomplete-migration) after `SIGKILL`, power loss, or another event that prevents the trap from running.

## Verification

Keep OpenCode stopped. Choose `Package status` in the Dotfiles wizard. The status for `opencode` must be `linked`.

From the repository root, verify both links and the bytes at each managed target. Then run the package validator:

```bash
(
	set -euo pipefail

	repo_root=$(readlink -f -- "$(git rev-parse --show-toplevel)")
	targets=(
		"$HOME/.config/opencode/opencode.json"
		"$HOME/.config/opencode/tui.json"
	)
	sources=(
		"$repo_root/config/opencode/.config/opencode/opencode.json"
		"$repo_root/config/opencode/.config/opencode/tui.json"
	)

	[[ -d $HOME/.config/opencode && ! -L $HOME/.config/opencode ]]
	for i in 0 1; do
		[[ -L ${targets[$i]} ]]
		[[ $(readlink -f -- "${targets[$i]}") == $(readlink -f -- "${sources[$i]}") ]]
		cmp -s -- "${targets[$i]}" "${sources[$i]}"
	done

	bash "$repo_root/lib/dotfiles/opencode-validator.sh" \
		"${targets[0]}" "${targets[1]}"
)
```

Generated siblings that existed before apply must still be present. The package validator requires the two exact JSON objects. This check rejects a `plugin` field, a global `lsp` field, an unknown field, or a changed value. The validator also runs the installed OpenCode parser for `opencode.json` in an isolated environment.

The package validator does not test runtime precedence, project settings, remote or account configuration, plugin behavior, or language server behavior. OpenCode has no strict native command for `tui.json`. The package validator therefore checks the complete approved TUI object before it starts OpenCode.

Restart OpenCode once. Confirm that OpenCode starts without configuration diagnostics. Confirm that `/skills` lists the separately installed global skills and that `/<skill-name>` invokes one. Project settings can still override global settings where OpenCode permits it.

Run the focused tests with:

```bash
bash tests/opencode_test.sh
```

Run the complete suite with `make test`.

## Recovery after an incomplete migration

The migration block normally restores both managed targets. Use this procedure only when the recovery trap did not run or when automatic recovery failed.

Keep OpenCode stopped. Set `backup_root` to the exact path that the migration block printed. The XDG state backup must contain both files and a regular, non-symlink `SHA256SUMS` manifest from the same timestamp. The recovery block validates the exact two manifest entries and both checksums before it changes a managed target. It removes only links to the expected tracked sources. It accepts an existing regular file only when it matches its backup copy byte for byte.

```bash
backup_root=/absolute/path/from-the-migration-output
(
	set -euo pipefail

	repo_root=$(readlink -f -- "$(git rev-parse --show-toplevel)")
	state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
	targets=(
		"$HOME/.config/opencode/opencode.json"
		"$HOME/.config/opencode/tui.json"
	)
	sources=(
		"$repo_root/config/opencode/.config/opencode/opencode.json"
		"$repo_root/config/opencode/.config/opencode/tui.json"
	)
	backups=(
		"$backup_root/.config/opencode/opencode.json"
		"$backup_root/.config/opencode/tui.json"
	)
	relatives=(
		.config/opencode/opencode.json
		.config/opencode/tui.json
	)
	temps=()

	resolve_link() {
		local target=$1 value
		value=$(readlink -- "$target") || return 1
		if [[ $value == /* ]]; then
			readlink -m -- "$value"
		else
			readlink -m -- "${target%/*}/$value"
		fi
	}

	verify_manifest() {
		local root=$1 manifest_file=$1/SHA256SUMS i line digest
		local -a lines=()

		[[ -d $root && ! -L $root ]] || return 1
		[[ -f $manifest_file && ! -L $manifest_file ]] || return 1
		[[ $(readlink -f -- "$manifest_file") == "$(readlink -f -- "$root")/SHA256SUMS" ]] || return 1
		mapfile -t lines <"$manifest_file" || return 1
		[[ ${#lines[@]} -eq 2 ]] || return 1

		for i in 0 1; do
			[[ -f $root/${relatives[$i]} && ! -L $root/${relatives[$i]} ]] || return 1
			line=${lines[$i]}
			digest=${line%% *}
			[[ ${#digest} -eq 64 && $digest != *[!0-9a-f]* ]] || return 1
			[[ $line == "$digest  ${relatives[$i]}" ]] || return 1
		done

		(
			cd -- "$root" || exit 1
			sha256sum --check --strict --quiet -- SHA256SUMS
		)
	}

	if [[ $state_home != /* || $backup_root != /* ]]; then
		printf '%s\n' 'XDG state and backup roots must be absolute paths.' >&2
		exit 1
	fi
	resolved_state_home=$(readlink -m -- "$state_home")
	resolved_backup_root=$(readlink -m -- "$backup_root")
	if [[ $resolved_backup_root != "$resolved_state_home/dotfiles/backups/opencode/"* ]] ||
		[[ $resolved_backup_root == "$repo_root" || $resolved_backup_root == "$repo_root/"* ]]; then
		printf 'Backup root is outside OpenCode XDG state backups or inside Git: %s -> %s\n' \
			"$backup_root" "$resolved_backup_root" >&2
		exit 1
	fi
	for i in 0 1; do
		[[ -f ${backups[$i]} && ! -L ${backups[$i]} ]]
		[[ -f ${sources[$i]} && ! -L ${sources[$i]} ]]
		if [[ -L ${targets[$i]} ]]; then
			[[ $(resolve_link "${targets[$i]}") == $(readlink -f -- "${sources[$i]}") ]]
		elif [[ -f ${targets[$i]} && ! -L ${targets[$i]} ]] &&
			cmp -s -- "${backups[$i]}" "${targets[$i]}"; then
			printf 'Already restored from the paired backup: %s\n' "${targets[$i]}"
		elif [[ -e ${targets[$i]} ]]; then
			printf 'Refusing to replace an unexpected path: %s\n' "${targets[$i]}" >&2
			exit 1
		fi
	done
	if ! verify_manifest "$backup_root"; then
		printf 'Required checksum manifest is missing, linked, malformed, or invalid: %s\n' \
			"$backup_root/SHA256SUMS" >&2
		exit 1
	fi
	for i in 0 1; do
		candidate=${targets[$i]}.dotfiles-restore.$BASHPID.$i
		[[ ! -e $candidate && ! -L $candidate ]]
	done

	for i in 0 1; do
		if [[ -L ${targets[$i]} ]]; then
			rm -- "${targets[$i]}"
		fi
	done

	for i in 0 1; do
		if [[ ! -e ${targets[$i]} && ! -L ${targets[$i]} ]]; then
			temps[$i]=${targets[$i]}.dotfiles-restore.$BASHPID.$i
			[[ ! -e ${temps[$i]} && ! -L ${temps[$i]} ]]
			cp --archive -- "${backups[$i]}" "${temps[$i]}"
			[[ -f ${temps[$i]} && ! -L ${temps[$i]} ]]
			cmp -s -- "${backups[$i]}" "${temps[$i]}"
		else
			[[ -f ${targets[$i]} && ! -L ${targets[$i]} ]]
			cmp -s -- "${backups[$i]}" "${targets[$i]}"
		fi
	done
	for i in 0 1; do
		if [[ -n ${temps[$i]-} ]]; then
			[[ ! -e ${targets[$i]} && ! -L ${targets[$i]} ]]
		fi
	done
	for i in 0 1; do
		if [[ -n ${temps[$i]-} ]]; then
			mv --no-clobber --no-target-directory -- \
				"${temps[$i]}" "${targets[$i]}"
		fi
	done
	for i in 0 1; do
		[[ -f ${targets[$i]} && ! -L ${targets[$i]} ]]
		cmp -s -- "${backups[$i]}" "${targets[$i]}"
	done

	printf 'Restored both managed targets as regular files from: %s\n' "$backup_root"
)
```

After recovery, `Package status` must report `opencode` as `conflicting` because both managed targets are regular files again. Correct the cause of the incomplete migration. Then repeat the preflight and the paired migration. Never copy an XDG state backup through a Stow link. Never restore only one file from the pair.

## Writes and updates

OpenCode, `opencode plugin --global`, the TUI plugin installer, and global config APIs can write through both Stow links. Such a write changes a tracked source. Before you directly edit either tracked source, quit every OpenCode process. Keep OpenCode stopped while you edit, review the Git diff, keep or reject the change, and run the package validator. Restart OpenCode once after you finish the review and the package validator passes.

Do not use `opencode plugin --global` to maintain the Stow package. The command downloads code before it edits settings, and it can edit the two files separately. External plugins are outside this package. Another OpenCode layer can own them.

`omarchy refresh config opencode/opencode.json`, `omarchy reinstall configs`, and `omarchy reinstall` can follow a Stow link and replace a tracked source. Remove the `opencode` Stow package first unless you intend to replace and review the tracked sources. Keep files below `/usr/share/omarchy/` read-only.

After an Omarchy or Mise update, stop OpenCode and check its installed version. Inspect both tracked sources and both links. Run the package validator and the focused tests. Then restart OpenCode once.

## Removal and reapplication

Quit every OpenCode process. Start `make`, choose `Remove Stow package`, and select `opencode`. The wizard simulates the removal, removes only the two leaf links, and verifies that both managed targets are absent. It keeps `~/.config/opencode/` and all excluded siblings.

Removal does not uninstall OpenCode or run `opencode uninstall`. It does not remove a language server, credentials, caches, generated support files, plugins, themes, runtime state, or XDG state backups. It does not restore an Omarchy baseline.

Keep OpenCode stopped before reapplication. Inspect the layers in [Competing settings](#competing-settings). If both managed targets are absent, choose `Apply Stow packages`, select `opencode`, and repeat [Verification](#verification). If both managed targets are regular files, repeat [Existing regular settings](#existing-regular-settings). Do not leave the package with only one managed target.

Optional Omarchy baseline restoration is a separate human action after verified removal:

```bash
omarchy refresh config opencode/opencode.json
```

This command restores only the Omarchy main baseline. The baseline can contain legacy TUI settings. On the next start, OpenCode can create `tui.json` and a TUI migration backup. Inspect both files before you reapply the Stow package.

## Clone relocation

Keep OpenCode stopped. Before you move the repository, remove the `opencode` Stow package from the old clone. Move the clone, apply the package from the new location, and repeat verification.

If the clone has moved, do not run `stow --restow` over the old dangling links. First verify that each stored referent is the matching tracked source below the old canonical `config/opencode/` root. Verify both links before you remove either link. Remove the two links as one pair, then apply from the new clone. Do not change an unrelated link or a regular file.
