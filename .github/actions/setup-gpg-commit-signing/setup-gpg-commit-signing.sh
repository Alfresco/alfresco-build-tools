#!/usr/bin/env bash

if [[ -n "${GPG_PRIVATE_KEY:-}" ]]; then
  if [[ -z "${GPG_PRIVATE_KEY_FINGERPRINT:-}" ]]; then
    echo "gpg-private-key-fingerprint must be set when gpg-private-key is provided" >&2
    exit 1
  fi
  GNUPGHOME=$(mktemp -d)
  chmod 700 "$GNUPGHOME"
  export GNUPGHOME
  printf '%s' "$GPG_PRIVATE_KEY" | gpg --batch --yes --import
  export GIT_CONFIG_COUNT=2
  export GIT_CONFIG_KEY_0=user.signingkey
  export GIT_CONFIG_VALUE_0="$GPG_PRIVATE_KEY_FINGERPRINT"
  export GIT_CONFIG_KEY_1=commit.gpgsign
  export GIT_CONFIG_VALUE_1=true
fi
