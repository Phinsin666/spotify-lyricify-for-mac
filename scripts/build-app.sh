#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
output_dir="${1:-$project_dir/dist}"
app_path="$output_dir/Spotify Lyricify for Mac.app"
source_icon="$project_dir/Sources/DockLyrics/Resources/AppIcon.png"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

if [[ -e "$app_path" ]]; then
  print -u2 "Refusing to overwrite existing app: $app_path"
  print -u2 "Move it away or choose another output directory."
  exit 1
fi

cd "$project_dir"
swift build -c release
build_dir="$(swift build -c release --show-bin-path)"

iconset="$temporary_dir/AppIcon.iconset"
mkdir -p "$iconset" "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

for spec in \
  '16 icon_16x16.png' \
  '32 icon_16x16@2x.png' \
  '32 icon_32x32.png' \
  '64 icon_32x32@2x.png' \
  '128 icon_128x128.png' \
  '256 icon_128x128@2x.png' \
  '256 icon_256x256.png' \
  '512 icon_256x256@2x.png' \
  '512 icon_512x512.png' \
  '1024 icon_512x512@2x.png'; do
  size="${spec%% *}"
  filename="${spec#* }"
  sips -z "$size" "$size" "$source_icon" --out "$iconset/$filename" >/dev/null
done

iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
cp "$project_dir/packaging/Info.plist" "$app_path/Contents/Info.plist"
cp "$build_dir/DockLyrics" "$app_path/Contents/MacOS/SpotifyLyricifyForMac"
chmod 755 "$app_path/Contents/MacOS/SpotifyLyricifyForMac"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"

print "Built: $app_path"
