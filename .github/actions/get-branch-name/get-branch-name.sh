#!/bin/bash -e
BRANCH_NAME=${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}
if [ "$SANITIZE" = "true" ]; then
    BRANCH_NAME=$(echo "$BRANCH_NAME" | tr -d "." | tr "/" "-" | tr "[:upper:]" "[:lower:]")
fi
if [ "$MAX_LENGTH" -gt "0" ]; then
    BRANCH_NAME="${BRANCH_NAME:0:$MAX_LENGTH}"
    BRANCH_NAME=$(echo "$BRANCH_NAME" | sed 's/-$//')
fi

echo "Branch name is '$BRANCH_NAME'"
echo "BRANCH_NAME=$BRANCH_NAME" >> $GITHUB_ENV
