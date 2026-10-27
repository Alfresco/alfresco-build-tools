#!/usr/bin/env bash
set -euo pipefail

CARD_BODY="${CARD_BODY:-[]}"
CARD_ACTIONS="${CARD_ACTIONS:-[]}"
ENTITIES="${ENTITIES:-[]}"

check_array() {
    if [ "$(jq -r 'type' <<<"$2" 2>/dev/null)" != "array" ]; then
        echo "::error::$1 must be a JSON array (e.g. '$3'), got: $2"
        exit 1
    fi
}

check_array card-body "$CARD_BODY" '[{"type":"TextBlock","text":"hi"}]'
check_array card-actions "$CARD_ACTIONS" '[{"type":"Action.OpenUrl","title":"View run","url":"https://example.com"}]'

# printf is a shell builtin, so jq's argument length is not a limit on the card.
# The body still arrives in an environment variable, which Linux caps at 128 KiB.
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
printf '%s' "$CARD_BODY" > "$body_file"

PAYLOAD="$(jq -n \
    --slurpfile body "$body_file" \
    --argjson actions "$CARD_ACTIONS" \
    --argjson entities "$ENTITIES" \
    --arg color "${COLOR:-808080}" \
    '{
        type: "message",
        attachments: [{
            contentType: "application/vnd.microsoft.card.adaptive",
            content: {
                type: "AdaptiveCard",
                body: $body[0],
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

# curl reads the payload from a file for the same reason.
payload_file="$(mktemp)"
response_file="$(mktemp)"
trap 'rm -f "$body_file" "$payload_file" "$response_file"' EXIT
printf '%s' "$PAYLOAD" > "$payload_file"

http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' \
    --data-binary "@$payload_file" "$WEBHOOK_URL")"

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
