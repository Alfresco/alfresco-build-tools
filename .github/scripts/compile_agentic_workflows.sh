#!/bin/bash
set -e

# Pre-commit hook to ensure agentic workflow .lock.yml files are in sync
# Compiles .md files and compares frontmatter hash to detect drift

# Get list of .md files in .github/workflows/
md_files=$(find .github/workflows -name "*.md" -type f 2>/dev/null || true)

if [ -z "$md_files" ]; then
    exit 0
fi

# Filter to only agentic workflows
aw_files=""
for md_file in $md_files; do
    if head -n 20 "$md_file" | grep -q "^on:$\|^engine:$"; then
        aw_files="$aw_files $md_file"
    fi
done

if [ -z "$aw_files" ]; then
    exit 0
fi

echo "Validating agentic workflow compilation..."

# Check if gh aw extension is installed
if ! gh extension list 2>/dev/null | grep -q "gh-aw"; then
    echo "✗ Error: gh aw extension is not installed"
    echo "  Install it with: gh extension install github/gh-aw"
    exit 1
fi

needs_recompile=false
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

for md_file in $aw_files; do
    lock_file="${md_file%.md}.lock.yml"

    echo "  Checking $(basename "$md_file")..."

    # Check if lock file exists
    if [ ! -f "$lock_file" ]; then
        echo "    ✗ Missing lock file"
        needs_recompile=true
        continue
    fi

    # Compile in temp directory
    temp_md="$temp_dir/$(basename "$md_file")"
    cp "$md_file" "$temp_md"

    if ! (cd "$temp_dir" && gh aw compile "$(basename "$md_file")" >/dev/null 2>&1); then
        echo "    ✗ Compilation failed"
        needs_recompile=true
        continue
    fi

    # Extract frontmatter hash from both lock files
    current_hash=$(grep "^# gh-aw-metadata:" "$lock_file" | sed 's/.*"frontmatter_hash":"\([^"]*\)".*/\1/' || echo "none")
    new_hash=$(grep "^# gh-aw-metadata:" "$temp_dir/$(basename "$lock_file")" | sed 's/.*"frontmatter_hash":"\([^"]*\)".*/\1/' || echo "none")

    if [ "$current_hash" != "$new_hash" ]; then
        echo "    ✗ Lock file out of sync (frontmatter changed)"
        needs_recompile=true
    else
        echo "    ✓ In sync"
    fi
done

if [ "$needs_recompile" = true ]; then
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Agentic workflow needs recompilation"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "Run: gh extension upgrade aw && gh aw compile .github/workflows/<workflow-name>.md"
    echo ""
    echo "Then stage: git add .github/workflows/*.lock.yml .github/aw/"
    echo ""
    exit 1
fi

echo "✓ All agentic workflows in sync"
exit 0
