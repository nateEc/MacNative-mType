#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
config_fixture="$project_root/Compatibility/official-configs.json"
language_fixture="$project_root/Compatibility/official-languages.json"

fail() {
  print -u2 -- "reference metadata audit check failed: $1"
  exit 1
}

if (( $# != 1 )); then
  fail "usage: $0 /absolute/path/to/monkeytype-reference"
fi

reference_root="$1"
[[ "$reference_root" = /* ]] || fail "reference checkout path must be absolute"
git -C "$reference_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail \
  "reference checkout is not a Git worktree"
[[ -f "$config_fixture" ]] || fail "missing config compatibility fixture"
[[ -f "$language_fixture" ]] || fail "missing language compatibility fixture"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-reference-metadata-audits.XXXXXX")"
trap 'rm -rf -- "$temporary_directory"' EXIT

generated_config="$temporary_directory/official-configs.json"
generated_language="$temporary_directory/official-languages.json"

ruby "$project_root/Scripts/generate-official-config-audit.rb" "$reference_root" "$generated_config"
ruby "$project_root/Scripts/generate-official-language-audit.rb" "$reference_root" "$generated_language"

if ! diff -u "$config_fixture" "$generated_config"; then
  fail "config fixture differs from the fixed reference and native evidence contract"
fi
if ! diff -u "$language_fixture" "$generated_language"; then
  fail "language fixture differs from the fixed reference and native selection contract"
fi

print -- "reference metadata audit check passed (config and language fixtures regenerate without drift)"
