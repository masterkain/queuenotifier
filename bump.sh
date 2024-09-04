#!/bin/bash

# Function to increment the version number
increment_version() {
  local version=$1
  local major minor patch

  IFS='.' read -r major minor patch <<<"$version"
  patch=$((patch + 1))
  echo "$major.$minor.$patch"
}

# Iterate over all .toc files in the current directory
for TOC_FILE in *.toc; do
  # Extract the current version from the .toc file
  current_version=$(grep -oE '## Version: [0-9.]+' "$TOC_FILE" | awk '{print $3}')

  # Check if a version was found
  if [[ -n "$current_version" ]]; then
    # Increment the version number
    new_version=$(increment_version "$current_version")

    # Update the .toc file with the new version
    sed -i.bak "s/## Version: $current_version/## Version: $new_version/" "$TOC_FILE"

    # Remove the backup file
    rm "${TOC_FILE}.bak"

    echo "Updated $TOC_FILE from version $current_version to $new_version"
  else
    echo "No version found in $TOC_FILE"
  fi
done

# Commit the changes
git add .
git commit -m "Release new versions in .toc files"

# Tag the new version (optional: adjust this if you want a single tag or different per file)
git tag -a "$new_version" -m "Version $new_version"

# Push the changes and the new tag to the remote repository
git push origin main --tags
