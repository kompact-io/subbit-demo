#!/usr/bin/env bash
# Build the static tape-gallery site.
#
# usage: build-site.sh <videos-dir> <site-out-dir>
#
# Takes every .mp4/.webm/.gif found in <videos-dir>, copies it under
# <site-out-dir>/videos/, feeds a small JSON description of them through
# site/index.mustache, and writes <site-out-dir>/index.html.
#
# Requires: jq, mustache (mustache-go), find, awk — all provided by the
# `build-site` app in flake.nix, or the devShell.
set -euo pipefail

usage() { echo "usage: $(basename "$0") <videos-dir> <site-out-dir>" >&2; exit 1; }
[ "$#" -eq 2 ] || usage

videos_dir=$1
site_dir=$2
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

[ -d "$videos_dir" ] || { echo "error: $videos_dir is not a directory" >&2; exit 1; }

mkdir -p "$site_dir/videos"
cp "$repo_root/site/style.css" "$site_dir/style.css"

data_json=$(mktemp)
trap 'rm -f "$data_json"' EXIT

{
  printf '{"videos":['
  first=1
  while IFS= read -r -d '' f; do
    base=$(basename "$f")
    stem=${base%.*}
    ext_lc=$(printf '%s' "${base##*.}" | tr '[:upper:]' '[:lower:]')
    case "$ext_lc" in
      mp4) mime="video/mp4" ;;
      webm) mime="video/webm" ;;
      gif) mime="image/gif" ;;
      *) continue ;;
    esac

    cp "$f" "$site_dir/videos/$base"

    title=$(printf '%s' "$stem" | tr '-_' '  ' | awk '{
      for (i = 1; i <= NF; i++) $i = toupper(substr($i,1,1)) substr($i,2)
      print
    }')

    [ "$first" -eq 1 ] || printf ','
    first=0
    jq -n --arg title "$title" --arg file "$base" --arg mime "$mime" --arg stem "$stem" \
      '{title:$title, file:$file, mime:$mime, stem:$stem}'
  done < <(find "$videos_dir" -type f \( -iname '*.mp4' -o -iname '*.webm' -o -iname '*.gif' \) -print0 | sort -z)
  printf ']}'
} > "$data_json"

mustache "$data_json" "$repo_root/site/index.mustache" > "$site_dir/index.html"
echo "wrote $site_dir/index.html"
