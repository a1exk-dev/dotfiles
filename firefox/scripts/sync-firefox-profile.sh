#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
firefox_dir="$(cd -- "$script_dir/.." && pwd)"

"$script_dir/backup-firefox-prefs.sh"
"$script_dir/stow-firefox-profile.sh"

echo "Backup complete: $firefox_dir/backup/prefs.js"
