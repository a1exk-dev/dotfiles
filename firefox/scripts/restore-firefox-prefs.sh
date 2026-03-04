#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
firefox_dir="$(cd -- "$script_dir/.." && pwd)"
repo_root="$(cd -- "$firefox_dir/.." && pwd)"

copy_tool="$repo_root/_scripts/copy-file.sh"
profile_path="$($script_dir/firefox-active-profile-path.sh)"

"$copy_tool" "$firefox_dir/backup/prefs.js" "$profile_path/prefs.js"
