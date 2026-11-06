#!/bin/bash -e

ENTITIES=()

function add_entity() {
  local TYPE=$1
  local ITEMS=$2
  if [ -n "$ITEMS" ]; then
    IFS=',' read -ra ARRAY <<< "$ITEMS"
    for ITEM in "${ARRAY[@]}"; do
      if [[ ! "$ITEM" =~ \| ]]; then
        echo "Error: Input '$ITEM' does not contain the expected format with a '|' separator" >&2
        exit 1
      fi
      NAME="${ITEM%|*}"
      ID="${ITEM#*|}"

      # Built with jq because a display name is free text and a quote in it would break the payload.
      ENTITIES+=("$(jq -n -c --arg name "$NAME" --arg id "$ID" --arg type "$TYPE" \
        '{type: "mention", text: "<at>\($name)</at>",
          mentioned: ({id: $id, name: $name} + (if $type == "tag" then {type: "tag"} else {} end))}')")
    done
  fi
}

add_entity "user" "$USERS"
add_entity "tag" "$TAGS"

echo "result=$(printf '%s\n' "${ENTITIES[@]}" | jq -s -c '.')"
