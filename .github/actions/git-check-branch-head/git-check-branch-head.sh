#!/usr/bin/env bash
set -euo pipefail

if [ -n "$REPO_DIR" ]; then
  cd "$REPO_DIR"
fi

if [ -z "$EXPECTED_SHA" ]; then
  EXPECTED_SHA=$(git rev-parse HEAD)
fi

BRANCH="${BRANCH#refs/heads/}"

REMOTE_SHA=$(git ls-remote "$REMOTE" "refs/heads/$BRANCH" | cut -f1)
if [ -z "$REMOTE_SHA" ]; then
  echo "::error::Branch '$BRANCH' not found on remote '$REMOTE'"
  exit 1
fi

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set (this script must run in a GitHub Actions step)}"
echo "remote-sha=$REMOTE_SHA" >> "$GITHUB_OUTPUT"

if [ "$REMOTE_SHA" = "$EXPECTED_SHA" ]; then
  echo "Branch '$BRANCH' on '$REMOTE' is still at expected SHA $EXPECTED_SHA"
  echo "changed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "changed=true" >> "$GITHUB_OUTPUT"
echo "::error::Branch '$BRANCH' on '$REMOTE' moved from expected $EXPECTED_SHA to $REMOTE_SHA since this run started. New commits landed concurrently; re-run once it is safe."
if [ "$FAIL_ON_MISMATCH" = "true" ]; then
  exit 1
fi
