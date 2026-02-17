#!/usr/bin/env bash
set -euo pipefail

LABEL_INT="test/python-integration"
LABEL_POLL="test/python-integration-pollution"

# Default policy: unit only
MARKER='not (integration or integration_pollution)'
MODE='unit-only'

# Not a PR event => keep default
if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
  EVENT_PATH="${GITHUB_EVENT_PATH:-}"
  if [[ -n "$EVENT_PATH" && -f "$EVENT_PATH" ]]; then
    has_label() {
      local label="$1"
      jq -e --arg L "$label" '.pull_request.labels[].name | select(. == $L)' "$EVENT_PATH" > /dev/null
    }

    HAS_INT=false
    HAS_POLL=false

    if has_label "$LABEL_INT"; then HAS_INT=true; fi
    if has_label "$LABEL_POLL"; then HAS_POLL=true; fi

    # Policy:
    # - no label => unit only
    # - integration label => unit + integration (safe)
    # - both labels => everything
    if [[ "$HAS_INT" == true && "$HAS_POLL" == true ]]; then
      MARKER=''     # empty => don't pass -m (run everything)
      MODE='all'
    elif [[ "$HAS_INT" == true ]]; then
      MARKER='not integration_pollution'
      MODE='safe'
    fi
  fi
fi

# Emit outputs (GitHub Actions)
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "marker=$MARKER" >> "$GITHUB_OUTPUT"
  echo "mode=$MODE" >> "$GITHUB_OUTPUT"
else
  # local usage fallback
  echo "$MARKER"
fi
