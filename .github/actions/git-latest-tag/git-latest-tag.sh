#!/bin/bash

if [ -n "$REPO_DIR" ]; then
    cd "$REPO_DIR"
fi
git fetch --tags
TAG=$(git tag --list "$PATTERN" --sort=-creatordate | head -n 1)
TAG_LONG_SHA=$(git rev-list -n 1 $TAG)
echo "Tag for the pattern $PATTERN is $TAG ($TAG_LONG_SHA)"
echo "tag=$TAG" >> "$GITHUB_OUTPUT"
echo "tag_long_sha=$TAG_LONG_SHA" >> "$GITHUB_OUTPUT"
