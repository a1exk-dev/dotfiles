[Back to README](../README.md)

# Telegram Desktop theme integration

The `telegram-theme` Stow package adapts the active Omarchy palette to Telegram Desktop's native theme format. It changes Telegram's colors and chat background. Telegram still owns its layout, controls, icons, fonts, spacing, and behavior.

The integration uses Omarchy's user theme template and `theme-set.d` hook. It does not modify Omarchy-packaged files, launch or restart Telegram, automate Telegram's interface, or read or edit Telegram's private `tdata`.

## Requirements

The integration supports these exact package versions:

- Omarchy `4.0.1-1`
- Telegram Desktop `7.0.9-4`

It also requires:

- GNU Stow
- Node.js 22.20.0 or newer
- `zip`
- `flock`
- A writable absolute `XDG_STATE_HOME`, or the default `~/.local/state`
- A writable absolute `XDG_RUNTIME_DIR` while the hook runs

The package catalog declares `telegram-desktop` and `zip` as Arch requirements. If either is missing, the Dotfiles wizard includes it in the package plan and installs it through Omarchy after approval.

A different Omarchy or Telegram Desktop package version fails closed. The integration retains the last valid generated theme until the compatibility baseline and tests are updated.

## Owned files

The Stow package installs these user-owned files:

- `~/.config/omarchy/themed/telegram-omarchy-theme.json.tpl`
- `~/.config/omarchy/hooks/theme-set.d/telegram-theme`
- `~/.local/libexec/dotfiles/telegram-theme/`

Omarchy renders the template into its active generated theme state as `telegram-omarchy-theme.json`.

The integration writes its generated archive and diagnostics below:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/telegram-theme/
```

The stable Telegram theme path is:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/telegram-theme/current.tdesktop-theme
```

The hook uses `XDG_RUNTIME_DIR` for its synchronization lock.

## Install

Start the Dotfiles wizard:

```bash
make
```

Choose `Apply Stow packages`, select `telegram-theme`, review the complete package and Arch requirement plan, and approve it.

Package application links the tracked template, hook, generator, and pinned role data. It does not refresh the active Omarchy theme or change Telegram's selected theme.

## Set up synchronization

Start the wizard again:

```bash
make
```

Choose `Manage Telegram theme`, then `Setup / refresh`.

Setup verifies the exact supported package versions and shows this planned command:

```text
omarchy theme refresh
```

The refresh regenerates Omarchy's user theme templates and invokes the installed theme-set hook. It can retint other Omarchy-managed applications, so the wizard requires approval before it runs the command.

After a successful refresh, the wizard verifies the stable archive and prints its path. With the default state directory, import:

```text
~/.local/state/dotfiles/telegram-theme/current.tdesktop-theme
```

If Telegram's file chooser hides `.local`, enable **Show Hidden Files**. If you set `XDG_STATE_HOME`, use `$XDG_STATE_HOME/dotfiles/telegram-theme/current.tdesktop-theme` instead. Review the preview and select **Keep Changes** once.

Telegram then watches that stable path. Keeping the file changes Telegram's global local appearance state and can affect account-backed selected-theme metadata through Telegram's supported behavior. The Dotfiles wizard does not open Telegram or select **Keep Changes**.

## Automatic updates

After the one-time import and Keep step, a normal Omarchy theme set or refresh does the following:

1. Omarchy renders `telegram-omarchy-theme.json` from the active semantic palette.
2. The hook verifies that its event slug is still current.
3. The generator builds and validates a candidate archive.
4. Identical output is left untouched.
5. Changed output atomically replaces the stable archive.
6. Running Telegram reloads the watched file.
7. Stopped Telegram rereads the file at its next startup.

The hook does not run in Omarchy's headless or offline theme modes. Use `Retry` after returning to a normal desktop session.

Changing only the Omarchy background does not fire the theme-set hook.

## Validation

Each published archive contains exactly:

```text
colors.tdesktop-theme
background.png
```

Before publication, the integration checks:

- The pinned 586 Telegram Desktop 7.0.9 color roles and their order
- Unique direct hexadecimal assignments without aliases or placeholders
- Telegram's file, member, pixel, CRC, compression, and encryption limits
- A deterministic opaque flat PNG background
- At least `4.50:1` contrast for every declared text and background pair
- At least `0.025` OKLab separation for declared adjacent primary surfaces
- Source-palette-only fallback colors
- The exact supported Omarchy and Telegram package versions

An invalid custom Omarchy palette is not published.

## Status and retry

Choose `Manage Telegram theme`, then `Status`, to inspect the stable archive and persisted diagnostics. Status is read-only. It does not refresh Omarchy, generate a theme, launch Telegram, or alter Telegram state.

A generation, validation, packaging, compatibility, or publication failure preserves the previous stable archive. The first occurrence sends a desktop notification. Repeated failures with the same fingerprint do not send another notification.

Choose `Retry` to reuse the promoted active Omarchy manifest without running `omarchy theme refresh`.

If Telegram no longer follows the stable file after a successful retry, import the same path again and select **Keep Changes**.

## Custom Omarchy themes

A custom theme is supported when its resolved `colors.toml` supplies the common Omarchy semantic palette and passes all archive, contrast, and surface-separation checks.

The generator can choose another allowed source surface when the preferred pair is too close. It does not invent a fallback color. If no source color passes, the last valid archive remains unchanged.

## Remove and restore

Before removal, select a built-in Telegram theme if you no longer want Telegram to use the generated theme.

Start the wizard, choose `Remove Stow package`, and select `telegram-theme`.

Removal unlinks the tracked template, hook, generator, and role data. It stops future synchronization but leaves these items in place:

- The generated XDG state directory
- The stable generated archive
- Diagnostic status
- Telegram's saved theme selection
- The `telegram-desktop` and `zip` packages

After selecting another Telegram theme and removing the Stow package, you can remove the retained integration state:

```bash
rm -rf -- "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/telegram-theme"
```

Do not delete the stable archive while Telegram still uses it as the selected watched theme.

## Manual verification

These checks are manual because Telegram has no supported automation interface for local theme import or selection.

1. Put Telegram on a privacy-safe screen. Do not capture or record it.
2. Set Omarchy to Solitude through the normal Omarchy theme action.
3. Confirm that Telegram changes while running and that its native sections, incoming messages, outgoing messages, hover states, and selected chat remain distinct and readable.
4. Repeat the running-client check with Tokyo Night, Everforest, and one stock light theme.
5. Close Telegram without changing the watched file.
6. Change the Omarchy theme through the normal Omarchy theme action.
7. Start Telegram yourself and confirm that it loads the new palette.
8. Stop if Telegram loses the watch, shows an unexpected prompt, or fails to restore expected appearance. Use `Retry`, then manually import and Keep the stable file again if needed.

Do not automate Telegram's UI, inspect `tdata`, or launch or restart Telegram from the integration.
