# Durable Memory

## Write human documentation for outside users

Applies when: Updating `README.md` or human documentation under `docs/`.

Guidance: Explain setup and usage without relying on maintainer-only context.

Reason: The human documentation is intended for users of the currently supported Omarchy version. Leave support and contribution policy unstated until it is explicitly decided.

## Exclude archived files from current decisions

Applies when: Exploring the repository, defining its purpose, or planning future work.

Guidance: Treat `__old_files/` as outside the active repository and base decisions only on current files and explicit user answers.

Reason: The archived files do not represent the intended repository.

## Deploy through GNU Stow

Applies when: Organizing or applying tracked configuration.

Guidance: Use Stow packages and symlink their files into the user's home directory. Keep tracked files in the repository instead of copying them into place.

Reason: Symlink deployment keeps the repository and active configuration synchronized.

## Support one Omarchy version

Applies when: Omarchy releases or compatibility questions affect configuration or documentation.

Guidance: Maintain one explicit current target and change it only through a deliberate repository decision.

Reason: Multi-version compatibility is outside the current repository promise.

## Keep archived shell migration on Bash

Applies when: Planning or implementing shell configuration from the archived Zsh files.

Guidance: Keep Bash as the target shell and place each approved shell-native port directly in `.bashrc`'s interactive custom section after Omarchy's packaged defaults. Ports require explicit approval for each collision, must tolerate repeated sourcing, and need focused verification. Revalidate intentional overlaps when the supported Omarchy target changes. Put shell-independent executables in separate application Stow packages. Keep Starship configuration and Omarchy theme state outside the Bash package.

Reason: Omarchy 4 supplies and updates Bash-specific defaults through the user extension seam in `~/.bashrc`; retaining that seam preserves current behavior and avoids a user-owned Zsh compatibility layer that can drift from Omarchy updates.

## Load Omarchy Bash defaults once

Applies when: Changing or reloading `config/bash/.bashrc`.

Guidance: Source Omarchy's packaged Bash `rc` once per Bash process. Keep custom aliases outside the guard so each `.bashrc` source reapplies them. Start a new Bash shell to load updated packaged defaults.

Reason: Repeated packaged initialization duplicates Starship and zoxide `PROMPT_COMMAND` hooks under the current Arch/Omarchy stack.

## Keep Omarchy editor selection

Applies when: Configuring `EDITOR` or reconsidering the archived fixed Neovim setting.

Guidance: Retain Omarchy's exported `omarchy-launch-editor --inline` value. Add a fixed editor override only after an explicit decision to replace Omarchy's selectable editor behavior.

Reason: The launcher defaults to Neovim while preserving saved editor choices and the correct inline or GUI launch path.

## Defer machine-specific mechanisms

Applies when: A configuration first requires a monitor name, device path, username, or other machine-specific value.

Guidance: Decide the handling mechanism from that concrete case instead of adding profiles or templates in advance.

Reason: The repository has no current machine-specific requirement to design around.

## Operate Stow packages safely

Applies when: Adding, applying, editing, verifying, or removing a Stow package.

Guidance: Edit tracked files inside the repository. Run every Stow operation with `--no-folding` so new deployments link leaf targets. Preserve valid older folded links until their package is removed and reapplied. Dry-run each change, stop and show any existing-file conflict, and verify the expected links and clean removal. Target the user's home directory by default; decide any other target with the human when a concrete need appears. Before migration, resolve symlinks and prove both the existing target and repository destination remain inside their canonical ownership roots.

Reason: Repository-owned links must not replace user files or claim parent directories shared with other packages.

## Escalate full Omarchy replacements

Applies when: An Omarchy customization might require tracking a complete configuration file.

Guidance: Prefer an Omarchy-supported override. Track a full configuration only when an override cannot express the required behavior, after reviewing the replacement scope with the human.

Reason: Omarchy should continue to own its packaged defaults wherever its customization seams are sufficient.

## Own tmux configuration as a full replacement

Applies when: Implementing or maintaining tmux configuration.

Guidance: Use the existing `tmux` Stow package to own a complete `config/tmux/.config/tmux/tmux.conf` for `~/.config/tmux/tmux.conf`. Seed it from the packaged Omarchy 4 baseline; inspect and back up the prior live file without adopting it. Track neither a pristine baseline snapshot nor a sourced drop-in. Removal leaves the active config absent and reports `omarchy refresh tmux` as the explicit baseline-restoration step.

Reason: Omarchy 4 has no stable tmux override seam; a sourced drop-in loses its include on refresh, while direct live edits are not portable or repository-owned.

## Stop before tracking sensitive values

Applies when: Candidate content contains a credential, token, session value, account identifier, or other sensitive value.

