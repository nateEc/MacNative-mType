#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_path="$project_root/Typebar.app"

if [[ -e "$app_path" ]]; then
  print -u2 "Refusing to overwrite existing artifact: $app_path"
  exit 1
fi

binary_dir="$(cd "$project_root" && swift build --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_dir/Typebar" "$app_path/Contents/MacOS/Typebar"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
codesign --force --deep --sign - "$app_path"
print "Created $app_path"
