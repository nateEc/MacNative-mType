#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
reference_fixture="$project_root/Compatibility/official-page-modal-surfaces.json"
minimum_overlap_length=120
reference_root=""
reference_commit=""
self_test_directory=""

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

normalise_long_lines() {
  LC_ALL=C awk -v minimum_length="$minimum_overlap_length" '
    {
      line = $0
      gsub(/[[:space:]]+/, " ", line)
      sub(/^ /, "", line)
      sub(/ $/, "", line)
      if (length(line) >= minimum_length) {
        print line
      }
    }
  ' "$@"
}

scan_native_sources_for_reference_overlap() {
  local native_source_root="$1"
  local reference_source_root="$2"
  local reference_source_directory source_file shared_count
  local -a native_source_files=()
  local -a reference_source_files=()

  [[ -d "$native_source_root" ]] || fail "missing native source directory: $native_source_root"

  while IFS= read -r -d "" source_file; do
    native_source_files+=("$source_file")
  done < <(rg --files -0 -g '*.swift' "$native_source_root")

  for reference_source_directory in \
    "$reference_source_root/frontend" \
    "$reference_source_root/backend" \
    "$reference_source_root/packages"; do
    [[ -d "$reference_source_directory" ]] || continue
    while IFS= read -r -d "" source_file; do
      reference_source_files+=("$source_file")
    done < <(rg --files -0 \
      -g '*.ts' \
      -g '*.tsx' \
      -g '*.js' \
      -g '*.jsx' \
      "$reference_source_directory")
  done

  (( ${#native_source_files[@]} > 0 )) || fail \
    "native source directory contains no Swift files: $native_source_root"
  (( ${#reference_source_files[@]} > 0 )) || fail \
    "reference checkout contains no JavaScript or TypeScript sources"

  shared_count="$(
    LC_ALL=C comm -12 \
      <(normalise_long_lines "${native_source_files[@]}" | LC_ALL=C sort -u) \
      <(normalise_long_lines "${reference_source_files[@]}" | LC_ALL=C sort -u) \
      | wc -l | tr -d '[:space:]'
  )"

  if (( shared_count > 0 )); then
    print -u2 -- "detected $shared_count copied-or-identical normalized source line(s) of at least $minimum_overlap_length bytes"
    return 1
  fi
}

verify_reference_checkout() {
  [[ "$reference_root" = /* ]] || fail "reference checkout path must be absolute"
  git -C "$reference_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "reference checkout is not a Git worktree"
  [[ -f "$reference_fixture" ]] || fail "missing compatibility fixture"
  command -v jq >/dev/null || fail "jq is required to read the compatibility fixture"

  local expected_commit
  expected_commit="$(jq -er '.referenceCommit' "$reference_fixture")"
  reference_commit="$(git -C "$reference_root" rev-parse HEAD)"
  [[ "$reference_commit" == "$expected_commit" ]] || fail \
    "reference commit is $reference_commit; expected $expected_commit"
}

cleanup() {
  if [[ -n "$self_test_directory" && -d "$self_test_directory" ]]; then
    rm -rf -- "$self_test_directory"
  fi
}

trap cleanup EXIT

run_self_test() {
  if reject_reference_paths "frontend/src/main.tsx" "package.json" >/dev/null 2>&1; then
    fail "the structural guard did not reject known reference paths"
  fi

  if ! reject_reference_paths "Sources/Typebar/TypingEngine.swift" "server/Sources/TypebarServerCore/Routes.swift"; then
    fail "the structural guard rejected native Typebar source paths"
  fi

  self_test_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-originality-boundary.XXXXXX")"
  local native_source_directory="$self_test_directory/native"
  local reference_source_directory="$self_test_directory/reference/frontend"
  local copied_line="This deliberately shared source line is long enough to prove that the originality guard rejects literal implementation copying across the rewrite boundary."

  mkdir -p "$native_source_directory" "$reference_source_directory"
  print -r -- "$copied_line" > "$native_source_directory/CopyProbe.swift"
  print -r -- "$copied_line" > "$reference_source_directory/copy-probe.ts"

  if scan_native_sources_for_reference_overlap "$native_source_directory" "$self_test_directory/reference" >/dev/null 2>&1; then
    fail "the overlap guard did not reject a copied long source line"
  fi

  print -r -- "shared short phrase" > "$native_source_directory/CopyProbe.swift"
  print -r -- "shared short phrase" > "$reference_source_directory/copy-probe.ts"

  if ! scan_native_sources_for_reference_overlap "$native_source_directory" "$self_test_directory/reference"; then
    fail "the overlap guard rejected a short common phrase"
  fi
}

typeset -i run_self_test_requested=0

while (( $# > 0 )); do
  case "$1" in
    --self-test)
      run_self_test_requested=1
      ;;
    --reference)
      shift
      (( $# > 0 )) || fail "usage: $0 [--self-test] [--reference /absolute/path/to/monkeytype-reference]"
      [[ -z "$reference_root" ]] || fail "reference checkout may be specified only once"
      reference_root="$1"
      ;;
    *)
      fail "usage: $0 [--self-test] [--reference /absolute/path/to/monkeytype-reference]"
      ;;
  esac
  shift
done

if (( run_self_test_requested )); then
  run_self_test
fi

typeset -a tracked_paths
tracked_paths=("${(@f)$(git -C "$project_root" ls-files)}")
reject_reference_paths "${tracked_paths[@]}"

if rg -n -i '([[:alnum:]-]+\.)?monkeytype\.com' "$project_root/Sources" "$project_root/server/Sources"; then
  fail "production Swift source must not contact the Monkeytype service"
fi

if [[ -n "$reference_root" ]]; then
  verify_reference_checkout
  scan_native_sources_for_reference_overlap "$project_root/Sources" "$reference_root"
  scan_native_sources_for_reference_overlap "$project_root/server/Sources" "$reference_root"
  print -- "originality boundary check passed (no long literal source overlap at $reference_commit)"
else
  print -- "originality boundary check passed"
fi
