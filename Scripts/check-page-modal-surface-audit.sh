#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
fixture="$project_root/Compatibility/official-page-modal-surfaces.json"

fail() {
  print -u2 -- "page/modal audit check failed: $1"
  exit 1
}

if (( $# != 1 )); then
  fail "usage: $0 /absolute/path/to/monkeytype-reference"
fi

reference_root="$1"
[[ "$reference_root" = /* ]] || fail "reference checkout path must be absolute"
git -C "$reference_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "reference checkout is not a Git worktree"
[[ -f "$fixture" ]] || fail "missing compatibility fixture"
command -v jq >/dev/null || fail "jq is required to read the compatibility fixture"

expected_commit="$(jq -er '.referenceCommit' "$fixture")"
actual_commit="$(git -C "$reference_root" rev-parse HEAD)"
[[ "$actual_commit" == "$expected_commit" ]] || fail \
  "reference commit is $actual_commit; expected $expected_commit"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-page-modal-audit.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
expected_surfaces="$temporary_directory/reference-surfaces.txt"
fixture_surfaces="$temporary_directory/fixture-surfaces.txt"

add_required_page() {
  local relative_path="$1"
  local surface="$2"
  [[ -f "$reference_root/$relative_path" ]] || fail "missing reference page: $relative_path"
  print -- "$surface" >> "$expected_surfaces"
}

add_modal_directory() {
  local relative_directory="$1"
  local source_file surface
  [[ -d "$reference_root/$relative_directory" ]] || fail "missing reference modal directory: $relative_directory"
  for source_file in "$reference_root/$relative_directory"/*.tsx(N); do
    surface="${source_file:t:r}"
    case "$surface" in
      Modals|SimpleModal) continue ;;
    esac
    print -- "$surface" >> "$expected_surfaces"
  done
}

add_required_page "frontend/src/ts/components/pages/404Page.tsx" "404Page"
add_required_page "frontend/src/ts/components/pages/AboutPage.tsx" "AboutPage"
add_required_page "frontend/src/ts/components/pages/account/AccountPage.tsx" "AccountPage"
add_required_page "frontend/src/ts/components/pages/account-settings/AccountSettingsPage.tsx" "AccountSettingsPage"
add_required_page "frontend/src/ts/components/pages/connections/FriendsPage.tsx" "FriendsPage"
add_required_page "frontend/src/ts/components/pages/leaderboard/LeaderboardPage.tsx" "LeaderboardPage"
add_required_page "frontend/src/ts/components/pages/login/LoginPage.tsx" "LoginPage"
add_required_page "frontend/src/ts/components/pages/profile/ProfilePage.tsx" "ProfilePage"
add_required_page "frontend/src/ts/components/pages/profile/ProfileSearchPage.tsx" "ProfileSearchPage"
add_required_page "frontend/src/ts/components/pages/settings/SettingsPage.tsx" "SettingsPage"
[[ -d "$reference_root/frontend/src/ts/components/pages/test" ]] || fail "missing reference test surface"
print -- "TestSurface" >> "$expected_surfaces"

add_modal_directory "frontend/src/ts/components/modals"
add_modal_directory "frontend/src/ts/components/modals/account-settings"
add_modal_directory "frontend/src/ts/components/modals/preset"

LC_ALL=C sort -o "$expected_surfaces" "$expected_surfaces"
jq -er '.officialSurfaces[]' "$fixture" | LC_ALL=C sort > "$fixture_surfaces"

expected_count="$(wc -l < "$expected_surfaces" | tr -d '[:space:]')"
fixture_count="$(wc -l < "$fixture_surfaces" | tr -d '[:space:]')"
declared_count="$(jq -er '.officialCount' "$fixture")"
[[ "$expected_count" == "$declared_count" ]] || fail \
  "reference surface count is $expected_count; fixture declares $declared_count"
[[ "$fixture_count" == "$declared_count" ]] || fail \
  "fixture contains $fixture_count surface names; declares $declared_count"

if ! diff -u "$expected_surfaces" "$fixture_surfaces"; then
  fail "fixture differs from the fixed reference page/modal surface inventory"
fi

print -- "page/modal audit check passed ($declared_count surfaces at $actual_commit)"
