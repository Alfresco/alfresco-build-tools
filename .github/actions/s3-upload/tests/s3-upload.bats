#!/usr/bin/env bats

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  SUT="$TEST_TMPDIR/s3-upload.sh"
  cp "$BATS_TEST_DIRNAME/../s3-upload.sh" "$SUT"
  chmod +x "$SUT"

  MOCKBIN="$TEST_TMPDIR/mockbin"
  mkdir -p "$MOCKBIN"

  AWS_LOG="$TEST_TMPDIR/aws.log"
  : > "$AWS_LOG"

  export TEST_TMPDIR SUT MOCKBIN AWS_LOG

  PATH="$MOCKBIN:$PATH"
  export PATH

  # Mock aws (no real network/credentials)
  cat > "$MOCKBIN/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "aws $*" >> "${AWS_LOG:?}"

if [[ "$1" == "s3api" && "$2" == "head-object" ]]; then
  exit "${MOCK_HEAD_OBJECT_RC:-0}"
fi

if [[ "$1" == "s3" && "$2" == "cp" ]]; then
  exit 0
fi

echo "Mock aws: unhandled args: $*" >&2
exit 9
EOF
  chmod +x "$MOCKBIN/aws"

  SRC_DIR="$TEST_TMPDIR/srcdir"
  mkdir -p "$SRC_DIR"
  echo hi > "$SRC_DIR/a.txt"

  SRC_FILE="$TEST_TMPDIR/artifact.zip"
  echo hi > "$SRC_FILE"

  export SRC_DIR SRC_FILE

  # Default env for most tests
  export DESTINATION="s3://bucket/path"
  export SOURCE=""
  export DEPLOY_DIR="./deploy_dir"
  export COPY_PROPS="none"
  export S3_BUCKET=""
  export S3_PATH=""
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

@test "local file source is uploaded without --recursive to a destination-as-prefix" {
  export SOURCE="$SRC_FILE"
  run "$SUT"
  assert_status 0
  refute_file_contains "$AWS_LOG" "--recursive"
  assert_file_contains "$AWS_LOG" "s3 cp --acl private ${SRC_FILE} s3://bucket/path/"
}

@test "local file source with a trailing slash destination does not double the slash" {
  export SOURCE="$SRC_FILE"
  export DESTINATION="s3://bucket/path/"
  run "$SUT"
  assert_status 0
  assert_file_contains "$AWS_LOG" "s3 cp --acl private ${SRC_FILE} s3://bucket/path/"
  refute_file_contains "$AWS_LOG" "s3://bucket/path//"
}

@test "local directory source still uses --recursive" {
  export SOURCE="$SRC_DIR"
  run "$SUT"
  assert_status 0
  assert_file_contains "$AWS_LOG" "s3 cp --acl private --recursive ${SRC_DIR} s3://bucket/path"
}

@test "s3 object source is copied without --recursive when head-object succeeds" {
  export SOURCE="s3://source-bucket/artifact.zip"
  export MOCK_HEAD_OBJECT_RC="0"
  run "$SUT"
  assert_status 0
  assert_file_contains "$AWS_LOG" "s3api head-object --bucket source-bucket --key artifact.zip"
  refute_file_contains "$AWS_LOG" "s3 cp --acl private --recursive"
  assert_file_contains "$AWS_LOG" "s3 cp --acl private --copy-props none s3://source-bucket/artifact.zip s3://bucket/path/"
}

@test "s3 source falls back to --recursive prefix copy when head-object fails" {
  export SOURCE="s3://source-bucket/some-prefix"
  export MOCK_HEAD_OBJECT_RC="254"
  run "$SUT"
  assert_status 0
  assert_file_contains "$AWS_LOG" "s3 cp --acl private --recursive --copy-props none s3://source-bucket/some-prefix s3://bucket/path"
}

@test "s3 source ending in a slash is treated as a prefix without calling head-object" {
  export SOURCE="s3://source-bucket/some-prefix/"
  run "$SUT"
  assert_status 0
  refute_file_contains "$AWS_LOG" "head-object"
  assert_file_contains "$AWS_LOG" "s3 cp --acl private --recursive --copy-props none s3://source-bucket/some-prefix/ s3://bucket/path"
}

@test "deprecated s3-bucket and s3-path inputs still resolve" {
  export DESTINATION=""
  export S3_BUCKET="legacy-bucket"
  export S3_PATH="legacy/path"
  export SOURCE="$SRC_DIR"
  run "$SUT"
  assert_status 0
  assert_output_contains "s3-bucket and s3-path are deprecated"
  assert_file_contains "$AWS_LOG" "s3 cp --acl private --recursive ${SRC_DIR} s3://legacy-bucket/legacy/path"
}

@test "deprecated deploy-dir input still resolves" {
  export SOURCE=""
  export DEPLOY_DIR="$SRC_DIR"
  run "$SUT"
  assert_status 0
  assert_output_contains "deploy-dir is deprecated"
  assert_file_contains "$AWS_LOG" "s3 cp --acl private --recursive ${SRC_DIR} s3://bucket/path"
}

@test "exit 1 when destination is not an s3:// URI" {
  export SOURCE="$SRC_DIR"
  export DESTINATION="not-an-s3-uri"
  run "$SUT"
  assert_status 1
  assert_output_contains "destination must be an s3:// URI"
}
