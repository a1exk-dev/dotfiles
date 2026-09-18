# Canonical Context

## Dotfiles repository

Portable Omarchy dotfiles for the current supported Omarchy version, deployed with GNU Stow. The repository is the source of truth for configuration files, scripts, hooks, themes, and required assets. It excludes live application state and complements Omarchy rather than owning general operating-system package provisioning. The wizard delegates explicit repository prerequisites and package-specific Arch and AUR requirements to Omarchy. The current target is Omarchy version 4.

## Stow package

A lowercase-named deployment unit under `config/<name>/` for one application or tightly coupled configuration concern. Its directory tree mirrors target paths under the user's home directory, and GNU Stow deploys it through symlinks instead of copying its files. Users edit the source inside the repository.

## Dotfiles wizard

The intended human interface for repository setup and operations. Guided setup runs nine phases in order: prerequisite preparation; pinned global agent-skill installation; application cleanup; optional application installation; Stow package application; Wallpaper library deployment; optional Shared Brave configuration application as phase seven; optional Laptop power policy application as phase eight; and an optional OBS machine set installation through `Install OBS set` as phase nine. Standalone actions provide each operation separately, including `Manage laptop power policy`. Public routes provide the same operations to Make targets, agents, scripts, and tests.

## Keyboard layouts

The Omarchy-native US English and Russian layout setup. The `hyprland` Stow package's `input.lua` sets `kb_layout = "us,ru"` with Omarchy's `grp:alts_toggle`, so Left Alt + Right Alt switches layouts, and stock Fcitx follows the compositor layout in its own clients. The stock `omarchy.keyboard-layout` indicator shows the active layout; the `shell-layout` action places it first in the bar's right section, before the system tray. The repository owns no switching logic, plugin, or Fcitx state.

## Hyprland machine profile

A tracked directory in the `hyprland` Stow package, named for the machine it configures (`pc` or `laptop`), holding that machine's `monitors.lua` and its machine-specific `bindings.lua`. The package links every profile into `~/.config/dotfiles/hypr/` and changes no active configuration. The shared `~/.config/hypr/monitors.lua` and `bindings.lua` load the selected profile through the `hypr.machine` module path and keep Omarchy's defaults while no profile is selected. The `Select Hyprland profile` action owns one link, `~/.config/hypr/machine`, and points it at the profile the human chooses, so the machine is never inferred from its hostname. Hotkeys that every machine uses stay in the shared `bindings.lua` rather than in a profile.

## Shared Brave configuration

One repository-owned managed-policy intent for Brave Browser and Brave Origin. Both products consume the same system policy, while browser profiles, Omarchy-owned launch flags and color policy, theme state, and font settings remain outside this boundary. Product differences belong to installed-consumer detection and manual guidance rather than duplicated policy sources.

## Laptop power policy

One repository-owned UPower and logind administrator-drop-in intent with user-owned lifecycle evidence. Native UPower and logind enforce its behavior; hibernation provisioning, foreign drop-ins, and Omarchy packaged power and sleep behavior remain outside this boundary.

## Application cleanup profile

The root `cleanup.json` file that contains saved selection defaults for removable Arch packages, Omarchy web apps, and Omarchy TUI launchers. Available defaults start selected during application cleanup. A selection change applies only to the current run. The profile does not record installed state and does not continuously suppress applications.

## Package catalog

`packages.json` is the package catalog. Each entry declares a Stow package's description, command prerequisites, Arch package requirements, optional AUR package requirements, Stow dependencies, validators, documentation, and cleanup notes.

## Optional application catalog

The repository-owned installation intent for standalone Arch applications that are desired on a fresh machine but are neither Dotfiles wizard prerequisites nor coupled to a Stow package. The wizard delegates package management to Omarchy, while application configuration and state remain outside this catalog.

## Skill manifest

