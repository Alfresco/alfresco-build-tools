#!/bin/bash
set -e

ITERATIONS="${ITERATIONS:-100}"
WARMUP="${WARMUP:-10}"
TCP_TIMEOUT="${TCP_TIMEOUT:-5}"
XFER_MAX_TIME="${XFER_MAX_TIME:-10}"

if [[ -z "$URL" ]]; then
  echo "❌ Error: URL environment variable is not set."
  exit 1
fi

echo "🔥 Warming up with $WARMUP requests..."
for i in $(seq 1 $WARMUP); do
  curl \
       --connect-timeout ${TCP_TIMEOUT} \
       --max-time ${XFER_MAX_TIME} \
       -s \
       -o /dev/null "$URL" || true
done

echo "📊 Running $ITERATIONS benchmark iterations..."

# Create temporary file for results
RESULTS_FILE=$(mktemp)

# Run iterations and collect metrics
for i in $(seq 1 $ITERATIONS); do
  echo -n "."
  curl \
       --connect-timeout ${TCP_TIMEOUT} \
       --max-time ${XFER_MAX_TIME} \
       -w "%{time_namelookup},%{time_connect},%{time_pretransfer},%{time_starttransfer},%{time_total}\n" \
       -o /dev/null -s "$URL" >> "$RESULTS_FILE"
done
echo ""

# Calculate statistics using awk
echo "🧮 Calculating statistics..."

awk -F',' '
{
  namelookup[NR] = $1
  connect[NR] = $2
  pretransfer[NR] = $3
  starttransfer[NR] = $4
  total[NR] = $5

  sum_namelookup += $1
  sum_connect += $2
  sum_pretransfer += $3
  sum_starttransfer += $4
  sum_total += $5
}
END {
  n = NR

  # Calculate means
  mean_namelookup = sum_namelookup / n
  mean_connect = sum_connect / n
  mean_pretransfer = sum_pretransfer / n
  mean_starttransfer = sum_starttransfer / n
  mean_total = sum_total / n

  # Calculate standard deviations
  for (i = 1; i <= n; i++) {
    sumsq_namelookup += (namelookup[i] - mean_namelookup)^2
    sumsq_connect += (connect[i] - mean_connect)^2
    sumsq_pretransfer += (pretransfer[i] - mean_pretransfer)^2
    sumsq_starttransfer += (starttransfer[i] - mean_starttransfer)^2
    sumsq_total += (total[i] - mean_total)^2
  }

  stddev_namelookup = sqrt(sumsq_namelookup / n)
  stddev_connect = sqrt(sumsq_connect / n)
  stddev_pretransfer = sqrt(sumsq_pretransfer / n)
  stddev_starttransfer = sqrt(sumsq_starttransfer / n)
  stddev_total = sqrt(sumsq_total / n)

  # Output for GitHub Actions
  printf "namelookup_time_mean=%.6f\n", mean_namelookup
  printf "namelookup_time_stddev=%.6f\n", stddev_namelookup
  printf "connect_time_mean=%.6f\n", mean_connect
  printf "connect_time_stddev=%.6f\n", stddev_connect
  printf "pretransfer_time_mean=%.6f\n", mean_pretransfer
  printf "pretransfer_time_stddev=%.6f\n", stddev_pretransfer
  printf "starttransfer_time_mean=%.6f\n", mean_starttransfer
  printf "starttransfer_time_stddev=%.6f\n", stddev_starttransfer
  printf "total_time_mean=%.6f\n", mean_total
  printf "total_time_stddev=%.6f\n", stddev_total

  # Create summary
  printf "summary<<EOF\n"
  printf "## 📈 Latency Benchmark Results\n\n"
  printf "**URL**: '"$URL"'\n"
  printf "**Iterations**: '"$ITERATIONS"'\n\n"
  printf "| Metric | Mean | Std Dev |\n"
  printf "|--------|------|----------|\n"
  printf "| DNS Lookup | %.3fs | ±%.3fs |\n", mean_namelookup, stddev_namelookup
  printf "| TCP Connect | %.3fs | ±%.3fs |\n", mean_connect, stddev_connect
  printf "| TLS + Send | %.3fs | ±%.3fs |\n", mean_pretransfer, stddev_pretransfer
  printf "| Time to First Byte | %.3fs | ±%.3fs |\n", mean_starttransfer, stddev_starttransfer
  printf "| **Total Time** | **%.3fs** | **±%.3fs** |\n", mean_total, stddev_total
  printf "EOF\n"
}' URL="$URL" ITERATIONS="$ITERATIONS" "$RESULTS_FILE" >> "$GITHUB_OUTPUT"

# Display summary
echo ""
echo "✅ Benchmark complete!"
echo ""
grep -A 20 "summary<<EOF" "$GITHUB_OUTPUT" | grep -v "^summary" | grep -v "^EOF" || true

# Cleanup
rm -f "$RESULTS_FILE"
