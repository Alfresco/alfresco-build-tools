#!/bin/bash -e

COMPUTED_MESSAGE=""

if [[ -n "$BLOCK_MESSAGE" && "$APPEND" == 'true' ]] || [ -z "$BLOCK_MESSAGE" ]; then
  case $EVENT_NAME in
    pull_request)
    COMPUTED_MESSAGE="$PR_TITLE"
    ;;
    issues)
    COMPUTED_MESSAGE="$ISSUE_BODY"
    ;;
    *)
    COMPUTED_MESSAGE="$COMMIT_MESSAGE"
    ;;
  esac
fi

if [ -n "$BLOCK_MESSAGE" ]; then
  if [[ "$APPEND" == 'true' && -n "$COMPUTED_MESSAGE" ]]; then
    COMPUTED_MESSAGE="${COMPUTED_MESSAGE}\n"
  fi
  COMPUTED_MESSAGE="${COMPUTED_MESSAGE}$BLOCK_MESSAGE"
fi

if [ -n "$COMPUTED_MESSAGE" ]; then
  echo 'result<<EOF'
  printf "*Message*\n${COMPUTED_MESSAGE}" | sed -z 's/\n/\\n/g' | sed -r 's/"/\\\"/g' | sed -e 's/\r//g'
  echo ''
  echo 'EOF'
else
  echo 'result='
fi
