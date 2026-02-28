#!/bin/bash
# Bump version, commit, tag, and push to trigger the release workflow.
#
# Usage: ./scripts/release.sh 0.2.0
#
# This will:
#   1. Update version in package.json, src-tauri/tauri.conf.json, src-tauri/Cargo.toml
#   2. Commit the version bump
#   3. Create a git tag (v0.2.0)
#   4. Push the commit and tag
#
# The push triggers .github/workflows/release.yml which:
#   - Builds the macOS universal binary DMG
#   - Creates a GitHub draft release
#   - Updates the Homebrew tap with the new SHA256

set -euo pipefail

VERSION="${1:?Usage: $0 <version> (e.g. 0.2.0)}"

# Validate semver format
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: Version must be semver (e.g. 1.2.3)"
  exit 1
fi

echo "Bumping to v${VERSION}..."

# Update package.json
sed -i '' "s/\"version\": \".*\"/\"version\": \"${VERSION}\"/" package.json

# Update tauri.conf.json
sed -i '' "s/\"version\": \".*\"/\"version\": \"${VERSION}\"/" src-tauri/tauri.conf.json

# Update Cargo.toml (only the package version, not dependency versions)
sed -i '' "/^\[package\]/,/^\[/ s/^version = \".*\"/version = \"${VERSION}\"/" src-tauri/Cargo.toml

# Update Cargo.lock if it exists
if [ -f src-tauri/Cargo.lock ]; then
  cd src-tauri && cargo generate-lockfile 2>/dev/null && cd ..
fi

echo "Updated version to ${VERSION} in:"
echo "  - package.json"
echo "  - src-tauri/tauri.conf.json"
echo "  - src-tauri/Cargo.toml"

git add package.json src-tauri/tauri.conf.json src-tauri/Cargo.toml src-tauri/Cargo.lock 2>/dev/null || true
git commit -m "chore: bump version to v${VERSION}"
git tag "v${VERSION}"

echo ""
echo "Ready to release. Run:"
echo "  git push && git push --tags"
echo ""
echo "This will trigger the GitHub Actions release workflow."
