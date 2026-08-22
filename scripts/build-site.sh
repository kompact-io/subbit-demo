#!/usr/bin/env bash
# Build the static tape-gallery site.
#
# usage: build-site.sh <videos-dir> <site-out-dir> [template-dir]
#
# Takes every .mp4/.webm/.gif found in <videos-dir>, copies it under
# <site-out-dir>/videos/, feeds a small JSON description of them through
# <template-dir>/index.mustache, and writes <site-out-dir>/index.html.
# <template-dir> defaults to ../site relative to this script (i.e. running
# it straight out of a repo checkout); the `build-site` nix app passes its
# own store path explicitly so it doesn't matter where the script itself
# ends up on disk.
#
# Requires: jq, mustache (mustache-go), awk — provided by the `build-site`
# app in flake.nix, or the devShell.
set -euo pipefail

usage() { echo "usage: $(basename "$0") <videos-dir> <site-out-dir> [template-dir]" >&2; exit 1; }
[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || usage

videos_dir=$1
site_dir=$2
template_dir=${3:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/../site" && pwd)"}

[ -d "$videos_dir" ] || { echo "error: $videos_dir is not a directory" >&2; exit 1; }
[ -d "$template_dir" ] || { echo "error: template dir $template_dir not found" >&2; exit 1; }

# Fully regenerate the site dir each run. This also avoids a nix gotcha:
# $template_dir (and possibly $videos_dir) may point into the nix store,
# whose files are read-only (mode 444) -- `cp` preserves that mode on the
# copies, so a stale $site_dir from a previous run would make the next
# run's `cp` fail with "Permission denied" on overwrite.
rm -rf "$site_dir"
mkdir -p "$site_dir/videos"
cp "$template_dir/style.css" "$site_dir/style.css"

shopt -s nullglob nocaseglob
files=("$videos_dir"/*.mp4 "$videos_dir"/*.webm "$videos_dir"/*.gif)
shopt -u nullglob nocaseglob
mapfile -t files < <(printf '%s\n' "${files[@]}" | sort)

data_json=$(mktemp)
trap 'rm -f "$data_json"' EXIT

count=0
{
  printf '{"videos":['
  first=1
  for f in "${files[@]}"; do
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

    title=$(printf '%s' "$stem" | tr '_-' '  ' | awk '{
      for (i = 1; i <= NF; i++) $i = toupper(substr($i,1,1)) substr($i,2)
      print
    }')

    [ "$first" -eq 1 ] || printf ','
    first=0
    count=$((count + 1))
    jq -n --arg title "$title" --arg file "$base" --arg mime "$mime" --arg stem "$stem" \
      '{title:$title, file:$file, mime:$mime, stem:$stem}'
  done
  printf ']}'
} > "$data_json"

[ "$count" -gt 0 ] || { echo "error: no videos found in $videos_dir - refusing to publish an empty gallery" >&2; exit 1; }

mustache "$data_json" "$template_dir/index.mustache" > "$site_dir/index.html"
echo "wrote $site_dir/index.html with $count video(s)"
