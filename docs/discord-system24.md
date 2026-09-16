[Back to README](../README.md)

# Discord system24 theme integration

The `discord-system24` Stow package applies the upstream system24 theme to the stock Discord desktop client through Vencord. Its colors follow the active Omarchy theme. Its font follows the Omarchy font. system24 is a TUI-style theme, so it also changes the structure of the client: it draws framed sections and visible borders.

The Stow package owns the Omarchy color and font adaptation, one generated Vencord theme file, and the Vencord patch on Discord's self-updated `app-*` directory. Discord and Vencord keep their own settings, which include the list of enabled themes. Vesktop, Vencord plugins, and Omarchy's Discord web app are outside this package.

## Requirements

The integration supports Omarchy 4.0. It was tested with these versions:

- Omarchy `4.0.3-1`
- `discord` `1:1.0.156-1`
- `vencord-installer-cli-bin` `1.4.0-3`

It also requires:

- GNU Stow
- The `discord` Stow package, which the Dotfiles wizard applies as a dependency
- Network access while Discord loads the theme, because the generated file imports system24 from `https://refact0r.github.io`

The Package catalog declares the AUR package `vencord-installer-cli-bin`. That package supplies the `vencordinstallercli` command. The Dotfiles wizard installs the package with `omarchy pkg aur add` after you approve the package plan. Third-party maintainers supply AUR packages, and Arch does not review them. Examine the package before you approve the plan.

If the Omarchy version is outside the 4.0 series, the apply operation, the removal, and the patch action ask for your consent. The hooks fail closed instead: they exit with a nonzero status and keep the last generated theme file. Discord and the Vencord command have no version check.

## Owned files

The Stow package links three files:

- `~/.config/omarchy/themed/discord-system24.css.tpl`
- `~/.config/omarchy/hooks/theme-set.d/discord-system24`
- `~/.config/omarchy/hooks/font-set.d/discord-system24`

The font hook is a link to the theme hook, so both hooks run the same publication.

Omarchy renders the template into its active theme state:

```text
~/.local/state/omarchy/current/theme/discord-system24.css
```

The hooks put the current font into that file. Then they publish the file that Vencord reads:

```text
~/.config/Vencord/themes/omarchy-system24.css
```

Vencord owns all other files in `~/.config/Vencord/`. These include `settings/settings.json`, which records the enabled themes, `settings/quickCss.css`, and `dist/`. The integration does not write these files. Discord owns its `~/.config/discord/app-*` directories.

## Install

Start the Dotfiles wizard:

```bash
make
```

Select `Apply Stow packages`, then select `discord-system24`. The plan includes the `discord` package as a dependency. The plan also lists `vencord-installer-cli-bin` as an AUR requirement. Examine the plan, then approve it.

The apply operation links the template and the two hooks. It does not patch Discord, and it does not generate the theme file. The Dotfiles wizard names `Patch Discord with Vencord` as the next step.

## Patch Discord

Start the Dotfiles wizard again. Select `Patch Discord with Vencord`.

The action finds the newest `~/.config/discord/app-*` directory. It shows this command before it makes a change:

```text
vencordinstallercli --repair --location <app-dir>
```

After you confirm, the action runs the command. Then it makes sure that `<app-dir>/resources/_app.asar` is present. If that file is not present, the action reports a failure.

The action does not start or stop Discord. Start Discord again yourself to load Vencord.

The action stops with a message if `vencordinstallercli` is not installed, or if no `app-*` directory is present. Start Discord one time to let it install an app directory. Then run the action again.

## Enable the theme one time

The apply operation does not write the Vencord theme file. The hooks write that file when you set an Omarchy theme or an Omarchy font.

After the file is present, start Discord and go to **Vencord → Themes**. Enable `omarchy-system24.css`. You do this one time only. Vencord records your selection in its own settings, and the integration does not write those settings.

## Automatic updates

After you enable the theme, each Omarchy theme change or font change does the following:

1. Omarchy renders `discord-system24.css` from the active palette.
2. The hook reads the current font from `omarchy-font-current`.
3. The hook writes the completed theme to a temporary file in the themes directory, then moves it into place.
4. If the new output is the same, the hook does not change the existing file.
5. A running Discord client reads the new file. You do not need to start Discord again.

The hook exits with a nonzero status and keeps the last generated file if the Omarchy version is outside the 4.0 series, if the rendered theme is missing, or if it cannot write the output.

## Status

Select `Package status`. Below the `discord-system24` line, the Dotfiles wizard reports:

- The newest `app-*` directory as patched or unpatched
- The generated theme file as present or absent

`Package status` is read-only.

## Patch Discord again after a Discord update

Discord updates itself and installs a new `app-*` directory. The new directory is unpatched, so Vencord and the theme do not load after that update.

Select `Patch Discord with Vencord` again, then start Discord again. The integration does not do this automatically: it has no watcher and no Pacman hook. When a new patch operation is necessary, `Package status` shows the newest directory as unpatched.

## Remove

Start the Dotfiles wizard, select `Remove Stow package`, then select `discord-system24`.

The plan shows the unpatch operation, the links, and the cleanup notes. One confirmation applies to all of them. The removal then does these steps:

1. It unpatches the newest `app-*` with `vencordinstallercli --uninstall --location <app-dir>`, then makes sure that `_app.asar` is gone.
2. It deletes `~/.config/Vencord/themes/omarchy-system24.css`.
3. It unlinks the Stow package.

If no `app-*` directory is patched, the plan tells you that it skips the unpatch operation.

The removal stops before step 2 if the command is not installed, if the unpatch operation fails, or if `_app.asar` stays in place. The Stow package stays applied, and the theme file stays in place. Correct the installer problem, then remove the package again.

The removal keeps these items:

- The `vencord-installer-cli-bin` and `discord` packages
- Vencord's settings, which include the enabled theme entry, `quickCss.css`, and `dist/`
- Older `app-*` directories, which keep their Vencord patch

To make Vencord stop showing the theme, disable `omarchy-system24.css` in **Vencord → Themes**.

## Manual verification

These checks are manual, because Discord has no supported interface that reports its appearance.

1. Make sure that `Package status` shows the newest `app-*` as patched and the theme file as present.
2. Start Discord. Make sure that it shows the system24 layout, the active Omarchy colors, and the Omarchy font.
3. Set a different Omarchy theme while Discord runs. Do this one time with a dark theme and one time with a light theme. Make sure that Discord follows each change without a restart.
4. Make sure that the text stays readable, and that no section keeps the colors of the previous theme.
