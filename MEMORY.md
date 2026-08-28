# Durable Memory

## Write human documentation for outside users

Applies when: Updating `README.md` or human documentation under `docs/`.

Guidance: Describe only currently implemented setup, requirements, and usage without relying on maintainer-only context. Keep support and contribution policy unstated until an explicit human decision.

Reason: Human documentation should match what users can run on the supported Omarchy target without implying an undecided project promise.

## Exclude archived files from current decisions

Applies when: Exploring the repository, defining its purpose, or planning future work.

Guidance: Treat `__old_files/` as outside the active repository and base decisions only on current files and explicit user answers.

Reason: The archived files do not represent the intended repository.

## Support one Omarchy version

Applies when: Checking Omarchy compatibility, detecting a version mismatch, changing the supported target, or maintaining a full replacement.

Guidance: Maintain one explicit current target and change it only through a deliberate repository decision. Before any mutation under a detected mismatch, show the target and detected versions and obtain an explicit human decision to continue. Compare every full replacement with the applicable packaged defaults and accept or reject each difference deliberately. Surface managed-path conflicts for a human decision and prefer stable Omarchy overrides. After a target change, run structural checks, all affected validators and focused tests, and the complete suite.

Reason: One target keeps compatibility bounded; version differences can invalidate full replacements and managed-path assumptions before ordinary validation exposes them.

## Check direct consumers of cloned Omarchy services

Applies when: Cloning or maintaining a built-in Omarchy shell service.

Guidance: Trace every direct service consumer as well as generic plugin-id routing. On Omarchy 4.0.1, `StayAwake.qml` looks up `omarchy.idle` directly, while the active clone is stored under its personal plugin id, so the Stay Awake indicator stops controlling the cloned service. Before accepting a clone, make each direct consumer resolve the active implementation or approve a specific compatibility route.

Reason: Omarchy's generic clone routing does not cover consumers that read the service registry by the built-in id.

## Carry screensaver overrides through Hyprland dispatch

Applies when: A user-owned Omarchy screensaver launcher must pass a private command or environment into terminals started through `hyprctl dispatch exec`.

Guidance: Put the private command or environment in the dispatched terminal payload. An environment change applied only to the launcher process does not cross the compositor dispatch. Verify that the launched terminal resolves the intended command while session-wide command resolution remains unchanged.

Reason: Hyprland, not the launcher process, starts the terminal after receiving the dispatch command.

## Select themed ttfx effects explicitly

Applies when: Building or validating effect-specific active-theme mappings for an Omarchy screensaver against `ttfx` 0.3.2.

Guidance: Resolve Omarchy theme tokens at launch, put root color arguments before an explicit effect name, and put effect-specific arguments after it. Choose the effect outside `--random-effect`; describe only the 25 audited fully controllable effects as fully theme-compatible, and repeat the catalog, grammar, fixed-color, and bounded-invocation audit when the `ttfx` version changes.

Reason: `ttfx` 0.3.2 reconstructs a randomly selected effect with default configuration, discarding effect-specific mappings, and 12 of its 37 effects retain visible fixed colors outside their accepted arguments.

## Account for the stock screensaver runner loop

Applies when: A private `ttfx` shim runs beneath Omarchy 4.0.1's packaged `omarchy-screensaver`.

Guidance: Preserve the stock black terminal background unless a separate ownership decision replaces its OSC 11 behavior; `--terminal-background-color` controls only effect fade endpoints. Ensure configuration, theme-token, and runtime failures cannot exit rapidly into the runner's unconditional loop while preserving input and focus dismissal and the lock deadline.

Reason: The packaged runner sets the terminal background to black before immediately relaunching each exited `ttfx` process, while `ttfx` does not apply its background argument to the terminal itself.

## Avoid idle-plugin reloads during an idle cycle

Applies when: Installing or changing a personal Omarchy 4.0.1 idle plugin clone.

Guidance: Install a complete validated clone before triggering one plugin rescan, and do not edit its installed files during an idle cycle. After any reload, start a fresh cycle and verify idle-service status before relying on screensaver or lock timing.

Reason: Omarchy reloads the complete plugin registry after a plugin change, recreating the idle service and resetting its timers, active-cycle state, screensaver-window bookkeeping, and pending lock coordination.

