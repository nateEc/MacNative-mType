#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
fixture="$project_root/Compatibility/official-layouts.json"
audit="$project_root/OFFICIAL_LAYOUT_AUDIT.md"
inventory="$project_root/FUNCTIONAL_INVENTORY.md"
coverage_test="$project_root/Tests/TypebarTests/OfficialLayoutCoverageTests.swift"

fail() {
  print -u2 -- "layout compatibility audit check failed: $1"
  exit 1
}

if (( $# != 1 )); then
  fail "usage: $0 /absolute/path/to/monkeytype-reference"
fi

reference_root="$1"
[[ "$reference_root" = /* ]] || fail "reference checkout path must be absolute"
git -C "$reference_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "reference checkout is not a Git worktree"
[[ -f "$fixture" ]] || fail "missing layout compatibility fixture"
[[ -f "$audit" ]] || fail "missing layout audit"
[[ -f "$inventory" ]] || fail "missing functional inventory"
[[ -f "$coverage_test" ]] || fail "missing layout coverage test"
command -v jq >/dev/null || fail "jq is required to read the compatibility fixture"

expected_commit="$(jq -er '.referenceCommit' "$fixture")"
actual_commit="$(git -C "$reference_root" rev-parse HEAD)"
[[ "$actual_commit" == "$expected_commit" ]] || fail \
  "reference commit is $actual_commit; expected $expected_commit"

layout_schema="$reference_root/packages/schemas/src/layouts.ts"
[[ -f "$layout_schema" ]] || fail "missing reference LayoutNameSchema"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-layout-audit.XXXXXX")"
trap 'rm -rf -- "$temporary_directory"' EXIT
reference_layouts="$temporary_directory/reference-layouts.txt"
fixture_layouts="$temporary_directory/fixture-layouts.txt"
native_layouts="$temporary_directory/native-layouts.txt"

sed -n '/export const LayoutNameSchema = z.enum(/,/^[[:space:]]*],/p' "$layout_schema" \
  | grep -Eo '"[^"]+"' \
  | tr -d '"' \
  | LC_ALL=C sort > "$reference_layouts"
jq -er '.officialNames[]' "$fixture" | LC_ALL=C sort > "$fixture_layouts"
jq -er '.nativeExact | keys[]' "$fixture" | LC_ALL=C sort > "$native_layouts"

expected_count="$(wc -l < "$reference_layouts" | tr -d '[:space:]')"
fixture_count="$(wc -l < "$fixture_layouts" | tr -d '[:space:]')"
native_count="$(wc -l < "$native_layouts" | tr -d '[:space:]')"
declared_count="$(jq -er '.officialCount' "$fixture")"

[[ "$expected_count" == "$declared_count" ]] || fail \
  "reference LayoutNameSchema has $expected_count names; fixture declares $declared_count"
[[ "$fixture_count" == "$declared_count" ]] || fail \
  "fixture has $fixture_count official names; declares $declared_count"
[[ "$native_count" == "$declared_count" ]] || fail \
  "fixture has $native_count native exact layouts; declares $declared_count"
if ! diff -u "$reference_layouts" "$fixture_layouts"; then
  fail "fixture official names differ from the fixed reference LayoutNameSchema"
fi
if ! diff -u "$fixture_layouts" "$native_layouts"; then
  fail "fixture does not map every official layout to a native exact layout"
fi

if ! jq -e '
  .officialCount as $count
  | (.officialNames | length == $count)
  and ((.officialNames | unique | length) == $count)
  and ((.nativeExact | keys | length) == $count)
  and ((.nativeExact | keys | sort) == (.officialNames | sort))
' "$fixture" >/dev/null; then
  fail "fixture counts or native exact mapping are not a complete one-to-one partition"
fi

grep -Fq -- "| \`nativeExact\` | $declared_count |" "$audit" \
  || fail "layout audit does not declare the complete native exact count"
grep -Fq -- "${declared_count} 项精确原生、0 项相关替代、0 项系统输入或自定义回退" "$inventory" \
  || fail "functional inventory does not state the current layout coverage"
grep -Fq -- "${declared_count} 项精确原生映射、0 项相关替代、0 项系统输入或自定义回退" "$inventory" \
  || fail "functional inventory does not supersede its historical layout limitation"
grep -Fq -- "\`OfficialLayoutCoverageTests\`" "$inventory" \
  || fail "functional inventory does not link the executable layout evidence"
grep -Fq -- "XCTAssertTrue(unimplementedKeys.isEmpty)" "$coverage_test" \
  || fail "layout coverage test does not reject unimplemented official layouts"

print -- "layout compatibility audit check passed ($declared_count native exact layouts at $actual_commit)"
