#!/usr/bin/env bash
set -e

test "${GITHUB_PR_NUMBER}" && PREVIEW_NAME=pr-${GITHUB_PR_NUMBER} || PREVIEW_NAME=gh-$GITHUB_RUN_NUMBER
echo set PREVIEW_NAME="$PREVIEW_NAME"
echo "PREVIEW_NAME=$PREVIEW_NAME" >> "$GITHUB_ENV"
echo "::set-output name=preview-name::$PREVIEW_NAME"
