#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
fixture="$project_root/Compatibility/official-reference-behavior-specs.json"
audit="$project_root/REFERENCE_BEHAVIOR_TEST_AUDIT.md"

fail() {
  print -u2 -- "reference behavior audit check failed: $1"
  exit 1
}

if (( $# != 1 )); then
  fail "usage: $0 /absolute/path/to/monkeytype-reference"
fi

reference_root="$1"
[[ "$reference_root" = /* ]] || fail "reference checkout path must be absolute"
git -C "$reference_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "reference checkout is not a Git worktree"
[[ -f "$fixture" ]] || fail "missing compatibility fixture"
[[ -f "$audit" ]] || fail "missing behavior audit"
command -v jq >/dev/null || fail "jq is required to read the compatibility fixture"

expected_commit="$(jq -er '.referenceCommit' "$fixture")"
actual_commit="$(git -C "$reference_root" rev-parse HEAD)"
[[ "$actual_commit" == "$expected_commit" ]] || fail "reference commit is $actual_commit; expected $expected_commit"

if ! jq -e '(.specs | length) > 0 and (([.specs[].source] | length) == ([.specs[].source] | unique | length)) and ([.specs[].kind] | all(. == "direct" or . == "support")) and ([.specs[] | select(.kind == "direct") | ((.nativeEvidence | length > 0) and ((.nativeTests | type) == "array") and (.nativeTests | length > 0))] | all)' "$fixture" >/dev/null; then
  fail "fixture has duplicate paths, an unknown category, or direct behavior without native evidence or test symbols"
fi

actual_specs="$(cd "$reference_root" && {
  find frontend/__tests__ -type f -name '*.spec.ts' -print
  find backend/__tests__/api/controllers -type f -name '*.spec.ts' -print
  find packages/contracts/__test__ -type f -name '*.spec.ts' -print
  find packages/funbox/__test__ -type f -name '*.spec.ts' -print
  find packages/schemas/__tests__ -type f -name '*.spec.ts' -print
  find packages/util/__test__ -type f -name '*.spec.ts' -print
} | LC_ALL=C sort)"
fixture_specs="$(jq -er '.specs[].source' "$fixture" | LC_ALL=C sort)"
if ! diff -u <(print -r -- "$actual_specs") <(print -r -- "$fixture_specs"); then
  fail "fixture differs from the fixed reference client, controller, and package test inventory"
fi

while IFS= read -r evidence; do
  [[ -n "$evidence" ]] || continue
  [[ "$evidence" != /* && "$evidence" != *".."* ]] || fail "unsafe native evidence path: $evidence"
  [[ -f "$project_root/$evidence" ]] || fail "missing native evidence: $evidence"
done < <(jq -r '.specs[] | select(.kind == "direct") | .nativeEvidence[]' "$fixture")

while IFS=$'\t' read -r source symbol; do
  [[ -n "$source" && -n "$symbol" ]] || fail "direct behavior has an empty native test symbol"
  [[ "$symbol" == test* ]] || fail "native test symbol for $source must start with test: $symbol"
  grep -RFq -- "func $symbol(" \
    "$project_root/Tests/TypebarTests" "$project_root/server/Tests" \
    || fail "missing native test symbol for $source: $symbol"
done < <(jq -r '.specs[] | select(.kind == "direct") | .source as $source | .nativeTests[] | "\($source)\t\(.)"' "$fixture")

while IFS= read -r source; do
  [[ -n "$source" ]] || continue
  grep -Fq -- "$source" "$audit" || fail "audit omits direct behavior spec: $source"
done < <(jq -r '.specs[] | select(.kind == "direct") | .source' "$fixture")

grep -Fq -- '`Compatibility/official-reference-behavior-specs.json`' "$audit" || fail "audit does not name its machine-readable fixture"

direct_count="$(jq -r '[.specs[] | select(.kind == "direct")] | length' "$fixture")"
support_count="$(jq -r '[.specs[] | select(.kind == "support")] | length' "$fixture")"
native_test_count="$(jq -r '[.specs[] | select(.kind == "direct") | .nativeTests[]] | length' "$fixture")"
print -- "reference behavior audit check passed ($direct_count direct, $native_test_count native test symbols, $support_count supporting specs at $actual_commit)"