## Keep the screensaver allowlist outside the plugin tree

Applies when: Implementing or validating the Screensaver effect allowlist or its Make-driven selector.

Guidance: Track the bare JSON array at `config/screensaver-effects/.config/dotfiles/screensaver-effects.json` and deploy it to `~/.config/dotfiles/screensaver-effects.json`. Read it at each effect start. Atomically replace the repository source through a sibling temporary file, then verify that any deployed leaf still resolves to it through Stow.

Reason: A write below `~/.config/omarchy/plugins/` reloads the plugin registry and can reset idle coordination, while atomically replacing the deployed path would replace its Stow symlink and split repository and live state.

## Keep the Omarchy root separate from command paths

Applies when: Invoking packaged Omarchy commands from Bash, especially from a process that inherits exported `OMARCHY_PATH`.

Guidance: Keep `OMARCHY_PATH` as the installation root `/usr/share/omarchy`; use a differently named variable for an Omarchy executable. For an exact compatibility probe, use a minimal environment with the fixed root, `/usr/bin` path, and C locale, and test under an inherited exported `OMARCHY_PATH`.

Reason: Bash preserves an inherited variable's export attribute across assignment. Reusing `OMARCHY_PATH` for `/usr/share/omarchy/bin/omarchy` makes `omarchy-version` interpret the executable as its installation root and report a development version.

## Keep archived shell migration on Bash

Applies when: Planning or implementing shell configuration from the archived Zsh files.

Guidance: Keep Bash as the target shell and place each approved shell-native port directly in `.bashrc`'s interactive custom section after Omarchy's packaged defaults. Ports require explicit approval for each collision, must tolerate repeated sourcing, and need focused verification. Revalidate intentional overlaps when the supported Omarchy target changes. Put shell-independent executables in separate application Stow packages. Keep Starship configuration and Omarchy theme state outside the Bash package.

Reason: Omarchy 4 supplies and updates Bash-specific defaults through the user extension seam in `~/.bashrc`; retaining that seam preserves current behavior and avoids a user-owned Zsh compatibility layer that can drift from Omarchy updates.

## Load Omarchy Bash defaults once

Applies when: Changing or reloading `config/bash/.bashrc`.

Guidance: Source Omarchy's packaged Bash `rc` once per Bash process. Keep custom aliases outside the guard so each `.bashrc` source reapplies them. Start a new Bash shell to load updated packaged defaults.

Reason: Repeated packaged initialization duplicates Starship and zoxide `PROMPT_COMMAND` hooks under the current Arch/Omarchy stack.

## Verify Bash PATH in fresh shell modes

Applies when: Changing Bash PATH or startup-environment behavior, or changing ownership of an executable provider.

Guidance: Verify Bash from a scrubbed environment in login, interactive non-login, and non-interactive modes. Repeat startup-file sourcing in each mode where it applies. Assert the count and order of managed PATH components and the provider resolved for each affected executable. Treat a long-lived shell's PATH as inherited process state and use fresh-shell results as configuration evidence.

Reason: Parent-process history can retain stale PATH entries even when fresh Omarchy and Mise initialization is idempotent.

## Keep repository-owned Bash startup offline

Applies when: Adding a Bash startup dependency, plugin, or generated initializer.

Guidance: Keep repository-owned startup deterministic and offline by loading installed, reviewed code. Decide each user-visible capability separately from its startup integration. Prefer a reviewed static integration when it preserves exact semantics. When generation is necessary, require it to succeed before evaluating its output, and place runtime evaluation behind the user action that requests it.

Reason: Startup-time generation or network access adds latency and supply-chain risk. The proven static command-correction approach retains exact semantics while keeping startup offline.

## Keep Omarchy editor selection

Applies when: Configuring `EDITOR` or reconsidering the archived fixed Neovim setting.

Guidance: Retain Omarchy's exported `omarchy-launch-editor --inline` value. Add a fixed editor override only after an explicit decision to replace Omarchy's selectable editor behavior.

Reason: The launcher defaults to Neovim while preserving saved editor choices and the correct inline or GUI launch path.

## Defer machine-specific mechanisms

