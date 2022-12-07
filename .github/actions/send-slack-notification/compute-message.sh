#!/bin/bash -e

COMPUTED_MESSAGE=""
if [ -n "$BLOCK_MESSAGE" ]; then
    COMPUTED_MESSAGE=$BLOCK_MESSAGE
else
    case $EVENT_NAME in
        pull_request)
        COMPUTED_MESSAGE=$PR_TITLE
        ;;
        issues)
        COMPUTED_MESSAGE=$ISSUE_BODY
        ;;
        *)
        COMPUTED_MESSAGE=$COMMIT_MESSAGE
        ;;
    esac
fi

if [ -n "$COMPUTED_MESSAGE" ]; then
    echo 'result<<EOF'
    echo -n "*Message*\n${COMPUTED_MESSAGE}" | sed -z 's/\n/\\n/g'
    echo ''
    echo 'EOF'
else
    echo 'result='
fi
