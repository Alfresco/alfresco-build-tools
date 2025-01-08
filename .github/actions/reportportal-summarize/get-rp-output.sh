#!/bin/bash -e

CONTENT=''
URL=''

# support spaces on launch key
urlEncode() {
  echo $1 | python -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read()))" | sed -E 's/(.*).../\1/' | tr -d '\n'
}

if [[ -n "$RP_LAUNCH_KEY" && -n "$RP_TOKEN" && -n "$RP_URL" && -n "$RP_PROJECT" ]]
then
  echo "enabled=true" >> $GITHUB_OUTPUT

  CONTENT=$(curl -s -G -X GET "$RP_URL/api/v1/$RP_PROJECT/launch" \
    -d "filter.cnt.name=$(urlEncode "$RP_LAUNCH_KEY")" \
    -d "filter.has.compositeAttribute=ghrun:$GITHUB_RUN_ID" \
    -d "page.sort=startTime,number,DESC" \
    -H "Authorization: bearer $RP_TOKEN" \
    ) || CONTENT=''

  URL="$RP_URL/ui/#$RP_PROJECT/launches/all"
else
  echo "Report Portal not enabled: configuration not available"

  echo "enabled=false" >> $GITHUB_OUTPUT
fi

echo "content=$CONTENT" >> $GITHUB_OUTPUT
echo "url=$URL" >> $GITHUB_OUTPUT
