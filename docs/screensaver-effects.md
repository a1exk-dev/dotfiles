[Back to README](../README.md)

# Selective screensaver effects

The `screensaver-effects` Stow package limits automatic idle and System-menu Omarchy screensavers to a tracked allowlist of mapped `ttfx` effects. It resolves the active Omarchy theme for each effect process.

Stock CLI screensaver commands remain unchanged. Omarchy continues to own lock and wake behavior, terminal selection, monitor policy, branding, and the black screensaver background.

## Requirements

The package was verified with:

- Omarchy `4.0.1-1`
- `ttfx` package `0.3.2-1`
- `ttfx` CLI `0.3.2`

It requires:

- GNU Stow
- Node.js 22.20.0 or newer
- `omarchy`
- `omarchy-shell`
- `xdg-terminal-exec`
- `hyprctl`
- `omarchy-screensaver`
- `omarchy-toggle-enabled`
- `omarchy-hyprland-monitor-focused`
- A writable absolute `XDG_STATE_HOME`, or the default `~/.local/state`
- A writable absolute `XDG_RUNTIME_DIR` during launch and preview
- Alacritty, Ghostty, Foot, or Kitty as the active terminal

The package catalog declares `ttfx`, `jq`, and `socat` as Arch requirements. The Dotfiles wizard installs missing requirements through Omarchy after confirmation. Gum is optional.

Version mismatches produce warnings. Previously mapped effects that remain installed stay available. New effects remain Unmapped until their colors and command grammar are reviewed.

## Owned files

The Stow package installs:

- `~/.config/dotfiles/screensaver-effects.json`
- `~/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/`
- `~/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/`
- `~/.local/libexec/dotfiles/screensaver-effects-selector`

The lifecycle also manages:

- `~/.config/omarchy/plugins/dotfiles.idle`
- `~/.config/omarchy/plugins/dotfiles.indicators`
- Its `system.screensaver` entry in `~/.config/omarchy/extensions/omarchy-menu.jsonc`
- Receipts, migration backups, and diagnostics under `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/screensaver-effects/`

The package does not own the complete `shell.json`, complete menu extension, Stay Awake state, preview runtime, or unrelated Omarchy plugin and bar settings.

## Apply

Start the Dotfiles wizard:

```bash
make
```

Choose `Apply Stow packages`, select `screensaver-effects`, review the package and Arch requirement plan, and approve it.

Apply validates the complete package before activation. It then publishes both complete plugin-directory links, preserves the existing Indicators placement and options, enables the idle clone, and adds the System-menu screensaver route.

An exact repeated Apply does not rescan the plugin registry or rewrite lifecycle state.

If another personal clone of `omarchy.idle` or `omarchy.indicators` exists, Apply stops without replacing it. Return to the wizard and choose `Migrate competing screensaver clones`. Migration stores complete backups under the lifecycle XDG state directory before it changes activation.

## Manage effects

Run:

```bash
make screensaver-effects
```

The manager requires terminal input and output. It reads the installed `ttfx` catalog and labels effects as Full, Partial, Unmapped, or Unavailable.

`Change effects` uses Gum multi-select when Gum is installed. Otherwise, it uses a numbered Bash prompt. New Partial effects require one acknowledgement because they retain fixed upstream colors.

`Preview effect` opens one production-configured screensaver terminal on the focused monitor. A Partial preview requires a separate acknowledgement. Preview does not save or discard pending changes.

`Save` writes the repository source atomically and verifies that the deployed Stow leaf still resolves to it. An unchanged selection is a no-op. An empty selection and unresolved invalid entries cannot be saved.

The tracked default is:

```json
[
  "matrix"
]
```

One allowlisted name always selects that effect. Several names are sampled independently and uniformly for each new effect process. Repeats are allowed.

Save updates the tracked repository source but does not create a Git commit.

## Runtime behavior

The allowlist applies to automatic idle launches and the System-menu Screensaver action. Stock CLI and direct packaged screensaver commands remain unchanged.

The runtime reads and validates the complete allowlist for every effect process. It resolves active theme colors at the same boundary, so a later valid save or theme change applies to the next effect.

Full effects expose all visible mapped colors. Partial effects retain one or more fixed upstream colors. Omarchy's stock runner continues to set the terminal background to black.

A configuration, mapping, token, launch, or effect failure does not fall back to stock random selection or another effect. A failure detected after terminal launch leaves a blank dismissible screensaver process instead of entering the stock runner's retry loop. One automatic or System-menu launch attempt emits at most one notification and one matching log entry.

## Status and recovery

Choose `Package status` to inspect both the Stow links and lifecycle state. The lifecycle reports one of:

- `active`
- `inactive`
- `drifted`
- `conflicting`
- `recovery-required`

Use the recovery action printed by Package status before another mutation. Apply repairs receipt-owned drift but refuses unrelated conflicts.

Migration backups, receipts, and diagnostics remain under:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/screensaver-effects/
```

## Remove

Start the wizard, choose `Remove Stow package`, and select `screensaver-effects`.

Removal first restores the prior Omarchy idle and Indicators state. It removes both live Dotfiles plugin links and deletes the System-menu entry only when the receipt proves that the lifecycle inserted it and its bytes are unchanged. Generic Stow removal runs after deactivation succeeds.

Removal retains:

- Lifecycle receipts
- Migration backups
- Failure diagnostics
- Successfully migrated old plugin clones stored in backups
- The repository allowlist source
- The `ttfx`, `jq`, and `socat` Arch packages

Normal removal does not reactivate a successfully migrated old personal clone.

## Manual verification

After Apply:

1. Choose `Package status` and confirm that `screensaver-effects` is linked and `active`.
2. Launch Screensaver from the Omarchy System menu.
3. Confirm that the effect is in the allowlist and uses the active-theme mapping.
4. Dismiss it with the normal screensaver input behavior.
5. Remove the package and confirm that Package status reports the prior Omarchy plugin and bar state restored.

This check does not require waiting for automatic idle, changing lock timing, testing wake behavior, using a second monitor, or testing every supported terminal.