Applies when: A configuration first requires a monitor name, device path, username, or other machine-specific value.

Guidance: Decide the handling mechanism from that concrete case instead of adding profiles or templates in advance.

Reason: Profiles and templates add complexity before a concrete machine-specific requirement establishes the needed boundary.

## Operate Stow packages safely

Applies when: Adding, applying, editing, verifying, or removing a Stow package.

Guidance: Edit tracked files inside the repository. Run every Stow operation with `--no-folding` so new deployments link leaf targets. Preserve valid older folded links until their package is removed and reapplied. Dry-run each change, stop and show any existing-file conflict, and verify the expected links and clean removal. Target the user's home directory by default; decide any other target with the human when a concrete need appears. Before migration, resolve symlinks and prove both the existing target and repository destination remain inside their canonical ownership roots.

Reason: Repository-owned links must not replace user files or claim parent directories shared with other packages.

## Deploy shared Brave policy outside Stow

Applies when: Implementing or maintaining the shared Brave configuration.

Guidance: Keep one canonical managed-policy source and deploy a root-owned regular copy through a dedicated Dotfiles wizard operation. Keep it out of `config/` and `packages.json`; preserve Omarchy's color policy and launch flags, browser profiles, themes, and fonts. Apply one shared policy to every supported installed Brave consumer, block overlapping foreign policy, and use the approved preview, backup, verification, rollback, and removal lifecycle.

Reason: Both Brave products consume one privileged system policy path. A Stow link would make active policy user-writable through the repository, while taking ownership of Omarchy's color policy would break browser recoloring.

## Escalate full Omarchy replacements

Applies when: An Omarchy customization might require tracking a complete configuration file.

Guidance: Prefer an Omarchy-supported override. Track a full configuration only when an override cannot express the required behavior, after reviewing the replacement scope with the human.

Reason: Omarchy should continue to own its packaged defaults wherever its customization seams are sufficient.

## Own tmux configuration as a full replacement

Applies when: Implementing or maintaining tmux configuration.

Guidance: Use the `tmux` Stow package to own a complete replacement for the active tmux configuration. Seed it from the packaged Omarchy baseline; inspect and back up the prior live file without adopting it. Track one self-contained replacement rather than a pristine baseline snapshot or sourced drop-in. Removal leaves the active configuration absent and reports restoration of the packaged baseline as a separate Omarchy-owned recovery action.

Reason: Omarchy has no stable tmux override seam; a sourced drop-in loses its include on refresh, while direct live edits are not portable or repository-owned.

## Validate btop's machine-specific CPU sensor

Applies when: Changing or applying the `btop` package, or diagnosing its CPU temperature.

Guidance: Keep the complete configuration machine-scoped. Apply it only after the hardware check in `docs/btop.md` passes. Treat `No good candidate for cpu sensor found` as inconclusive; verification is complete when btop's displayed temperature agrees with repeated reads from the configured thermal zone after unit conversion.

Reason: btop offers no include or drop-in seam; the supported release can emit that warning while building its Auto fallback before using the explicit selector, and ACPI THRM is a processor-associated proxy rather than package temperature.

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

## Append package catalog entries

Applies when: Adding a Stow package to `packages.json`.

Guidance: Append the new entry after every existing package so established wizard menu numbers remain stable.

Reason: Package catalog order defines the wizard's user-facing numeric choices; inserting an entry changes existing selections and can make saved or scripted input operate on the wrong package.

## Add one requested package at a time

Applies when: A user asks to add a new configuration concern.

Guidance: Inspect the live user configuration and Omarchy defaults, agree the ownership boundary with the human, then create and verify one lowercase-named Stow package.

Reason: Bulk capture would bypass the repository's ownership and safety decisions.

## Decide generated artifacts from the concrete generator

Applies when: Tracked source or a script can generate an active configuration file or asset.

Guidance: Decide whether Git stores source, output, or both after reviewing that generator's reproducibility and user value.

Reason: The repository has no single generated-file policy that fits every configuration concern.

## Keep Telegram theming on supported native seams

Applies when: Implementing or maintaining the `telegram-theme` package.

