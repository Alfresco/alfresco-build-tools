#!/usr/bin/env bats

REPO_ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="$REPO_ROOT/.github/actions/jira-propagate-release/extract-tickets-from-release-payload.sh"

setup() {
  [ -f "${SCRIPT}" ]
  chmod +x "${SCRIPT}"
}

@test "writes outputs to GITHUB_OUTPUT (unique, sorted, one-line CSV)" {
  payload="$(mktemp)"
  out_file="$(mktemp)"

  cat > "${payload}" <<'JSON'
{
  "release": {
    "name": "Release v1.2.3",
    "tag_name": "v1.2.3",
    "html_url": "https://github.com/org/repo/releases/tag/v1.2.3",
    "body": "Fixes: ABC-12, DEF-3\nAlso mentions ABC-12 again.\nRef: XYZ-999"
  }
}
JSON

  run env GITHUB_OUTPUT="${out_file}" bash "${SCRIPT}" "${payload}"
  [ "$status" -eq 0 ]

  # Output file should contain tickets-csv=...
  grep -qx "tickets-csv=ABC-12,DEF-3,XYZ-999" "${out_file}"
  grep -qx "jira-version-name=v1.2.3" "${out_file}"
}

@test "writes empty tickets-csv to GITHUB_OUTPUT when none found" {
  payload="$(mktemp)"
  out_file="$(mktemp)"

  cat > "${payload}" <<'JSON'
{
  "release": {
    "name": "Release v1.2.3",
    "tag_name": "v1.2.3",
    "body": "No ticket references here"
  }
}
JSON

  run env GITHUB_OUTPUT="${out_file}" bash "${SCRIPT}" "${payload}"
  [ "$status" -eq 0 ]

  grep -qx "tickets-csv=" "${out_file}"
  grep -qx "jira-version-name=v1.2.3" "${out_file}"
}

@test "supports overriding ticket regex via env var (and writes to outputs)" {
  payload="$(mktemp)"
  out_file="$(mktemp)"

  cat > "${payload}" <<'JSON'
{
  "release": {
    "name": "Release",
    "body": "Matches only TC-1 and OPS-22, ignores ABC-9"
  }
}
JSON

  run env \
    GITHUB_OUTPUT="${out_file}" \
    TICKET_REGEX='(TC|OPS)-[0-9]+' \
    bash "${SCRIPT}" "${payload}"

  [ "$status" -eq 0 ]
  grep -qx "tickets-csv=OPS-22,TC-1" "${out_file}"
}

@test "null-safe: missing fields do not crash and produce empty output" {
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

@test "CLI mode prints tickets-csv=... when GITHUB_OUTPUT is not set" {
  payload="$(mktemp)"

  cat > "${payload}" <<'JSON'
{
  "release": {
    "body": "Fix: ABC-1"
  }
}
JSON

  # In GitHub Actions, GITHUB_OUTPUT is usually set by default.
  # Unset it explicitly to test CLI stdout behavior.
  run env -u GITHUB_OUTPUT bash "${SCRIPT}" "${payload}"
  [ "$status" -eq 0 ]
  output="${output//$'\n'/}"
  [ "$output" = "tickets-csv=ABC-1" ]
}

@test "fails gracefully on malformed JSON input" {
  payload="$(mktemp)"
  cat > "${payload}" <<'JSON'
{
  "release": {
    "name": "Release v1.2.3",
    "body": "This JSON is malformed"
  }
JSON
  run bash "${SCRIPT}" "${payload}"
  # Expect a non-zero status due to JSON parse error
  [ "$status" -ne 0 ]
  # Ensure some error output is produced (from jq or the script)
  [ -n "$output" ]
}

@test "fails with clear error on invalid TICKET_REGEX" {
  payload="$(mktemp)"
  out_file="$(mktemp)"

  cat >"${payload}" <<EOF
{
  "release": {
    "tag_name": "v1.2.3",
    "name": "Release",
    "body": "ABC-1"
  }
}
EOF

  export GITHUB_OUTPUT="${out_file}"
  export TICKET_REGEX="["   # invalid regex

  run "${SCRIPT}" "${payload}"

  # Should fail
  [ "$status" -ne 0 ]

  # Should emit error annotation
  [[ "$output" == *"Invalid TICKET_REGEX"* ]]

  # Should not write tickets-csv
  ! grep -q "^tickets-csv=" "${out_file}"
}
