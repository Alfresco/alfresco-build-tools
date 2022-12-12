#!/bin/bash -e

[[ "$OUTCOME" == 'success' ]] && ICON="✅" || ICON="❌"

echo "#### 📋 Results: $ICON" >> $GITHUB_STEP_SUMMARY

if [[ -n "$RP_LAUNCH_KEY" ]]; then
  NB=$(echo "$RP_CONTENT" | jq -r '.page.totalElements // "0"')
  if [[ "$NB" == "0" || -z "$NB" ]]; then
    echo "- No report found for key "'`'"$RP_LAUNCH_KEY"'`' >> $GITHUB_STEP_SUMMARY
    echo "- See [latest reports]($RP_LAUNCH_URL)" >> $GITHUB_STEP_SUMMARY
  elif [ "$NB" == "1" ]; then
    RP_LAUNCH_ID=$(echo "$RP_CONTENT" | jq -r '.content[0].id // empty')
    echo "See [report]($RP_LAUNCH_URL/$RP_LAUNCH_ID)" >> $GITHUB_STEP_SUMMARY
  else
    echo "$NB reports found for key "'`'"$RP_LAUNCH_KEY"'`' >> $GITHUB_STEP_SUMMARY
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
      echo "- [Report #$number]($RP_LAUNCH_URL/$id) $sstatus" >> $GITHUB_STEP_SUMMARY
    done < <(echo "$RP_CONTENT" | jq -r '.content[] | .id, .number, .status')
  fi
fi
