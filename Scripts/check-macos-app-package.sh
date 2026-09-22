#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-package-check.XXXXXX")"
app_path="$temporary_directory/Typebar.app"

cleanup() {
  rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

TYPEBAR_APP_PATH="$app_path" \
  TYPEBAR_QA_IN_MEMORY_STORE=1 \
  zsh "$project_root/Scripts/package-macos-app.sh"

info_plist="$app_path/Contents/Info.plist"
bundle_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$info_plist"
}

[[ -x "$app_path/Contents/MacOS/Typebar" ]] \
  || { print -u2 -- "package check failed: missing Typebar executable"; exit 1; }
[[ "$(bundle_value CFBundlePackageType)" == "APPL" ]] \
  || { print -u2 -- "package check failed: bundle is not an application"; exit 1; }
[[ "$(bundle_value CFBundleExecutable)" == "Typebar" ]] \
  || { print -u2 -- "package check failed: unexpected executable name"; exit 1; }
[[ "$(bundle_value CFBundleIdentifier)" == "app.typebar.desktop" ]] \
  || { print -u2 -- "package check failed: unexpected bundle identifier"; exit 1; }
[[ "$(bundle_value LSMinimumSystemVersion)" == "14.0" ]] \
  || { print -u2 -- "package check failed: unexpected minimum macOS version"; exit 1; }
[[ "$(bundle_value TypebarQAInMemoryStore)" == "true" ]] \
  || { print -u2 -- "package check failed: QA store marker missing"; exit 1; }

codesign --verify --deep --strict "$app_path"
print -- "macOS app package check passed"
