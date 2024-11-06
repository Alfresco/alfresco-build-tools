#!/bin/bash

actions_dir=".github/actions"
readme_file="docs/README.md"
missing_entries=0

# List all folders under .github/actions
folders=$(ls -d $actions_dir/*/)

# Check each folder
for folder in $folders; do
  action_name=$(basename $folder)
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
