#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"

fail() {
  print -u2 -- "originality boundary check failed: $1"
  exit 1
}

reject_reference_paths() {
  local path
  local -a rejected=()

  for path in "$@"; do
    case "$path" in
      backend/*|frontend/*|packages/*|*.ts|*.tsx|*.jsx|*.vue|*.svelte|package.json|pnpm-lock.yaml|pnpm-workspace.yaml|turbo.json|vitest.config.ts|monkeytype.code-workspace)
        rejected+=("$path")
        ;;
    esac
  done

  if (( ${#rejected[@]} > 0 )); then
    print -u2 -- "tracked paths reserved for the reference web project are not allowed:"
    for path in "${rejected[@]}"; do
      print -u2 -- "  $path"
    done
    return 1
  fi
}

run_self_test() {
  if reject_reference_paths "frontend/src/main.tsx" "package.json" >/dev/null 2>&1; then
    fail "the structural guard did not reject known reference paths"
  fi

  if ! reject_reference_paths "Sources/Typebar/TypingEngine.swift" "server/Sources/TypebarServerCore/Routes.swift"; then
    fail "the structural guard rejected native Typebar source paths"
  fi
}

case "${1:-}" in
  "")
    ;;
  --self-test)
    run_self_test
    ;;
  *)
    fail "usage: $0 [--self-test]"
    ;;
esac

typeset -a tracked_paths
tracked_paths=("${(@f)$(git -C "$project_root" ls-files)}")
reject_reference_paths "${tracked_paths[@]}"

if rg -n -i '([[:alnum:]-]+\.)?monkeytype\.com' "$project_root/Sources" "$project_root/server/Sources"; then
  fail "production Swift source must not contact the Monkeytype service"
fi

print -- "originality boundary check passed"
