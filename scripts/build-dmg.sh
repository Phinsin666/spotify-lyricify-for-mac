#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/packaging/Info.plist")"
output_dir="${1:-$project_dir/dist}"
dmg_path="$output_dir/Spotify-Lyricify-for-Mac-v$version.dmg"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

if [[ -e "$dmg_path" ]]; then
  print -u2 "Refusing to overwrite existing disk image: $dmg_path"
  print -u2 "Move it away or choose another output directory."
  exit 1
fi

app_output="$temporary_dir/app"
dmg_root="$temporary_dir/dmg-root"

"$project_dir/scripts/build-app.sh" "$app_output"
mkdir -p "$output_dir" "$dmg_root"
ditto "$app_output/Spotify Lyricify for Mac.app" "$dmg_root/Spotify Lyricify for Mac.app"
ln -s /Applications "$dmg_root/Applications"

hdiutil create \
  -volname "Spotify Lyricify for Mac" \
  -srcfolder "$dmg_root" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$dmg_path"

print "Built: $dmg_path"
