#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "warning: SwiftLint is not installed. Install with 'brew install swiftlint' and rerun for lint verification."
    if [[ "${CI:-0}" == "1" ]]; then
        exit 1
    fi
    exit 0
fi

swiftlint lint --config .swiftlint.yml
