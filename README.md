# CLILauncher (formerly GeminiLauncherNative) v24

This build focuses on **iTerm2 launch reliability** and **runtime observability** for multiple CLI agents.

## New in v24

- **More reliable iTerm2 control**
  - iTerm2 profile discovery now reads the local iTerm preferences domain/plist first instead of relying only on in-process AppleScript parsing.
  - iTerm2 launch automation now runs through `/usr/bin/osascript`, which is a better fit for this SwiftPM/Xcode-run app than direct `NSAppleScript` execution.
  - iTerm2 launch scripts now create the window/tab first and then `write text` into the session, which is more tolerant than the older inline `command` form.
  - iTerm2 is explicitly resolved and launched before command dispatch.

- **Better launch fallbacks**
  - Gemini automation-runner profiles now fall back to direct-wrapper launch if the runner path is empty or missing.
  - Kiro CLI resolution now also checks `kiro` and `kiro-cli` aliases.

- **Improved logs and observability**
  - Added **debug log level** and **log categories** (`launch`, `preflight`, `iterm`, `monitoring`, etc.).
  - Runtime logs can now be persisted to disk at:
    - `~/Library/Application Support/CLILauncherNativeV24/Logs/runtime.log`
  - Repeated log entries can be deduplicated in memory.
  - The Log tab now supports level/category filtering, log-folder reveal, and diagnostic JSON export.
  - Added a diagnostic export bundle with current preflight status, iTerm2 runtime info, command preview, AppleScript preview, monitoring summary, and recent logs.

- **Reduced refresh churn**
  - Live diagnostics/profile refresh is now lightly debounced to avoid excessive repeated refresh work while editing settings.

- **State migration**
  - App state now lives in:
    - `~/Library/Application Support/CLILauncherNativeV24/state.json`
  - v24 attempts to migrate state from v20 and older folders.

## Monitoring features still included

- PostgreSQL-backed terminal session tracking
- Session/event/chunk inspector
- Storage summary
- Retention/pruning controls
- Local transcript retention and export

## Build on macOS

1. Unzip the bundle.
2. Open `Package.swift` in Xcode.
3. Build and run `CLILauncherNative`.

## Notes

- Targets **macOS 13+**.
- This is **source code** for local Xcode build, not a signed/notarized app bundle.