Guidance: Use Omarchy's user theme template and `theme-set.d` hook. Use Node for the generator core, a thin Bash adapter for hook entry, and system `zip` for archive creation. Track implementation source and pinned role data in Git; write generated themes and diagnostics to XDG state. Atomically publish one stable watched theme file, retain the last-good output on failure, and activate that file once through Telegram's manual Import and Keep flow. Enforce text contrast of at least `4.50:1` and a minimum `0.025` OKLab distance between primary surfaces. Fail closed without publishing when either the Omarchy or Telegram version is unverified. Use only Telegram's supported watched-file seam; do not edit private `tdata`, automate the UI, or launch or restart the client.

Reason: Telegram's supported watcher applies later theme publishes after one manual activation. Restricting integration to that watcher keeps synchronization stable across updates and leaves Telegram-owned state and process control intact.

## Review writes through Stow links

Applies when: An application or an Omarchy update, migration, refresh, reinstall, installer, or hook can write to a path owned through a Stow symlink.

Guidance: Treat any resulting repository-source edit as a proposed Git change: review it, keep or reject it deliberately, restore required customizations, and run package validation. For Omarchy writes, also compare the packaged default. Treat `omarchy refresh config` as a tracked replacement rather than a local reset when its target is linked. Before `omarchy reinstall configs` or `omarchy reinstall`, unlink affected packages or explicitly accept that it will overwrite their repository sources.

Reason: Writers can follow the symlink and modify the repository-owned source instead of isolated live state.

## Deploy the Wallpaper library outside Stow

Applies when: Planning, implementing, or validating repository wallpaper deployment.

Guidance: Keep theme-grouped source under `wallpapers/library/` and the ignored Wallpaper inbox under `wallpapers/inbox/`. Leave both outside `config/` and `packages.json`. Use a dedicated wizard operation to materialize receipt-owned regular files under `~/.config/omarchy/backgrounds/`, preserve unrelated files, and store clone-independent target and digest inventory in strictly validated XDG state. Serialize Apply and removal; use verified pending evidence and backups to restore every touched live path and receipt after failure or interruption, and block ordinary work when recovery cannot be proved. Treat different foreign targets, changed owned files, invalid receipts, unsafe paths, and active-background deletion as pre-mutation conflicts; adopt only exact unowned matches. Preserve exact no-ops without metadata churn. Reuse Apply in Guided setup after Stow package application and before Shared Brave policy. Enforce the supported Omarchy-version decision before mutation and reinspect background behavior when that target changes.

Reason: Direct Stow symlinks break repeated background cycling on Omarchy 4.0.1, while the package catalog has no materialization lifecycle. Regular copies preserve cycling, and receipts make convergence and removal safe without owning complete themes or user backgrounds.

## Curate Managed wallpapers by verified content identity

Applies when: Planning, implementing, or validating repository wallpaper curation.

Guidance: Identify a Managed wallpaper with the full lowercase SHA-256 digest of its exact, unmodified bytes and append the canonical extension detected from supported image content. Accept JPEG, PNG, GIF, BMP, or WebP only after warning-free complete decoding of all image data or animation frames. Reuse exact duplicates and fail closed if equal digests have different bytes. Allow unrelated worktree changes, but validate the complete Wallpaper library and revalidate confirmed operation paths before mutation. Serialize Add, Move, and Remove with recoverable transaction evidence that restores prior assignments and Intake images after failure or interruption. Delete an Intake image only after the complete Managed wallpaper and every requested Theme assignment exist in repository state and the stored bytes match the intake.

Reason: Content identity avoids source-name collisions and remains stable across Theme assignments. Complete decoding keeps unreadable assets out of Git, while transactional restoration and post-verification deletion preserve recoverable maintainer input.

## Keep wallpaper curation in one manager

Applies when: Implementing or validating the maintainer-facing wallpaper workflow.

Guidance: Route `make wallpapers` through `bin/dotfiles --action wallpapers` to one manager with Add, Inspect, Move, Remove, and Back. Offer only installed packaged and user theme slugs, showing each exact slug and origin. Process one Intake image per visible, confirmed Add plan; make duplicate cleanup explicit. Keep Inspect read-only. Move or remove one Theme assignment at a time, warn before final-assignment deletion, and preserve source state on cancellation or failure. After successful curation, offer the separate deployment Apply once when leaving the manager.

