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
    COMPUTED_MESSAGE="${COMPUTED_MESSAGE}\n\n"
  fi
  COMPUTED_MESSAGE="${COMPUTED_MESSAGE}$BLOCK_MESSAGE"
fi

if [ -n "$NEEDS" ]; then
  COMPUTED_MESSAGE="${COMPUTED_MESSAGE}\n\n$NEEDS"
fi

if [ -n "$COMPUTED_MESSAGE" ]; then
  COMPUTED_MESSAGE="${COMPUTED_MESSAGE}"
  COMPUTED_MESSAGE=$(printf "${COMPUTED_MESSAGE}" | sed -z 's/\n/\\n/g' | sed -r 's/"/\\\"/g' | sed -e 's/\r//g')
  # avoid error if message is too long (total message must be less than 3001 characters)
  COMPUTED_MESSAGE=${COMPUTED_MESSAGE:0:3000}
  echo 'result<<EOF'
  echo -n "${COMPUTED_MESSAGE}"
  echo ''
  echo 'EOF'
else
  echo 'result='
fi
