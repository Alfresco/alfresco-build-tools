#!/bin/bash -e

echo 'result<<EOF'

if [ -n "$BLOCK_MESSAGE" ]; then
    echo -n "${BLOCK_MESSAGE}" | sed -z 's/\n/\\n/g'
else
    case $EVENT_NAME in
        pull_request)
        echo -n "${PR_TITLE}" | sed -z 's/\n/\\n/g'
        ;;
        issues)
        echo -n "${ISSUE_BODY}" | sed -z 's/\n/\\n/g'
        ;;
        *)
        echo -n "${COMMIT_MESSAGE}" | sed -z 's/\n/\\n/g'
        ;;
    esac
fi

echo ''
echo 'EOF'
