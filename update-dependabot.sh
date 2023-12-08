#!/bin/bash

# Directory containing composite actions
actions_dir='.github/actions'

# Dependabot source config file
master_config='.github/dependabot.template.yml'

# Dependabot target config file
dependabot_config='.github/dependabot.yml'

# Temp file for new Dependabot config section
temp_config='temp_dependabot.yml'

# Function to generate Dependabot config section for a composite action
generate_dependabot_section() {
    local action_dir=$1
    echo "  - package-ecosystem: \"github-actions\""
    echo "    directory: \"/${action_dir}\""
    echo "    schedule:"
    echo "      interval: \"weekly\""
}

# Check if Dependabot config exists
if [ ! -f "$master_config" ]; then
    echo "$master_config config not found."
    exit 1
fi

# Start building the new config section
echo "version: 2" > "$temp_config"
echo "updates:" >> "$temp_config"

# Loop through composite actions and append to temp config
for action_filename in $(find "$actions_dir" -mindepth 2 -type f -name action.yml | env -i LC_COLLATE=C sort -n); do
    action_dir=$(dirname $action_filename)
    generate_dependabot_section "$action_dir" >> "$temp_config"
done

# Merge new section with existing Dependabot config using yq
yq eval-all '. as $item ireduce ({}; . *+ $item)' $master_config $temp_config > "$dependabot_config"

# Clean up
rm "$temp_config"
