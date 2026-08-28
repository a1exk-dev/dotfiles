# Canonical Context

## Dotfiles repository

Portable Omarchy dotfiles for the current supported Omarchy version, deployed with GNU Stow. The repository is the source of truth for configuration files, scripts, hooks, themes, and required assets. It excludes live application state and complements Omarchy rather than owning general operating-system package provisioning. The wizard delegates explicit repository prerequisites and package-specific Arch requirements to Omarchy. The current target is Omarchy version 4.

## Stow package

A lowercase-named deployment unit under `config/<name>/` for one application or tightly coupled configuration concern. Its directory tree mirrors target paths under the user's home directory, and GNU Stow deploys it through symlinks instead of copying its files. Users edit the source inside the repository.

## Dotfiles wizard

The intended human interface for repository setup and operations. Guided setup runs prerequisite preparation, pinned global agent-skill installation, application cleanup, Stow package application, and Wallpaper library deployment, then optionally applies the Shared Brave configuration as phase six. Standalone actions provide each operation separately. Public routes provide the same operations to Make targets, agents, scripts, and tests.

## Shared Brave configuration

One repository-owned managed-policy intent for Brave Browser and Brave Origin. Both products consume the same system policy, while browser profiles, Omarchy-owned launch flags and color policy, theme state, and font settings remain outside this boundary. Product differences belong to installed-consumer detection and manual guidance rather than duplicated policy sources.

## Application cleanup profile

The root `cleanup.json` file that contains saved selection defaults for removable Arch packages, Omarchy web apps, and Omarchy TUI launchers. Available defaults start selected during application cleanup. A selection change applies only to the current run. The profile does not record installed state and does not continuously suppress applications.

## Package catalog

`packages.json` is the package catalog. Each entry declares a Stow package's description, command prerequisites, Arch package requirements, Stow dependencies, validators, documentation, and cleanup notes.

## Skill manifest

The root `skills.json` file containing exact source revisions, each repository's official installation method, expected collection sizes, and installation requirements for global agent skills placed under `~/.agents/skills/`.

## Telegram theme integration

A dedicated `telegram-theme` Stow package that adapts the active Omarchy semantic colors to Telegram Desktop's native theming. The repository owns the color mapping and integration lifecycle; generated output is integration-owned, regenerable local state; Telegram owns saved theme and account state. The visual promise is Omarchy colors and clear native sections within Telegram's native structure, rather than structural TUI styling.

## Screensaver effect allowlist

The repository-owned nonempty set of verified `ttfx` effects available to the selective Omarchy screensaver integration. One member fixes the effect; several members are sampled independently and uniformly at each effect start. Members may have Full or Partial active-theme mappings, while effects without a verified mapping remain outside the allowlist.

## Wallpaper inbox

The repository-local, untracked holding area for maintainer-supplied image files awaiting acceptance. Its contents are intake images, not repository-owned assets.

## Intake image

An image file in the Wallpaper inbox that has not been accepted as a Managed wallpaper. It remains maintainer-owned input until curation succeeds.

## Managed wallpaper

A validated image accepted into the Wallpaper library. Its identity comes from its exact file content, not its original name or Theme assignments, and it exists only while it has at least one Theme assignment.

## Theme assignment

The relationship that makes one Managed wallpaper available to one Omarchy theme. A Managed wallpaper can have Theme assignments to multiple themes, and those assignments can change without changing its identity.

## Wallpaper library

The repository-owned collection of Managed wallpapers grouped by Theme assignment. A Managed wallpaper assigned to multiple themes appears in each corresponding group while retaining one identity.
