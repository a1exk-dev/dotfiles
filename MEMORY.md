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

## Defer machine-specific mechanisms

Applies when: A configuration first requires a monitor name, device path, username, or other machine-specific value.

Guidance: Decide the handling mechanism from that concrete case instead of adding profiles or templates in advance.

Reason: The repository has no current machine-specific requirement to design around.

## Operate Stow packages safely

Applies when: Adding, applying, editing, verifying, or removing a Stow package.

Guidance: Edit tracked files inside the repository. Run a Stow dry run, stop and show any existing-file conflict, verify the expected links, and verify clean removal. Target the user's home directory by default; decide any other target with the human when a concrete need appears.

Reason: Repository-owned symlinks must remain predictable and must not replace user files without a decision.

## Escalate full Omarchy replacements

Applies when: An Omarchy customization might require tracking a complete configuration file.

Guidance: Prefer an Omarchy-supported override. Track a full configuration only when an override cannot express the required behavior, after reviewing the replacement scope with the human.

Reason: Omarchy should continue to own its packaged defaults wherever its customization seams are sufficient.

## Stop before tracking sensitive values

Applies when: Candidate content contains a credential, token, session value, account identifier, or other sensitive value.

Guidance: Stop before adding the content and ask the human to choose exclusion, a local value, or encryption.

Reason: The repository has no blanket policy that makes sensitive values safe to track.

## Document prerequisites and installers

Applies when: A Stow package requires software that Omarchy does not already provide.

Guidance: List the prerequisite and its Omarchy-supported installation command when available. Add an installation script only after making that choice for the package, and document the script in the relevant topic guide.

Reason: The repository synchronizes dotfiles by default but may carry explicit package-specific installers when they are justified.

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

Guidance: Support package status, apply, removal, and confirmed prerequisite installation. Launch interactive mode through `make`, use Gum with a Bash fallback, select no changes by default, and expose the same engine through noninteractive commands. Stop on the first failed package, preserve earlier successes, and report recovery steps.

Reason: The wizard is the normal user interface and must make each system change visible and recoverable.

## Store migration backups in XDG state

Applies when: An approved migration preserves an existing target before Stow links it.

Guidance: Write timestamped backups below the user's XDG state directory, outside Git.

Reason: Migration backups are local recovery data, not repository content.

## Offer confirmed Stow installation

Applies when: The wizard finds that GNU Stow is missing.

Guidance: Explain the missing prerequisite and offer the Omarchy-supported installation command after human confirmation.

Reason: GNU Stow is required for package deployment but is not present by default on the current Omarchy 4 system.

## Keep package dependencies explicit

Applies when: One Stow package requires another package.

Guidance: Declare the edge in the package catalog and make the wizard show whether the dependency will be included or blocks the requested operation.

Reason: Hidden package dependencies would make package selection and removal unpredictable.

## Handle Omarchy mismatch before changes

Applies when: The wizard detects an Omarchy version different from the repository's current target.

Guidance: Show both versions and ask the human whether to continue before changing packages.

Reason: Compatibility outside the current target is not guaranteed, but inspection and an explicit human decision remain useful.

## Delegate privilege to Omarchy

Applies when: An approved prerequisite installation requires elevated privileges.

Guidance: Call the supported Omarchy command and let it manage privilege prompts.

Reason: The wizard should not reproduce Omarchy's package-management or privilege behavior.

## Install global agent skills conservatively

Applies when: Running the wizard's agent-skill action or `make skills`.

Guidance: Install every skill exposed by the official installers at pinned revisions from `https://github.com/blader/humanizer` and `https://github.com/mattpocock/skills` under `~/.agents/skills/`. Delegate draft exclusion, skill discovery, and supporting-file installation to each repository's documented installer; this repository adds only version pinning, difference preview, confirmation, and backup. When an installed skill differs, stop and show the difference before replacement. After approval, back it up under XDG state before installing the pinned copy. `make skills-update` previews upstream and installed-skill differences, then updates `skills.json` and global skills together after one approval. A failed update restores both the old manifest and global skill backups.

Reason: Future agents need reproducible repository skills without silently overwriting global customizations.

## Order wizard changes explicitly

Applies when: The wizard prepares any package change.

Guidance: Check the Omarchy version, check required tools, calculate package dependencies and conflicts, show the complete plan, and then request confirmation. Block removal when another linked package depends on the selected package and name each dependent.

Reason: The human must see version, prerequisite, and dependency effects before the first mutation.

## Separate current behavior from planned design

Applies when: Writing `README.md`, `docs/stow.md`, or `docs/agent-setup.md` before the described tooling is implemented.

Guidance: Present working commands only as current quick-start steps and label the wizard, package catalog, and package workflow as planned. List global agent skills as development requirements rather than end-user runtime requirements.

Reason: Human documentation must describe the repository honestly while preserving the agreed target design.
