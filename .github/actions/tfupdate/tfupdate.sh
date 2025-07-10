#!/bin/bash -e
# Run tfupdate for all the currently used providers

GREP_CMD=$(command -v ggrep || command -v grep)
providers=$(find . -name "versions.tf" -not -path "*/.terraform/*" -exec $GREP_CMD -oP 'source\s*=\s*"\K[^"]+' {} \; | sort -u)

# Run tfupdate for each unique provider
for provider_name in $providers; do
    echo "Updating provider: $provider_name"
    tfupdate provider -r "$provider_name" .
done
