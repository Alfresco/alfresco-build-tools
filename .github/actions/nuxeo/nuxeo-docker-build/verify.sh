#!/usr/bin/env bash
set -euo pipefail

IMAGE_URL=${IMAGE_URL:-}
EXPECTED_MODULES=${EXPECTED_MODULES:-}
EXPECTED_PACKAGES=${EXPECTED_PACKAGES:-}

if [[ -z "$IMAGE_URL" ]]; then
  echo "Image URL not provided" >&2
  exit 2
fi

echo "Verifying image: $IMAGE_URL"

echo "Running nuxeoctl mp-list..."
MP_LIST_OUTPUT=$(docker run --rm "$IMAGE_URL" bash -lc 'nuxeoctl mp-list')
echo "--- nuxeoctl mp-list output ---"
echo "$MP_LIST_OUTPUT"
echo "--------------------------------"

missing=0
for mod in $EXPECTED_MODULES; do
  [[ -z "$mod" ]] && continue
  if echo "$MP_LIST_OUTPUT" | grep -q "${mod}"; then
    echo "✅ Nuxeo module '$mod' found"
  else
    echo "❌ Nuxeo module '$mod' NOT found"
    missing=1
  fi
done

echo "Listing installed OS packages via rpm -qa..."
INSTALLED_PACKAGES_OUTPUT=$(docker run --rm "$IMAGE_URL" bash -lc 'rpm -qa')
echo "--- Installed OS packages ---"
echo "$INSTALLED_PACKAGES_OUTPUT" | head -n 200 || true
echo "--------------------------------"

# Read EXPECTED_PACKAGES items safely (space-separated sanitized)
for pkg in $EXPECTED_PACKAGES; do
  [[ -z "$pkg" ]] && continue
  if echo "$INSTALLED_PACKAGES_OUTPUT" | grep -q "^${pkg}"; then
    echo "✅ OS package '$pkg' found"
  else
    echo "❌ OS package '$pkg' NOT found"
    missing=1
  fi
done

exit $missing
