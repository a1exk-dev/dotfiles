#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <src-file> <dest-file>" >&2
  exit 1
fi

src="$1"
dest="$2"

if [ ! -f "$src" ]; then
  echo "Source file not found: $src" >&2
  exit 1
fi

mkdir -p "$(dirname -- "$dest")"
cp -f "$src" "$dest"
