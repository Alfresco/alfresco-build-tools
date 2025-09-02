#!/bin/bash

# TODO: Take a path input instead of current folder
# TODO: Exclude HylandSoftware repos and other first party actions?
# TODO: add discovery mode (no API calls, no changes)
# TODO: add dry run mode (does API calls, no file changes)
# TODO: check appropriate way to handle token
# TODO: make a map of matches to only make single API call per action@version
# TODO: allow no / empty token but warn
# TODO: return error count

[[ "$1" == "--force" ]] && force=true

if [ "$GITHUB_TOKEN" == "" ]; then
  echo "GITHUB_TOKEN value was not set, aborting."
  exit 1
fi

yaml_files=$(find .github/workflows .github/actions -type f -name "*.yml" -o -name "*.yaml")

find_owner_repo () {
  s="$1"
  i=$(expr index $s /)
  if [ $i -eq 0 ]; then
    echo $s;
  else
    s2="${s:$i}"
    j=$(expr index $s2 /)
    if [ $j -eq 0 ]; then
      echo $s;
    else
      n=$i+$j-1
      echo ${s:0:$n};
    fi
  fi
}

for file in $yaml_files; do
  echo -e "\nProcessing file: $file"

  covered=()
  references=$(grep -E "uses: ([^@]+)@([^\s]+)" "$file")
  while read -r reference; do
    if [[ -z "$reference" ]]; then continue; fi

    action_ref=$(echo "$reference" | grep -oP "uses: \K[^@]+")

    owner_repo=$(find_owner_repo "$action_ref")
    version=$(echo "$reference" | grep -oP "@\K[^\s]+")
    comment_version=$(echo "$reference" | grep -oP "#\s\K[^\s]+")

    source="uses: $action_ref@$version"
    [[ ! -z "$comment_version" ]] && source="uses: $action_ref@$version # $comment_version"

    if [[ ${covered[@]} =~ $source ]]; then
      echo "skipping $source, already covered."
      continue
    fi
    covered+=($source)

    ref=$version
    [[ ${#version} -eq 40 ]] && ref=$comment_version

    semver_ok="false"
    semver_check=$(grep -o '\.' <<< "$ref" | grep -c .)
    if (( $semver_check >= 2 )); then
      semver_ok="true"
    fi

    if [[ (${#version} -eq 40 && $force != true) && "${semver_ok}" == "true" ]]; then
      echo "$owner_repo@$version # $comment_version found already using SHA and semver, skipping."
      continue
    fi

    sha="$version"
    if [[ ${#version} -ne 40 || $force == true ]]; then
      response=$(curl -s -w "\n%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$owner_repo/git/refs/tags/$ref")
      content=$(echo "$response" | head -n -1)
      status_code=$(echo "$response" | tail -n 1)

      if [ "$status_code" -eq 429 ]; then
        echo -e "\033[31mError: Rate limit exceeded, aborting.\033[0m"
        echo "API response: $content"
        exit $status_code
      fi

      if [ "$status_code" -eq 404 ]; then
        echo -e "\033[31mError: version not found $action_ref@$ref, skipping.\033[0m"
        continue
      fi

      if [ "$status_code" -ge 400 ]; then
        echo -e "\033[31mError: API request failed for $reference with status code: $status_code, skipping.\033[0m"
        echo "API Response: $content"
        continue
      fi

      type=$(echo "$content" | jq -r 'if type=="array" then .[0].object.type else .object.type end')
      if [ $type == "tag" ]; then
        url=$(echo "$content" | jq -r 'if type=="array" then .[0].object.url else .object.url end')
        content=$(curl -s -L -H "Authorization: token $GITHUB_TOKEN" "$url")
      fi

      sha=$(echo "$content" | jq -r 'if type=="array" then .[0].object.sha else .object.sha end')

      if [ ${#sha} -ne 40 ]; then
        echo -e "\033[31mError: Unexpected SHA value $sha, from $content, skipping.\033[0m"
        continue
      fi
    fi

    final_version="$ref"
    if [ "${semver_ok}" != "true" ]; then
      if (( $semver_check == 0 )); then
        pattern="$ref.[0-9]{1,2}.[0-9]{1,2}"
      fi
      if (( $semver_check == 1 )); then
        pattern="$ref.[0-9]{1,2}"
      fi
      if [ -z "$ref" ]; then
        pattern=".*[0-9]{1,2}.[0-9]{1,2}.[0-9]{1,2}"
      fi

      response=$(curl -s -L -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$owner_repo/tags")
      found_version=$(echo $response | jq -r --arg SHA "$sha" '.[] | select(.commit.sha == $SHA) | .name' |grep -Eo "$pattern"|sort -r|head -n1)

      if [ -z "$found_version" ]; then
        # take first matching version for comment
        found_version="$(echo $response | jq -r --arg SHA "$sha" '.[] | select(.commit.sha == $SHA) | .name' |sort -r|head -n1)"
      fi

      if [ ! -z "$found_version" ]; then
        final_version="$found_version"
      else
        if [ -z "$ref" ]; then
          echo -e "\033[33mWarning: no semver version found for $action_ref@$version: keeping empty comment.\033[0m"
        else
          echo -e "\033[33mWarning: no semver version found for $action_ref@$version: keeping $ref for comment.\033[0m"
        fi
        [[ ${#version} -eq 40 ]] && continue
      fi

    fi

    target="uses: $action_ref@$sha # $final_version"
    echo -e "\033[32mUpdating '$source' with '$target'\033[0m"
    sed -i "s|$source|$target|" "$file"

  done <<< "$references"
done
