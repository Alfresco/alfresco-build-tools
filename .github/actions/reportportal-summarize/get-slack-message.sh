#!/bin/bash -e

if [[ -n "$RP_LAUNCH_KEY" ]]; then

  NB=$(echo "$RP_CONTENT" | jq -r '.page.totalElements // "0"')
  if [[ "$NB" == "0" || -z "$NB" ]]; then
    MSG+="No report found for key "'`'$RP_LAUNCH_KEY'`'"."
    MSG+="\nSee <$RP_LAUNCH_URL|latest reports>."
  elif [ "$NB" == "1" ]; then
    RP_LAUNCH_ID=$(echo "$RP_CONTENT" | jq -r '.content[0].id // empty')
    MSG+="See <$RP_LAUNCH_URL/$RP_LAUNCH_ID|report>"
  else
    MSG+="$NB reports found for key "'`'$RP_LAUNCH_KEY'`'"."
    while read -r id ; do
      read -r number
      read -r status
      case $status in
        PASSED)
        sstatus="✅" ;;
        FAILED)
        sstatus="❌"
        ;;
        *)
        sstatus="$status"
        ;;
      esac
      MSG+="\n<$RP_LAUNCH_URL/$id|Report #$number> $sstatus"
    done < <(echo "$RP_CONTENT" | jq -r '.content[] | .id, .number, .status')
  fi
fi

echo "message=$MSG" >> $GITHUB_OUTPUT
