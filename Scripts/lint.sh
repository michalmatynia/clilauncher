#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
LINT_BASELINE="${LINT_BASELINE:-$ROOT_DIR/.swiftlint-baseline.json}"
SWIFTLINT_CACHE_DIR="${SWIFTLINT_CACHE_DIR:-/tmp/clilauncher-swiftlint-cache}"
SWIFTLINT_AGGRESSIVE="${SWIFTLINT_AGGRESSIVE:-1}"
SWIFTLINT_REPORTER="${SWIFTLINT_REPORTER:-xcode}"
WRITE_BASELINE="${1:-}"

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "warning: SwiftLint is not installed. Install with 'brew install swiftlint' and rerun for lint verification."
    if [[ "${CI:-0}" == "1" ]]; then
        exit 1
    fi
    exit 0
fi

# max lint = all rules + warnings-as-errors, with baseline filtering
lint_args=(
  lint
  --config .swiftlint.yml
  --strict
  --cache-path "$SWIFTLINT_CACHE_DIR"
  --reporter "$SWIFTLINT_REPORTER"
)

if [[ "$SWIFTLINT_AGGRESSIVE" == "1" ]]; then
  echo "Running SwiftLint in aggressive mode (all rules enabled)."
  lint_args+=(--enable-all-rules)
fi

if [[ "$WRITE_BASELINE" == "--write-baseline" ]]; then
  lint_args+=(--write-baseline "$LINT_BASELINE")
  # Keep baseline refresh output compact; baseline regeneration can be extremely noisy in all-rules mode.
  lint_args+=(--quiet)
elif [[ -f "$LINT_BASELINE" ]]; then
  lint_args+=(--baseline "$LINT_BASELINE")
fi

if [[ "$WRITE_BASELINE" == "--write-baseline" ]]; then
  swiftlint "${lint_args[@]}" || {
    # Writing baseline intentionally reports violations (exit code 2), but still updates the file.
    rc=$?
    if [[ $rc -ne 2 ]]; then
      exit $rc
    fi
  }
else
  swiftlint "${lint_args[@]}"
fi
