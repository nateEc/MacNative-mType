#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
behavior_fixture="$project_root/Compatibility/official-reference-behavior-specs.json"
service_fixture="$project_root/Compatibility/official-service-surfaces.json"

fail() {
  print -u2 -- "service-behavior alignment audit check failed: $1"
  exit 1
}

alignment_is_valid() {
  local behavior="$1"
  local service="$2"

  jq -e --slurpfile service "$service" '
    ($service[0]) as $service
    | ([.specs[] | select(.source | startswith("backend/__tests__/api/controllers/"))]) as $controllers
    | ([.specs[] | select((.source | startswith("backend/__tests__/api/controllers/")) | not)]) as $nonControllers
    | (($controllers | length) == ($service.officialRouteModules | length))
    and ($controllers | all(
      (.routeModule | type == "string")
      and (.routeModule | gsub("^[[:space:]]+|[[:space:]]+$"; "") | length > 0)
    ))
    and ($nonControllers | all(has("routeModule") | not))
    and (([$controllers[].routeModule] | sort) == ($service.officialRouteModules | sort))
    and (([$controllers[].routeModule] | length) == ([$controllers[].routeModule] | unique | length))
    and ([$controllers[] | select(.kind == "direct") | .routeModule as $module | $service.mapped | has($module)] | all)
    and ([$controllers[] | select(.kind == "direct") | .nativeEvidence[] | startswith("server/")] | all)
  ' "$behavior" >/dev/null
}

verify_reference() {
  local reference_root="$1"
  local behavior_commit service_commit actual_commit

  [[ "$reference_root" = /* ]] || fail "reference checkout path must be absolute"
  git -C "$reference_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail \
    "reference checkout is not a Git worktree"

  behavior_commit="$(jq -er '.referenceCommit' "$behavior_fixture")"
  service_commit="$(jq -er '.referenceCommit' "$service_fixture")"
  [[ "$behavior_commit" == "$service_commit" ]] || fail \
    "behavior and service fixtures pin different reference commits"
  actual_commit="$(git -C "$reference_root" rev-parse HEAD)"
  [[ "$actual_commit" == "$behavior_commit" ]] || fail \
    "reference commit is $actual_commit; expected $behavior_commit"
}

run_self_test() {
  local temporary_directory invalid_service

  temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-service-behavior-alignment.XXXXXX")"
  trap "rm -rf -- ${(q)temporary_directory}" EXIT
  invalid_service="$temporary_directory/official-service-surfaces.json"

  jq 'del(.mapped.admin) | .notApplicable.admin = "deliberately invalid self-test partition"' \
    "$service_fixture" > "$invalid_service"
  if alignment_is_valid "$behavior_fixture" "$invalid_service"; then
    fail "the guard accepted a direct controller behavior in the not-applicable partition"
  fi

  print -- "service-behavior alignment audit self-test passed"
}

if (( $# != 1 )); then
  fail "usage: $0 --self-test | /absolute/path/to/monkeytype-reference"
fi

[[ -f "$behavior_fixture" ]] || fail "missing reference behavior fixture"
[[ -f "$service_fixture" ]] || fail "missing service surface fixture"
command -v jq >/dev/null || fail "jq is required to read compatibility fixtures"

if [[ "$1" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

verify_reference "$1"
alignment_is_valid "$behavior_fixture" "$service_fixture" || fail \
  "controller behavior and service-surface fixtures disagree"

controller_count="$(jq -r '[.specs[] | select(.source | startswith("backend/__tests__/api/controllers/"))] | length' "$behavior_fixture")"
direct_count="$(jq -r '[.specs[] | select((.source | startswith("backend/__tests__/api/controllers/")) and .kind == "direct")] | length' "$behavior_fixture")"
print -- "service-behavior alignment audit check passed ($direct_count direct controller behaviors across $controller_count route modules)"
