#!/bin/bash

if ! command -v yq >/dev/null 2>&1; then
  echo "Error: yq is not installed. Please install yq to continue."
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$repo_root" ]; then
  echo "Error: Not in a git repository"
  exit 1
fi

cd "$repo_root"

if [ ! -d ".github/actions" ]; then
  echo "Error: .github/actions directory not found"
  exit
fi

if [ ! -f ".github/dependabot.yml" ]; then
  echo "Error: .github/dependabot.yml file not found"
  exit 1
fi

actions=$(find .github/actions -name "action.yml" -type f | xargs -I {} dirname {} | sed 's|^./||')

# Extract listed directories from dependabot.yml - support both directory and directories
listed_single=$(yq '.updates[] | select(.package-ecosystem == "github-actions") | .directory' .github/dependabot.yml | sed 's|^/||' | grep '^\.github/actions/' | sed 's|^\./||')
listed_multiple=$(yq '.updates[] | select(.package-ecosystem == "github-actions") | .directories[]?' .github/dependabot.yml | sed 's|^/||' | grep '^\.github/actions/' | sed 's|^\./||')

listed=$(printf "%s\n%s" "$listed_single" "$listed_multiple" | sort -u | grep -v '^$')

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
