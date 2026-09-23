#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
expected_commit="91bd24bb8513785c7364cbea29296ff7adafac41"

fail() {
  print -u2 -- "native rewrite readiness check failed: $1"
  exit 1
}

if (( $# != 1 )); then
  fail "usage: $0 /absolute/path/to/monkeytype-reference"
fi

reference_root="$1"
[[ "$reference_root" = /* ]] || fail "reference checkout path must be absolute"
git -C "$reference_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail \
  "reference checkout is not a Git worktree"
actual_commit="$(git -C "$reference_root" rev-parse HEAD)"
[[ "$actual_commit" == "$expected_commit" ]] || fail \
  "reference commit is $actual_commit; expected $expected_commit"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-native-rewrite-readiness.XXXXXX")"

cleanup() {
  rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

require_no_conflicting_processes() {
  local process_name
  local process_output
  local compiler_pattern
  integer found_conflict=0

  for process_name in Typebar xctest swift-test; do
    if process_output="$(pgrep -alf -x "$process_name")"; then
      print -u2 -- "active $process_name process prevents a single-instance readiness check:"
      print -u2 -- "$process_output"
      found_conflict=1
    fi
  done

  for compiler_pattern in '/swift-frontend ' '/swift-driver ' '/swiftc '; do
    if process_output="$(pgrep -alf -f "$compiler_pattern")"; then
      print -u2 -- "active Swift compiler process prevents a single-instance readiness check:"
      print -u2 -- "$process_output"
      found_conflict=1
    fi
  done

  if process_output="$(ps -A -o pid=,command= | rg '[s]wift-test|[x]ctest')"; then
    print -u2 -- "active test process prevents a single-instance readiness check:"
    print -u2 -- "$process_output"
    found_conflict=1
  fi

  (( found_conflict == 0 )) || return 1
}

run_check() {
  local label="$1"
  shift

  print -- "→ $label"
  "$@"
}

run_logged_check() {
  local label="$1"
  local log_path="$2"
  shift 2

  print -- "→ $label"
  if "$@" >"$log_path" 2>&1; then
    tail -n 12 "$log_path"
    print -- "✓ $label"
  else
    print -u2 -- "✗ $label"
    tail -n 200 "$log_path" >&2
    return 1
  fi
}

run_check "checking originality boundaries" \
  zsh "$project_root/Scripts/check-originality-boundaries.sh" --reference "$reference_root"
run_check "checking reference metadata audits" \
  zsh "$project_root/Scripts/check-reference-metadata-audits.sh" "$reference_root"
run_check "checking page and modal surfaces" \
  zsh "$project_root/Scripts/check-page-modal-surface-audit.sh" "$reference_root"
run_check "checking reference service surfaces" \
  zsh "$project_root/Scripts/check-reference-service-surface-audit.sh" "$reference_root"
run_check "checking reference service behavior alignment" \
  zsh "$project_root/Scripts/check-reference-service-behavior-alignment.sh" "$reference_root"
run_check "checking exact keyboard-layout coverage" \
  zsh "$project_root/Scripts/check-layout-compatibility-audit.sh" "$reference_root"
run_check "checking reference behavior evidence" \
  zsh "$project_root/Scripts/check-reference-behavior-audit.sh" "$reference_root"
run_check "checking manual acceptance inventory" \
  ruby "$project_root/Scripts/check-manual-acceptance-audit.rb"

require_no_conflicting_processes || fail "stop the listed process before running client tests"
run_logged_check "running native client test suite" "$temporary_directory/client-tests.log" \
  env TYPEBAR_QA_IN_MEMORY_STORE=1 swift test

require_no_conflicting_processes || fail "stop the listed process before running service tests"
run_logged_check "running self-hosted service test suite" "$temporary_directory/service-tests.log" \
  zsh -c 'cd "$1" && swift test' -- "$project_root/server"

require_no_conflicting_processes || fail "stop the listed process before packaging"
run_logged_check "building and validating the unopened macOS application package" \
  "$temporary_directory/package-check.log" \
  zsh "$project_root/Scripts/check-macos-app-package.sh" --reference "$reference_root"

print -- "native rewrite readiness check passed at $actual_commit (no Typebar process was started)"
