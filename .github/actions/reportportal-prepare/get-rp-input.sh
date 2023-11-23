#!/bin/bash -e

if [[ -n "$RP_LAUNCH_PREFIX" && -n "$RP_TOKEN" && -n "$RP_URL" && -n "$RP_PROJECT" ]]; then
  echo "enabled=true" >> $GITHUB_OUTPUT

  RP_LAUNCH_KEY="$RP_LAUNCH_PREFIX"
  if [[ "$AUTO" == "true" && "$USE_STATIC_LAUNCH_NAME" == "false" ]]; then
    RP_LAUNCH_KEY="$RP_LAUNCH_PREFIX-$GITHUB_EVENT_NAME-$GITHUB_RUN_ID"
  fi
  echo "key=$RP_LAUNCH_KEY" >> $GITHUB_OUTPUT

  URL="$RP_URL/ui/#$RP_PROJECT/launches/all"
  echo "url=$URL" >> $GITHUB_OUTPUT

  echo "Report Portal key=$RP_LAUNCH_KEY, url=$URL"

  RUN_TITLE="Run on GitHub Actions $GITHUB_RUN_ID"
  RUN_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"

  OPTS='"'-Drp.launch="$RP_LAUNCH_KEY"'"'
  OPTS+=' "'-Drp.uuid="$RP_TOKEN"'"'
  OPTS+=' "'-Drp.endpoint="$RP_URL"'"'
  OPTS+=' "'-Drp.project="$RP_PROJECT"'"'
  if [[ "$AUTO" == "true" ]]; then
    OPTS+=' "'-Drp.description=["$RUN_TITLE"]\("$RUN_URL"\)'"'
    OPTS+=' "'-Drp.attributes='branch:'"$BRANCH_NAME"';event:'"$GITHUB_EVENT_NAME"';repository:'"$GITHUB_REPOSITORY"';run:'"$RP_LAUNCH_KEY$RP_EXTRA_ATTRIBUTES"'"'
  fi

  echo "mvn-opts=$OPTS" >> $GITHUB_OUTPUT
else
  echo "Report Portal not enabled: configuration not available"

  echo "enabled=false" >> $GITHUB_OUTPUT
  echo "key=" >> $GITHUB_OUTPUT
  echo "url=" >> $GITHUB_OUTPUT
  echo "mvnopts=" >> $GITHUB_OUTPUT
fi
