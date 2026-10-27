#!/usr/bin/env bash
set -euo pipefail

CARD_BODY="${CARD_BODY:-[]}"
CARD_ACTIONS="${CARD_ACTIONS:-[]}"
ENTITIES="${ENTITIES:-[]}"

check_array() {
    if [ "$(jq -r 'type' <<<"$2" 2>/dev/null)" != "array" ]; then
        echo "::error::$1 must be a JSON array (e.g. '[{\"type\":\"TextBlock\",\"text\":\"hi\"}]'), got: $2"
        exit 1
    fi
}

check_array card-body "$CARD_BODY"
check_array card-actions "$CARD_ACTIONS"

PAYLOAD="$(jq -n \
    --argjson body "$CARD_BODY" \
    --argjson actions "$CARD_ACTIONS" \
    --argjson entities "$ENTITIES" \
    --arg color "${COLOR:-808080}" \
    '{
        type: "message",
        attachments: [{
            contentType: "application/vnd.microsoft.card.adaptive",
            content: {
                type: "AdaptiveCard",
                body: $body,
                actions: $actions,
                backgroundImage: {
                    url: "https://singlecolorimage.com/get/\($color)/2x2",
                    fillMode: "RepeatHorizontally"
                },
                "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                version: "1.5",
                msteams: { width: "full", entities: $entities }
            }
        }]
    }')"

if [ -n "${DRY_RUN:-}" ] && [ "${DRY_RUN}" != "false" ]; then
    echo "Dry run - skipping notification send. Payload:"
    jq . <<<"$PAYLOAD"
    exit 0
fi

: "${WEBHOOK_URL:?webhook-url is required}"

response_file="$(mktemp)"
http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' \
    --data-raw "$PAYLOAD" "$WEBHOOK_URL")"

echo "Response status: ${http_code}"
cat "$response_file" && echo

case "${http_code}" in
    200 | 202)
        echo "Notification sent to Microsoft Teams"
        ;;
    *)
        echo "::error::Failed to send notification to Microsoft Teams (HTTP ${http_code})"
        exit 1
        ;;
esac
