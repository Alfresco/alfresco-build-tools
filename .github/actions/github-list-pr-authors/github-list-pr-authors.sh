#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set (this script must run in a GitHub Actions step)}"
: "${REPOSITORY:?repository is required}"
: "${FROM_REF:?from-ref is required}"
: "${TO_REF:?to-ref is required}"

MENTION_EMAIL_DOMAIN="${MENTION_EMAIL_DOMAIN:-}"

# Will retry on gh API 5xx errors
api() {
  local stderr out attempt=1
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
    cat "$stderr" >&2
    rm -f "$stderr"
    return 1
  done
}

TRUNCATED=false

COMPARE=$(api "repos/$REPOSITORY/compare/${FROM_REF}...${TO_REF}") || {
  echo "::warning::Could not compare ${FROM_REF}...${TO_REF} in $REPOSITORY"
  TRUNCATED=true
  COMPARE='{"commits":[]}'
}

# The compare endpoint stops at 250 commits, and a partial list must not read as the whole story.
if [ "$(jq -r '(.total_commits // 0) > (.commits | length)' <<<"$COMPARE")" = "true" ]; then
  echo "::warning::${FROM_REF}...${TO_REF} in $REPOSITORY is longer than one page of the compare API, so this list is partial"
  TRUNCATED=true
fi

# A pull request carries no email, so the address to mention comes from a commit in
# range that the same account authored.
IDENTITIES=$(jq -c '[ .commits[]
  | select((.author.login // "") != "")
  | { key: .author.login,
      value: { name: .commit.author.name, email: (.commit.author.email // "") } } ]
  | from_entries' <<<"$COMPARE")

CHANGES="[]"

# GitHub knows which pull request a commit came from. A commit with no pull request behind it is a direct push.
for sha in $(jq -r '.commits[].sha' <<<"$COMPARE"); do
  pulls=$(api "repos/$REPOSITORY/commits/$sha/pulls") || {
    echo "::warning::Could not look up the pull request behind ${sha:0:9} in $REPOSITORY"
    TRUNCATED=true
    continue
  }
  # An open pull request can also contain the commit, so a merged one wins.
  row=$(jq -c --arg repo "$REPOSITORY" --arg sha "$sha" --argjson who "$IDENTITIES" '
    ( ( [ .[] | select(.merged_at != null) ] + . )[0] // empty )
    | (.user.login // "") as $login
    | { repo: $repo,
        pr: .number,
        sha: $sha[0:9],
        login: $login,
        name: ($who[$login].name // $login),
        email: ($who[$login].email // ""),
        kind: (if $login | endswith("[bot]") then "bot" else "user" end),
        title: .title,
        url: .html_url }' <<<"$pulls")
  [ -n "$row" ] || continue
  CHANGES=$(jq -c --argjson row "$row" '. + [$row]' <<<"$CHANGES")
done

# Every commit of a merged pull request points back at the same one.
CHANGES=$(jq -c 'unique_by(.pr)' <<<"$CHANGES")

# Somebody merged the bot's pull request, and that person is the one who can act on it.
for pr in $(jq -r '.[] | select(.kind == "bot") | .pr' <<<"$CHANGES"); do
  merger=$(api "repos/$REPOSITORY/pulls/$pr" --jq '.merged_by.login // ""') || merger=""
  [ -n "$merger" ] || continue
  CHANGES=$(jq -c --argjson p "$pr" --arg m "$merger" \
    'map(if .pr == $p then . + {merged_by: $m} else . end)' <<<"$CHANGES")
done

emit() { printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; }
emit_block() {
  local delim="EOF_${RANDOM}${RANDOM}"
  { echo "$1<<${delim}"; printf '%s\n' "$2"; echo "$delim"; } >> "$GITHUB_OUTPUT"
}

# Only a company address resolves to a Teams account, so anyone else keeps their GitHub
# handle, which is more useful to a reader than an unlinked display name.
MENTIONABLE=$(jq -r --arg d "$MENTION_EMAIL_DOMAIN" '
  if $d == "" then empty else
    map(select(.kind == "user" and .email != ""
               and (.email | ascii_downcase | endswith("@" + ($d | ascii_downcase)))))
    | unique_by(.email | ascii_downcase) | map("\(.name)|\(.email)") | join(",")
  end' <<<"$CHANGES")

PLAIN=$(jq -r --arg d "$MENTION_EMAIL_DOMAIN" '
  ( map(select(.kind == "user")
        | select($d == "" or .email == ""
                 or ((.email | ascii_downcase | endswith("@" + ($d | ascii_downcase))) | not))
        | "@" + .login)
    + map(.merged_by // empty | select(. != "") | "@" + .) )
  | map(select(. != "@")) | unique | join(",")' <<<"$CHANGES")

emit people "$(jq -r '(map(select(.kind == "user") | .login) + map(.merged_by // empty))
  | map(select(. != "")) | unique | join(",")' <<<"$CHANGES")"
emit bots "$(jq -r 'map(select(.kind == "bot") | .login) | unique | join(",")' <<<"$CHANGES")"
# One list, each person in whichever form can reach them.
emit cc "$(printf '%s,%s' "$MENTIONABLE" "$PLAIN" | sed 's/^,//; s/,$//')"
emit truncated "$TRUNCATED"
emit count "$(jq 'length' <<<"$CHANGES")"
emit_block changes "$(jq -c '.' <<<"$CHANGES")"

echo "Found $(jq 'length' <<<"$CHANGES") pull request(s) in $REPOSITORY."
