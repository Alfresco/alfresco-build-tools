#!/bin/bash
set -eo pipefail

if [ ! -f "$YML_PATH" ]; then
  echo "::warning::$YML_PATH not found, skipping"
  exit 0
fi

entries="$(yq '.env.global[]' "$YML_PATH")"

while IFS= read -r ENVVAR; do
  [ -z "$ENVVAR" ] && continue
  if [[ "$ENVVAR" =~ $IGNORE_REGEX ]]; then
    echo "Skipping unwanted $ENVVAR"
    continue
  fi
  name="${ENVVAR%%=*}"
  rhs="${ENVVAR#*=}"
  # Values are taken verbatim (quotes, spaces, JSON kept byte-for-byte) with
  # only $VAR/${VAR} expansion applied, via envsubst rather than eval, so a
  # value can never trigger shell word-splitting or command execution.
  value="$(printf '%s' "$rhs" | envsubst)"
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
