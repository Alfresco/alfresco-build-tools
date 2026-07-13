#!/usr/bin/env bash
set -euo pipefail

EXTRA_BODY="${EXTRA_BODY:-[]}"

if [ "$(jq -r 'type' <<<"$EXTRA_BODY" 2>/dev/null)" != "array" ]; then
    echo "card-extra-body must be a JSON array (e.g. '[{\"type\":\"TextBlock\",\"text\":\"hi\"}]'), got: ${EXTRA_BODY}" >&2
    exit 1
fi

if [ "$(jq 'length' <<<"$EXTRA_BODY")" -eq 0 ]; then
    echo "result="
else
    echo "result=,$(jq -c '.[]' <<<"$EXTRA_BODY" | paste -sd, -)"
fi
