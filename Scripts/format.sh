#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-format}"

for tool in swiftformat swift-format; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "warning: $tool is not installed. Install with './Scripts/install-swift-tools.sh' and rerun."
    if [[ "${CI:-0}" == "1" ]]; then
      exit 1
    fi
    exit 0
  fi
done

if [[ "$MODE" == "check" ]]; then
  status=0

  echo "Running swiftformat in lint mode..."
  swiftformat Sources --lint || status=1
  swiftformat Tests --lint || status=1

  echo "Running swift-format in lint mode..."
  swift-format lint --recursive Sources Tests || status=1

  exit "$status"
else
  echo "Formatting with swiftformat..."
  swiftformat Sources Tests
  echo "Formatting with swift-format..."
  swift-format format --in-place --recursive Sources Tests
fi
