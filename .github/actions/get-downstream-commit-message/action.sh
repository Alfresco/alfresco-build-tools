#!/bin/bash
set -euo pipefail

if [[ "${COMMIT_TITLE}" =~ \[force[^]]*\] ]]; then
    FORCE_TOKEN=$(echo "${COMMIT_TITLE}" | sed "s|^.*\(\[force[^]]*\]\).*$|\1|g")
    echo "message=${FORCE_TOKEN} Update ${DOWNSTREAM_REPO} version to ${VERSION}" >> "$GITHUB_OUTPUT"
    echo "allow-empty-commit=true" >> "$GITHUB_OUTPUT"
else
    echo "message=Update ${DOWNSTREAM_REPO} version to ${VERSION}" >> "$GITHUB_OUTPUT"
    echo "allow-empty-commit=false" >> "$GITHUB_OUTPUT"
fi
