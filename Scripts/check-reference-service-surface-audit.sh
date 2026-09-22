#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
fixture="$project_root/Compatibility/official-service-surfaces.json"
audit="$project_root/OFFICIAL_SERVICE_SURFACE_AUDIT.md"

fail() {
  print -u2 -- "service surface audit check failed: $1"
  exit 1
}

if (( $# != 1 )); then
  fail "usage: $0 /absolute/path/to/monkeytype-reference"
fi

reference_root="$1"
[[ "$reference_root" = /* ]] || fail "reference checkout path must be absolute"
git -C "$reference_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail \
  "reference checkout is not a Git worktree"
[[ -f "$fixture" ]] || fail "missing compatibility fixture"
[[ -f "$audit" ]] || fail "missing service audit"
command -v jq >/dev/null || fail "jq is required to read the compatibility fixture"
command -v ruby >/dev/null || fail "ruby is required to read the fixed route registry"

expected_commit="$(jq -er '.referenceCommit' "$fixture")"
actual_commit="$(git -C "$reference_root" rev-parse HEAD)"
[[ "$actual_commit" == "$expected_commit" ]] || fail \
  "reference commit is $actual_commit; expected $expected_commit"

if ! jq -e '
  (.referenceRepository == "monkeytypegame/monkeytype")
  and (.officialCount > 0)
  and ((.officialRouteModules | length) == .officialCount)
  and ((.officialRouteModules | length) == (.officialRouteModules | unique | length))
  and ((.mapped | keys) == (.nativeEvidenceFiles | keys))
  and ((.mapped | keys_unsorted) | length > 0)
  and ((.mapped | keys_unsorted) as $mapped
       | (.notApplicable | keys_unsorted) as $notApplicable
       | (.unimplemented | keys_unsorted) as $unimplemented
       | (($mapped + $notApplicable + $unimplemented) | sort) == (.officialRouteModules | sort))
  and (((.mapped | values) + (.notApplicable | values) + (.unimplemented | values))
       | all(type == "string" and (gsub("^[[:space:]]+|[[:space:]]+$"; "") | length > 0)))
  and ([.nativeEvidenceFiles[] | type == "array" and length > 0] | all)
  and (.sourceFiles == ["backend/src/api/routes/index.ts", "OFFICIAL_SERVICE_SURFACE_AUDIT.md"])
  and (.method | contains("Identifier-level metadata only"))
' "$fixture" >/dev/null; then
  fail "fixture has an invalid route partition, mapping, or native evidence declaration"
fi

registry="$reference_root/backend/src/api/routes/index.ts"
[[ -f "$registry" ]] || fail "missing fixed reference route registry"
actual_modules="$(ruby - "$registry" <<'RUBY'
source = File.read(ARGV.fetch(0))
body = source[/const router = s\.router\(contract, \{(.*?)\n\}\);/m, 1]
abort "could not locate ts-rest route registry" unless body
modules = body.scan(/^  ([A-Za-z][A-Za-z0-9]*)(?::\s*[A-Za-z][A-Za-z0-9]*)?,$/).flatten
abort "route registry contains duplicate modules" unless modules.uniq.length == modules.length
abort "route registry is empty" if modules.empty?
puts modules.sort
RUBY
)"
fixture_modules="$(jq -er '.officialRouteModules[]' "$fixture" | LC_ALL=C sort)"
if ! diff -u <(print -r -- "$actual_modules") <(print -r -- "$fixture_modules"); then
  fail "fixture differs from the fixed reference ts-rest route registry"
fi

while IFS= read -r evidence; do
  [[ -n "$evidence" ]] || continue
  [[ "$evidence" != /* && "$evidence" != *".."* ]] || fail "unsafe native evidence path: $evidence"
  case "$evidence" in
    Sources/Typebar/*|server/Sources/TypebarServerCore/*|server/Tests/TypebarServerCoreTests/*) ;;
    *) fail "native evidence falls outside Typebar client/service/test roots: $evidence" ;;
  esac
  [[ -f "$project_root/$evidence" ]] || fail "missing native evidence: $evidence"
done < <(jq -r '.nativeEvidenceFiles[] | .[]' "$fixture")

grep -Fq -- '`Compatibility/official-service-surfaces.json`' "$audit" \
  || fail "service audit does not name its machine-readable fixture"

mapped_count="$(jq -r '.mapped | length' "$fixture")"
not_applicable_count="$(jq -r '.notApplicable | length' "$fixture")"
unimplemented_count="$(jq -r '.unimplemented | length' "$fixture")"
print -- "service surface audit check passed ($mapped_count mapped, $not_applicable_count not applicable, $unimplemented_count unimplemented at $actual_commit)"
