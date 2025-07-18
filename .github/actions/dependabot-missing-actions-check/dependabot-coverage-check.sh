#!/bin/bash

# dependabot-coverage-check
# Author: wojciech.piotrowiak
# Description: Workaround for https://github.com/dependabot/dependabot-core/issues/6345.
# This script checks if all GitHub Actions in .github/actions are listed in .github/dependabot.yml.

# Find repository root (where .git directory exists)
repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$repo_root" ]; then
  echo "Error: Not in a git repository"
  exit 1
fi

# Change to repository root
cd "$repo_root"

# Check if required files exist
if [ ! -d ".github/actions" ]; then
  echo "Error: .github/actions directory not found"
  exit 1
fi

if [ ! -f ".github/dependabot.yml" ]; then
  echo "Error: .github/dependabot.yml file not found"
  exit 1
fi

# Find all directories that contain action.yml files
actions=$(find .github/actions -name "action.yml" -type f | xargs -I {} dirname {} | sed 's|^./||')

# Extract listed directories from dependabot.yml - support both directory and directories
listed_single=$(yq '.updates[] | select(.package-ecosystem == "github-actions") | .directory' .github/dependabot.yml | sed 's|^/||' | grep '^\.github/actions/' | sed 's|^\./||')
listed_multiple=$(yq '.updates[] | select(.package-ecosystem == "github-actions") | .directories[]?' .github/dependabot.yml | sed 's|^/||' | grep '^\.github/actions/' | sed 's|^\./||')

# Combine both formats
listed=$(printf "%s\n%s" "$listed_single" "$listed_multiple" | sort -u | grep -v '^$')

# Check for missing actions
missing=""
for action in $actions; do
  if ! echo "$listed" | grep -qx "$action"; then
    missing="$missing\n$action"
  fi
done

if [ -n "$missing" ]; then
  echo -e "Missing actions in dependabot.yml:$missing"
  exit 1
else
  echo "All actions are listed in dependabot.yml"
fi
