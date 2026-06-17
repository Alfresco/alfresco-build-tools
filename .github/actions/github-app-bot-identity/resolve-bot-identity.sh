#!/bin/bash -e
if [ -n "$APP_SLUG" ]; then
    BOT_NAME="${APP_SLUG}[bot]"
    USER_ID="$(gh api "/users/${BOT_NAME}" --jq .id)"
else
    BOT_NAME="github-actions[bot]"
    USER_ID="41898282"
fi

EMAIL="${USER_ID}+${BOT_NAME}@users.noreply.github.com"
IDENTITY="${BOT_NAME} <${EMAIL}>"

echo "Resolved bot name is '$BOT_NAME'"
echo "Resolved user id is '$USER_ID'"
echo "Resolved identity is '$IDENTITY'"

{
    echo "user-id=$USER_ID"
    echo "name=$BOT_NAME"
    echo "email=$EMAIL"
    echo "identity=$IDENTITY"
} >> "$GITHUB_OUTPUT"
