#!/bin/bash -e

# Checked up front, in the main shell, so a bad entry stops the step rather than a subshell.
check_format() {
  local ITEMS=$1 ITEM
  [ -n "$ITEMS" ] || return 0
  IFS=',' read -ra ARRAY <<< "$ITEMS"
  for ITEM in "${ARRAY[@]}"; do
    if [[ ! "$ITEM" =~ \| ]]; then
      echo "Error: Input '$ITEM' does not contain the expected format with a '|' separator" >&2
      exit 1
    fi
  done
}

# jq builds each entity so a quote or backslash in a display name cannot break the JSON.
add_entity() {
  local TYPE=$1 ITEMS=$2 ITEM NAME ID
  [ -n "$ITEMS" ] || return 0
  IFS=',' read -ra ARRAY <<< "$ITEMS"
  for ITEM in "${ARRAY[@]}"; do
    NAME="${ITEM%|*}"
    ID="${ITEM#*|}"
    jq -n -c --arg name "$NAME" --arg id "$ID" --arg type "$TYPE" \
      '{type: "mention", text: "<at>\($name)</at>",
        mentioned: ({id: $id, name: $name} + (if $type == "tag" then {type: "tag"} else {} end))}'
  done
}

check_format "$USERS"
check_format "$TAGS"

ENTITIES="$( { add_entity "user" "$USERS"; add_entity "tag" "$TAGS"; } | jq -s -c .)"
echo "result=${ENTITIES}"
