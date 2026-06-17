#!/bin/bash -e
if [ -n "$APP_SLUG" ]; then
    BOT_NAME="${APP_SLUG}[bot]"
else
    BOT_NAME="github-actions[bot]"
fi

# Resolve the bot user id via the API in both branches so we never hard-code a
# magic id (which would be wrong on GitHub Enterprise Server or if GitHub ever
# changes it).
USER_ID="$(gh api "/users/${BOT_NAME}" --jq .id)"

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
