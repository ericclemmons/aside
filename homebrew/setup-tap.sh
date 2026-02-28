#!/bin/bash
# Bootstrap script to create the homebrew-tap repository.
#
# Run this once to set up: ericclemmons/homebrew-tap
# Then users can install with: brew install --cask ericclemmons/tap/aside
#
# Prerequisites:
#   - gh CLI authenticated (gh auth login)
#   - The animated-tribble repo has at least one release

set -euo pipefail

OWNER="${1:-ericclemmons}"
TAP_REPO="homebrew-tap"

echo "Creating ${OWNER}/${TAP_REPO}..."

# Create the repo on GitHub
gh repo create "${OWNER}/${TAP_REPO}" \
  --public \
  --description "Homebrew tap for ${OWNER}'s projects" \
  --clone

cd "${TAP_REPO}"

# Create the Casks directory and copy the formula
mkdir -p Casks
cp "$(dirname "$0")/aside.rb" Casks/aside.rb

# Create a README
cat > README.md << 'EOF'
# Homebrew Tap

Custom Homebrew tap for my projects.

## Installation

```bash
brew tap ericclemmons/tap
brew install --cask aside
```

## Available Casks

| Cask | Description |
|------|-------------|
| aside | macOS push-to-talk voice assistant with local Parakeet STT |
EOF

git add -A
git commit -m "Initial tap setup with aside cask"
git push -u origin main

echo ""
echo "Done! Users can now install with:"
echo "  brew tap ${OWNER}/tap"
echo "  brew install --cask aside"
echo ""
echo "Next steps:"
echo "  1. Create a GitHub release in animated-tribble (git tag v0.1.0 && git push --tags)"
echo "  2. Wait for the release workflow to build the DMG"
echo "  3. Update the SHA256 in Casks/aside.rb (or let CI do it automatically)"
echo ""
echo "For automatic tap updates on release, add a HOMEBREW_TAP_TOKEN secret"
echo "to the animated-tribble repo (a GitHub PAT with repo scope)."
