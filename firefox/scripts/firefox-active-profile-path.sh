#!/usr/bin/env bash
set -euo pipefail

profiles_ini="$HOME/.mozilla/firefox/profiles.ini"
if [ ! -f "$profiles_ini" ]; then
  echo "profiles.ini not found at $profiles_ini" >&2
  exit 1
fi

active_profile_path="$(
  awk -F= '
    /^\[Install/ {section="install"; next}
    /^\[Profile/ {section="profile"; idx++; next}
    /^\[/ {section=""}
    section=="install" && $1=="Default" {inst_default=$2}
    section=="profile" && $1=="Path" {path[idx]=$2}
    section=="profile" && $1=="IsRelative" {rel[idx]=$2}
    section=="profile" && $1=="Default" {def[idx]=$2}
    END {
      if (inst_default!="") {
        for (i=1;i<=idx;i++) if (path[i]==inst_default) {sel=i; break}
      }
      if (!sel) {
        for (i=1;i<=idx;i++) if (def[i]=="1") {sel=i; break}
      }
      if (sel) {
        if (rel[sel]=="1") print ENVIRON["HOME"] "/.mozilla/firefox/" path[sel]
        else print path[sel]
      }
    }
  ' "$profiles_ini"
)"

if [ -z "$active_profile_path" ]; then
  echo "No active Firefox profile found." >&2
  exit 1
fi

echo "$active_profile_path"
