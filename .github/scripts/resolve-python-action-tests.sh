#!/usr/bin/env bash
set -euo pipefail

# Reads changed files (one per line) from stdin.
# Outputs:
# - has_tests=true/false
# - tests_dirs (multiline)
# - matrix_json for GitHub Actions matrix {"include":[{"action":"x","tests_dir":"..."}, ...]}

ACTIONS_ROOT=".github/actions"
TESTS_ROOT=".github/tests/python-scripts"
SHARED_DIR="shared"

declare -A impacted=()
shared_changed="false"

# Helper: mark all actions that have a tests dir as impacted
mark_all_tested_actions_impacted() {
  [[ -d "$TESTS_ROOT" ]] || return 0

  for dir in "$TESTS_ROOT"/*; do
    [[ -d "$dir" ]] || continue
    action="$(basename "$dir")"
    [[ -n "$action" ]] && impacted["$action"]=1
  done
}

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # 1) Changes under actions/
  if [[ "$file" == "$ACTIONS_ROOT/"* ]]; then
    rest="${file#"${ACTIONS_ROOT}"/}"
    action="${rest%%/*}"

    # shared changed => run ALL action tests
    if [[ "$action" == "$SHARED_DIR" ]]; then
      shared_changed="true"
      continue
    fi

    # normal action changed => mark that action
    [[ -n "$action" ]] && impacted["$action"]=1
    continue
  fi

  # 2) Changes under tests/
  if [[ "$file" == "$TESTS_ROOT/"* ]]; then
    rest="${file#"${TESTS_ROOT}"/}"
    action="${rest%%/*}"
    [[ -n "$action" ]] && impacted["$action"]=1
    continue
  fi

  # 3) Anything else: ignore (do NOT trigger tests)
done

# If shared changed => mark all tested actions impacted
if [[ "$shared_changed" == "true" ]]; then
  mark_all_tested_actions_impacted
fi

tests_dirs=()
matrix_items=()

for action in "${!impacted[@]}"; do
  [[ "$action" == "$SHARED_DIR" ]] && continue

  test_dir="${TESTS_ROOT}/${action}"
  if [[ -d "$test_dir" ]]; then
    tests_dirs+=("$test_dir")
    matrix_items+=("{\"action\":\"$action\",\"tests_dir\":\"$test_dir\"}")
  fi
done

# Sort unique WITHOUT generating a fake empty line when arrays are empty
tests_dirs_sorted=()
if [[ ${#tests_dirs[@]} -gt 0 ]]; then
  mapfile -t tests_dirs_sorted < <(printf "%s\n" "${tests_dirs[@]}" | sort -u)
fi

matrix_sorted=()
if [[ ${#matrix_items[@]} -gt 0 ]]; then
  mapfile -t matrix_sorted < <(printf "%s\n" "${matrix_items[@]}" | sort -u)
fi

# Single source of truth: has_tests follows the matrix
has_tests="false"
if [[ ${#matrix_sorted[@]} -gt 0 ]]; then
  has_tests="true"
fi

# Build matrix_json
matrix_json='{"include":[]}'
if [[ ${#matrix_sorted[@]} -gt 0 ]]; then
  joined=""
  for item in "${matrix_sorted[@]}"; do
    if [[ -z "$joined" ]]; then
      joined="$item"
    else
      joined="$joined,$item"
    fi
  done
  matrix_json="{\"include\":[${joined}]}"
fi

# Determine output destination: GitHub output file if available, else stdout (for local runs)
output_dest="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "has_tests=$has_tests"
  echo "tests_dirs<<EOF"
  printf "%s\n" "${tests_dirs_sorted[@]}"
  echo "EOF"
  echo "matrix_json=$matrix_json"
} >> "$output_dest"
