#!/usr/bin/env bats

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" >/dev/null 2>&1 && pwd)"
  SCRIPT="$DIR/../setup-gpg-commit-signing.sh"

  TEST_GNUPGHOME=$(mktemp -d)
  chmod 700 "$TEST_GNUPGHOME"

  cat >"$TEST_GNUPGHOME/key-params" <<'EOF'
Key-Type: RSA
Key-Length: 2048
Name-Real: Test
Name-Email: test@example.com
Expire-Date: 0
%no-protection
%commit
EOF

  gpg --homedir "$TEST_GNUPGHOME" --batch --generate-key "$TEST_GNUPGHOME/key-params"
  GPG_PRIVATE_KEY=$(gpg --homedir "$TEST_GNUPGHOME" --armor --export-secret-keys test@example.com)
  export GPG_PRIVATE_KEY
  export GPG_PRIVATE_KEY_FINGERPRINT="$(
    gpg --homedir "$TEST_GNUPGHOME" --with-colons --fingerprint test@example.com |
      awk -F: '$1 == "fpr" && $10 != "" { print $10; exit }'
  )"
}

teardown() {
  rm -rf "$TEST_GNUPGHOME"
  unset GPG_PRIVATE_KEY GPG_PRIVATE_KEY_FINGERPRINT GIT_CONFIG_COUNT
  unset GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1 GNUPGHOME
}

@test "does nothing without gpg key" {
  unset GPG_PRIVATE_KEY

  # shellcheck source=/dev/null
  source "$SCRIPT"

  [ -z "${GIT_CONFIG_COUNT:-}" ]
}

@test "fails when fingerprint is missing" {
  unset GPG_PRIVATE_KEY_FINGERPRINT

  run bash -c "source \"$SCRIPT\""

  [ "$status" -eq 1 ]
  [[ "$output" == *"gpg-private-key-fingerprint must be set"* ]]
}

@test "fails when gpg import fails" {
  export GPG_PRIVATE_KEY="not a gpg key"

  run bash -c "source \"$SCRIPT\""

  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to import GPG private key"* ]]
}

@test "cleans up gnupg home when the step shell exits" {
  gnupg_home=$(bash -c "source \"$SCRIPT\"; echo \"\$GNUPGHOME\"")

  [ -n "$gnupg_home" ]
  [ ! -d "$gnupg_home" ]
}

@test "configures step-scoped git signing" {
  # shellcheck source=/dev/null
  source "$SCRIPT"

  [ "$GIT_CONFIG_COUNT" = "2" ]
  [ "$GIT_CONFIG_KEY_0" = "user.signingkey" ]
  [ "$GIT_CONFIG_VALUE_0" = "$GPG_PRIVATE_KEY_FINGERPRINT" ]
  [ "$GIT_CONFIG_KEY_1" = "commit.gpgsign" ]
  [ "$GIT_CONFIG_VALUE_1" = "true" ]
  [ -n "$GNUPGHOME" ]
  gpg --list-secret-keys | grep -q test@example.com
}
