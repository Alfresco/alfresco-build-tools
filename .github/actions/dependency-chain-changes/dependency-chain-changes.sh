#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set (this script must run in a GitHub Actions step)}"
: "${REPOSITORY:?repository is required}"
: "${FROM_REF:?from-ref is required}"
: "${TO_REF:?to-ref is required}"

MAX_DEPTH="${MAX_DEPTH:-4}"
MENTION_DOMAIN="${MENTION_DOMAIN:-}"
UPSTREAM="${UPSTREAM:-}"
PR_ONLY="${PULL_REQUESTS_ONLY:-true}"
case "$PR_ONLY" in
  true|false) ;;
  *) echo "::error::pull-requests-only must be true or false, found '$PR_ONLY'"; exit 1 ;;
esac

require_positive() {
  [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] && return 0
  echo "::error::$1 must be a positive whole number, found '$2'"
  exit 1
}
require_positive max-depth "$MAX_DEPTH"

# Returns 2 on an HTTP 404 so callers can tell "it is not there" from "the API call failed",
# which otherwise both look like an empty answer. A transient 5xx is not an answer either,
# so give the API a few tries before believing it.
api() {
  local stderr status out attempt=1
  stderr=$(mktemp)
  while :; do
    if out=$(gh api "$@" 2>"$stderr"); then
      rm -f "$stderr"
      printf '%s' "$out"
      return 0
    fi
    if [ "$attempt" -lt "${API_MAX_ATTEMPTS:-3}" ] && grep -qE 'HTTP 5[0-9][0-9]|Server Error' "$stderr"; then
      sleep $(( attempt * ${API_RETRY_DELAY:-2} ))
      attempt=$(( attempt + 1 ))
      continue
    fi
    status=1
    if grep -q 'HTTP 404' "$stderr"; then
      status=2
    fi
    cat "$stderr" >&2
    rm -f "$stderr"
    return "$status"
  done
}

CHANGES="[]"
VISITED=""
TRUNCATED=false

# Picks the version out of a file at one ref. The caller owns the regex, so a pom property,
# a package.json field and a gradle property all work without this knowing the format.
read_version() {
  local repo="$1" ref="$2" file="$3" regex="$4" content
  content=$(api "repos/$repo/contents/${file}?ref=${ref}" --jq '.content') || return 1
  printf '%s' "$content" | base64 --decode \
    | jq -Rrs --arg rx "$regex" '[ match($rx) | .captures[0].string ] | first // ""'
}