Guidance: Stop before adding the content and ask the human to choose exclusion, a local value, or encryption.

Reason: The repository has no blanket policy that makes sensitive values safe to track.

## Document non-Arch prerequisites and installers

Applies when: A Stow package requires software that cannot be declared as an official Arch package.

Guidance: Document the prerequisite and its supported installation command. Add an installation script only after making that choice for the package, and document the script in the relevant topic guide.

Reason: Software outside `arch_packages` needs an explicit setup and ownership decision instead of implicit provisioning.

## Install Arch requirements with Stow packages

Applies when: A Stow package requires an official Arch package.

Guidance: Declare the package in `arch_packages`. During apply and migration, include missing packages in the complete plan, confirm once, install them with `omarchy pkg add`, verify package identity, and repeat Stow simulation before mutation. Stow removal retains the Arch packages and reports them in cleanup notes.

Reason: Arch packages have independent ownership and can be shared. Package-specific planning avoids global installs, while retention avoids removing software without installation provenance.

## Add one requested package at a time

Applies when: A user asks to add a new configuration concern.

Guidance: Inspect the live user configuration and Omarchy defaults, agree the ownership boundary with the human, then create and verify one lowercase-named Stow package.

Reason: Bulk capture would bypass the repository's ownership and safety decisions.

## Decide generated artifacts from the concrete generator

Applies when: Tracked source or a script can generate an active configuration file or asset.

Guidance: Decide whether Git stores source, output, or both after reviewing that generator's reproducibility and user value.

Reason: The repository has no single generated-file policy that fits every configuration concern.

## Revalidate after Omarchy target changes

Applies when: Changing the repository's supported Omarchy version or maintaining a full tracked replacement.

Guidance: Compare full replacements with the new packaged defaults, update them deliberately, and repeat package verification. Prefer stable Omarchy override paths and notify the human when an update conflicts with a managed path.

Reason: Full replacements and directly managed paths can become stale when Omarchy changes.

## Review Omarchy writes through Stow links

Applies when: An Omarchy update, migration, refresh, reinstall, installer, or hook can write to a path owned through a Stow symlink.

Guidance: Treat the resulting repository-source edit as a proposed Git change. Compare it with the packaged default, keep or reject it deliberately, restore required customizations, and run package validation. Treat `omarchy refresh config` as a tracked replacement rather than a local reset when its target is linked. Before `omarchy reinstall configs`, unlink affected packages or explicitly accept that it will overwrite their repository sources.

Reason: Omarchy file operations can follow the symlink and modify the repository-owned source instead of isolated live state.

## Fail Starship validation on diagnostics

Applies when: Validating a Starship configuration or adding its package validators and focused tests.

Guidance: Run `starship print-config` with a fresh isolated `STARSHIP_CACHE` and a fixed `STARSHIP_SESSION_KEY`, and require both a successful status and empty standard error. Use controlled `starship prompt` or `starship module` renders to verify behavior and appearance.

Reason: Starship 1.26.0 can report malformed TOML or invalid values on standard error, fall back to defaults, and still return status 0; its cache can also suppress repeated diagnostics.

## Write safe Bash installers

Applies when: A package-specific installer is approved.

Guidance: Use Bash, resolve the repository without a fixed clone path, preview actions, request confirmation, tolerate repeated execution, and verify the result.

Reason: Installers change the system beyond ordinary Stow linking and need a predictable safety boundary.

## Preserve the Stow package lifecycle

Applies when: Migrating, validating, removing, or relocating a package.

Guidance: Migrate an approved existing file by backing it up, inspecting it, moving it into the package, and then Stowing it. Run application-specific validation when available. Removal unlinks the package and explains remaining generated files or application state. Moving the clone requires Restowing packages from the new path.

Reason: A package must remain recoverable across its full lifecycle, not only during first installation.

## Keep wizard operations conservative

Applies when: Designing or running the dotfiles wizard.

Guidance: Use `make` and guided setup as the intended human workflow. Keep every operation available as a standalone wizard action. Run prerequisite preparation, pinned global skill installation, application cleanup, and Stow package application in that order. Use Gum with a Bash fallback. Start Stow package selection with no package selected. Continue after a skipped nonessential phase. Stop after an operational failure and name the related standalone action for recovery. Preserve public action preselection and noninteractive operation functions for Make targets, agents, scripts, and tests, but keep them out of normal human instructions.

Reason: The wizard is the normal user interface and must make each system change visible and recoverable.

## Store migration backups in XDG state

Applies when: An approved migration preserves an existing target before Stow links it.

Guidance: Write timestamped backups below the user's XDG state directory, outside Git.

Reason: Migration backups are local recovery data, not repository content.

