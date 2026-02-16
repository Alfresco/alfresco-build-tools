#!/bin/bash
set -e

actions_dir=".github/actions"
readme_file="docs/README.md"
missing_entries=0
allowed_missing_entries=0
exclude_paths=()

usage() {
  echo "Usage: $0 [--actions-dir DIR] [--readme-file FILE] [--missing-entries N] [--exclude-path PATH]..."
}

require_arg() {
  if [ -z "$2" ]; then
    echo "Missing value for $1"
    usage
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --actions-dir)
      require_arg "$1" "$2"
      actions_dir="$2"
      shift 2
      ;;
    --readme-file)
      require_arg "$1" "$2"
      readme_file="$2"
      shift 2
      ;;
    --missing-entries)
      require_arg "$1" "$2"
      allowed_missing_entries="$2"
      shift 2
      ;;
    --exclude-path)
      require_arg "$1" "$2"
      exclude_paths+=("$2")
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

if [ ! -d "$actions_dir" ]; then
  echo "Actions directory not found: $actions_dir"
  exit 2
fi

if ! find "$actions_dir" -type f -name action.yml -print -quit | grep -q .; then
  echo "No action.yml files found in $actions_dir"
  exit 2
fi

folders=$(find "$actions_dir" -type f -name action.yml -print | xargs -n1 dirname | sort -u)

# Check each folder
for folder in $folders; do
  [ -d "$folder" ] || continue
  for exclude_path in "${exclude_paths[@]}"; do
    case "$folder" in
      "$exclude_path"|"$exclude_path"/*) continue 2 ;;
    esac
  done
  action_name=$(basename "$folder")
  search_string="### $action_name"
  if ! grep -q "$search_string" "$readme_file"; then
    echo "No entry found for $search_string in $readme_file"
    ((missing_entries++))
  fi
done

# Report the number of missing entries
if [ $missing_entries -gt 0 ]; then
  echo "$missing_entries entries not found in $readme_file"
fi

if [ $missing_entries -gt $allowed_missing_entries ]; then
  exit 1
fi
