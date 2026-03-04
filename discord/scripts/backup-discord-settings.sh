#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
discord_dir="$(cd -- "$script_dir/.." && pwd)"
repo_root="$(cd -- "$discord_dir/.." && pwd)"

copy_tool="$repo_root/_scripts/copy-file.sh"

"$copy_tool" "$HOME/.config/discord/settings.json" "$discord_dir/backup/settings.json"
