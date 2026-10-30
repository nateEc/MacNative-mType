#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
reference_root=""
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-package-check.XXXXXX")"
app_path="$temporary_directory/Typebar.app"

fail() {
  print -u2 -- "package check failed: $1"
  exit 1
}

while (( $# > 0 )); do
  case "$1" in
    --reference)
      shift
      (( $# > 0 )) || fail "usage: $0 [--reference /absolute/path/to/monkeytype-reference]"
      [[ -z "$reference_root" ]] || fail "reference checkout may be specified only once"
      reference_root="$1"
      ;;
    *)
      fail "usage: $0 [--reference /absolute/path/to/monkeytype-reference]"
      ;;
  esac
  shift
done

cleanup() {
  rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

TYPEBAR_APP_PATH="$app_path" \
  TYPEBAR_QA_IN_MEMORY_STORE=1 \
  TYPEBAR_BUNDLE_IDENTIFIER=app.typebar.qa.package-check \
  TYPEBAR_APP_NAME=Typebar-QA-Package-Check \
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
[[ "$(bundle_value CFBundleIdentifier)" == "app.typebar.qa.package-check" ]] \
  || { print -u2 -- "package check failed: unexpected bundle identifier"; exit 1; }
[[ "$(bundle_value CFBundleName)" == "Typebar-QA-Package-Check" ]] \
  || { print -u2 -- "package check failed: unexpected app name"; exit 1; }
[[ "$(bundle_value LSMinimumSystemVersion)" == "14.0" ]] \
  || { print -u2 -- "package check failed: unexpected minimum macOS version"; exit 1; }
[[ "$(bundle_value TypebarQAInMemoryStore)" == "true" ]] \
  || { print -u2 -- "package check failed: QA store marker missing"; exit 1; }
[[ "$(bundle_value CFBundleURLTypes:0:CFBundleURLSchemes:0)" == "typebar" ]] \
  || fail "native OAuth/profile URL scheme is missing"

codesign --verify --deep --strict "$app_path"
cmp "$project_root/Resources/ThirdPartyNotices.txt" \
  "$app_path/Contents/Resources/ThirdPartyNotices.txt" \
  || fail "third-party license notices missing or modified"
cmp "$project_root/Resources/UnicodeNotice.txt" \
  "$app_path/Contents/Resources/UnicodeNotice.txt" \
  || fail "Unicode data license notice missing or modified"
cmp "$project_root/Resources/EnglishFrequencyCorpusNotices.txt" \
  "$app_path/Contents/Resources/EnglishFrequencyCorpusNotices.txt" \
  || fail "English corpus attribution missing or modified"
cmp "$project_root/Resources/EnglishLargeCorpusNotices.txt" \
  "$app_path/Contents/Resources/EnglishLargeCorpusNotices.txt" \
  || fail "large English corpus attribution missing or modified"
cmp "$project_root/Resources/EnglishFiveLetterCorpusNotices.txt" \
  "$app_path/Contents/Resources/EnglishFiveLetterCorpusNotices.txt" \
  || fail "Five-letter English corpus attribution missing or modified"
cmp "$project_root/Resources/EnglishFiveLetterCorpusSources.txt" \
  "$app_path/Contents/Resources/EnglishFiveLetterCorpusSources.txt" \
  || fail "Five-letter English spelling sources missing or modified"
cmp "$project_root/Resources/UkrainianCorpusNotices.txt" \
  "$app_path/Contents/Resources/UkrainianCorpusNotices.txt" \
  || fail "Ukrainian corpus attribution missing or modified"
cmp "$project_root/Resources/UkrainianCorpusSources.txt" \
  "$app_path/Contents/Resources/UkrainianCorpusSources.txt" \
  || fail "Ukrainian spelling sources missing or modified"
cmp "$project_root/Resources/UkrainianLatynkaCorpusNotices.txt" \
  "$app_path/Contents/Resources/UkrainianLatynkaCorpusNotices.txt" \
  || fail "Ukrainian Latynka corpus attribution missing or modified"
cmp "$project_root/Resources/UkrainianLatynkaCorpusSources.txt" \
  "$app_path/Contents/Resources/UkrainianLatynkaCorpusSources.txt" \
  || fail "Ukrainian Latynka spelling sources missing or modified"
cmp "$project_root/Resources/GreekCorpusNotices.txt" \
  "$app_path/Contents/Resources/GreekCorpusNotices.txt" \
  || fail "Greek corpus attribution missing or modified"
cmp "$project_root/Resources/GreekCorpusSources.txt" \
  "$app_path/Contents/Resources/GreekCorpusSources.txt" \
  || fail "Greek spelling sources missing or modified"
cmp "$project_root/Resources/SpanishFrequencyCorpusNotices.txt" \
  "$app_path/Contents/Resources/SpanishFrequencyCorpusNotices.txt" \
  || fail "Spanish corpus attribution missing or modified"
cmp "$project_root/Resources/SpanishLargeCorpusNotices.txt" \
  "$app_path/Contents/Resources/SpanishLargeCorpusNotices.txt" \
  || fail "large Spanish attribution missing or modified"
cmp "$project_root/Resources/SpanishLargeCorpusSources.txt" \
  "$app_path/Contents/Resources/SpanishLargeCorpusSources.txt" \
  || fail "large Spanish source map missing or modified"
cmp "$project_root/Resources/FrenchFrequencyCorpusNotices.txt" \
  "$app_path/Contents/Resources/FrenchFrequencyCorpusNotices.txt" \
  || fail "French corpus attribution missing or modified"
cmp "$project_root/Resources/FrenchLargeCorpusNotices.txt" \
  "$app_path/Contents/Resources/FrenchLargeCorpusNotices.txt" \
  || fail "large French attribution missing or modified"
cmp "$project_root/Resources/FrenchLargeCorpusSources.txt" \
  "$app_path/Contents/Resources/FrenchLargeCorpusSources.txt" \
  || fail "large French source map missing or modified"
cmp "$project_root/Resources/ItalianFrequencyCorpusNotices.txt" \
  "$app_path/Contents/Resources/ItalianFrequencyCorpusNotices.txt" \
  || fail "Italian corpus attribution missing or modified"
cmp "$project_root/Resources/GermanFrequencyCorpusNotices.txt" \
  "$app_path/Contents/Resources/GermanFrequencyCorpusNotices.txt" \
  || fail "German corpus attribution missing or modified"
cmp "$project_root/Resources/GermanCorpusSources.txt" \
  "$app_path/Contents/Resources/GermanCorpusSources.txt" \
  || fail "German entry attribution map missing or modified"
cmp "$project_root/Resources/RomanianCorpusNotices.txt" \
  "$app_path/Contents/Resources/RomanianCorpusNotices.txt" \
  || fail "Romanian corpus attribution missing or modified"
cmp "$project_root/Resources/RomanianCorpusSources.txt" \
  "$app_path/Contents/Resources/RomanianCorpusSources.txt" \
  || fail "Romanian entry source map missing or modified"
cmp "$project_root/Resources/PolishCorpusNotices.txt" \
  "$app_path/Contents/Resources/PolishCorpusNotices.txt" \
  || fail "Polish corpus attribution missing or modified"
cmp "$project_root/Resources/PolishCorpusSources.txt" \
  "$app_path/Contents/Resources/PolishCorpusSources.txt" \
  || fail "Polish source mapping missing or modified"
cmp "$project_root/Resources/PortugueseCorpusNotices.txt" \
  "$app_path/Contents/Resources/PortugueseCorpusNotices.txt" \
  || fail "Portuguese corpus attribution missing or modified"
cmp "$project_root/Resources/PortugueseCorpusSources.txt" \
  "$app_path/Contents/Resources/PortugueseCorpusSources.txt" \
  || fail "Portuguese evidence mapping missing or modified"
cmp "$project_root/Resources/EsperantoCorpusNotices.txt" \
  "$app_path/Contents/Resources/EsperantoCorpusNotices.txt" \
  || fail "Esperanto corpus attribution missing or modified"
cmp "$project_root/Resources/EsperantoCorpusSources.txt" \
  "$app_path/Contents/Resources/EsperantoCorpusSources.txt" \
  || fail "Esperanto spelling sources missing or modified"
cmp "$project_root/Resources/NorwegianCorpusNotices.txt" \
  "$app_path/Contents/Resources/NorwegianCorpusNotices.txt" \
  || fail "Norwegian corpus attribution missing or modified"
cmp "$project_root/Resources/NorwegianCorpusSources.txt" \
  "$app_path/Contents/Resources/NorwegianCorpusSources.txt" \
  || fail "Norwegian row provenance missing or modified"
cmp "$project_root/Resources/NorwegianBasicCorpusNotices.txt" \
  "$app_path/Contents/Resources/NorwegianBasicCorpusNotices.txt" \
  || fail "Basic Norwegian attribution missing or modified"
cmp "$project_root/Resources/NorwegianBasicCorpusSources.txt" \
  "$app_path/Contents/Resources/NorwegianBasicCorpusSources.txt" \
  || fail "Basic Norwegian row provenance missing or modified"
cmp "$project_root/Resources/RussianCorpusNotices.txt" \
  "$app_path/Contents/Resources/RussianCorpusNotices.txt" \
  || fail "Russian corpus attribution missing or modified"
cmp "$project_root/Resources/RussianCorpusSources.txt" \
  "$app_path/Contents/Resources/RussianCorpusSources.txt" \
  || fail "Russian spelling sources missing or modified"
cmp "$project_root/Resources/RussianBasicCorpusNotices.txt" \
  "$app_path/Contents/Resources/RussianBasicCorpusNotices.txt" \
  || fail "Basic Russian corpus attribution missing or modified"
cmp "$project_root/Resources/RussianBasicCorpusSources.txt" \
  "$app_path/Contents/Resources/RussianBasicCorpusSources.txt" \
  || fail "Basic Russian spelling sources missing or modified"
  cmp "$project_root/Resources/SimplifiedChineseCorpusNotices.txt" "$app_path/Contents/Resources/SimplifiedChineseCorpusNotices.txt" || fail "Simplified Chinese attribution missing or modified"
  cmp "$project_root/Resources/SimplifiedChineseCorpusSources.txt" "$app_path/Contents/Resources/SimplifiedChineseCorpusSources.txt" || fail "Simplified Chinese sources missing or modified"
if [[ -n "$reference_root" ]]; then
  zsh "$project_root/Scripts/check-originality-boundaries.sh" \
    --reference "$reference_root" \
    --bundle "$app_path"
fi
print -- "macOS app package check passed"
