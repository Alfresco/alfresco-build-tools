#!/bin/bash

# Directory containing composite actions
actions_dir='.github/actions'

# Dependabot config file
dependabot_config='.github/dependabot.yml'

# Temp file for new Dependabot config section
temp_config='temp_dependabot.yml'

# Function to generate Dependabot config section for a composite action
generate_dependabot_section() {
    local action_dir=$1
    local action_name=$(basename "$action_dir")
    echo "  - package-ecosystem: \"github-actions\""
    echo "    directory: \"/${action_dir}\""
    echo "    schedule:"
    echo "      interval: \"weekly\""
}

# Check if Dependabot config exists
if [ ! -f "$dependabot_config" ]; then
    echo "Dependabot config not found."
    exit 1
fi

# Start building the new config section
echo "version: 2" > "$temp_config"
echo "updates:" >> "$temp_config"

# Loop through composite actions and append to temp config
for action_dir in $(find "$actions_dir" -mindepth 1 -maxdepth 1 -type d -printf '%h\0%d\0%p\n' | sort -t '\0' -n | awk -F '\0' '{print $3}'); do
    generate_dependabot_section "$action_dir" >> "$temp_config"
done

# Merge new section with existing Dependabot config using yq
yq -i "$dependabot_config" "$temp_config"

# Clean up
rm "$temp_config"
