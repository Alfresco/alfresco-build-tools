#!/bin/bash
set -euo pipefail

# Installs the Bats libs pinned in .github/tests/bats-versions.yml, laid out like
# bats-core/bats-action. Must stay bash 3.2 compatible (macOS); progress goes
# to stderr so `eval "$(...)"` only sees the BATS_LIB_PATH export.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
versions_file="$script_dir/../tests/bats-versions.yml"
dest="$HOME/.local/lib/bats"
libs=(bats-support bats-assert bats-file)

usage() {
  echo "Usage: $0 [--dest DIR] [--versions-file FILE]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) dest="${2:?--dest needs a value}"; shift 2 ;;
    --versions-file) versions_file="${2:?--versions-file needs a value}"; shift 2 ;;
    *) usage; exit 1 ;;
  esac
done

read_version() {
  local key="${1//-/_}" value
  value="$(sed -nE "s/^${key}:[[:space:]]*[\"']?([^\"'[:space:]#]+).*/\\1/p" "$versions_file" | head -n 1)"
  if [[ -z "$value" ]]; then
    echo "No version for $key in $versions_file" >&2
    return 1
  fi
  echo "$value"
}

# Validate every entry first so a bad file fails before anything is touched
for lib in "${libs[@]}"; do
  read_version "$lib" > /dev/null
done

mkdir -p "$dest"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for lib in "${libs[@]}"; do
  version="$(read_version "$lib")"

  if [[ "$(cat "$dest/$lib/.version" 2>/dev/null || true)" == "$version" ]]; then
    echo "$lib $version already installed" >&2
    continue
  fi

  echo "Installing $lib $version" >&2
  mkdir -p "$tmp/$lib"
  curl -fsSL "https://github.com/bats-core/$lib/archive/refs/tags/v$version.tar.gz" \
    | tar -xz -C "$tmp/$lib" --strip-components=1

  rm -rf "${dest:?}/$lib"
  mkdir -p "$dest/$lib/src"
  cp "$tmp/$lib/load.bash" "$dest/$lib/"
  cp "$tmp/$lib"/src/*.bash "$dest/$lib/src/"
  echo "$version" > "$dest/$lib/.version"
done

echo "export BATS_LIB_PATH=\"$dest\""
