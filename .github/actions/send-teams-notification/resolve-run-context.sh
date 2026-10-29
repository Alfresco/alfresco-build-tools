#!/usr/bin/env bash
set -euo pipefail

REPORT_ON="${REPORT_ON:-triggering-run}"

# A typo here would quietly report the wrong run, so reject anything unexpected.
case "$REPORT_ON" in
  triggering-run|self) ;;
  *) echo "::error::report-on must be 'triggering-run' or 'self', found '$REPORT_ON'"; exit 1 ;;
esac

# The card always describes one run. On a workflow_run event that is the run which
# triggered this one, unless the caller asks for the watcher itself.
if [ "${GITHUB_EVENT_NAME:-}" = "workflow_run" ] && [ "$REPORT_ON" != "self" ]; then
  SHA="${WR_SHA:-}"
  BRANCH="${WR_BRANCH:-}"
  RUN_ID="${WR_RUN_ID:-}"
  RUN_ATTEMPT="${WR_RUN_ATTEMPT:-}"
  WORKFLOW="${WR_WORKFLOW:-}"
else
  SHA="${SELF_SHA:-}"
  BRANCH="${SELF_BRANCH:-}"
  RUN_ID="${SELF_RUN_ID:-}"
  RUN_ATTEMPT="${SELF_RUN_ATTEMPT:-}"
  WORKFLOW="${SELF_WORKFLOW:-}"
fi

WORKFLOW_TITLE="$WORKFLOW"
if [ "$RUN_ATTEMPT" != '1' ]; then
  WORKFLOW_TITLE="$WORKFLOW (attempt #$RUN_ATTEMPT)"
fi

echo "sha=$SHA"
echo "small-sha=${SHA:0:6}"
echo "branch=$BRANCH"
echo "run-link=${REPO_URL:-}/actions/runs/$RUN_ID/attempts/$RUN_ATTEMPT"
echo "workflow-title=$WORKFLOW_TITLE"
