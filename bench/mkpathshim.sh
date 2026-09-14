#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: mkpathshim.sh SOURCE_DIR DEST_DIR" >&2
  exit 2
fi

source_dir="$1"
dest_dir="$2"
mkdir -p "$dest_dir"
find "$dest_dir" -mindepth 1 -maxdepth 1 -delete
for entry in "$source_dir"/*; do
  [ -e "$entry" ] || continue
  [ "$(basename "$entry")" = gh-axi ] && continue
  ln -s "$entry" "$dest_dir/$(basename "$entry")"
done
