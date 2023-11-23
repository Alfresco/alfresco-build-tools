#!/bin/bash -e

CONTENT=''
URL=''

if [[ -n "$RP_LAUNCH_KEY" && -n "$RP_TOKEN" && -n "$RP_URL" && -n "$RP_PROJECT" ]]
then
  echo "enabled=true" >> $GITHUB_OUTPUT

  SEARCH_URL="$RP_URL/api/v1/$RP_PROJECT/launch?filter.cnt.name=$RP_LAUNCH_KEY&filter.has.compositeAttribute=ghrun:$GITHUB_RUN_ID&page.sort=startTime%2Cnumber%2CDESC"
  CONTENT=$(curl -s -X GET "$SEARCH_URL" -H  "accept: */*" -H  "Authorization: bearer $RP_TOKEN") || CONTENT=''

  URL="$RP_URL/ui/#$RP_PROJECT/launches/all"
else
  echo "Report Portal not enabled: configuration not available"

  echo "enabled=false" >> $GITHUB_OUTPUT
fi

echo "content=$CONTENT" >> $GITHUB_OUTPUT
echo "url=$URL" >> $GITHUB_OUTPUT