The root `skills.json` file containing exact source revisions, each repository's official installation method, expected collection sizes, and installation requirements for global agent skills placed under `~/.agents/skills/`.

## Telegram theme integration

A dedicated `telegram-theme` Stow package that adapts the active Omarchy semantic colors to Telegram Desktop's native theming. The repository owns the color mapping and integration lifecycle; generated output is integration-owned, regenerable local state; Telegram owns saved theme and account state. The visual promise is Omarchy colors and clear native sections within Telegram's native structure, rather than structural TUI styling.

## Discord system24 integration

A repository-owned customization that applies the upstream system24 theme to the stock Discord desktop client through Vencord, with its colors following the active Omarchy theme and its font following the Omarchy font. Unlike Telegram theme integration, its visual promise includes system24's structural TUI styling. Upstream owns system24's structure and delivery; the repository owns the Omarchy color and font adaptation, one generated Vencord theme file, and the Vencord patch lifecycle on Discord's self-updated `app-*` directory. It is a separate Stow package that depends on the `discord` package. Discord and Vencord own their settings, including which themes are enabled. Vencord plugins, Vesktop, and Omarchy's Discord web app remain outside this boundary.

## OBS theme integration

The `obs-theme` Stow package that makes OBS Studio's interface follow the active Omarchy theme and font through one hook-published user theme, `Omarchy.ovt`, extending OBS's stock Yami theme. The repository owns the colour mapping, the light-icon fragment, the published theme file, and the two `user.ini` keys that select it (`[Appearance] Theme` and `AutoReload`), written only while OBS is closed. OBS owns every other part of `user.ini`.

## OBS scene integration

The `obs-scene` Stow package, which depends on OBS theme integration, that renders the Omarchy-styled scene assets (SVG chrome, `theme.txt`, `chat.css`, the camera-off avatar layers and `title.txt`) into `~/.config/obs-studio/omarchy-scene/` at one OBS machine set's canvas, plus the Lua script that carries theme changes into a running OBS. The repository owns the generator, the script and that asset folder. The copied scene collection belongs to OBS. The avatar portrait is tracked in the package and linked to `~/.config/dotfiles/obs-avatar.jpg`; the generator renders for that exact image and stops with an error for any other file, because every collection declares the avatar layers. A render runs on `Install OBS set`, on an Omarchy theme or font change, and on applying the package once a set's `geometry.json` exists.

## OBS machine set

A repository-tracked bundle under `obs/sets/<set>/` of one machine's OBS profiles and its generated `Omarchy Scene` collection with the `geometry.json` that drives the scene render. `Install OBS set` copies a set into OBS instead of linking it, because OBS rewrites those files; once copied, the profiles and collection belong to OBS, with no receipt and no Remove. Sets are chosen by the human and never coupled to the hostname.

## Voxtype profile

One tracked Voxtype configuration file in the `voxtype` Stow package, named for the machine it configures (`pc` or `laptop`). The package links every profile into `~/.config/dotfiles/voxtype/` and changes no active configuration. The `Select Voxtype profile` action owns one link, `~/.config/voxtype/config.toml`, and points it at the profile the human chooses, so the machine is never inferred from its hostname. Voxtype owns everything else below `~/.config/voxtype/`, and the installed executable variant that selects CPU or GPU acceleration stays outside this boundary.

## Screensaver effect allowlist

The repository-owned nonempty set of verified `ttfx` effects available to the selective Omarchy screensaver integration. One member fixes the effect; several members are sampled independently and uniformly at each effect start. Members may have Full or Partial active-theme mappings, while effects without a verified mapping remain outside the allowlist.

## Selective screensaver integration

The repository-owned Omarchy customization that applies the Screensaver effect allowlist to automatic idle and System-menu launches. The repository owns its Stow sources and receipt-managed activation edges. Omarchy owns the shared shell configuration and general idle, lock, wake, terminal, and monitor behavior, while stock CLI screensaver launches remain outside the integration.

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
