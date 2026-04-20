#!/usr/bin/env bash
set -euo pipefail

echo "Installing Swift developer tooling via Homebrew..."

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install these tools. Please install Homebrew and retry."
  exit 1
fi

brew install swiftlint swiftformat swift-format
brew upgrade swiftlint swiftformat swift-format || true

echo "Swift DX tooling installed:"
echo "  - swiftlint: $(swiftlint --version)"
echo "  - swiftformat: $(swiftformat --version)"
echo "  - swift-format: $(swift-format --version)"
