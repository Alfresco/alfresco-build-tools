#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert
  bats_load_library bats-file

  TEST_TMPDIR="$(mktemp -d)"
  SUT="$TEST_TMPDIR/jira_delete_release_by_name.sh"
  cp "$BATS_TEST_DIRNAME/../jira_delete_release_by_name.sh" "$SUT"

  MOCKBIN="$TEST_TMPDIR/mockbin"
  mkdir -p "$MOCKBIN"

  CURL_LOG="$TEST_TMPDIR/curl.log"
  : > "$CURL_LOG"

  # Minimal bin dir containing ONLY bash (portable way to simulate "jq missing")
  MINBIN="$TEST_TMPDIR/minbin"
  mkdir -p "$MINBIN"

  if [[ -x /usr/bin/bash ]]; then
    ln -s /usr/bin/bash "$MINBIN/bash"
  else
    ln -s /bin/bash "$MINBIN/bash"
  fi

  export TEST_TMPDIR SUT MOCKBIN CURL_LOG MINBIN

  # Prepend mocks by default (keep system PATH for normal tests)
  PATH="$MOCKBIN:$PATH"
  export PATH

  # Mock curl (no real network)
  cat > "$MOCKBIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "curl $*" >> "${CURL_LOG:?}"
args="$*"

# GET /project/OPSEXP/versions
if [[ "$args" == *"/rest/api/3/project/OPSEXP/versions"* ]]; then
  printf '%s' "${MOCK_VERSIONS_JSON:-[]}"
  exit 0
fi

# DELETE /version/<id>
if [[ "$args" == *" -X DELETE "* ]] && [[ "$args" == *"/rest/api/3/version/"* ]]; then
  printf '%s' "${MOCK_DELETE_HTTP_CODE:-204}"
  exit 0
fi

echo "Mock curl: unhandled args: $*" >&2
exit 9
EOF
  chmod +x "$MOCKBIN/curl"

  # Default env for most tests
  export JIRA_API_TOKEN="dummy-token"
  export JIRA_API_USER="alfresco-build@hyland.com"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# --- Tests ---

@test "exit 2 when release name missing" {
  run "$SUT"
  assert_failure 2
  assert_output --partial "Usage:"
}

@test "exit 3 when JIRA_API_TOKEN missing" {
  unset JIRA_API_TOKEN
  run "$SUT" "Test - FF"
  assert_failure 3
  assert_output --partial "JIRA_API_TOKEN environment variable is not set"
}

@test "exit 4 when jq is missing" {
  run env PATH="$MOCKBIN:$MINBIN" "$SUT" "Test - FF"
  assert_failure 4
  assert_output --partial "jq is required"
}

@test "exit 5 on Jira API errorMessages" {
  export MOCK_VERSIONS_JSON='{"errorMessages":["No permission"],"errors":{}}'
  run "$SUT" "Test - FF"
  assert_failure 5
  assert_output --partial "Jira API error"
  assert_output --partial "No permission"
}

@test "exit 6 when version name not found" {
  export MOCK_VERSIONS_JSON='[
    {"id":"100","name":"Other","released":false,"archived":false}
  ]'
  run "$SUT" "Test - FF"
  assert_failure 6
  assert_output --partial "No version found with exact name"
}

@test "exit 7 when multiple versions share same name" {
  export MOCK_VERSIONS_JSON='[
    {"id":"101","name":"Test - FF","released":false,"archived":false},
    {"id":"102","name":"Test - FF","released":true,"archived":false}
  ]'
  run "$SUT" "Test - FF"
  assert_failure 7
  assert_output --partial "Found 2 match(es)"
  assert_output --partial "Refusing to delete"
}

@test "abort on prompt does not call DELETE" {
  export MOCK_VERSIONS_JSON='[
    {"id":"12345","name":"Test - FF","released":false,"archived":false}
  ]'

  run bash -c "printf 'n\n' | \"$SUT\" \"Test - FF\""
  assert_success
  assert_output --partial "Aborted."
  assert_file_not_contains "$CURL_LOG" " -X DELETE "
}

@test "happy path: confirm yes deletes and returns 0 on HTTP 204" {
  export MOCK_VERSIONS_JSON='[
    {"id":"12345","name":"Test - FF","released":false,"archived":false}
  ]'
  export MOCK_DELETE_HTTP_CODE="204"

  run bash -c "printf 'y\n' | \"$SUT\" \"Test - FF\""
  assert_success
  assert_output --partial "Deleted successfully"
  assert_file_contains "$CURL_LOG" "/rest/api/3/version/12345"
}

@test "exit 8 when DELETE returns non-204" {
  export MOCK_VERSIONS_JSON='[
    {"id":"12345","name":"Test - FF","released":false,"archived":false}
  ]'
  export MOCK_DELETE_HTTP_CODE="500"

  run bash -c "printf 'y\n' | \"$SUT\" \"Test - FF\""
  assert_failure 8
  assert_output --partial "Delete failed (HTTP 500)"
}
