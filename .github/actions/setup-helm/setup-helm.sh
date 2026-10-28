#!/bin/bash
set -euo pipefail

BASE_URL=${BASE_URL:-https://get.helm.sh}
INSTALL_DIR=${INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/setup-helm/bin}
VERSION=${VERSION:-}
VERSION_FILE=${VERSION_FILE:-}

fail() {
  echo "::error::$1"
  exit 1
}

if [[ -z "$VERSION" && -z "$VERSION_FILE" ]] || [[ -n "$VERSION" && -n "$VERSION_FILE" ]]; then
  fail "Set either version or version-file"
fi

if [[ -n "$VERSION_FILE" ]]; then
  [[ -f "$VERSION_FILE" ]] || fail "$VERSION_FILE not found"
  # asdf .tool-versions: "<tool> <version> [fallback...]", with # comments
  VERSION=$(awk '{ sub(/#.*/, "") } $1 == "helm" { print $2; exit }' "$VERSION_FILE")
  [[ -n "$VERSION" ]] || fail "No helm version found in $VERSION_FILE"
fi

VERSION=${VERSION#v}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || fail "Invalid helm version: $VERSION"

OS=$(uname | tr '[:upper:]' '[:lower:]')
case $(uname -m) in
  x86_64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *) fail "Unsupported architecture: $(uname -m)" ;;
esac

TARBALL="helm-v${VERSION}-${OS}-${ARCH}.tar.gz"
DOWNLOAD_DIR=$(mktemp -d)
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

echo "Downloading $BASE_URL/$TARBALL ..."
curl -fsSL -o "$DOWNLOAD_DIR/$TARBALL" "$BASE_URL/$TARBALL"
curl -fsSL -o "$DOWNLOAD_DIR/$TARBALL.sha256sum" "$BASE_URL/$TARBALL.sha256sum"

EXPECTED_CHECKSUM=$(awk '{ print $1 }' "$DOWNLOAD_DIR/$TARBALL.sha256sum")
ACTUAL_CHECKSUM=$(shasum -a 256 "$DOWNLOAD_DIR/$TARBALL" | awk '{ print $1 }')
if [[ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]]; then
  fail "Checksum mismatch for $TARBALL: expected $EXPECTED_CHECKSUM, got $ACTUAL_CHECKSUM"
fi

tar -xzf "$DOWNLOAD_DIR/$TARBALL" -C "$DOWNLOAD_DIR" "${OS}-${ARCH}/helm"
mkdir -p "$INSTALL_DIR"
mv "$DOWNLOAD_DIR/${OS}-${ARCH}/helm" "$INSTALL_DIR/helm"

echo "$INSTALL_DIR" >> "$GITHUB_PATH"
echo "version=$VERSION" >> "$GITHUB_OUTPUT"
"$INSTALL_DIR/helm" version
