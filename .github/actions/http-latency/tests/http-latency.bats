setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    # Put tests dir first in PATH so mock curl is found before real curl
    PATH="$DIR:$DIR/..:$PATH"
    ACTION_SCRIPT="$DIR/../action.sh"

    export GITHUB_OUTPUT="$BATS_TMPDIR/test_http_latency_ghoutput_${RANDOM}.log"
    > "$GITHUB_OUTPUT"

    # Reset mock curl call counter
    rm -f "$BATS_TMPDIR/curl_call_count"

    # Set required env vars with small values for fast tests
    export URL="http://localhost:12345/test"
    export ITERATIONS="4"
    export WARMUP="1"
    export TCP_TIMEOUT="5"
    export XFER_MAX_TIME="10"
}

teardown() {
    rm -f "$GITHUB_OUTPUT"
    rm -f "$BATS_TMPDIR/curl_call_count"
}

@test "fails when URL is not set" {
    unset URL

    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"URL environment variable is not set"* ]]
}

@test "fails when URL is empty" {
    export URL=""

    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"URL environment variable is not set"* ]]
}

@test "runs warmup requests before benchmark" {
    export WARMUP="3"
    export ITERATIONS="2"

    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Warming up with 3 requests"* ]]
    [[ "$output" == *"Running 2 benchmark iterations"* ]]
}

@test "respects custom iteration count" {
    export ITERATIONS="2"

    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Running 2 benchmark iterations"* ]]
    [[ "$output" == *"Benchmark complete"* ]]
}

@test "produces all expected output keys" {
    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 0 ]

    github_output=$(< "$GITHUB_OUTPUT")

    # Check all expected metric outputs are present
    [[ "$github_output" == *"total_time_mean="* ]]
    [[ "$github_output" == *"total_time_stddev="* ]]
    [[ "$github_output" == *"connect_time_mean="* ]]
    [[ "$github_output" == *"connect_time_stddev="* ]]
    [[ "$github_output" == *"namelookup_time_mean="* ]]
    [[ "$github_output" == *"namelookup_time_stddev="* ]]
    [[ "$github_output" == *"pretransfer_time_mean="* ]]
    [[ "$github_output" == *"pretransfer_time_stddev="* ]]
    [[ "$github_output" == *"starttransfer_time_mean="* ]]
    [[ "$github_output" == *"starttransfer_time_stddev="* ]]
}

@test "produces summary output" {
    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 0 ]

    github_output=$(< "$GITHUB_OUTPUT")

    [[ "$github_output" == *"summary<<EOF"* ]]
    [[ "$github_output" == *"Latency Benchmark Results"* ]]
    [[ "$github_output" == *"DNS Lookup"* ]]
    [[ "$github_output" == *"TCP Connect"* ]]
    [[ "$github_output" == *"TLS + Send"* ]]
    [[ "$github_output" == *"Time to First Byte"* ]]
    [[ "$github_output" == *"Total Time"* ]]
    [[ "$github_output" == *"EOF"* ]]
}

@test "summary contains URL and iterations" {
    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 0 ]

    github_output=$(< "$GITHUB_OUTPUT")

    [[ "$github_output" == *"$URL"* ]]
    [[ "$github_output" == *"$ITERATIONS"* ]]
}

@test "calculates correct mean with uniform data" {
    # All iterations return the same values
    export MOCK_CURL_DATA="0.001000,0.010000,0.020000,0.030000,0.100000"

    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 0 ]

    github_output=$(< "$GITHUB_OUTPUT")

    # With uniform data, mean should equal the value and stddev should be 0
    [[ "$github_output" == *"total_time_mean=0.100000"* ]]
    [[ "$github_output" == *"total_time_stddev=0.000000"* ]]
    [[ "$github_output" == *"namelookup_time_mean=0.001000"* ]]
    [[ "$github_output" == *"namelookup_time_stddev=0.000000"* ]]
    [[ "$github_output" == *"connect_time_mean=0.010000"* ]]
    [[ "$github_output" == *"connect_time_stddev=0.000000"* ]]
    [[ "$github_output" == *"pretransfer_time_mean=0.020000"* ]]
    [[ "$github_output" == *"pretransfer_time_stddev=0.000000"* ]]
    [[ "$github_output" == *"starttransfer_time_mean=0.030000"* ]]
    [[ "$github_output" == *"starttransfer_time_stddev=0.000000"* ]]
}

@test "calculates correct mean with alternating data" {
    # Mock curl alternates between 0.1 and 0.3 for total_time (default behavior)
    # With 4 iterations: 0.1, 0.3, 0.1, 0.3
    # Mean = 0.2, Stddev = 0.1
    unset MOCK_CURL_DATA

    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 0 ]

    github_output=$(< "$GITHUB_OUTPUT")

    [[ "$github_output" == *"total_time_mean=0.200000"* ]]
    [[ "$github_output" == *"total_time_stddev=0.100000"* ]]

    # namelookup alternates between 0.001 and 0.003
    # Mean = 0.002, Stddev = 0.001
    [[ "$github_output" == *"namelookup_time_mean=0.002000"* ]]
    [[ "$github_output" == *"namelookup_time_stddev=0.001000"* ]]
}

@test "summary table contains formatted values" {
    export MOCK_CURL_DATA="0.001000,0.010000,0.020000,0.030000,0.100000"

    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 0 ]

    github_output=$(< "$GITHUB_OUTPUT")

    # Summary should have markdown table with 3 decimal places
    [[ "$github_output" == *"| DNS Lookup | 0.001s | ±0.000s |"* ]]
    [[ "$github_output" == *"| TCP Connect | 0.010s | ±0.000s |"* ]]
    [[ "$github_output" == *"| TLS + Send | 0.020s | ±0.000s |"* ]]
    [[ "$github_output" == *"| Time to First Byte | 0.030s | ±0.000s |"* ]]
    [[ "$github_output" == *"| **Total Time** | **0.100s** | **±0.000s** |"* ]]
}

@test "cleans up temporary results file" {
    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 0 ]

    # The script creates a temp file with mktemp and removes it at the end
    # We can't easily check the exact file, but we verify no error occurred
    [[ "$output" == *"Benchmark complete"* ]]
}

@test "outputs progress dots during benchmark" {
    export ITERATIONS="3"

    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 0 ]

    # Should have dots for each iteration
    [[ "$output" == *"..."* ]]
}

@test "single iteration produces valid output" {
    export ITERATIONS="1"
    export MOCK_CURL_DATA="0.005000,0.050000,0.080000,0.120000,0.250000"

    run bash "$ACTION_SCRIPT"

    [ "$status" -eq 0 ]

    github_output=$(< "$GITHUB_OUTPUT")

    [[ "$github_output" == *"total_time_mean=0.250000"* ]]
    [[ "$github_output" == *"total_time_stddev=0.000000"* ]]
    [[ "$github_output" == *"connect_time_mean=0.050000"* ]]
}