# The subject is the only place GitHub records a pull request number, and by default a commit
# without one is the pipeline talking to itself rather than somebody's work.
collect() {
  local repo="$1" from="$2" to="$3" cmp
  cmp=$(api "repos/$repo/compare/${from}...${to}") || {
    echo "::warning::Could not compare ${from}...${to} in $repo, skipping it"
    return 0
  }
  # The compare endpoint stops at 250 commits, and a partial list must not read as the whole story.
  if [ "$(jq -r '(.total_commits // 0) > (.commits | length)' <<<"$cmp")" = "true" ]; then
    echo "::warning::${from}...${to} in $repo is longer than one page of the compare API, so this list is partial"
    TRUNCATED=true
  fi
  local rows
  rows=$(printf '%s' "$cmp" | jq -c --arg repo "$repo" --argjson pr_only "$PR_ONLY" '
    [ .commits[]
      | (.commit.message | split("\n")[0]) as $subject
      | ( if ($subject | test("\\(#[0-9]+\\)$"))
          then ($subject | capture("\\(#(?<pr>[0-9]+)\\)$"))
          elif ($subject | test("^Merge pull request #[0-9]+"))
          then ($subject | capture("^Merge pull request #(?<pr>[0-9]+)"))
          else null end ) as $m
      | select($pr_only == false or $m != null)
      | { repo: $repo,
          sha: .sha[0:9],
          login: (.author.login // ""),
          name: .commit.author.name,
          email: (.commit.author.email // ""),
          kind: (if (.author.login // "") | endswith("[bot]") then "bot" else "user" end),
          pr: (if $m == null then null else ($m.pr | tonumber) end),
          title: ($subject | sub(" \\(#[0-9]+\\)$"; "")),
          url: .html_url } ]')
  CHANGES=$(jq -c --argjson new "$rows" '. + $new' <<<"$CHANGES")
}

walk() {
  local repo="$1" from="$2" to="$3" depth="$4"
  if [ "$depth" -gt "$MAX_DEPTH" ]; then TRUNCATED=true; return 0; fi
  local key="${repo}@${from}..${to}"
  case " $VISITED " in *" $key "*) return 0 ;; esac
  VISITED="$VISITED $key"

  collect "$repo" "$from" "$to"

  # Only an upstream whose pinned version actually moved contributed anything to this range.
  local line consumer up file regex template v_from v_to
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    IFS='|' read -r consumer up file regex template <<<"$line"
    consumer="$(trim "$consumer")"; up="$(trim "$up")"; file="$(trim "$file")"
    regex="$(trim "$regex")"; template="$(trim "$template")"
    [ "$consumer" = "$repo" ] || continue
    # An unreadable version is not the same as one that did not move, so say the walk fell short.
    if ! v_from=$(read_version "$repo" "$from" "$file" "$regex") \
      || ! v_to=$(read_version "$repo" "$to" "$file" "$regex") \
      || [ -z "$v_from" ] || [ -z "$v_to" ]; then
      echo "::warning::Could not read the $up version from $file in $repo, so its changes are missing"
      TRUNCATED=true
      continue
    fi
    [ "$v_from" != "$v_to" ] || continue
    walk "$up" "${template//\{version\}/$v_from}" "${template//\{version\}/$v_to}" "$((depth + 1))"
  done <<<"$EDGES"
}

# trims leading and trailing whitespace from a string
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

EDGES=$(printf '%s\n' "$UPSTREAM" | sed 's/^[[:space:]]*#.*//' | grep -v '^[[:space:]]*$' || true)

walk "$REPOSITORY" "$FROM_REF" "$TO_REF" 1

# Somebody merged the bot's pull request, and that person is the one who can act on it.
for pr in $(jq -r '.[] | select(.kind == "bot" and .pr != null) | "\(.repo)#\(.pr)"' <<<"$CHANGES" | sort -u); do
  merger=$(api "repos/${pr%%#*}/pulls/${pr##*#}" --jq '.merged_by.login // ""') || merger=""
  [ -n "$merger" ] || continue
  CHANGES=$(jq -c --arg k "$pr" --arg m "$merger" \
    'map(if "\(.repo)#\(.pr)" == $k then . + {merged_by: $m} else . end)' <<<"$CHANGES")
done

emit() { printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; }
emit_block() {
  local delim="EOF_${RANDOM}${RANDOM}"
  { echo "$1<<${delim}"; printf '%s\n' "$2"; echo "$delim"; } >> "$GITHUB_OUTPUT"
}

# Only a company address resolves to a Teams account, so anyone else keeps their GitHub handle,
# which is more useful to a reader than an unlinked display name.
MENTIONABLE=$(jq -r --arg d "$MENTION_DOMAIN" '
  if $d == "" then empty else
    map(select(.kind == "user" and (.email | ascii_downcase | endswith("@" + ($d | ascii_downcase)))))
    | unique_by(.email | ascii_downcase) | map("\(.name)|\(.email)") | join(",")
  end' <<<"$CHANGES")

# GitHub matches a commit to an account by its email, so an address registered nowhere
# leaves no handle at all. The name is then all we have, and it beats dropping the person.
PLAIN=$(jq -r --arg d "$MENTION_DOMAIN" '
  ( map(select(.kind == "user")
        | select($d == "" or ((.email | ascii_downcase | endswith("@" + ($d | ascii_downcase))) | not))
        | (if .login == "" then .name else "@" + .login end))
    + map(.merged_by // empty | select(. != "") | "@" + .) )
  | map(select(. != "")) | unique | join(",")' <<<"$CHANGES")

emit people "$(jq -r '(map(select(.kind == "user") | .login) + map(.merged_by // empty))
  | map(select(. != "")) | unique | join(",")' <<<"$CHANGES")"
emit bots "$(jq -r 'map(select(.kind == "bot") | .login) | unique | join(",")' <<<"$CHANGES")"
# One list, each person in whichever form can reach them.
emit cc "$(printf '%s,%s' "$MENTIONABLE" "$PLAIN" | sed 's/^,//; s/,$//')"
emit truncated "$TRUNCATED"
emit count "$(jq 'length' <<<"$CHANGES")"
emit_block changes "$(jq -c '.' <<<"$CHANGES")"

echo "Found $(jq 'length' <<<"$CHANGES") change(s) across $(jq -r '[.[].repo] | unique | length' <<<"$CHANGES") repo(s)."
