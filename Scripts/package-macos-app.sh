#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_path="${TYPEBAR_APP_PATH:-$project_root/Typebar.app}"
bundle_identifier="${TYPEBAR_BUNDLE_IDENTIFIER:-}"
app_name="${TYPEBAR_APP_NAME:-}"

if [[ -e "$app_path" ]]; then
  print -u2 "Refusing to overwrite existing artifact: $app_path"
  exit 1
fi

binary_dir="$(cd "$project_root" && swift build --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_dir/Typebar" "$app_path/Contents/MacOS/Typebar"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
if [[ -n "$bundle_identifier" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_identifier" "$app_path/Contents/Info.plist"
fi
if [[ -n "$app_name" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $app_name" "$app_path/Contents/Info.plist"
fi
codesign --force --deep --sign - "$app_path"
print "Created $app_path"
