#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
profile_path="$($script_dir/firefox-active-profile-path.sh)"

workdir="$(mktemp -d /tmp/textfox-install.XXXXXX)"
cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

git clone --depth 1 https://github.com/adriankarlen/textfox.git "$workdir" >/dev/null

# Disable backup step in the upstream installer.
sed -i 's/^\s*backup_existing_profile .*$/  : # backup disabled/' "$workdir/tf-install.sh"

if [ "${TEXTFOX_INSTALL_USER_JS:-1}" = "1" ]; then
  printf 'Y\n' | (cd "$workdir" && bash ./tf-install.sh "$profile_path")
else
  printf 'N\n' | (cd "$workdir" && bash ./tf-install.sh "$profile_path")
fi
