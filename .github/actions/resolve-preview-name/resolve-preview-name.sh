#!/usr/bin/env bash
set -e

test "${GITHUB_PR_NUMBER}" && PREVIEW_NAME=pr-${GITHUB_PR_NUMBER} || PREVIEW_NAME=gh-$GITHUB_RUN_NUMBER
echo Preview name: "$PREVIEW_NAME"
echo "preview-name=$PREVIEW_NAME" >> $GITHUB_OUTPUT