## Prepare wizard prerequisites through Omarchy

Applies when: Prerequisite preparation finds GNU Stow missing or finds Node.js, npm, or npx missing or below the supported version.

Guidance: Show one complete prerequisite plan and ask for confirmation. Use `omarchy pkg add stow` to install GNU Stow. Use `omarchy install dev-env node` to install the Node.js toolchain. Let Omarchy manage privilege prompts. Verify GNU Stow, Node.js 22.20.0 or newer, npm, and npx in the same run. In guided setup, stop before later phases if the user declines required prerequisites or if installation or verification fails.

Reason: Guided setup must establish and verify its required tools without implementing Omarchy package management or privilege handling.

## Keep package dependencies explicit

Applies when: One Stow package requires another package.

Guidance: Declare the edge in the package catalog and make the wizard show whether the dependency will be included or blocks the requested operation.

Reason: Hidden package dependencies would make package selection and removal unpredictable.

## Handle Omarchy mismatch before changes

Applies when: The wizard detects an Omarchy version different from the repository's current target.

Guidance: Show both versions and ask the human whether to continue before changing packages.

Reason: Compatibility outside the current target is not guaranteed, but inspection and an explicit human decision remain useful.

## Install global agent skills conservatively

Applies when: Running the wizard's agent-skill action or `make skills`.

Guidance: Install every skill exposed by the official installers at pinned revisions from `https://github.com/blader/humanizer` and `https://github.com/mattpocock/skills` under `~/.agents/skills/`. Delegate draft exclusion, skill discovery, and supporting-file installation to each repository's documented installer; this repository adds only version pinning, difference preview, confirmation, and backup. Show recursive differences before approval. Before a mutating source installer runs, back up every existing skill it can rewrite, including currently unchanged skills, then verify its output against the approved preview. `make skills-update` previews upstream and installed-skill differences, then updates `skills.json` and global skills together after one approval. A failed update restores both the old manifest and global skill backups.

Reason: Future agents need reproducible repository skills without silently overwriting global customizations.

## Order wizard changes explicitly

Applies when: The wizard prepares any package change.

Guidance: Before mutation, inspect the Omarchy version, determine dependencies and conflicts, check core and package-specific tools at the points when their package set is known, show the complete plan, and request confirmation. Block removal when another linked package depends on the selected package and name each dependent.

Reason: The human must see version, prerequisite, and dependency effects before the first mutation.

## Document current behavior

Applies when: Writing `README.md`, `docs/stow.md`, `docs/cleanup.md`, or `docs/agent-setup.md`.

Guidance: Present working wizard actions and Make targets as human usage. Keep README as the purpose, complete requirements, quick start, and documentation index. Keep Stow package operations in `docs/stow.md`, application cleanup in `docs/cleanup.md`, and global skill operations in `docs/agent-setup.md`. State separate requirements for core wizard use, application cleanup, Stow operations, global skills, and tests.

Reason: Human documentation must match the implemented command engine without duplicating topic-guide detail.

## Keep the command engine modular

Applies when: Extending or testing the Dotfiles wizard.

Guidance: Keep `bin/dotfiles` as the single public command interface. Keep shared behavior, Stow package operations, global skill operations, application cleanup, and interactive orchestration in separate modules under `lib/dotfiles/`. Keep operation logic callable without top-level menu selection. Group command-level integration tests by behavior under `tests/` and keep fixture isolation in one shared harness.

Reason: Future functionality should remain local to its domain instead of expanding one command or test file indefinitely.

## Keep application cleanup selection temporary

Applies when: Changing the application cleanup profile, discovery, or selection behavior.

Guidance: Keep separate package, web app, and TUI default arrays in `cleanup.json`. Validate its shape, names, unique entries, and protected package exclusions. Select only available defaults at the start of a run. Report unavailable defaults. Permit additions and deselections for the current run, and do not write those choices to the profile. Exclude protected system packages and the installed providers of active cleanup runtime commands from selection.

Reason: The application cleanup profile supplies repeatable defaults without becoming machine state or allowing cleanup to remove a command that it needs.

## Verify delegated application cleanup

Applies when: Changing or running an application cleanup mutation.

Guidance: Show one complete plan grouped by web apps, TUIs, and packages before mutation. Delegate each item through `omarchy webapp remove <name>`, `omarchy tui remove <name>`, or `omarchy pkg drop <name>`. Verify that each item is absent before continuing. Stop on the first removal or verification failure, preserve earlier verified removals, report incomplete items, and direct recovery to `Clean up Omarchy applications`. Treat unavailable defaults and an empty selection as successful no-ops.

Reason: Omarchy owns application removal. Per-item verification and bounded failure make a partial cleanup visible and safe to rerun.
