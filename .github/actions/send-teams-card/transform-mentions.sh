#!/bin/bash -e

# Entries may be separated by commas or newlines, and blank ones are ignored, so a
# trailing separator or a YAML block list works as written.
split_items() {
  local ITEMS="${1//$'\n'/,}" ITEM
  IFS=',' read -ra ARRAY <<< "$ITEMS"
  for ITEM in "${ARRAY[@]}"; do
    ITEM="${ITEM#"${ITEM%%[![:space:]]*}"}"
    ITEM="${ITEM%"${ITEM##*[![:space:]]}"}"
    [ -n "$ITEM" ] && printf '%s\n' "$ITEM"
  done
  return 0
}

# Checked up front, in the main shell, so a bad entry stops the step rather than a subshell.
check_format() {
  local ITEM
  while IFS= read -r ITEM; do
    if [[ ! "$ITEM" =~ \| ]]; then
      echo "Error: Input '$ITEM' does not contain the expected format with a '|' separator" >&2
      exit 1
    fi
  done < <(split_items "$1")
}

# jq builds each entity so a quote or backslash in a display name cannot break the JSON.
add_entity() {
  local TYPE=$1 ITEM NAME ID
  while IFS= read -r ITEM; do
    NAME="${ITEM%%|*}"
    ID="${ITEM#*|}"
    NAME="${NAME%"${NAME##*[![:space:]]}"}"
    ID="${ID#"${ID%%[![:space:]]*}"}"
    jq -n -c --arg name "$NAME" --arg id "$ID" --arg type "$TYPE" \
      '{type: "mention", text: "<at>\($name)</at>",
        mentioned: ({id: $id, name: $name} + (if $type == "tag" then {type: "tag"} else {} end))}'
  done < <(split_items "$2")
}

check_format "$USERS"
check_format "$TAGS"

ENTITIES="$( { add_entity "user" "$USERS"; add_entity "tag" "$TAGS"; } | jq -s -c .)"
echo "result=${ENTITIES}"
