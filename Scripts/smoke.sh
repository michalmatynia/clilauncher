#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for tool in node swift; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: Required tool '$tool' is not installed."
    exit 1
  fi
done

echo "Running automation detection smoke test..."
./Scripts/automation-detection-smoke.mjs

echo "Validating automation runner syntax..."
node --check Sources/GeminiLauncherNative/Resources/gemini-automation-runner.mjs

echo "Running Swift package build smoke check..."
SMOKE_BUILD_DIR="${TMPDIR:-/tmp}/clilauncher-smoke-build"
rm -rf "$SMOKE_BUILD_DIR"
swift build --scratch-path "$SMOKE_BUILD_DIR"

echo "Smoke checks passed."
