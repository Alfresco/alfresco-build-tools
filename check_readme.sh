#!/bin/bash

actions_dir=".github/actions"
readme_file="docs/README.md"
missing_entries=0

usage() {
  echo "Usage: $0 [--actions-dir DIR] [--readme-file FILE] [--missing-entries N]"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --actions-dir)
      actions_dir="$2"
      shift 2
      ;;
    --readme-file)
      readme_file="$2"
      shift 2
      ;;
    --missing-entries)
      missing_entries="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

# List all folders under .github/actions
folders=$(ls -d "$actions_dir"/*/)

# Check each folder
for folder in $folders; do
  [ -d "$folder" ] || continue
  action_name=$(basename "$folder")
  search_string="### $action_name"
  if ! grep -q "$search_string" "$readme_file"; then
    echo "No entry found for $search_string in README.md"
    ((missing_entries++))
  fi
done

# Report the number of missing entries
if [ $missing_entries -gt 0 ]; then
  echo "$missing_entries entries not found in README.md"
  exit 1
fi
