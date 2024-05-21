#!/bin/bash

# Function to increment the version number
increment_version() {
  local version=$1
  local major minor patch

  IFS='.' read -r major minor patch <<<"$version"
  patch=$((patch + 1))
  echo "$major.$minor.$patch"
}

# Path to the .toc file
TOC_FILE="QueueNotifier.toc"

# Extract the current version from the .toc file
current_version=$(grep -oE '## Version: [0-9.]+' "$TOC_FILE" | awk '{print $3}')

# Increment the version number
new_version=$(increment_version "$current_version")

# Update the .toc file with the new version
sed -i.bak "s/## Version: $current_version/## Version: $new_version/" "$TOC_FILE"

# Commit the changes
git add .
git commit -m "Release version $new_version"

# Tag the new version
git tag -a "v$new_version" -m "Version $new_version"

# Push the changes and the new tag to the remote repository
git push origin main --tags
