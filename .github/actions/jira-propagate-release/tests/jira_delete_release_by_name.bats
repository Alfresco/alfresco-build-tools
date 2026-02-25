#!/usr/bin/env bats

setup() {
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

# --- tiny assertion helpers (vanilla) ---

assert_status() {
  local expected="$1"
  if [[ "$status" -ne "$expected" ]]; then
    echo "Expected status $expected, got $status" >&2
    echo "Output:" >&2
    echo "$output" >&2
    return 1
  fi
}

assert_output_contains() {
  local needle="$1"
  if [[ "$output" != *"$needle"* ]]; then
    echo "Expected output to contain: $needle" >&2
    echo "Output:" >&2
    echo "$output" >&2
    return 1
  fi
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "Expected file $file to contain: $needle" >&2
    echo "File content:" >&2
    cat "$file" >&2
    return 1
  fi
}

refute_file_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "Expected file $file NOT to contain: $needle" >&2
    echo "File content:" >&2
    cat "$file" >&2
    return 1
  fi
}

# --- Tests ---

@test "exit 2 when release name missing" {
  run "$SUT"
  assert_status 2
  assert_output_contains "Usage:"
}

@test "exit 3 when JIRA_API_TOKEN missing" {
  unset JIRA_API_TOKEN
  run "$SUT" "Test - FF"
  assert_status 3
  assert_output_contains "JIRA_API_TOKEN environment variable is not set"
}

@test "exit 4 when jq is missing" {
  run env PATH="$MOCKBIN:$MINBIN" "$SUT" "Test - FF"
  assert_status 4
  assert_output_contains "jq is required"
}

@test "exit 5 on Jira API errorMessages" {
  export MOCK_VERSIONS_JSON='{"errorMessages":["No permission"],"errors":{}}'
  run "$SUT" "Test - FF"
  assert_status 5
  assert_output_contains "Jira API error"
  assert_output_contains "No permission"
}

@test "exit 6 when version name not found" {
  export MOCK_VERSIONS_JSON='[
    {"id":"100","name":"Other","released":false,"archived":false}
  ]'
  run "$SUT" "Test - FF"
  assert_status 6
  assert_output_contains "No version found with exact name"
}

@test "exit 7 when multiple versions share same name" {
  export MOCK_VERSIONS_JSON='[
    {"id":"101","name":"Test - FF","released":false,"archived":false},
    {"id":"102","name":"Test - FF","released":true,"archived":false}
  ]'
  run "$SUT" "Test - FF"
  assert_status 7
  assert_output_contains "Found 2 match(es)"
  assert_output_contains "Refusing to delete"
}

@test "abort on prompt does not call DELETE" {
  export MOCK_VERSIONS_JSON='[
    {"id":"12345","name":"Test - FF","released":false,"archived":false}
  ]'

  run bash -c "printf 'n\n' | \"$SUT\" \"Test - FF\""
  assert_status 0
  assert_output_contains "Aborted."
  refute_file_contains "$CURL_LOG" " -X DELETE "
}

@test "happy path: confirm yes deletes and returns 0 on HTTP 204" {
  export MOCK_VERSIONS_JSON='[
    {"id":"12345","name":"Test - FF","released":false,"archived":false}
  ]'
  export MOCK_DELETE_HTTP_CODE="204"

  run bash -c "printf 'y\n' | \"$SUT\" \"Test - FF\""
  assert_status 0
  assert_output_contains "Deleted successfully"
  assert_file_contains "$CURL_LOG" "/rest/api/3/version/12345"
}

@test "exit 8 when DELETE returns non-204" {
  export MOCK_VERSIONS_JSON='[
    {"id":"12345","name":"Test - FF","released":false,"archived":false}
  ]'
  export MOCK_DELETE_HTTP_CODE="500"

  run bash -c "printf 'y\n' | \"$SUT\" \"Test - FF\""
  assert_status 8
  assert_output_contains "Delete failed (HTTP 500)"
}
