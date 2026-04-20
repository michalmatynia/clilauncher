# CLILauncherNative Application Documentation

## 1) Product overview

`CLILauncherNative` is a local macOS GUI app that builds and runs command plans for multiple CLI providers inside iTerm2. It is designed to reduce brittle launch behavior by:

- pre-validating tools before execution,
- resolving executables consistently,
- generating reproducible command previews,
- and launching one or more tabs consistently through iTerm2 AppleScript.

The app is built around the following runtime layers:

- **Profile model** (`LaunchProfile`) for provider-specific launch settings.
- **Command planner** (`LaunchPlanner`) for rendering final shell commands.
- **Preflight checks** (`PreflightService`) for dependency/config/runtime validation.
- **Terminal integration** (`ITerm2Launcher`) for safe script execution.
- **Monitoring/observability** (`TerminalMonitorStore`, `LaunchLogger`) for logs and launch history.

## 2) Core concepts

### 2.1 Profiles

Each profile maps to one provider. Active provider kinds are:

- Gemini
- GitHub Copilot
- OpenAI Codex
- Claude Bypass
- Kiro CLI
- Ollama Launch
- **Aider**

Profiles include:

- working directory
- open mode (new window/tab behavior)
- shell bootstrap command/presets
- provider executable and arguments
- environment overrides (shared + per-profile)
- companion profiles (optional)

Profile presets and normalization are handled in `LaunchProfile` defaults.

### 2.2 Workbenches

Workbenches launch multiple profiles as a single orchestrated plan:

- each workbench has a role (`Research`, `Coding`, `Review`),
- startup delay controls staging between profiles,
- optional shared workspace bookmark,
- optional post-launch actions and notes.

### 2.3 Monitoring and history

- launch history and errors/warnings are tracked in-app,
- terminal process events are recorded with optional retention settings in a MongoDB-backed history store,
- diagnostics exports are available as JSON bundles for sharing support issues,
- **Session Export**: Export transcripts and session metadata to JSON from the monitoring dashboard,
- **Clear History**: Wipes all monitoring records and local transcripts,
- **Connection Diagnostics**: Test MongoDB connectivity with real-time feedback.

## 3) Command flow

The app follows this path:

1. User selects profile/workbench and triggers launch.
2. `LaunchPlanner` builds a command plan.
3. `PreflightService` validates:
   - executable availability,
   - wrapper/tool dependencies,
   - model capabilities where available,
   - workspace/config hints.
4. `TerminalMonitorStore` prepares monitoring state.
5. `ITerm2Launcher` writes script and opens iTerm2 tabs/windows.
6. Post-launch actions run if configured.

## 4) Executable discovery and wrapper handling

Execution resolution is centralized and provider-aware in `LauncherServices`.

For provider-specific checks:

- Gemini may require wrapper + Node in wrapper mode.
- MongoDB-backed history tracking uses `mongosh`.
- For local Mongo URLs (`127.0.0.1`/`localhost`), monitoring auto-starts a local `mongod` using:
  - data directory `~/Library/Application Support/CLILauncherNativeV24/Mongo` by default (configurable),
  - local workspace transcript/diagnostic folders as configured in settings.
- Non-Gemini providers validate their own primary executable.
- Model/version probes are run as part of preflight when possible.

Diagnostics output includes:

- discovered path,
- probe source (`PATH`, aliases, working-directory override),
- failure reasons,
- and version/model hints.

## 5) Configuration locations

All app data is stored under:

`~/Library/Application Support/CLILauncherNativeV24/`

with:

- `state.json` — profiles, workbenches, settings, history, and bookmarks
- `Logs/runtime.log` — runtime logs when disk persistence is enabled
- `Transcripts/` — terminal transcript outputs (when enabled by settings)

Legacy state folders are migrated automatically when found:

- `GeminiLauncherNativeV24`, `GeminiLauncherNativeV20`, …, `GeminiLauncherNativeV8`.

## 6) Troubleshooting

### 6.1 Common startup issues

- **iTerm2 not starting**
  - Ensure iTerm2 is installed and has permission to run AppleScript.
  - Verify command preview and AppleScript preview in diagnostics.
- **Missing CLI executable**
  - Check provider default executable value.
  - Ensure tool binary is visible to non-login GUI launch paths.
- **Monitoring/Storage errors**
  - Enable database writes and confirm the monitoring connection URL points to a valid Mongo database.
  - Ensure `mongosh` is discoverable in app diagnostics and check the terminal monitoring status output for resolution details.
  - For localhost URLs, ensure `mongod` resolves and the local data directory is writable so the app can auto-bootstrap the daemon.
- **Gemini launch issues**
  - Confirm the Gemini wrapper alias (`gemini-iso`, `gemini-preview-iso`, `gemini-nightly-iso`, or your configured alias) resolves in diagnostics.
  - Confirm the `Automation runner`, `Node`, and `Gemini PTY backend` statuses in diagnostics for automation-runner mode.
  - Leave the automation runner path blank if you want to use the app-bundled runner.
  - Install `@lydell/node-pty` or `node-pty` in the launch workspace if you need PTY hotkeys and prompt automation.
  - In PTY-enabled automation-runner mode, capacity menus (`Keep trying` / `Switch` / `Stop`) are handled automatically.
  - Toggle automation using keystrokes:
    - App shortcut: **Cmd+Shift+A** (selected Gemini profile).
    - Runner shortcut: **Ctrl-G a** (or your configured hotkey prefix + `a`).
  - Ensure working directory is expected by the selected launch mode.
- **Preflight warnings but launch still succeeds**
  - Warnings can be informational; use error-state blocks for required blockers.

### 6.2 Where to inspect

- Logs tab: command preview, runtime categories, error/warning levels.
- Diagnostics tab: provider checks and dependency hints.
- Export Diagnostics from the app menu for snapshots.

## 7) Development notes

### Build targets

- Product: `CLILauncherNative`
- Swift package: `Package.swift`

### Useful files

- `Sources/GeminiLauncherNative/LauncherServices.swift` — command construction and launch infrastructure
- `Sources/GeminiLauncherNative/Models.swift` — provider definitions and data models
- `Sources/GeminiLauncherNative/ProfileStore.swift` — persistence, defaults, migrations
- `Sources/GeminiLauncherNative/ContentView.swift` — tabs, launch UX, diagnostics views
- `Sources/GeminiLauncherNative/MonitoringDashboardView.swift` — runtime/session monitoring

### Contributing guidance

- Keep provider defaults and health checks in the provider definition path.
- Add new providers by extending `AgentKind` and `providerDefinition`.
- Mirror provider-specific preflight logic in the same model/service path to keep launch behavior consistent.

---

## 8) Quick glossary

- **Profile**: one launch unit for a single provider.
- **Workbench**: ordered set of profiles launched together.
- **Preflight**: validation run that guards against known broken states before runtime execution.
- **Companion profile**: optional profile relationship used for cross-provider workflows.
- **Diagnostic export**: packaged snapshot of checks, logs, and launch context for debugging.
