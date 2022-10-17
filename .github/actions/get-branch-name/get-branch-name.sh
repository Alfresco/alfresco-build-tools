#!/bin/bash -e
BRANCH_NAME=${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}
if [ "$SANITIZE" = "true" ]; then
    BRANCH_NAME=$(echo "$BRANCH_NAME"| tr -d "." | tr "/" "-" | tr "[:upper:]" "[:lower:]")
fi
echo "Branch name is '$BRANCH_NAME'"
echo "BRANCH_NAME=$BRANCH_NAME" >> $GITHUB_ENV
