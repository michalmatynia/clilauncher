# CLILauncherNative

A macOS native launcher for running multiple AI CLI tools (and local tooling companions) with resilient startup sequencing and runtime diagnostics.

This project was previously published as *GeminiLauncherNative* and has kept source compatibility while expanding provider coverage.

## What it does

- Runs CLI sessions for configured providers (Gemini, Copilot, Codex, Claude Bypass, Kiro CLI, Ollama Launch).
- Performs provider-aware preflight checks before launch (binary/config/env checks, command preview).
- Launches commands into iTerm2 with safer AppleScript execution and startup sequencing.
- Tracks launches in history and records structured runtime diagnostics.
- Persists app state and local transcript/diagnostic artifacts in Application Support.
- Includes monitoring features (session tracking, storage summaries, retention controls).

## Requirements

- macOS 13+
- iTerm2 installed (for default terminal execution path)
- Swift 5.9+ toolchain (via Xcode or SwiftPM)
- Local CLI tools for providers you intend to use:
  - `gemini-preview-iso` (and `node` for legacy Gemini wrapper flow)
  - `copilot`
  - `codex`
  - `claude`
  - `kiro` or `kiro-cli`
  - `ollama`

## Quick start

1. Open the package in Xcode:

   ```bash
   cd "/Users/michalmatynia/Desktop/NPM/2026/Gemini new Pull/clilauncher"
   open Package.swift
   ```

2. Build and run the `CLILauncherNative` target.
3. In the app:

   - Create or pick a profile.
   - Set working directory and runtime options.
   - Run diagnostics preflight.
   - Launch into iTerm2.

## Build with SwiftPM

```bash
swift build
swift run CLILauncherNative
```

## Repo setup

```bash
git clone https://github.com/michalmatynia/clilauncher.git
cd clilauncher
git checkout main
swift build
```

## Data and runtime paths

- App state:
  - `~/Library/Application Support/CLILauncherNativeV24/state.json`
- Logs:
  - `~/Library/Application Support/CLILauncherNativeV24/Logs/runtime.log`
- Transcripts:
  - `~/Library/Application Support/CLILauncherNativeV24/Transcripts`

The app tries to migrate older state from legacy folders:

- `GeminiLauncherNativeV24`, `GeminiLauncherNativeV20`, …, `GeminiLauncherNativeV8`

## Documentation

See [`ApplicationDocumentation.md`](ApplicationDocumentation.md) for setup details, launch profiles, preflight behavior, workbench orchestration, and troubleshooting tips.

## Contributing

- Keep edits in `Sources/GeminiLauncherNative`.
- The app is intentionally provider-agnostic in architecture, with provider-specific defaults and execution definitions per profile.
- If you add a new provider, keep command construction, defaults, and validation in provider definition/model code paths and wire new diagnostics accordingly.

## License

This repository currently has no explicit license file. Please add one if you need redistribution/reuse constraints.
