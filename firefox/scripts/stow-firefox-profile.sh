#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
firefox_dir="$(cd -- "$script_dir/.." && pwd)"

"$script_dir/restore-firefox-prefs.sh"

active_profile_path="$("$script_dir/firefox-active-profile-path.sh")"

stow --adopt --dir "$firefox_dir" --target "$active_profile_path" profile
