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

command -v rg >/dev/null 2>&1 || fail \
  "rg is required for complete process-conflict scans; preserve its directory in PATH"

reference_root="$1"
[[ "$reference_root" = /* ]] || fail "reference checkout path must be absolute"
git -C "$reference_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail \
  "reference checkout is not a Git worktree"
actual_commit="$(git -C "$reference_root" rev-parse HEAD)"
[[ "$actual_commit" == "$expected_commit" ]] || fail \
  "reference commit is $actual_commit; expected $expected_commit"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-native-rewrite-readiness.XXXXXX")"
readiness_log_directory="${TYPEBAR_READINESS_LOG_DIRECTORY:-}"
if [[ -n "$readiness_log_directory" ]]; then
  [[ "$readiness_log_directory" = /* && -d "$readiness_log_directory" && -w "$readiness_log_directory" ]] || \
    fail "log destination must be an existing writable absolute directory"
  retained_log_entries=("$readiness_log_directory"/*(DN))
  (( ${#retained_log_entries} == 0 )) || fail "log destination must be empty; never overwrite previous evidence"
fi

cleanup() {
  if [[ -n "$readiness_log_directory" ]]; then
    local logs=("$temporary_directory"/*.log(N))
    if (( ${#logs} > 0 )); then
      cp -- "${logs[@]}" "$readiness_log_directory/"
    fi
  fi
  rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

require_no_conflicting_processes() {
  local process_name
  local process_output
  local compiler_pattern
  integer found_conflict=0

  for process_name in Typebar xctest swift-test; do
    if process_output="$(pgrep -l -x "$process_name")"; then
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
run_check "checking official theme identity coverage" \
  ruby "$project_root/Scripts/check-theme-compatibility-audit.rb" "$reference_root"
run_check "checking official challenge identity coverage" \
  zsh "$project_root/Scripts/check-challenge-compatibility-audit.sh" "$reference_root"
run_check "checking reference script challenge fingerprints" \
  zsh "$project_root/Scripts/check-reference-script-challenge-metadata.sh" "$reference_root"
run_check "checking reference behavior evidence" \
  zsh "$project_root/Scripts/check-reference-behavior-audit.sh" "$reference_root"
run_check "checking manual acceptance inventory" \
  ruby "$project_root/Scripts/check-manual-acceptance-audit.rb"

run_logged_check "executing actual pinned ranking admission branches" "$temporary_directory/ranking-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-ranking-admission.mjs" "$reference_root"

run_logged_check "executing pinned PB replacement, grouping and bounded DAL lifecycle" \
  "$temporary_directory/personal-best-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-personal-best.mjs" "$reference_root"

run_logged_check "executing pinned weekly XP service with isolated Redis 6.2.6" \
  "$temporary_directory/weekly-xp-read-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-weekly-xp-read.mjs" "$reference_root"

run_logged_check "executing pinned daily cache service and isolated Redis 6.2.6" \
  "$temporary_directory/daily-cache-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-daily-cache.mjs" "$reference_root"

run_logged_check "executing pinned weekly XP date and controller partition selection" \
  "$temporary_directory/weekly-xp-partition-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-weekly-xp-partition.mjs" "$reference_root"

practice_source_dependencies="${TYPEBAR_PRACTICE_SOURCE_DEPENDENCIES:-$temporary_directory/practice-source-runtime}"
if [[ ! -f "$practice_source_dependencies/node_modules/date-fns/package.json" ]]; then
  run_logged_check "preparing pinned read-only account date dependencies" "$temporary_directory/practice-source-runtime.log" \
    npm install --prefix "$practice_source_dependencies" --ignore-scripts --no-save --package-lock=false \
    date-fns@3.6.0 @date-fns/utc@1.2.0
fi
run_logged_check "executing actual pinned account functions" "$temporary_directory/practice-source-check.log" \
  env TYPEBAR_PRACTICE_SOURCE_DEPENDENCIES="$practice_source_dependencies" \
  "${TYPEBAR_PRACTICE_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-account-practice.mjs" "$reference_root"

run_logged_check "executing pinned frontend weekly time formatting" "$temporary_directory/weekly-xp-presentation-source-check.log" \
  env TYPEBAR_PRACTICE_SOURCE_DEPENDENCIES="$practice_source_dependencies" \
  "${TYPEBAR_PRACTICE_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-weekly-xp-presentation.mjs" "$reference_root"

weekly_reward_source_dependencies="${TYPEBAR_WEEKLY_REWARD_SOURCE_DEPENDENCIES:-$temporary_directory/weekly-reward-source-runtime}"
if [[ ! -f "$weekly_reward_source_dependencies/node_modules/lru-cache/package.json" ]]; then
  run_logged_check "preparing pinned weekly reward LRU dependency" "$temporary_directory/weekly-reward-source-runtime.log" \
    npm install --prefix "$weekly_reward_source_dependencies" --ignore-scripts --no-save --package-lock=false \
    lru-cache@11.5.1
fi
run_logged_check "executing pinned weekly and daily reward workers, schedules and announcement selection" \
  "$temporary_directory/weekly-xp-reward-source-check.log" \
  env TYPEBAR_WEEKLY_REWARD_SOURCE_DEPENDENCIES="$weekly_reward_source_dependencies" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-weekly-xp-rewards.mjs" "$reference_root"

run_logged_check "executing pinned inbox claim function and repeated requests" \
  "$temporary_directory/inbox-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-inbox-claims.mjs" "$reference_root"

inbox_source_package="${TYPEBAR_INBOX_SOURCE_PACKAGE:-$temporary_directory/inbox-source-runtime/node_modules/@tanstack/db}"
if [[ ! -f "$inbox_source_package/package.json" ]]; then
  run_logged_check "preparing pinned QA-only inbox sorting dependency" "$temporary_directory/inbox-source-runtime.log" \
    npm install --prefix "$temporary_directory/inbox-source-runtime" --ignore-scripts --no-save --package-lock=false \
    @tanstack/db@0.6.8
fi
run_logged_check "executing pinned inbox dependency title ordering" "$temporary_directory/inbox-order-source-check.log" \
  env TYPEBAR_INBOX_SOURCE_PACKAGE="$inbox_source_package" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-inbox-order.mjs" "$reference_root"

require_no_conflicting_processes || fail "stop the listed process before running client tests"
run_logged_check "executing pinned speed calculation and two-decimal rounding" "$temporary_directory/speed-precision-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-speed-precision.mjs" "$reference_root"
run_logged_check "executing pinned completion tags, failed save retries and signed-out claim" \
  "$temporary_directory/account-tag-capture-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-tag-capture.mjs" "$reference_root"
run_logged_check "executing pinned stable tag PB getter and pace initialization" \
  "$temporary_directory/account-tag-pace-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-tag-pace.mjs" "$reference_root"
run_logged_check "executing pinned history tag edits and complete cached PB replacement" \
  "$temporary_directory/account-tag-history-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-tag-history.mjs" "$reference_root"
run_logged_check "executing pinned tag edit controller and separate PB awards" \
  "$temporary_directory/account-tag-edit-awards-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" --experimental-vm-modules \
  "$project_root/Scripts/check-source-account-tag-edit-awards.mjs" "$reference_root"
run_logged_check "executing pinned unloaded last-result tag edits and award-only PB writes" \
  "$temporary_directory/account-tag-last-result-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-tag-last-result.mjs" "$reference_root"

run_logged_check "executing pinned result-tag draft/save callbacks and retained crown display" \
  "$temporary_directory/account-tag-result-editor-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-tag-result-editor.mjs" "$reference_root"
run_logged_check "executing pinned initial tag crowns, client PB writes and chart lines" \
  "$temporary_directory/account-tag-completion-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-tag-completion.mjs" "$reference_root"
run_logged_check "executing pinned stable-ID result queries, directory transitions and current-settings tags" \
  "$temporary_directory/account-tag-filter-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-tag-filter.mjs" "$reference_root"
run_logged_check "executing pinned filtered account all/recent-ten/daily statistics" \
  "$temporary_directory/account-history-stats-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-history-stats.mjs" "$reference_root"
run_logged_check "executing pinned account filter preset lifecycle and names" \
  "$temporary_directory/account-filter-presets-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-filter-presets.mjs" "$reference_root"
run_logged_check "executing pinned account history chart numeric functions" \
  "$temporary_directory/account-history-graphs-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-history-graphs.mjs" "$reference_root"
daily_trend_source_archive="${TYPEBAR_DAILY_TREND_SOURCE_ARCHIVE:-$temporary_directory/chartjs-plugin-trendline-3.2.4.tgz}"
if [[ -z "${TYPEBAR_DAILY_TREND_SOURCE_ARCHIVE:-}" ]]; then
  run_logged_check "preparing pinned QA-only daily trendline archive" "$temporary_directory/daily-trend-source-runtime.log" \
    npm pack --ignore-scripts --pack-destination "$temporary_directory" chartjs-plugin-trendline@3.2.4
fi
[[ -f "$daily_trend_source_archive" ]] || fail "missing QA-only daily trendline archive"
run_logged_check "executing pinned daily minute fit and complete trend clipping" \
  "$temporary_directory/account-daily-activity-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-daily-activity.mjs" "$reference_root" "$daily_trend_source_archive"
run_logged_check "executing pinned account result chart data, options and callbacks" \
  "$temporary_directory/account-result-chart-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-account-result-chart.mjs" "$reference_root"
howler_source_archive="${TYPEBAR_HOWLER_SOURCE_ARCHIVE:-$temporary_directory/howler-2.2.3.tgz}"
if [[ ! -f "$howler_source_archive" ]]; then
  run_logged_check "preparing pinned QA-only Howler archive" "$temporary_directory/howler-source-runtime.log" \
    npm pack --ignore-scripts --pack-destination "$temporary_directory" howler@2.2.3
fi
[[ -f "$howler_source_archive" ]] || fail "missing QA-only Howler archive"
run_logged_check "executing pinned sample sound playback and pool lifecycle" \
  "$temporary_directory/sample-sound-pool-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-sample-sound-pool.mjs" "$reference_root" "$howler_source_archive"
run_logged_check "executing pinned delayed sample readiness and queued seeks" \
  "$temporary_directory/sample-loading-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-sample-loading.mjs" "$reference_root" "$howler_source_archive"
run_logged_check "executing pinned WebAudio sample group seek, slot selection and deferred drain" \
  "$temporary_directory/sample-seek-source-check.log" \
  "${TYPEBAR_RANKING_SOURCE_NODE:-node}" "$project_root/Scripts/check-source-sample-seek.mjs" "$reference_root" "$howler_source_archive"
run_logged_check "preparing isolated historical disk model writers" "$temporary_directory/disk-fixtures.log" \
  ruby "$project_root/Scripts/prepare-disk-model-fixtures.rb" "$temporary_directory/disk-model-fixtures"
require_no_conflicting_processes || fail "stop the listed process before running client tests"
run_logged_check "running native client test suite" "$temporary_directory/client-tests.log" \
  env TYPEBAR_QA_IN_MEMORY_STORE=1 TYPEBAR_REFERENCE_ROOT="$reference_root" \
  TYPEBAR_PRACTICE_SOURCE_DEPENDENCIES="$practice_source_dependencies" \
  TYPEBAR_INBOX_SOURCE_PACKAGE="$inbox_source_package" \
  TYPEBAR_DAILY_TREND_SOURCE_ARCHIVE="$daily_trend_source_archive" \
  TYPEBAR_HOWLER_SOURCE_ARCHIVE="$howler_source_archive" \
  TYPEBAR_DISK_FIXTURE_ROOT="$temporary_directory/disk-model-fixtures" swift test

require_no_conflicting_processes || fail "stop the listed process before running service tests"
run_logged_check "running self-hosted service test suite" "$temporary_directory/service-tests.log" \
  env TYPEBAR_REFERENCE_ROOT="$reference_root" TYPEBAR_PRACTICE_SOURCE_DEPENDENCIES="$practice_source_dependencies" \
  TYPEBAR_WEEKLY_REWARD_SOURCE_DEPENDENCIES="$weekly_reward_source_dependencies" \
  zsh -c 'cd "$1" && swift test' -- "$project_root/server"

require_no_conflicting_processes || fail "stop the listed process before packaging"
run_logged_check "building and validating the unopened macOS application package" \
  "$temporary_directory/package-check.log" \
  zsh "$project_root/Scripts/check-macos-app-package.sh" --reference "$reference_root"

print -- "native rewrite readiness check passed at $actual_commit (no Typebar process was started)"
