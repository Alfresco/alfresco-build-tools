#!/bin/bash -e

ENTITIES="["
FIRST=true

function add_entity() {
  local TYPE=$1
  local ITEMS=$2
  if [ -n "$ITEMS" ]; then
    IFS=',' read -ra ARRAY <<< "$ITEMS"
    for ITEM in "${ARRAY[@]}"; do
      if [ "$FIRST" = false ]; then
        ENTITIES+=","
      fi
      FIRST=false

      if [[ ! "$ITEM" =~ \| ]]; then
        echo "Error: Input '$ITEM' does not contain the expected format with a '|' separator" >&2
        exit 1
      fi
      NAME="${ITEM%|*}"
      ID="${ITEM#*|}"

      case $TYPE in
        user)
          ENTITIES+="{\"type\":\"mention\",\"text\":\"<at>${NAME}</at>\",\"mentioned\":{\"id\":\"${ID}\",\"name\":\"${NAME}\"}}"
          ;;
        tag)
          ENTITIES+="{\"type\":\"mention\",\"text\":\"<at>${NAME}</at>\",\"mentioned\":{\"id\":\"${ID}\",\"name\":\"${NAME}\",\"type\":\"tag\"}}"
          ;;
      esac
    done
  fi
}

add_entity "user" "$USERS"
add_entity "tag" "$TAGS"

ENTITIES+="]"
echo "result=${ENTITIES}"
