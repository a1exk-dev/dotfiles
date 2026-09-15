[Back to README](../README.md)

# Discord

The `discord` Stow package keeps the Discord desktop client's local settings. It links one file:

- `~/.config/discord/settings.json`, linked to `config/discord/.config/discord/settings.json`

Stow links it with `--no-folding`, so `~/.config/discord/` stays an ordinary directory for Discord's own data.

## Requirements

The package plan installs the `discord` Arch package through Omarchy after you confirm it.

## Tracked settings

`settings.json` holds client options (OpenH264, ADM offload, startup background color) and flags Discord writes itself. It has no token, account ID, email, or home path. Account, server, and appearance settings live on Discord's servers and follow your login.

## What stays local

Everything else under `~/.config/discord/` stays local: cookies, local storage, caches, logs, `Preferences` (it has a device salt), self-updated `app-*` directories, and installer state.

## Changes through the link

Discord writes the file in place, so changes show up as a Git diff. Review it, then commit it or run `git restore`.

## Removal

Start `make`, choose `Remove Stow package`, and select `discord`. Only the link is removed. Discord recreates a default `settings.json` on its next start.
