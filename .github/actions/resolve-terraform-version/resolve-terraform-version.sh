#!/bin/bash
set -e

if [[ "$REQUESTED" == *$'\n'* ]]; then
  echo "::error::The requested Terraform version must be a single line"
  exit 1
fi

version="$REQUESTED"
if [ "$REQUESTED" = "dependabot" ]; then
  version=$(tr -d '[:space:]' < "$VERSION_FILE")
fi

echo "version=$version" >> "$GITHUB_OUTPUT"
