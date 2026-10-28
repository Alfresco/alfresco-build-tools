@test "Cloudsmith Maven promotion handles pagination, readiness, retries and failures" {
  run python3 -m unittest discover -s "$BATS_TEST_DIRNAME" -p 'test_*.py'
  [ "$status" -eq 0 ]
}
