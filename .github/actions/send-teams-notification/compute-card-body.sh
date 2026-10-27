#!/usr/bin/env bash
set -euo pipefail

CARD_BODY="${CARD_BODY:-[]}"

if [ "$(jq -r 'type' <<<"$CARD_BODY" 2>/dev/null)" != "array" ]; then
    echo "card-body must be a JSON array (e.g. '[{\"type\":\"TextBlock\",\"text\":\"hi\"}]'), got: ${CARD_BODY}" >&2
    exit 1
fi

echo "result=$(jq -c . <<<"$CARD_BODY")"
