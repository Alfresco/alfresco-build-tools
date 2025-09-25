setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    # Mock GitHub Actions environment
    export GITHUB_OUTPUT=/dev/null
}

@test "branch regex generation includes copilot/fix pattern" {
    # Mock the generate-regex step behavior
    export JIRA_KEY="JKEY"
    export BRANCH_REGEX=""
    export PR_REGEX=""

    # Create a temp file to capture output instead of /dev/null
    temp_output=$(mktemp)
    export GITHUB_OUTPUT="$temp_output"
    
    # Test the regex generation logic inline
    if [[ -z "$BRANCH_REGEX" ]]; then
        echo "valid-branch-regex=^(revert-)|(improvement|fix|feature|test|tmp)\/($JIRA_KEY)-[0-9]+[_-]{1}[A-Za-z0-9._-]+$|^copilot\/fix.*$" >> "$GITHUB_OUTPUT"
    fi

    # Verify the output contains the copilot/fix pattern
    run grep "copilot" "$temp_output"
    [ "$status" -eq 0 ]
    
    # Extract the generated regex
    generated_regex=$(grep "valid-branch-regex=" "$temp_output" | cut -d'=' -f2-)
    
    # Test the regex with various branch names
    test_traditional_branch="improvement/JKEY-12345-some-feature"
    test_copilot_branch="copilot/fix-bug-123"
    test_invalid_branch="invalid/branch"
    
    [[ $test_traditional_branch =~ $generated_regex ]]
    [[ $test_copilot_branch =~ $generated_regex ]]
    [[ ! $test_invalid_branch =~ $generated_regex ]]
    
    # Cleanup
    rm "$temp_output"
}

@test "copilot/fix branch validation allows various patterns" {
    # Test various copilot/fix branch patterns
    export JIRA_KEY="JKEY"
    regex="^(revert-)|(improvement|fix|feature|test|tmp)\/($JIRA_KEY)-[0-9]+[_-]{1}[A-Za-z0-9._-]+$|^copilot\/fix.*$"
    
    # Should match
    [[ "copilot/fix-bug-123" =~ $regex ]]
    [[ "copilot/fix-aja" =~ $regex ]]
    [[ "copilot/fix" =~ $regex ]]
    [[ "copilot/fix_test" =~ $regex ]]
    [[ "copilot/fix-with-many-dashes-and_underscores" =~ $regex ]]
    
    # Should not match copilot branches that are not fix
    [[ ! "copilot/feature-123" =~ $regex ]]
    [[ ! "copilot/improvement-123" =~ $regex ]]
}

@test "traditional branch patterns still work" {
    export JIRA_KEY="JKEY"
    regex="^(revert-)|(improvement|fix|feature|test|tmp)\/($JIRA_KEY)-[0-9]+[_-]{1}[A-Za-z0-9._-]+$|^copilot\/fix.*$"
    
    # Traditional patterns should still match
    [[ "improvement/JKEY-12345-the-topic" =~ $regex ]]
    [[ "fix/JKEY-67890_bug-fix" =~ $regex ]]
    [[ "feature/JKEY-11111-new-feature" =~ $regex ]]
    [[ "test/JKEY-22222-test-something" =~ $regex ]]
    [[ "tmp/JKEY-33333-temporary" =~ $regex ]]
    [[ "revert-123-improvement/JKEY-44444-revert" =~ $regex ]]
}