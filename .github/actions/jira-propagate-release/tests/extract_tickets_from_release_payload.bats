#!/usr/bin/env bats

REPO_ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="$REPO_ROOT/.github/actions/jira-propagate-release/extract-tickets-from-release-payload.sh"

teardown() {
  rm -f "grep_err.txt"
}

# --------------------------------------------------
# 🧱 Helpers
# --------------------------------------------------

make_payload() {
  local tag="$1"
  local name="${2:-Release}"
  local body="${3:-}"

  payload="$(mktemp)"
  cat > "${payload}" <<JSON
{
  "release": {
    "name": "${name}",
    "tag_name": "${tag}",
    "html_url": "https://github.com/org/repo/releases/tag/${tag}",
    "body": "${body}"
  }
}
JSON
}

# --------------------------------------------------
# 🎯 Core behavior
# --------------------------------------------------

@test "writes outputs to GITHUB_OUTPUT (unique, sorted CSV)" {
  make_payload "v1.2.3" "Release v1.2.3" "Fixes: ABC-12, DEF-3\nABC-12 again\nRef XYZ-999"
  out_file="$(mktemp)"

  run env GITHUB_OUTPUT="${out_file}" bash "${SCRIPT}" "${payload}"
  [ "$status" -eq 0 ]

  grep -qx "tickets-csv=ABC-12,DEF-3,XYZ-999" "${out_file}"
  grep -qx "jira-version-name=v1.2.3" "${out_file}"
}

@test "writes empty tickets-csv when none found" {
  make_payload "v1.2.3" "Release v1.2.3" "No tickets here"
  out_file="$(mktemp)"

  run env GITHUB_OUTPUT="${out_file}" bash "${SCRIPT}" "${payload}"
  [ "$status" -eq 0 ]

  grep -qx "tickets-csv=" "${out_file}"
  grep -qx "jira-version-name=v1.2.3" "${out_file}"
}

# --------------------------------------------------
# 🧩 Prefix logic (NEW FEATURE)
# --------------------------------------------------

@test "no prefixes → unchanged tag" {
  make_payload "v1.2.3"
  out_file="$(mktemp)"

  run env GITHUB_OUTPUT="${out_file}" bash "${SCRIPT}" "${payload}"
  [ "$status" -eq 0 ]

  grep -qx "jira-version-name=v1.2.3" "${out_file}"
}

@test "removes GitHub release prefix" {
  make_payload "v2.3.4"
  out_file="$(mktemp)"

  run env \
    GITHUB_OUTPUT="${out_file}" \
    GITHUB_VERSION_PREFIX="v" \
    bash "${SCRIPT}" "${payload}"

  [ "$status" -eq 0 ]
  grep -qx "jira-version-name=2.3.4" "${out_file}"
}

@test "adds Jira release prefix" {
  make_payload "3.4.5"
  out_file="$(mktemp)"

  run env \
    GITHUB_OUTPUT="${out_file}" \
    JIRA_VERSION_PREFIX="MyComponent-" \
    bash "${SCRIPT}" "${payload}"

  [ "$status" -eq 0 ]
  grep -qx "jira-version-name=MyComponent-3.4.5" "${out_file}"
}

@test "applies both GitHub and Jira prefixes" {
  make_payload "release-5.6.7"
  out_file="$(mktemp)"

  run env \
    GITHUB_OUTPUT="${out_file}" \
    GITHUB_VERSION_PREFIX="release-" \
    JIRA_VERSION_PREFIX="MyComponent-" \
    bash "${SCRIPT}" "${payload}"

  [ "$status" -eq 0 ]
  grep -qx "jira-version-name=MyComponent-5.6.7" "${out_file}"
}

@test "empty prefixes are ignored" {
  make_payload "v1.2.3"
  out_file="$(mktemp)"

  run env \
    GITHUB_OUTPUT="${out_file}" \
    GITHUB_VERSION_PREFIX="" \
    JIRA_VERSION_PREFIX="" \
    bash "${SCRIPT}" "${payload}"

  [ "$status" -eq 0 ]
  grep -qx "jira-version-name=v1.2.3" "${out_file}"
}

@test "GitHub prefix not present → no change" {
  make_payload "1.2.3"
  out_file="$(mktemp)"

  run env \
    GITHUB_OUTPUT="${out_file}" \
    GITHUB_VERSION_PREFIX="v" \
    bash "${SCRIPT}" "${payload}"

  [ "$status" -eq 0 ]
  grep -qx "jira-version-name=1.2.3" "${out_file}"
}

# --------------------------------------------------
# 🎯 Ticket extraction
# --------------------------------------------------

@test "supports overriding ticket regex" {
  make_payload "v1.0.0" "Release" "Matches TC-1 OPS-22 ignores ABC-9"
  out_file="$(mktemp)"

  run env \
    GITHUB_OUTPUT="${out_file}" \
    TICKET_REGEX='(TC|OPS)-[0-9]+' \
    bash "${SCRIPT}" "${payload}"

  [ "$status" -eq 0 ]
  grep -qx "tickets-csv=OPS-22,TC-1" "${out_file}"
}

# --------------------------------------------------
# 🛡️ Robustness
# --------------------------------------------------

@test "null-safe: missing fields do not crash" {
  payload="$(mktemp)"
  out_file="$(mktemp)"

  cat > "${payload}" <<'JSON'
{
  "release": {
    "body": null,
    "name": null,
    "tag_name": null,
    "html_url": null
  }
}
JSON

  run env GITHUB_OUTPUT="${out_file}" bash "${SCRIPT}" "${payload}"
  [ "$status" -eq 0 ]

  grep -qx "tickets-csv=" "${out_file}"
  grep -qx "jira-version-name=" "${out_file}"
}

@test "CLI mode prints to stdout when GITHUB_OUTPUT is unset" {
  make_payload "v1.0.0" "Release" "Fix: ABC-1"

  run env -u GITHUB_OUTPUT bash "${SCRIPT}" "${payload}"
  [ "$status" -eq 0 ]

  output="${output//$'\n'/}"
  [ "$output" = "tickets-csv=ABC-1" ]
}

@test "fails on malformed JSON" {
  payload="$(mktemp)"

  cat > "${payload}" <<'JSON'
{
  "release": {
    "name": "Release",
    "body": "broken"
  }
JSON

  run bash "${SCRIPT}" "${payload}"
  [ "$status" -ne 0 ]
  [ -n "$output" ]
}

@test "fails on invalid TICKET_REGEX" {
  make_payload "v1.2.3" "Release" "ABC-1"
  out_file="$(mktemp)"

  run env \
    GITHUB_OUTPUT="${out_file}" \
    TICKET_REGEX="[" \
    bash "${SCRIPT}" "${payload}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid TICKET_REGEX"* ]]
  ! grep -q "^tickets-csv=" "${out_file}"
}
