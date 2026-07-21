#!/bin/bash
set -eo pipefail

# Capture yq output before looping so a yq failure/missing file aborts the
# script instead of being swallowed by process substitution.
entries="$(yq '.env.global[]' "$YML_PATH")"

while IFS= read -r ENVVAR; do
  [ -z "$ENVVAR" ] && continue
  if [[ "$ENVVAR" =~ $IGNORE_REGEX ]]; then
    echo "Skipping unwanted $ENVVAR"
    continue
  fi
  name="${ENVVAR%%=*}"
  rhs="${ENVVAR#*=}"
  eval "value=\"$rhs\""
  # shellcheck disable=SC2154 # value is assigned above via eval
  export "$name=$value"
  if [[ "$value" == *$'\n'* ]]; then
    delimiter="EOF_$(openssl rand -hex 8)"
    {
      printf '%s<<%s\n' "$name" "$delimiter"
      printf '%s\n' "$value"
      printf '%s\n' "$delimiter"
    } >> "$GITHUB_ENV"
  else
    printf '%s=%s\n' "$name" "$value" >> "$GITHUB_ENV"
  fi
done <<< "$entries"
