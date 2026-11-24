#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert
  bats_load_library bats-file

  TEST_TMPDIR="$(mktemp -d)"
  SUT="$BATS_TEST_DIRNAME/../resolve-terraform-version.sh"

  VERSION_FILE="$TEST_TMPDIR/version"
  printf '1.2.3\n' > "$VERSION_FILE"
  GITHUB_OUTPUT="$TEST_TMPDIR/output"
  : > "$GITHUB_OUTPUT"

  export VERSION_FILE GITHUB_OUTPUT
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "dependabot resolves to the version file content" {
  REQUESTED=dependabot run "$SUT"

  assert_success
  assert_file_contains "$GITHUB_OUTPUT" '^version=1\.2\.3$'
}

@test "a concrete version passes through unchanged" {
  REQUESTED=1.15.0 run "$SUT"

  assert_success
  assert_file_contains "$GITHUB_OUTPUT" '^version=1\.15\.0$'
}

@test "a version constraint passes through unchanged" {
  REQUESTED='~> 1.14' run "$SUT"

  assert_success
  assert_file_contains "$GITHUB_OUTPUT" '^version=~> 1\.14$'
}

@test "an empty value passes through as empty" {
  REQUESTED='' run "$SUT"

  assert_success
  assert_file_contains "$GITHUB_OUTPUT" '^version=$'
}

@test "a multiline value is rejected without writing the output" {
  REQUESTED=$'1.15.0\nINJECTED=1' run "$SUT"

  assert_failure
  assert_output --partial 'must be a single line'
  assert_equal "$(cat "$GITHUB_OUTPUT")" ''
}
