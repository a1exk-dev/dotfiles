# Discord

## Install 
- Arch Linux: `sudo pacman -S --needed discord noto-fonts noto-fonts-emoji noto-fonts-extra`
- Rebuild the font cache after installing fonts: `fc-cache -r`
- Restart Discord after rebuilding the cache.

TODO: Vencord installation and settings

## Layout
- `discord/backup/` - Backup copies (e.g. `settings.json`).
- `discord/scripts/` - Helper scripts.

## Scripts
- `discord/scripts/backup-discord-settings.sh` - backs up `settings.json` to `discord/backup/settings.json`.
- `discord/scripts/restore-discord-settings.sh` - restores `settings.json` from `discord/backup/settings.json`.
