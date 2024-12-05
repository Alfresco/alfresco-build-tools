#!/bin/bash -e

if [[ -n "$RP_LAUNCH_KEY" ]]; then

  NB=$(echo "$RP_CONTENT" | jq -r '.page.totalElements // "0"')
  if [[ "$NB" == "0" || -z "$NB" ]]; then
    MSG+="No report found for key "'`'"$RP_LAUNCH_KEY"'`'"."
    MSG+="\n\nSee [latest reports]($RP_LAUNCH_URL)."
  elif [ "$NB" == "1" ]; then
    RP_LAUNCH_ID=$(echo "$RP_CONTENT" | jq -r '.content[0].id // empty')
    STATUS=$(echo "$RP_CONTENT" | jq -r '.content[0].status // empty')
    [[ "$STATUS" == 'PASSED' ]] && ICON="✅" || ICON="❌"
    MSG+="See [report]($RP_LAUNCH_URL/$RP_LAUNCH_ID) $ICON"
  else
    MSG+="$NB reports found for key "'`'"$RP_LAUNCH_KEY"'`'"."
    while read -r id ; do
      read -r number
      read -r status
      case $status in
        PASSED)
        status_icon="✅" ;;
        FAILED)
        status_icon="❌"
        ;;
        *)
        status_icon="$status"
        ;;
      esac
      MSG+="\n\n[Report #$number]($RP_LAUNCH_URL/$id) $status_icon"
    done < <(echo "$RP_CONTENT" | jq -r '.content[] | .id, .number, .status')
  fi
fi

echo "message=$MSG" >> $GITHUB_OUTPUT