Reason: One-image plans and explicit assignment changes keep destructive effects reviewable, while a separate exit-time deployment offer preserves transaction boundaries without making local refresh cumbersome.

## Fail Starship validation on diagnostics

Applies when: Validating a Starship configuration or adding its package validators and focused tests.

Guidance: Run `starship print-config` with a fresh isolated `STARSHIP_CACHE` and a fixed `STARSHIP_SESSION_KEY`, and require both a successful status and empty standard error. Use controlled `starship prompt` or `starship module` renders to verify behavior and appearance.

Reason: Starship 1.26.0 can report malformed TOML or invalid values on standard error, fall back to defaults, and still return status 0; its cache can also suppress repeated diagnostics.

## Test Starship directory substitutions with absolute paths

Applies when: Changing Starship directory substitutions or their focused tests.

Guidance: Starship 1.26.0 applies each regex substitution entry to one match before directory truncation. Use equivalent absolute physical and logical fixture paths below an isolated home. Cover earlier hidden matches, repeated visible components, repository roots, and truncated repository children. Use ordered rightmost passes when every visible repeated component must change.

Reason: Relative fixtures skip home contraction and can skip truncation. A single regex entry can also replace a hidden component while leaving the visible occurrence unchanged.

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

Guidance: Use `make` and guided setup as the intended human workflow. Keep every operation available as a standalone wizard action. The current sequence is prerequisite preparation, pinned global skill installation, application cleanup, Stow package application, and optional shared Brave policy application. Phase five calls the same apply function as the standalone action. It skips successfully when no supported browser is installed or the human declines. Use Gum with a Bash fallback. Start Stow package selection with no package selected. Continue after a skipped nonessential phase. Stop after an operational failure and name the related standalone action for recovery. Preserve public action preselection and noninteractive operation functions for Make targets, agents, scripts, and tests, but keep them out of normal human instructions.

Reason: The wizard is the normal user interface and must make each system change visible and recoverable; the privileged Brave policy remains optional and reuses one tested lifecycle.

## Store migration backups in XDG state

Applies when: An approved migration preserves an existing target before Stow links it.

Guidance: Write timestamped backups below the user's XDG state directory, outside Git.

Reason: Migration backups are local recovery data, not repository content.

## Prepare wizard prerequisites through Omarchy

Applies when: Any repository-declared core prerequisite is missing or outside its supported constraint.

Guidance: Show one complete prerequisite plan and ask for confirmation. Delegate installation and privilege handling to Omarchy. In the same run, verify every repository-declared prerequisite command and version constraint. In guided setup, stop before later phases if the user declines required prerequisites or if installation or verification fails.

Reason: Guided setup must establish and verify its required tools without implementing Omarchy package management or privilege handling.

## Keep package dependencies explicit

Applies when: One Stow package requires another package.

Guidance: Declare the edge in the package catalog and make the wizard show whether the dependency will be included or blocks the requested operation.

Reason: Hidden package dependencies would make package selection and removal unpredictable.

## Install global agent skills conservatively

Applies when: Running the wizard's agent-skill action or updating manifest-declared global skills.

Guidance: Install every skill exposed by the source installers at the revisions pinned in the manifest. Delegate draft exclusion, skill discovery, and supporting-file installation to each source's documented installer; this repository adds only manifest pinning, complete recursive difference preview, confirmation, comprehensive pre-mutation backup, and verification. Before a mutating source installer runs, back up every existing skill it can rewrite, including currently unchanged skills, then verify its output against the approved preview. The skill update operation previews upstream and installed-skill differences, then atomically updates the manifest and installed skills after one approval. A failed update restores both the prior manifest and skill backups.

Reason: Future agents need reproducible repository skills without silently overwriting global customizations.

## Order wizard changes explicitly

Applies when: The wizard prepares any package change.

Guidance: Before mutation, inspect the Omarchy version, determine dependencies and conflicts, check core and package-specific tools at the points when their package set is known, show the complete plan, and request confirmation. Block removal when another linked package depends on the selected package and name each dependent.

Reason: The human must see version, prerequisite, and dependency effects before the first mutation.

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
