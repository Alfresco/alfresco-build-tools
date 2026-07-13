#!/usr/bin/env bash
set -euo pipefail

EXTRA_BODY="${EXTRA_BODY:-[]}"

if [ "$(jq 'length' <<<"$EXTRA_BODY")" -eq 0 ]; then
    echo "result="
else
    echo "result=,$(jq -c '.[]' <<<"$EXTRA_BODY" | paste -sd, -)"
fi
