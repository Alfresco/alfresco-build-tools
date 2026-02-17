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

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  if [[ "$file" == "$ACTIONS_ROOT/"* ]]; then
    rest="${file#${ACTIONS_ROOT}/}"
    action="${rest%%/*}"
    # Ignore shared test helpers (not an action)
    [[ "$action" == "$SHARED_DIR" ]] && continue
    [[ -n "$action" ]] && impacted["$action"]=1
  elif [[ "$file" == "$TESTS_ROOT/"* ]]; then
    rest="${file#${TESTS_ROOT}/}"
    action="${rest%%/*}"
    [[ -n "$action" ]] && impacted["$action"]=1
  fi
done

tests_dirs=()
matrix_items=()

for action in "${!impacted[@]}"; do
  # Safety: ignore shared even if it ends up here somehow
  [[ "$action" == "$SHARED_DIR" ]] && continue
  test_dir="${TESTS_ROOT}/${action}"
  if [[ -d "$test_dir" ]]; then
    tests_dirs+=("$test_dir")
    matrix_items+=("{\"action\":\"$action\",\"tests_dir\":\"$test_dir\"}")
  fi
done

# stable ordering
IFS=$'\n' tests_dirs_sorted=($(printf "%s\n" "${tests_dirs[@]:-}" | sort -u))
IFS=$'\n' matrix_sorted=($(printf "%s\n" "${matrix_items[@]:-}" | sort -u))
unset IFS

has_tests="false"
if [[ ${#tests_dirs_sorted[@]} -gt 0 ]]; then
  has_tests="true"
fi

{
  echo "has_tests=$has_tests"
  echo "tests_dirs<<EOF"
  printf "%s\n" "${tests_dirs_sorted[@]}"
  echo "EOF"
  (
    IFS=,
    echo "matrix_json={\"include\":[${matrix_sorted[*]}]}"
  )
} >> "$GITHUB_OUTPUT"
