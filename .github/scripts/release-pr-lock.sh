#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?}"
LOCK_REF_PATH="${LOCK_REF_PATH:?}"   # e.g. git/refs/tags/ci-lock-python-tests-pr-123-run-456

echo "Releasing lock: ${LOCK_REF_PATH}"
gh api -X DELETE -H "Accept: application/vnd.github+json" \
  "/repos/${REPO}/${LOCK_REF_PATH}" >/dev/null 2>&1 || true
echo "Lock released (or already absent)."
