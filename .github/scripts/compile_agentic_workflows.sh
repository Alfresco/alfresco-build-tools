#!/bin/bash
set -e

# Pre-commit hook to auto-compile GitHub Agentic Workflow .md files
# This hook ensures that .lock.yml files are kept in sync with .md sources

# Find all .md files in .github/workflows/ that are staged
md_files=$(git diff --cached --name-only --diff-filter=ACM | grep '^\.github/workflows/.*\.md$' || true)

if [ -z "$md_files" ]; then
    # No agentic workflow files modified, exit silently
    exit 0
fi

echo "Compiling agentic workflows..."

# Check if gh aw extension is installed
if ! gh extension list 2>/dev/null | grep -q "gh-aw"; then
    echo "✗ Error: gh aw extension is not installed"
    echo "  Install it with: gh extension install github/gh-aw"
    exit 1
fi

# Get current version for reference
current_version=$(gh extension list 2>/dev/null | grep gh-aw | awk '{print $3}' || echo "unknown")

# Upgrade gh aw extension to latest version (suppress output unless there's an error)
if ! gh extension upgrade aw >/dev/null 2>&1; then
    echo "⚠ Warning: Failed to upgrade gh aw extension, using version $current_version"
fi

# Compile all modified .md files
for md_file in $md_files; do
    echo "  Compiling $(basename "$md_file")..."

    # Run compilation
    if ! gh aw compile "$md_file" >/dev/null 2>&1; then
        echo "✗ Error: Failed to compile $md_file"
        gh aw compile "$md_file" 2>&1 | head -20  # Show error details
        exit 1
    fi

    # Stage the generated .lock.yml file
    lock_file="${md_file%.md}.lock.yml"
    if [ -f "$lock_file" ]; then
        git add "$lock_file"
    fi

    # Also stage any other generated files
    [ -f ".github/aw/actions-lock.json" ] && git add ".github/aw/actions-lock.json"
    [ -f ".gitattributes" ] && git add ".gitattributes"
    [ -f ".github/dependabot.yml" ] && git add ".github/dependabot.yml"
done

echo "✓ Compilation complete"
exit 0
