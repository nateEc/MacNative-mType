#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_path="${TYPEBAR_APP_PATH:-$project_root/Typebar.app}"
bundle_identifier="${TYPEBAR_BUNDLE_IDENTIFIER:-}"
app_name="${TYPEBAR_APP_NAME:-}"
qa_in_memory_store="${TYPEBAR_QA_IN_MEMORY_STORE:-0}"
build_configuration="${TYPEBAR_BUILD_CONFIGURATION:-release}"

if [[ "$build_configuration" != "debug" && "$build_configuration" != "release" ]]; then
  print -u2 "TYPEBAR_BUILD_CONFIGURATION must be debug or release"
  exit 1
fi

if [[ "$qa_in_memory_store" != "0" && "$qa_in_memory_store" != "1" ]]; then
  print -u2 "TYPEBAR_QA_IN_MEMORY_STORE must be 0 or 1"
  exit 1
fi

if [[ "$qa_in_memory_store" == "1" ]]; then
  if [[ -z "$bundle_identifier" || "$bundle_identifier" == "app.typebar.desktop" || -z "$app_name" || "$app_name" == "Typebar" ]]; then
    print -u2 "QA packages require distinct TYPEBAR_BUNDLE_IDENTIFIER and TYPEBAR_APP_NAME values"
    exit 1
  fi
fi

if [[ -e "$app_path" ]]; then
  print -u2 "Refusing to overwrite existing artifact: $app_path"
  exit 1
fi

cd "$project_root"
swift build --configuration "$build_configuration"
binary_dir="$(swift build --configuration "$build_configuration" --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_dir/Typebar" "$app_path/Contents/MacOS/Typebar"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
mkdir -p "$app_path/Contents/Resources"
cp "$project_root/Resources/ThirdPartyNotices.txt" "$app_path/Contents/Resources/ThirdPartyNotices.txt"
cp "$project_root/Resources/UnicodeNotice.txt" "$app_path/Contents/Resources/UnicodeNotice.txt"
cp "$project_root/Resources/EnglishFrequencyCorpusNotices.txt" "$app_path/Contents/Resources/EnglishFrequencyCorpusNotices.txt"
cp "$project_root/Resources/EnglishLargeCorpusNotices.txt" "$app_path/Contents/Resources/EnglishLargeCorpusNotices.txt"
cp "$project_root/Resources/SpanishFrequencyCorpusNotices.txt" "$app_path/Contents/Resources/SpanishFrequencyCorpusNotices.txt"
cp "$project_root/Resources/SpanishLargeCorpusNotices.txt" "$app_path/Contents/Resources/SpanishLargeCorpusNotices.txt"
cp "$project_root/Resources/SpanishLargeCorpusSources.txt" "$app_path/Contents/Resources/SpanishLargeCorpusSources.txt"
cp "$project_root/Resources/FrenchFrequencyCorpusNotices.txt" "$app_path/Contents/Resources/FrenchFrequencyCorpusNotices.txt"
cp "$project_root/Resources/FrenchLargeCorpusNotices.txt" "$app_path/Contents/Resources/FrenchLargeCorpusNotices.txt"
cp "$project_root/Resources/FrenchLargeCorpusSources.txt" "$app_path/Contents/Resources/FrenchLargeCorpusSources.txt"
cp "$project_root/Resources/ItalianFrequencyCorpusNotices.txt" "$app_path/Contents/Resources/ItalianFrequencyCorpusNotices.txt"
cp "$project_root/Resources/GermanFrequencyCorpusNotices.txt" "$app_path/Contents/Resources/GermanFrequencyCorpusNotices.txt"
cp "$project_root/Resources/GermanCorpusSources.txt" "$app_path/Contents/Resources/GermanCorpusSources.txt"
cp "$project_root/Resources/RomanianCorpusNotices.txt" "$app_path/Contents/Resources/RomanianCorpusNotices.txt"
cp "$project_root/Resources/RomanianCorpusSources.txt" "$app_path/Contents/Resources/RomanianCorpusSources.txt"
cp "$project_root/Resources/PolishCorpusNotices.txt" "$app_path/Contents/Resources/PolishCorpusNotices.txt"
cp "$project_root/Resources/PolishCorpusSources.txt" "$app_path/Contents/Resources/PolishCorpusSources.txt"
cp "$project_root/Resources/PortugueseCorpusNotices.txt" "$app_path/Contents/Resources/PortugueseCorpusNotices.txt"
cp "$project_root/Resources/PortugueseCorpusSources.txt" "$app_path/Contents/Resources/PortugueseCorpusSources.txt"
cp "$project_root/Resources/EsperantoCorpusNotices.txt" "$app_path/Contents/Resources/EsperantoCorpusNotices.txt"
cp "$project_root/Resources/EsperantoCorpusSources.txt" "$app_path/Contents/Resources/EsperantoCorpusSources.txt"
cp "$project_root/Resources/NorwegianCorpusNotices.txt" "$app_path/Contents/Resources/NorwegianCorpusNotices.txt"
cp "$project_root/Resources/NorwegianCorpusSources.txt" "$app_path/Contents/Resources/NorwegianCorpusSources.txt"
cp "$project_root/Resources/RussianCorpusNotices.txt" "$app_path/Contents/Resources/RussianCorpusNotices.txt"
cp "$project_root/Resources/RussianCorpusSources.txt" "$app_path/Contents/Resources/RussianCorpusSources.txt"
cp "$project_root/Resources/RussianBasicCorpusNotices.txt" "$app_path/Contents/Resources/RussianBasicCorpusNotices.txt"
cp "$project_root/Resources/RussianBasicCorpusSources.txt" "$app_path/Contents/Resources/RussianBasicCorpusSources.txt"
if [[ -n "$bundle_identifier" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_identifier" "$app_path/Contents/Info.plist"
fi
if [[ -n "$app_name" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $app_name" "$app_path/Contents/Info.plist"
fi
if [[ "$qa_in_memory_store" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Add :TypebarQAInMemoryStore bool YES" "$app_path/Contents/Info.plist"
fi
codesign --force --deep --sign - "$app_path"
print "Created $app_path"
