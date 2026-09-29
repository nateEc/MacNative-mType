#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
fixture="$project_root/Compatibility/official-challenges.json"

fail() {
  print -u2 -- "challenge compatibility audit failed: $1"
  exit 1
}

(( $# == 1 )) || fail "usage: $0 /absolute/path/to/monkeytype-reference"
reference_root="$1"
[[ "$reference_root" = /* ]] || fail "reference checkout path must be absolute"
git -C "$reference_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "reference checkout is not a Git worktree"
command -v jq >/dev/null || fail "jq is required"
[[ -f "$fixture" ]] || fail "missing challenge compatibility fixture"

expected_commit="$(jq -er '.referenceCommit' "$fixture")"
actual_commit="$(git -C "$reference_root" rev-parse HEAD)"
[[ "$actual_commit" == "$expected_commit" ]] || fail \
  "reference commit is $actual_commit; expected $expected_commit"

schema="$reference_root/packages/schemas/src/challenges.ts"
[[ -f "$schema" ]] || fail "missing reference ChallengeNameSchema"

if ! diff -u \
  <(sed -n '/export const ChallengeNameSchema = z.enum(/,/^[[:space:]]*],/p' "$schema" \
    | grep -Eo '"[^"]+"' | tr -d '"' | LC_ALL=C sort) \
  <(jq -er '.officialNames[]' "$fixture" | LC_ALL=C sort); then
  fail "fixture challenge names differ from the fixed reference schema"
fi

jq -e '
  . as $fixture
  | ($fixture.officialCount == 58)
  and ($fixture.officialNames | length == 58)
  and ($fixture.officialNames | unique | length == 58)
  and ($fixture.nativeEquivalent | length == 27)
  and ($fixture.pending | length == 31)
  and ($fixture.pending | unique | length == 31)
  and (((($fixture.nativeEquivalent | keys) + $fixture.pending) | sort)
    == ($fixture.officialNames | sort))
' "$fixture" >/dev/null || fail "mapped and pending names do not partition 58 official identities"

print -- "challenge compatibility audit passed (27 mapped, 31 pending at $actual_commit)"
