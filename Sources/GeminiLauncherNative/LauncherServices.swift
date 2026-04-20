import AppKit
import Foundation
import UniformTypeIdentifiers

enum LauncherError: LocalizedError {
    case validation(String)
    case appleScript(String)

    var errorDescription: String? {
        switch self {
        case .validation(let value): return value
        case .appleScript(let value): return value
        }
    }
}

private final class LockedLaunchErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    func set(_ error: Error?) {
        lock.lock()
        storedError = error
        lock.unlock()
    }

    func get() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }
}

private final class LockedBooleanBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

struct CommandBuilder {
    private let executableResolver = ExecutableResolver()

    func buildLaunchResult(profile: LaunchProfile, settings: AppSettings) throws -> LaunchResult {
        let command = try buildCommand(profile: profile, settings: settings)
        let description = descriptionForProfile(profile)
        let appleScript = ITerm2Launcher().buildAppleScript(
            command: command,
            openMode: profile.openMode,
            iTermProfile: profile.trimmedITermProfile
        )
        return LaunchResult(command: command, appleScript: appleScript, description: description)
    }

    func buildCommand(profile: LaunchProfile, settings: AppSettings) throws -> String {
        let workingDirectory = profile.expandedWorkingDirectory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LauncherError.validation("Working directory does not exist: \(workingDirectory)")
        }

        let env = buildEnvironment(profile: profile, settings: settings)
        let executableAndArgs = try buildExecutableAndArgs(profile: profile, settings: settings)

        let prefix = env.isEmpty ? "" : "env " + env
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\(shellQuote($0.value))" }
            .joined(separator: " ") + " "

        let joinedArgs = executableAndArgs.arguments.map(shellQuotePreservingFlags).joined(separator: " ")
        let probe = "printf '%s %s\\n' \"$(date -u +%FT%TZ)\" 'shell-reached-exec' >> /tmp/clilauncher_probe.txt && "
        let commandCore = "\(probe)exec \(prefix)\(shellQuote(executableAndArgs.executable))" + (joinedArgs.isEmpty ? "" : " \(joinedArgs)")

        let bootstrapCommands = [
            settings.defaultShellBootstrapCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedBootstrapPreset(profile: profile, settings: settings)?.trimmedCommand ?? "",
            profile.trimmedShellBootstrapCommand
        ].filter { !$0.isEmpty }

        let bootstrapPrefix = bootstrapCommands.isEmpty ? "" : bootstrapCommands.joined(separator: " && ") + " && "

        return "cd \(shellQuote(workingDirectory)) && \(bootstrapPrefix)\(commandCore)"
    }

    func buildEnvironment(profile: LaunchProfile, settings: AppSettings) -> [String: String] {
        var env = selectedEnvironmentPreset(profile: profile, settings: settings)?.environmentMap ?? [:]
        for (key, value) in profile.environmentMap {
            env[key] = value
        }

        switch profile.agentKind {
        case .gemini:
            let resolvedWrapper = resolveGeminiWrapper(profile: profile, workingDirectory: profile.expandedWorkingDirectory).resolved
            env["CLI_FLAVOR"] = profile.geminiFlavor.cliFlavorValue
            env["GEMINI_WRAPPER"] = resolvedWrapper ?? resolvedGeminiWrapper(profile: profile)
            env["GEMINI_ISO_HOME"] = profile.expandedGeminiISOHome
            env["RESUME_LATEST"] = profile.geminiResumeLatest ? "1" : "0"
            env["KEEP_TRY_MAX"] = String(profile.geminiKeepTryMax)
            if profile.geminiAutoContinueMode == .yolo {
                env["AUTO_CONTINUE_MODE"] = "always"
                env["AUTO_CONTINUE_MAX_PER_EVENT"] = "1000"
                env["KEEP_TRY_MAX"] = "1000"
            } else {
                env["AUTO_CONTINUE_MODE"] = profile.geminiAutoContinueMode.rawValue
            }
            env["AUTO_ALLOW_SESSION_PERMISSIONS"] = profile.geminiAutoAllowSessionPermissions ? "1" : "0"
            env["AUTOMATION_ENABLED"] = profile.geminiAutomationEnabled ? "1" : "0"
            env["NEVER_SWITCH"] = profile.geminiNeverSwitch ? "1" : "0"
            env["GEMINI_YOLO"] = profile.geminiYolo ? "1" : "0"
            env["PTY_SET_HOME_TO_ISO"] = profile.geminiSetHomeToIso ? "1" : "0"
            env["QUIET_CHILD_NODE_WARNINGS"] = profile.geminiQuietChildNodeWarnings ? "1" : "0"
            env["RAW_OUTPUT"] = profile.geminiRawOutput ? "1" : "0"
            env["MANUAL_OVERRIDE_MS"] = String(profile.geminiManualOverrideMs)
            env["CAPACITY_RETRY_MS"] = String(profile.geminiCapacityRetryMs)
            env["HOTKEY_PREFIX"] = profile.geminiHotkeyPrefix
            env["MODEL_CHAIN"] = profile.geminiModelChain
            if env["RUNNER_LOG_FILE"] == nil || env["RUNNER_LOG_FILE"]?.isEmpty == true {
                env["RUNNER_LOG_FILE"] = "/tmp/clilauncher.log"
            }
            switch profile.geminiFlavor {
            case .stable:
                env["GEMINI_HOME"] = profile.expandedGeminiISOHome
            case .preview:
                env["GEMINI_PREVIEW_ISO_HOME"] = profile.expandedGeminiISOHome
            case .nightly:
                env["GEMINI_NIGHTLY_ISO_HOME"] = profile.expandedGeminiISOHome
            }
        case .copilot:
            let home = profile.expandedCopilotHome.trimmingCharacters(in: .whitespacesAndNewlines)
            if !home.isEmpty {
                env["COPILOT_HOME"] = home
            }
        case .codex, .claudeBypass, .kiroCLI, .ollamaLaunch, .aider:
            break
        }

        return env
    }

    func selectedEnvironmentPreset(profile: LaunchProfile, settings: AppSettings) -> EnvironmentPreset? {
        guard let presetID = profile.environmentPresetID else { return nil }
        return settings.environmentPresets.first(where: { $0.id == presetID })
    }

    func selectedBootstrapPreset(profile: LaunchProfile, settings: AppSettings) -> ShellBootstrapPreset? {
        guard let presetID = profile.bootstrapPresetID else { return nil }
        return settings.shellBootstrapPresets.first(where: { $0.id == presetID })
    }

    func buildExecutableAndArgs(profile: LaunchProfile, settings: AppSettings) throws -> (executable: String, arguments: [String]) {
        switch profile.agentKind {
        case .gemini:
            return try buildGeminiExecutableAndArgs(profile: profile, settings: settings)
        case .copilot:
            return try buildCopilotExecutableAndArgs(profile: profile)
        case .codex:
            return try buildCodexExecutableAndArgs(profile: profile)
        case .claudeBypass:
            return try buildClaudeExecutableAndArgs(profile: profile)
        case .kiroCLI:
            return try buildKiroExecutableAndArgs(profile: profile)
        case .ollamaLaunch:
            return try buildOllamaExecutableAndArgs(profile: profile)
        case .aider:
            return try buildAiderExecutableAndArgs(profile: profile)
        }
    }

    private func buildGeminiExecutableAndArgs(profile: LaunchProfile, settings: AppSettings) throws -> (String, [String]) {
        switch profile.geminiLaunchMode {
        case .automationRunner:
            let runnerResolution = resolveAutomationRunner(profile: profile, settings: settings, workingDirectory: profile.expandedWorkingDirectory)
            if !runnerResolution.isResolved {
                return try buildGeminiDirectWrapperExecutableAndArgs(profile: profile)
            }
            _ = try resolveProviderExecutableOrThrow(
                profile: profile,
                workingDirectory: profile.expandedWorkingDirectory
            )
            let node = try resolvedExecutableOrThrow(
                resolvedNodeExecutable(profile: profile, settings: settings),
                displayName: "Node",
                workingDirectory: profile.expandedWorkingDirectory
            )
            return (node, [runnerResolution.resolved ?? ""])
        case .directWrapper:
            return try buildGeminiDirectWrapperExecutableAndArgs(profile: profile)
        }
    }

    private func buildGeminiDirectWrapperExecutableAndArgs(profile: LaunchProfile) throws -> (String, [String]) {
        let wrapper = try resolveProviderExecutableOrThrow(
            profile: profile,
            workingDirectory: profile.expandedWorkingDirectory
        )
        var args: [String] = []
        let initialModel = profile.geminiInitialModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !initialModel.isEmpty {
            args += ["--model", initialModel]
        }
        if profile.geminiResumeLatest {
            args.append("--resume")
            args.append("latest")
        }
        if profile.geminiYolo {
            args.append("--yolo")
        }
        if profile.geminiRawOutput {
            args.append("--raw-output")
            args.append("--accept-raw-output-risk")
        }
        args.append(contentsOf: splitCLIArguments(profile.trimmedExtraCLIArgs))
        return (wrapper, args)
    }

    private func buildCopilotExecutableAndArgs(profile: LaunchProfile) throws -> (String, [String]) {
        let executable = try resolveProviderExecutableOrThrow(
            profile: profile,
            workingDirectory: profile.expandedWorkingDirectory
        )
        var args: [String] = []

        switch profile.copilotMode {
        case .interactive:
            break
        case .plan:
            args += ["--mode", "plan"]
        case .autopilot:
            args.append("--autopilot")
        case .autopilotYolo:
            args += ["--autopilot", "--yolo"]
        }

        let model = profile.copilotModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            args += ["--model", model]
        }
        if profile.copilotMode.isAutonomous && profile.copilotMaxAutopilotContinues > 0 {
            args += ["--max-autopilot-continues", String(profile.copilotMaxAutopilotContinues)]
        }
        let prompt = profile.copilotInitialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            args += ["-i", prompt]
        }
        args.append(contentsOf: splitCLIArguments(profile.trimmedExtraCLIArgs))
        return (executable, args)
    }

    private func buildCodexExecutableAndArgs(profile: LaunchProfile) throws -> (String, [String]) {
        let executable = try resolveProviderExecutableOrThrow(
            profile: profile,
            workingDirectory: profile.expandedWorkingDirectory
        )
        var args: [String] = []
        if let flag = profile.codexMode.cliFlag {
            args.append(flag)
        }
        let model = profile.codexModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            args += ["-m", model]
        }
        args.append(contentsOf: splitCLIArguments(profile.trimmedExtraCLIArgs))
        return (executable, args)
    }

    private func buildClaudeExecutableAndArgs(profile: LaunchProfile) throws -> (String, [String]) {
        let executable = try resolveProviderExecutableOrThrow(
            profile: profile,
            workingDirectory: profile.expandedWorkingDirectory
        )
        var args: [String] = ["--dangerously-skip-permissions"]
        let model = profile.claudeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            args += ["--model", model]
        }
        args.append(contentsOf: splitCLIArguments(profile.trimmedExtraCLIArgs))
        return (executable, args)
    }

    private func buildKiroExecutableAndArgs(profile: LaunchProfile) throws -> (String, [String]) {
        let executable = try resolveProviderExecutableOrThrow(
            profile: profile,
            workingDirectory: profile.expandedWorkingDirectory
        )

        var args: [String] = []
        switch profile.kiroMode {
        case .interactive:
            break
        case .chat:
            args.append("chat")
        case .chatResume:
            args += ["chat", "--resume"]
        }
        args.append(contentsOf: splitCLIArguments(profile.trimmedExtraCLIArgs))
        return (executable, args)
    }

    private func buildOllamaExecutableAndArgs(profile: LaunchProfile) throws -> (String, [String]) {
        let executable = try resolveProviderExecutableOrThrow(
            profile: profile,
            workingDirectory: profile.expandedWorkingDirectory
        )
        var args: [String] = ["launch", profile.ollamaIntegration.subcommand]
        let model = profile.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            args += ["--model", model]
        }
        if profile.ollamaConfigOnly {
            args.append("--config")
        }
        args.append(contentsOf: splitCLIArguments(profile.trimmedExtraCLIArgs))
        return (executable, args)
    }

    private func buildAiderExecutableAndArgs(profile: LaunchProfile) throws -> (String, [String]) {
        let executable = try resolveProviderExecutableOrThrow(
            profile: profile,
            workingDirectory: profile.expandedWorkingDirectory
        )
        var args: [String] = []

        switch profile.aiderMode {
        case .code:
            break
        case .architect:
            args.append("--architect")
        case .ask:
            args.append("--ask")
        }

        let model = profile.aiderModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            args += ["--model", model]
        }

        if !profile.aiderAutoCommit {
            args.append("--no-auto-commit")
        }

        if profile.aiderNotify {
            args.append("--notify")
        }

        if profile.aiderDarkTheme {
            args.append("--dark-mode")
        } else {
            args.append("--light-mode")
        }

        args.append(contentsOf: splitCLIArguments(profile.trimmedExtraCLIArgs))
        return (executable, args)
    }

    func descriptionForProfile(_ profile: LaunchProfile) -> String {
        return profile.agentKind.providerDefinition.description(profile)
    }

    func resolvedNodeExecutable(profile: LaunchProfile, settings: AppSettings) -> String {
        let raw = profile.nodeExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return raw }

        let defaultNode = settings.defaultNodeExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        return defaultNode.isEmpty ? "node" : defaultNode
    }

    func resolvedGeminiWrapper(profile: LaunchProfile) -> String {
        let explicitWrapper = profile.geminiWrapperCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitWrapper.isEmpty { return explicitWrapper }
        return profile.geminiFlavor.wrapperName
    }

    private func geminiWrapperCandidates(for profile: LaunchProfile) -> [String] {
        let candidates = profile.providerExecutableCandidates
        if !candidates.isEmpty {
            return candidates
        }
        return [resolvedGeminiWrapper(profile: profile)]
    }

    func resolveGeminiWrapper(profile: LaunchProfile, workingDirectory: String) -> ExecutableResolution {
        let candidates = geminiWrapperCandidates(for: profile)
        let defaultCandidate = resolvedGeminiWrapper(profile: profile)

        var failedResolutions: [ExecutableResolution] = []
        for candidate in candidates {
            let candidateResolution = resolveExecutable(candidate, workingDirectory: workingDirectory)
            if candidateResolution.isResolved {
                return candidateResolution
            }
            failedResolutions.append(candidateResolution)
        }

        let firstCandidate = candidates.first ?? defaultCandidate
        let requestedCandidate = firstCandidate.isEmpty ? "Gemini wrapper command" : firstCandidate
        guard !failedResolutions.isEmpty else {
            return ExecutableResolution(
                requested: requestedCandidate,
                resolved: nil,
                source: "no gemini wrapper candidates were evaluated",
                detail: "No Gemini wrapper candidates were evaluated."
            )
        }

        let sourceSummary = {
            let uniqueSources = Array(Set(failedResolutions.compactMap(\.source))).sorted()
            return uniqueSources.isEmpty ? "candidate executable probes" : uniqueSources.joined(separator: ", ")
        }()
        let failureDetails = failedResolutions.enumerated().map { index, resolution in
            "\(index + 1). \(resolution.requested) -> \(resolution.detail) [\(resolution.source ?? "not found")]"
        }.joined(separator: "; ")

        return ExecutableResolution(
                requested: requestedCandidate,
                resolved: nil,
                source: sourceSummary,
                detail: "Checked candidate wrappers: \(candidates.joined(separator: ", ")). \(failureDetails)",
                searchedLocations: Array(failedResolutions.flatMap { $0.searchedLocations }.prefix(40))
            )
        }

    func resolveGeminiWrapperOrThrow(profile: LaunchProfile, workingDirectory: String) throws -> String {
        let resolution = resolveGeminiWrapper(profile: profile, workingDirectory: workingDirectory)
        guard let resolved = resolution.resolved else {
            let candidates = geminiWrapperCandidates(for: profile)
            throw LauncherError.validation(
                "Gemini wrapper was not found. Checked candidates: \(candidates.joined(separator: ", ")). \(resolution.detail)"
            )
        }
        return resolved
    }

    func resolvedRunnerPath(profile: LaunchProfile, settings: AppSettings) -> String {
        let raw = profile.expandedGeminiRunnerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            return raw
        }

        let defaultRunner = NSString(string: settings.defaultGeminiRunnerPath)
            .expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !defaultRunner.isEmpty {
            return defaultRunner
        }

        return BundledGeminiAutomationRunner.defaultPath
    }

    func resolveAutomationRunner(profile: LaunchProfile, settings: AppSettings, workingDirectory: String) -> ExecutableResolution {
        let rawRunner = resolvedRunnerPath(profile: profile, settings: settings)
        guard !rawRunner.isEmpty else {
            return ExecutableResolution(
                requested: "Automation runner",
                resolved: nil,
                source: "not configured",
                detail: "Automation runner is not configured. Launcher will use direct wrapper mode."
            )
        }

        let expandedRunner = NSString(string: rawRunner).expandingTildeInPath
        let runnerPath = expandedRunner.hasPrefix("/") ? expandedRunner : (workingDirectory as NSString).appendingPathComponent(expandedRunner)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: runnerPath, isDirectory: &isDirectory), !isDirectory.boolValue {
            return ExecutableResolution(
                requested: rawRunner,
                resolved: runnerPath,
                source: "configured file path",
                detail: "Automation runner script found at \(runnerPath)."
            )
        }

        return resolveExecutable(rawRunner, workingDirectory: workingDirectory)
    }

    func resolveExecutable(_ command: String, workingDirectory: String? = nil) -> ExecutableResolution {
        executableResolver.resolve(command, workingDirectory: workingDirectory)
    }

    func resolvedExecutable(_ command: String, workingDirectory: String? = nil) -> String? {
        resolveExecutable(command, workingDirectory: workingDirectory).resolved
    }

    func executableResolverSnapshot() -> ExecutableResolverSnapshot {
        executableResolver.snapshot()
    }

    func resolvedExecutableOrThrow(_ command: String, displayName: String, workingDirectory: String? = nil) throws -> String {
        let resolution = resolveExecutable(command, workingDirectory: workingDirectory)
        if let resolved = resolution.resolved {
            return resolved
        }
        throw LauncherError.validation("\(displayName) was not found: \(command). \(resolution.detail)")
    }

    private func resolveProviderExecutableOrThrow(
        profile: LaunchProfile,
        workingDirectory: String
    ) throws -> String {
        let candidates = profile.providerExecutableCandidates
        guard !candidates.isEmpty else {
            throw LauncherError.validation("\(profile.providerExecutableLabel) is not configured.")
        }

        var failures: [ExecutableResolution] = []
        for candidate in candidates {
            let resolution = resolveExecutable(candidate, workingDirectory: workingDirectory)
            if let resolved = resolution.resolved {
                return resolved
            }
            failures.append(resolution)
        }

        let failureDetails = failures.isEmpty
            ? "No executable candidates were evaluated."
            : "Checked candidates: " + failures.enumerated().map {
                "\( $0.offset + 1). \($0.element.requested) -> \($0.element.detail) [\($0.element.source ?? "not found")]"
            }.joined(separator: "; ")
        let detail = candidates.isEmpty
            ? "No executable candidates configured."
            : "\(failureDetails)."
        throw LauncherError.validation("\(profile.providerExecutableLabel) was not found: \(candidates[0]). \(detail)")
    }

    private func shellQuote(_ raw: String) -> String {
        let expanded = NSString(string: raw).expandingTildeInPath
        return "'" + expanded.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func shellQuotePreservingFlags(_ raw: String) -> String {
        if raw.hasPrefix("-") { return raw }
        return shellQuote(raw)
    }

    private func splitCLIArguments(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}

struct LaunchPlanner {
    let commandBuilder = CommandBuilder()

    func buildPlan(primary: LaunchProfile, allProfiles: [LaunchProfile], settings: AppSettings) throws -> PlannedLaunch {
        let primaryResult = try commandBuilder.buildLaunchResult(profile: primary, settings: settings)
        var items = [
            PlannedLaunchItem(
                profileID: primary.id,
                profileName: primary.name,
                command: primaryResult.command,
                openMode: primary.openMode,
                terminalApp: primary.terminalApp,
                iTermProfile: primary.trimmedITermProfile,
                description: primaryResult.description
            )
        ]
        var actionProfiles: [LaunchProfile] = [primary]

        if primary.autoLaunchCompanions {
            let lookup = Dictionary(uniqueKeysWithValues: allProfiles.map { ($0.id, $0) })
            for companionID in primary.companionProfileIDs {
                guard let companion = lookup[companionID], companion.id != primary.id else { continue }
                let result = try commandBuilder.buildLaunchResult(profile: companion, settings: settings)
                items.append(
                    PlannedLaunchItem(
                        profileID: companion.id,
                        profileName: companion.name,
                        command: result.command,
                        openMode: .newTab,
                        terminalApp: companion.terminalApp,
                        iTermProfile: companion.trimmedITermProfile,
                        description: result.description
                    )
                )
                actionProfiles.append(companion)
            }
        }

        let postLaunchActions = buildPostLaunchActions(for: actionProfiles)
        return PlannedLaunch(items: items, postLaunchActions: postLaunchActions, tabLaunchDelayMs: max(0, primary.tabLaunchDelayMs))
    }

    func buildWorkbenchPlan(workbench: LaunchWorkbench, profiles: [LaunchProfile], bookmarks: [WorkspaceBookmark], settings: AppSettings) throws -> PlannedLaunch {
        let profileLookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let bookmarkLookup = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0) })

        guard !workbench.profileIDs.isEmpty else {
            throw LauncherError.validation("Workbench has no profiles selected.")
        }

        let sharedBookmark = workbench.sharedBookmarkID.flatMap { bookmarkLookup[$0] }
        if workbench.sharedBookmarkID != nil && sharedBookmark == nil {
            throw LauncherError.validation("Workbench shared workspace no longer exists.")
        }

        var items: [PlannedLaunchItem] = []
        var adjustedProfiles: [LaunchProfile] = []
        for (index, profileID) in workbench.profileIDs.enumerated() {
            guard let original = profileLookup[profileID] else { continue }
            let adjusted = applying(sharedBookmark: sharedBookmark, to: original)
            let result = try commandBuilder.buildLaunchResult(profile: adjusted, settings: settings)
            let label = sharedBookmark.map { "\(original.name) @ \($0.name)" } ?? original.name
            items.append(
                PlannedLaunchItem(
                    profileID: original.id,
                    profileName: label,
                    command: result.command,
                    openMode: index == 0 ? original.openMode : .newTab,
                    terminalApp: adjusted.terminalApp,
                    iTermProfile: adjusted.trimmedITermProfile,
                    description: result.description
                )
            )
            adjustedProfiles.append(adjusted)
        }

        guard !items.isEmpty else {
            throw LauncherError.validation("Workbench does not reference any existing profiles.")
        }

        let primaryDelay = max(0, workbench.startupDelayMs)
        return PlannedLaunch(items: items, postLaunchActions: buildPostLaunchActions(for: adjustedProfiles), tabLaunchDelayMs: max(0, primaryDelay))
    }

    private func buildPostLaunchActions(for profiles: [LaunchProfile]) -> [PostLaunchAction] {
        var seen: Set<String> = []
        var actions: [PostLaunchAction] = []

        for profile in profiles {
            let path = profile.expandedWorkingDirectory
            for app in profile.workspaceCompanionApps {
                let key = "\(app.rawValue)|\(path)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                actions.append(
                    PostLaunchAction(
                        app: app,
                        path: path,
                        label: "\(app.displayName) • \(URL(fileURLWithPath: path).lastPathComponent)"
                    )
                )
            }
        }

        return actions
    }

    private func applying(sharedBookmark: WorkspaceBookmark?, to profile: LaunchProfile) -> LaunchProfile {
        guard let sharedBookmark else { return profile }
        var adjusted = profile
        adjusted.workingDirectory = sharedBookmark.path
        adjusted.tags = Array(Set(adjusted.tags + sharedBookmark.tags)).sorted()
        return adjusted
    }
}

struct PreflightCheck: Sendable {
    var warnings: [String] = []
    var errors: [String] = []
    var statuses: [ToolStatus] = []

    var isPassing: Bool { errors.isEmpty }
}

struct ToolDiscoveryService {
    private let builder = CommandBuilder()
    private let companionLauncher = WorkspaceCompanionLauncher()
    private let iTermRuntime = ITerm2RuntimeService()

    private func expandedResolutionDetail(_ resolution: ExecutableResolution) -> String {
        guard !resolution.searchedLocations.isEmpty else { return resolution.detail }
        let previewCount = min(12, resolution.searchedLocations.count)
        let preview = resolution.searchedLocations.prefix(previewCount).joined(separator: "\n  - ")
        if resolution.searchedLocations.count > previewCount {
            return "\(resolution.detail) Also checked candidate paths:\n  - \(preview)\n  - ... and \(resolution.searchedLocations.count - previewCount) more"
        }
        return "\(resolution.detail) Candidate paths checked:\n  - \(preview)"
    }

    private struct CommandProbeResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
    }

    private func firstNonEmptyLine(from value: String) -> String? {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func appendProviderHealthChecks(
        profile: LaunchProfile,
        executable: String,
        statusAppendBlock: @escaping (ToolStatus) -> Void,
        warnings: inout [String]
    ) {
        let definition = profile.agentKind.providerDefinition
        var statuses: [ToolStatus] = []
        appendVersionProbe(
            toolName: definition.kind.displayName,
            executable: executable,
            commandVariants: [["--version"], ["-v"]],
            statuses: &statuses,
            warnings: &warnings
        )

        appendModelCapabilityProbe(
            toolName: definition.kind.displayName,
            executable: executable,
            model: definition.defaultModel(profile),
            expectedFlags: definition.modelFlags,
            statuses: &statuses,
            warnings: &warnings
        )

        appendConfigHint(
            toolName: definition.kind.displayName,
            executable: executable,
            possibleConfigPaths: definition.configPaths,
            possibleEnvKeys: definition.envKeys,
            warnings: &warnings
        )

        for status in statuses {
            statusAppendBlock(status)
        }
    }

    private func appendProviderExecutableCheck(
        profile: LaunchProfile,
        workingDirectory: String,
        statusAppendBlock: @escaping (ToolStatus) -> Void,
        warnings: inout [String]
    ) -> String? {
        let definition = profile.agentKind.providerDefinition
        let candidates = profile.providerExecutableCandidates
        let requested = candidates.first ?? definition.kind.displayName

        guard !candidates.isEmpty else {
            statusAppendBlock(
                ToolStatus(
                    name: definition.kind.displayName,
                    requested: requested,
                    resolved: nil,
                    detail: "No executable was configured for this profile.",
                    isError: true
                )
            )
            return nil
        }

        var resolution: ExecutableResolution?
        var checkedCount = 0
        var failureDetails: [String] = []
        for candidate in candidates {
            let candidateResolution = builder.resolveExecutable(candidate, workingDirectory: workingDirectory)
            checkedCount += 1
            if candidateResolution.isResolved {
                resolution = candidateResolution
                break
            }
            if resolution == nil {
                resolution = candidateResolution
            }
            failureDetails.append("\(checkedCount). \(candidateResolution.requested) -> \(candidateResolution.detail) [\(candidateResolution.source ?? "not found")]")
        }

        let resolutionSummary: String
        if let found = resolution, found.isResolved {
            let candidateSummary = checkedCount > 1
                ? "Checked \(checkedCount) candidates: \(candidates.joined(separator: ", "))."
                : "Checked 1 candidate: \(candidates[0])."
            resolutionSummary = "\(expandedResolutionDetail(found)) \(candidateSummary)"
        } else if let lastResolution = resolution {
            if failureDetails.isEmpty {
                failureDetails = [
                    "\(checkedCount). \(lastResolution.requested) -> \(lastResolution.detail) [\(lastResolution.source ?? "not found")]"
                ]
            }
            resolutionSummary = "No executable was found using \(checkedCount) candidates. Checks: \(failureDetails.joined(separator: "; "))"
        } else {
            resolutionSummary = "No executable was found using candidates: \(candidates.joined(separator: ", "))."
        }

        statusAppendBlock(
            ToolStatus(
                name: definition.kind.displayName,
                requested: requested,
                resolved: resolution?.resolved,
                detail: resolutionSummary,
                isError: resolution?.isResolved != true,
                resolutionSource: resolution?.source
            )
        )

        if let resolved = resolution?.resolved {
            appendProviderHealthChecks(
                profile: profile,
                executable: resolved,
                statusAppendBlock: statusAppendBlock,
                warnings: &warnings
            )
        }

        return resolution?.resolved
    }

    private func hasPath(_ path: String) -> Bool {
        let expanded = NSString(string: path).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }

    private func appendConfigHint(
        toolName: String,
        executable: String,
        possibleConfigPaths: [String],
        possibleEnvKeys: [String],
        warnings: inout [String]
    ) {
        guard !executable.isEmpty else { return }
        let hasConfig = possibleConfigPaths.contains { hasPath($0) }
        let hasEnv = possibleEnvKeys.contains { ProcessInfo.processInfo.environment[$0] != nil && !ProcessInfo.processInfo.environment[$0]!.isEmpty }

        if !hasConfig && !hasEnv {
            warnings.append("\(toolName) appears to have no local auth/session artifacts detected for \(executable). Authentication may still be required before first use.")
        }
    }

    private func appendModelCapabilityProbe(
        toolName: String,
        executable: String,
        model: String,
        expectedFlags: [String],
        statuses: inout [ToolStatus],
        warnings: inout [String]
    ) {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else { return }

        let helpVariants = [["--help"], ["help"], ["-h"]]
        var foundHelp = false
        var matchedOutput: String = ""

        for arguments in helpVariants {
            guard let probe = runCommandProbe(executable: executable, arguments: arguments, timeoutSeconds: 1.6) else {
                continue
            }
            if probe.timedOut {
                warnings.append("\(toolName) model-capability check timed out using `\(toolName.lowercased()) \(arguments.joined(separator: " "))`.")
                return
            }
            let combined = ([probe.stdout, probe.stderr].joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
            if combined.isEmpty {
                continue
            }
            foundHelp = true
            matchedOutput = combined.lowercased()
            break
        }

        if !foundHelp {
            warnings.append("Could not validate \(toolName) model capability before launch from `\(toolName.lowercased()) --help`.")
            return
        }

        let missingFlags = expectedFlags.filter { !matchedOutput.contains($0.lowercased()) }
        if missingFlags.isEmpty {
            statuses.append(
                ToolStatus(
                    name: "\(toolName) model support",
                    requested: "\(toolName.lowercased()) --help",
                    resolved: "supported",
                    detail: "Model argument appears supported by CLI help output.",
                    isError: false,
                    resolutionSource: "runtime probe"
                )
            )
        } else {
            warnings.append("\(toolName) help output did not confirm all model flags (\(missingFlags.joined(separator: ", "))). The configured model `\(normalizedModel)` may be unsupported.")
        }
    }

    private func runCommandProbe(
        executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        timeoutSeconds: Double = 1.4
    ) -> CommandProbeResult? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory, !workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let start = Date()
        while process.isRunning && Date().timeIntervalSince(start) < timeoutSeconds {
            Thread.sleep(forTimeInterval: 0.05)
        }

        var timedOut = false
        if process.isRunning {
            timedOut = true
            process.terminate()
            process.waitUntilExit()
        } else {
            process.waitUntilExit()
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return CommandProbeResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            timedOut: timedOut
        )
    }

    private func appendVersionProbe(
        toolName: String,
        executable: String,
        commandVariants: [[String]],
        statuses: inout [ToolStatus],
        warnings: inout [String]
    ) {
        let commandArgStrings = commandVariants.map { $0.joined(separator: " ") }
        for (index, arguments) in commandVariants.enumerated() {
            guard let probe = runCommandProbe(executable: executable, arguments: arguments) else {
                continue
            }

            if probe.timedOut {
                warnings.append("\(toolName) version check timed out using `\(toolName.lowercased()) \(commandArgStrings[index])`.")
                continue
            }
            guard probe.exitCode == 0 else {
                continue
            }

            let combined = [probe.stdout, probe.stderr].joined(separator: "\n")
            guard let version = firstNonEmptyLine(from: combined) else {
                continue
            }

            statuses.append(
                ToolStatus(
                    name: "\(toolName) version",
                    requested: "\(toolName.lowercased()) \(commandArgStrings[index])",
                    resolved: version,
                    detail: "Detected runtime version for \(toolName) via health probe.",
                    isError: false,
                    resolutionSource: "runtime probe"
                )
            )
            return
        }

        warnings.append("Could not confirm \(toolName) version from quick probe. \(toolName) may still be usable, but runtime diagnostics could not be read.")
    }

    private func appendGeminiPtyModuleStatus(
        nodeExecutable: String,
        workingDirectory: String,
        statuses: inout [ToolStatus],
        warnings: inout [String]
    ) {
        let probeScript = """
        const candidates = ['@lydell/node-pty', 'node-pty'];
        for (const name of candidates) {
          try {
            const resolved = require.resolve(name, { paths: [process.cwd()] });
            console.log(`${name}|${resolved}`);
            process.exit(0);
          } catch {}
        }
        process.exit(1);
        """

        guard let probe = runCommandProbe(
            executable: nodeExecutable,
            arguments: ["-e", probeScript],
            workingDirectory: workingDirectory,
            timeoutSeconds: 1.4
        ) else {
            warnings.append("Could not verify Gemini PTY backend availability from Node. Automation runner may still fall back to direct child-process mode.")
            return
        }

        if probe.timedOut {
            warnings.append("Gemini PTY backend check timed out. Automation runner may still fall back to direct child-process mode.")
            return
        }

        if probe.exitCode == 0, let line = firstNonEmptyLine(from: probe.stdout) {
            let components = line.split(separator: "|", maxSplits: 1).map(String.init)
            let packageName = components.first ?? "node-pty"
            let resolvedPath = components.count > 1 ? components[1] : line
            statuses.append(
                ToolStatus(
                    name: "Gemini PTY backend",
                    requested: "@lydell/node-pty or node-pty",
                    resolved: packageName,
                    detail: "Automation runner will use PTY mode via \(packageName) resolved from \(resolvedPath).",
                    isError: false,
                    resolutionSource: "runtime probe"
                )
            )
            return
        }

        statuses.append(
            ToolStatus(
                name: "Gemini PTY backend",
                requested: "@lydell/node-pty or node-pty",
                resolved: nil,
                detail: "No PTY package was found from the workspace. Automation runner will fall back to plain child-process mode, so hotkeys and prompt automation will be unavailable.\nInstall one of these in the launch workspace:\ncd \(workingDirectory)\nnpm install @lydell/node-pty\nor\ncd \(workingDirectory)\nnpm install node-pty",
                isError: false,
                resolutionSource: "runtime probe"
            )
        )
        warnings.append("Gemini automation runner could not find `@lydell/node-pty` or `node-pty` from the workspace. Run `npm install @lydell/node-pty` (or `npm install node-pty`) in `\(workingDirectory)` to enable PTY automation and hotkeys.")
    }

    private func appendOllamaModelCheck(
        profile: LaunchProfile,
        executable: String,
        statuses: inout [ToolStatus],
        warnings: inout [String]
    ) {
        let model = profile.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        let normalizedModel = model.lowercased()

        guard let probe = runCommandProbe(executable: executable, arguments: ["list"], timeoutSeconds: 2.0) else {
            warnings.append("Could not verify local Ollama models; `ollama list` did not return within a quick probe window.")
            return
        }

        if probe.timedOut {
            warnings.append("Ollama model availability check timed out for `\(model)`.")
            return
        }

        guard probe.exitCode == 0 else {
            warnings.append("Ollama model availability check command failed (exit code: \(probe.exitCode)).")
            return
        }

        let lines = probe.stdout.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let hasModel = lines.contains { line in
            let parts = line.split { $0 == " " || $0 == "\t" }.map(String.init)
            guard let first = parts.first?.lowercased() else { return false }
            return first == normalizedModel
        }

        if hasModel {
            statuses.append(
                ToolStatus(
                    name: "Ollama model",
                    requested: "ollama list",
                    resolved: model,
                    detail: "Model is present in local Ollama catalog.",
                    isError: false,
                    resolutionSource: "runtime probe"
                )
            )
        } else {
            warnings.append("Ollama model `\(model)` is not present in local model list. Launch will still proceed, but model pull may be required.")
        }
    }

    func inspect(profile: LaunchProfile, settings: AppSettings) -> (statuses: [ToolStatus], warnings: [String]) {
        var statuses: [ToolStatus] = []
        var warnings: [String] = []
        let resolvedITermPath = iTermRuntime.applicationURL()?.path
        let iTermAvailable = resolvedITermPath != nil
        let iTermDetail: String
        if let resolvedITermPath {
            let runningDetail = iTermRuntime.isRunning() ? "currently running" : "ready to launch"
            iTermDetail = "Installed at \(resolvedITermPath) and \(runningDetail)."
        } else {
            iTermDetail = "Not found in Launch Services or standard /Applications locations."
        }
        statuses.append(ToolStatus(name: "iTerm2", requested: ITerm2RuntimeService.bundleIdentifier, resolved: resolvedITermPath, detail: iTermDetail, isError: !iTermAvailable))
        let osascriptAvailable = FileManager.default.isExecutableFile(atPath: "/usr/bin/osascript")
        statuses.append(ToolStatus(name: "AppleScript engine", requested: "/usr/bin/osascript", resolved: osascriptAvailable ? "/usr/bin/osascript" : nil, detail: osascriptAvailable ? "System AppleScript runner is available." : "/usr/bin/osascript is missing.", isError: !osascriptAvailable))

        let workspacePath = profile.expandedWorkingDirectory
        var isDirectory: ObjCBool = false
        let workspaceOK = FileManager.default.fileExists(atPath: workspacePath, isDirectory: &isDirectory) && isDirectory.boolValue
        statuses.append(ToolStatus(name: "Workspace", requested: workspacePath, resolved: workspaceOK ? workspacePath : nil, detail: workspaceOK ? "Directory exists" : "Missing directory", isError: !workspaceOK))

        let resolverSnapshot = builder.executableResolverSnapshot()
        let processPath = resolverSnapshot.processPath
        let pathHelperPath = resolverSnapshot.pathHelperPath
        let loginShellPath = resolverSnapshot.loginShellPath
        let pathHelperStatus = resolverSnapshot.pathHelperStatus
        let loginShellStatus = resolverSnapshot.loginShellStatus
        let resolverDetailLines = [
            "process PATH: \(processPath.isEmpty ? "not set" : processPath)",
            "path_helper PATH: \(pathHelperPath.isEmpty ? "not available" : pathHelperPath)",
            "path_helper status: \(pathHelperStatus)",
            "login shell PATH: \(loginShellPath.isEmpty ? "not available" : loginShellPath)",
            "login shell status: \(loginShellStatus)"
        ]
        let resolverDetail = resolverDetailLines.joined(separator: "\n")
        let resolverSources = resolverSnapshot.sourceSummary.isEmpty ? "No auxiliary resolver sources available." : resolverSnapshot.sourceSummary.joined(separator: ", ")
        statuses.append(
            ToolStatus(
                name: "Executable resolver context",
                requested: "PATH",
                resolved: nil,
                detail: "Resolver sources: \(resolverSources).\n\(resolverDetail)",
                isError: false
            )
        )

        if profile.openWorkspaceInFinderOnLaunch {
            statuses.append(ToolStatus(name: "Finder post-launch", requested: workspacePath, resolved: workspaceOK ? workspacePath : nil, detail: workspaceOK ? "Finder can reveal the selected workspace." : "Workspace missing", isError: !workspaceOK))
        }
        if profile.openWorkspaceInVSCodeOnLaunch {
            let available = companionLauncher.isAvailable(.visualStudioCode)
            statuses.append(ToolStatus(name: "VS Code post-launch", requested: "com.microsoft.VSCode", resolved: available ? "Installed" : nil, detail: available ? "Visual Studio Code is available for workspace open." : "Visual Studio Code app not found", isError: !available))
        }

        if settings.mongoMonitoring.enabled {
            statuses.append(contentsOf: MonitoringDiagnosticsService().inspect(settings: settings.mongoMonitoring))
        }

        switch profile.agentKind {
        case .gemini:
            let workingDirectory = profile.expandedWorkingDirectory
            let wrapperResolution = builder.resolveGeminiWrapper(profile: profile, workingDirectory: workingDirectory)
            let runnerResolution = builder.resolveAutomationRunner(profile: profile, settings: settings, workingDirectory: workingDirectory)
            statuses.append(
                ToolStatus(
                    name: "Gemini wrapper",
                    requested: wrapperResolution.requested,
                    resolved: wrapperResolution.resolved,
                    detail: expandedResolutionDetail(wrapperResolution),
                    isError: !wrapperResolution.isResolved,
                    resolutionSource: wrapperResolution.source
                )
            )
            if let wrapperResolved = wrapperResolution.resolved {
                appendProviderHealthChecks(
                    profile: profile,
                    executable: wrapperResolved,
                    statusAppendBlock: { statuses.append($0) },
                    warnings: &warnings
                )
            }
            let node = builder.resolvedNodeExecutable(profile: profile, settings: settings)
            let resolvedRunner = builder.resolvedRunnerPath(profile: profile, settings: settings)
            let runner = resolvedRunner.isEmpty ? "Not configured" : resolvedRunner
            let runnerResolved = runnerResolution.resolved
            let nodeResolution = builder.resolveExecutable(node, workingDirectory: workingDirectory)
            let runnerConfigured = !resolvedRunner.isEmpty
            let runnerAvailable = runnerResolution.isResolved

            if profile.geminiLaunchMode == .automationRunner {
                statuses.append(
                    ToolStatus(
                        name: "Automation runner",
                        requested: runnerConfigured ? runner : "Not configured",
                        resolved: runnerResolved,
                        detail: runnerAvailable
                            ? "Automation runner will be used."
                            : (runnerConfigured
                                ? "Runner not found. \(runnerResolution.detail) Launcher will fall back to the direct wrapper.\n\(expandedResolutionDetail(runnerResolution))"
                                : "No runner configured. Launcher will fall back to the direct wrapper."),
                        isError: false,
                        resolutionSource: runnerResolution.source
                    )
                )
                statuses.append(
                    ToolStatus(
                        name: "Node",
                        requested: node,
                        resolved: nodeResolution.resolved,
                        detail: runnerAvailable
                            ? expandedResolutionDetail(nodeResolution)
                            : "Not required because the automation runner is unavailable and launch will use the direct wrapper.",
                        isError: runnerAvailable && !nodeResolution.isResolved,
                        resolutionSource: nodeResolution.source
                    )
                )
                if let nodeResolved = nodeResolution.resolved {
                    appendVersionProbe(
                        toolName: "Node",
                        executable: nodeResolved,
                        commandVariants: [["--version"], ["-v"]],
                        statuses: &statuses,
                        warnings: &warnings
                    )
                    appendGeminiPtyModuleStatus(
                        nodeExecutable: nodeResolved,
                        workingDirectory: workingDirectory,
                        statuses: &statuses,
                        warnings: &warnings
                    )
                }
            } else {
                statuses.append(
                    ToolStatus(
                        name: "Node",
                        requested: node,
                        resolved: nodeResolution.resolved,
                        detail: "Not required in direct-wrapper mode.",
                        isError: false,
                        resolutionSource: nodeResolution.source
                    )
                )
                if let nodeResolved = nodeResolution.resolved {
                    appendVersionProbe(
                        toolName: "Node",
                        executable: nodeResolved,
                        commandVariants: [["--version"], ["-v"]],
                        statuses: &statuses,
                        warnings: &warnings
                    )
                }
                    if runnerConfigured {
                        statuses.append(
                            ToolStatus(
                                name: "Automation runner",
                                requested: runner,
                                resolved: runnerResolved,
                                detail: runnerResolution.isResolved
                                    ? "Available, but direct-wrapper mode is selected."
                                    : "Configured path not found. Direct-wrapper mode does not require it.\n\(expandedResolutionDetail(runnerResolution))",
                                isError: false,
                                resolutionSource: runnerResolution.source
                            )
                        )
                    }
            }
        case .copilot, .codex, .claudeBypass, .kiroCLI, .ollamaLaunch:
            let workingDirectory = profile.expandedWorkingDirectory
            let resolved = appendProviderExecutableCheck(
                profile: profile,
                workingDirectory: workingDirectory,
                statusAppendBlock: { statuses.append($0) },
                warnings: &warnings
            )
            if profile.agentKind == .ollamaLaunch, let resolved = resolved {
                appendOllamaModelCheck(profile: profile, executable: resolved, statuses: &statuses, warnings: &warnings)
            }

        case .aider:
            let workingDirectory = profile.expandedWorkingDirectory
            _ = appendProviderExecutableCheck(
                profile: profile,
                workingDirectory: workingDirectory,
                statusAppendBlock: { statuses.append($0) },
                warnings: &warnings
            )
        }

        return (statuses: statuses, warnings: warnings)
    }
}


struct WorkspaceCompanionLauncher {
    private let fileManager = FileManager.default

    func isAvailable(_ app: WorkspaceCompanionApp) -> Bool {
        switch app {
        case .finder:
            return true
        case .visualStudioCode:
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil
        }
    }

    func availableApps(for profile: LaunchProfile) -> [WorkspaceCompanionApp] {
        profile.workspaceCompanionApps.filter { isAvailable($0) }
    }

    func unavailableApps(for profile: LaunchProfile) -> [WorkspaceCompanionApp] {
        profile.workspaceCompanionApps.filter { !isAvailable($0) }
    }

    func perform(actions: [PostLaunchAction]) -> [String] {
        var performed: [String] = []
        for action in actions {
            if perform(action: action) {
                performed.append(action.label)
            }
        }
        return performed
    }

    @discardableResult
    func perform(action: PostLaunchAction) -> Bool {
        let expandedPath = NSString(string: action.path).expandingTildeInPath
        guard fileManager.fileExists(atPath: expandedPath) else { return false }
        let url = URL(fileURLWithPath: expandedPath)

        switch action.app {
        case .finder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true
        case .visualStudioCode:
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") else {
                return false
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, _ in }
            return true
        }
    }
}

struct PreflightService {
    let planner = LaunchPlanner()
    let discovery = ToolDiscoveryService()
    let companionLauncher = WorkspaceCompanionLauncher()
    private let commandBuilder = CommandBuilder()

    func run(profile: LaunchProfile, settings: AppSettings, allProfiles: [LaunchProfile]) -> PreflightCheck {
        var check = PreflightCheck()
        let discoveryResult = discovery.inspect(profile: profile, settings: settings)
        check.statuses = discoveryResult.statuses
        check.warnings.append(contentsOf: discoveryResult.warnings)

        if !check.statuses.filter({ $0.isError }).isEmpty {
            check.errors.append(contentsOf: check.statuses.filter { $0.isError }.map { $0.name + ": " + $0.detail })
        }

        check.warnings.append(contentsOf: profile.agentKind.defaultCautionMessages(for: profile))
        if profile.autoLaunchCompanions && profile.companionProfileIDs.isEmpty {
            check.warnings.append("Companion launch is enabled but no companion profiles are selected.")
        }
        if profile.autoLaunchCompanions {
            let existing = Set(allProfiles.map(\.id))
            let missing = profile.companionProfileIDs.filter { !existing.contains($0) }
            if !missing.isEmpty {
                check.warnings.append("One or more companion profiles no longer exist.")
            }
        }
        if let presetID = profile.environmentPresetID {
            if settings.environmentPresets.first(where: { $0.id == presetID }) == nil {
                check.warnings.append("Selected environment preset no longer exists.")
            }
        }
        if let presetID = profile.bootstrapPresetID {
            if settings.shellBootstrapPresets.first(where: { $0.id == presetID }) == nil {
                check.warnings.append("Selected shell bootstrap preset no longer exists.")
            }
        }
        if profile.openWorkspaceInVSCodeOnLaunch && !companionLauncher.isAvailable(.visualStudioCode) {
            check.warnings.append("Visual Studio Code will not open after launch because the app is not installed or not visible to Launch Services.")
        }
        if profile.tabLaunchDelayMs < 100 {
            check.warnings.append("Tab launch delay below 100 ms can cause iTerm2 tab creation race conditions.")
        }
        if settings.mongoMonitoring.enabled && settings.mongoMonitoring.captureMode.usesScriptKeyLogging {
            check.warnings.append("Terminal transcript monitoring is set to capture keyboard input and terminal output. Passwords or secrets typed in the terminal can be recorded.")
        }
        if settings.mongoMonitoring.enabled && settings.mongoMonitoring.enableMongoWrites && settings.mongoMonitoring.trimmedConnectionURL.isEmpty {
            check.errors.append("MongoDB monitoring is enabled but the connection URL is empty.")
        }
        if settings.mongoMonitoring.enabled && settings.mongoMonitoring.enableMongoWrites && settings.mongoMonitoring.mongoConnection.isLocal {
            if commandBuilder.resolvedExecutable(settings.mongoMonitoring.mongodExecutable) == nil {
                check.errors.append("Local MongoDB URL is configured, but mongod executable was not found. Set it in Monitoring settings.")
            }
            if settings.mongoMonitoring.expandedLocalDataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                check.errors.append("Local MongoDB URL is configured, but local Mongo data directory is empty.")
            } else if !FileManager.default.fileExists(atPath: settings.mongoMonitoring.expandedLocalDataDirectory) {
                check.warnings.append("Local Mongo data directory does not exist yet; it will be created on first monitoring write.")
            }
        }

        do {
            _ = try planner.buildPlan(primary: profile, allProfiles: allProfiles, settings: settings)
        } catch {
            check.errors.append(error.localizedDescription)
        }

        return check
    }

    func run(workbench: LaunchWorkbench, profiles: [LaunchProfile], bookmarks: [WorkspaceBookmark], settings: AppSettings) -> PreflightCheck {
        var check = PreflightCheck()
        let profileLookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let bookmarkLookup = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0) })

        if workbench.profileIDs.isEmpty {
            check.errors.append("Workbench has no profiles selected.")
        }

        let missingProfiles = workbench.profileIDs.filter { profileLookup[$0] == nil }
        if !missingProfiles.isEmpty {
            check.warnings.append("One or more workbench profiles no longer exist.")
        }

        if let sharedBookmarkID = workbench.sharedBookmarkID {
            if bookmarkLookup[sharedBookmarkID] == nil {
                check.errors.append("Workbench shared workspace no longer exists.")
            }
        }

        for profileID in workbench.profileIDs {
            guard var profile = profileLookup[profileID] else { continue }
            if let sharedBookmarkID = workbench.sharedBookmarkID, let bookmark = bookmarkLookup[sharedBookmarkID] {
                profile.workingDirectory = bookmark.path
                profile.tags = Array(Set(profile.tags + bookmark.tags)).sorted()
            }
            let inspection = discovery.inspect(profile: profile, settings: settings)
            check.warnings.append(contentsOf: profile.agentKind.defaultCautionMessages(for: profile).map { "\(profile.name): \($0)" })
            check.warnings.append(contentsOf: inspection.warnings.map { "\(profile.name): \($0)" })
            let statuses = inspection.statuses.map {
                ToolStatus(
                    name: "\(profile.name) • \($0.name)",
                    requested: $0.requested,
                    resolved: $0.resolved,
                    detail: $0.detail,
                    isError: $0.isError,
                    resolutionSource: $0.resolutionSource
                )
            }
            check.statuses.append(contentsOf: statuses)
        }

        if !check.statuses.filter({ $0.isError }).isEmpty {
            check.errors.append(contentsOf: check.statuses.filter { $0.isError }.map { $0.name + ": " + $0.detail })
        }
        if settings.mongoMonitoring.enabled && settings.mongoMonitoring.captureMode.usesScriptKeyLogging {
            check.warnings.append("Terminal transcript monitoring is set to capture keyboard input and terminal output for launched workbench tabs.")
        }
        if settings.mongoMonitoring.enabled && settings.mongoMonitoring.enableMongoWrites && settings.mongoMonitoring.trimmedConnectionURL.isEmpty {
            check.errors.append("MongoDB monitoring is enabled but the connection URL is empty.")
        }
        if settings.mongoMonitoring.enabled && settings.mongoMonitoring.enableMongoWrites && settings.mongoMonitoring.mongoConnection.isLocal {
            if commandBuilder.resolvedExecutable(settings.mongoMonitoring.mongodExecutable) == nil {
                check.errors.append("Local MongoDB URL is configured, but mongod executable was not found. Set it in Monitoring settings.")
            }
            if settings.mongoMonitoring.expandedLocalDataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                check.errors.append("Local MongoDB URL is configured, but local Mongo data directory is empty.")
            }
        }

        do {
            _ = try planner.buildWorkbenchPlan(workbench: workbench, profiles: profiles, bookmarks: bookmarks, settings: settings)
        } catch {
            check.errors.append(error.localizedDescription)
        }

        return check
    }

}

struct AppleScriptExecutionResult {
    var output: String
    var errorOutput: String
    var terminationStatus: Int32
}

struct AppleScriptExecutionService {
    func execute(source: String) throws -> AppleScriptExecutionResult {
        let osascriptPath = "/usr/bin/osascript"
        guard FileManager.default.isExecutableFile(atPath: osascriptPath) else {
            throw LauncherError.appleScript("AppleScript runner is missing: \(osascriptPath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: osascriptPath)
        process.arguments = ["-s", "h"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe

        try process.run()
        if let data = source.data(using: .utf8) {
            try? inputPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try? inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let errorOutput = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            let message = [errorOutput, output]
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
            throw LauncherError.appleScript(message.isEmpty ? "osascript failed with exit code \(process.terminationStatus)." : message)
        }

        return AppleScriptExecutionResult(output: output, errorOutput: errorOutput, terminationStatus: process.terminationStatus)
    }
}

struct ITerm2ProfileDiscoveryResult {
    var names: [String]
    var sourceDescription: String
}

struct ITerm2RuntimeService {
    static let bundleIdentifier = "com.googlecode.iterm2"
    static let appleScriptApplicationReference = "application id \"com.googlecode.iterm2\""

    private let fileManager = FileManager.default

    func applicationURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) {
            return url
        }

        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let candidates = [
            URL(fileURLWithPath: "/Applications/iTerm.app"),
            URL(fileURLWithPath: "/Applications/Utilities/iTerm.app"),
            homeApplications.appendingPathComponent("iTerm.app", isDirectory: true)
        ]

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    func isInstalled() -> Bool {
        applicationURL() != nil
    }

    func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    @MainActor
    @discardableResult
    func ensureRunning() throws -> URL {
        guard let url = applicationURL() else {
            throw LauncherError.validation("iTerm2 is not installed or could not be located.")
        }

        if isRunning() {
            return url
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false

        let launchErrorBox = LockedLaunchErrorBox()
        let didReceiveCompletionBox = LockedBooleanBox()

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            launchErrorBox.set(error)
            didReceiveCompletionBox.set(true)
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if isRunning() {
                return url
            }
            if let launchError = launchErrorBox.get() {
                throw LauncherError.validation("Failed to launch iTerm2: \(launchError.localizedDescription)")
            }
            if didReceiveCompletionBox.get() {
                break
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if !isRunning() {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.35))
        }

        if let launchError = launchErrorBox.get() {
            throw LauncherError.validation("Failed to launch iTerm2: \(launchError.localizedDescription)")
        }

        if !isRunning() {
            throw LauncherError.validation("iTerm2 did not finish launching in time.")
        }

        return url
    }

    func diagnosticSnapshot(profileNames: [String], discoverySource: String) -> DiagnosticITermSnapshot {
        let appURL = applicationURL()
        return DiagnosticITermSnapshot(
            applicationURL: appURL?.path,
            bundleIdentifier: Self.bundleIdentifier,
            isInstalled: appURL != nil,
            isRunning: isRunning(),
            profileDiscoverySource: discoverySource,
            profileNames: profileNames
        )
    }
}

struct ITerm2ProfileService {
    private let runtime = ITerm2RuntimeService()
    private let executor = AppleScriptExecutionService()

    func fetchProfileNames() throws -> [String] {
        try fetchProfiles().names
    }

    func fetchProfiles() throws -> ITerm2ProfileDiscoveryResult {
        guard runtime.isInstalled() else {
            return ITerm2ProfileDiscoveryResult(names: [], sourceDescription: "iTerm2 not installed")
        }

        if let preferenceResult = try readProfileNamesFromPreferences(), !preferenceResult.names.isEmpty {
            return preferenceResult
        }

        return try fetchProfileNamesUsingAppleScript()
    }

    private func readProfileNamesFromPreferences() throws -> ITerm2ProfileDiscoveryResult? {
        if let names = profileNamesFromDefaults(), !names.isEmpty {
            return ITerm2ProfileDiscoveryResult(names: names, sourceDescription: "Preferences domain")
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Library/Preferences/com.googlecode.iterm2.plist",
            "\(home)/Library/Containers/com.googlecode.iterm2/Data/Library/Preferences/com.googlecode.iterm2.plist"
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            let data = try Data(contentsOf: URL(fileURLWithPath: candidate))
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let names = extractProfileNames(from: plist)
            if !names.isEmpty {
                return ITerm2ProfileDiscoveryResult(names: names, sourceDescription: "Preferences plist: \(candidate)")
            }
        }

        return nil
    }

    private func profileNamesFromDefaults() -> [String]? {
        guard let array = UserDefaults(suiteName: ITerm2RuntimeService.bundleIdentifier)?.array(forKey: "New Bookmarks") else {
            return nil
        }
        let names = extractProfileNames(fromBookmarkArray: array)
        return names.isEmpty ? nil : names
    }

    private func extractProfileNames(from plist: Any) -> [String] {
        if let dictionary = plist as? [String: Any], let bookmarks = dictionary["New Bookmarks"] as? [Any] {
            return extractProfileNames(fromBookmarkArray: bookmarks)
        }
        if let bookmarks = plist as? [Any] {
            return extractProfileNames(fromBookmarkArray: bookmarks)
        }
        return []
    }

    private func extractProfileNames(fromBookmarkArray bookmarks: [Any]) -> [String] {
        let names = bookmarks.compactMap { item -> String? in
            guard let dictionary = item as? [String: Any] else { return nil }
            let name = (dictionary["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name?.isEmpty == false) ? name : nil
        }
        return Array(Set(names)).sorted()
    }

    private func fetchProfileNamesUsingAppleScript() throws -> ITerm2ProfileDiscoveryResult {
        let scripts: [(String, String)] = [
            (
                "name of every profile",
                """
                tell \(ITerm2RuntimeService.appleScriptApplicationReference)
                  set profileNames to name of every profile
                  set AppleScript's text item delimiters to linefeed
                  return profileNames as text
                end tell
                """
            ),
            (
                "name of profiles",
                """
                tell \(ITerm2RuntimeService.appleScriptApplicationReference)
                  set profileNames to name of profiles
                  set AppleScript's text item delimiters to linefeed
                  return profileNames as text
                end tell
                """
            )
        ]

        var failures: [String] = []
        for (label, source) in scripts {
            do {
                let result = try executor.execute(source: source)
                let names = parseProfileNames(from: result.output)
                if !names.isEmpty {
                    return ITerm2ProfileDiscoveryResult(names: names, sourceDescription: "AppleScript (\(label))")
                }
            } catch {
                failures.append("\(label): \(error.localizedDescription)")
            }
        }

        throw LauncherError.appleScript("Failed to read iTerm2 profiles. \(failures.joined(separator: " | "))")
    }

    private func parseProfileNames(from output: String) -> [String] {
        guard !output.isEmpty else { return [] }
        let cleaned = output
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "\"", with: "")

        let pieces = cleaned
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(Set(pieces)).sorted()
    }
}

enum LaunchLoggerBridge {
    static func log(_ logger: LaunchLogger?, _ level: LogLevel, _ message: String, category: LogCategory = .app, details: String? = nil) {
        guard let logger else { return }
        Task { @MainActor in
            logger.log(level, message, category: category, details: details)
        }
    }

    static func debug(_ logger: LaunchLogger?, _ message: String, category: LogCategory = .app, details: String? = nil) {
        log(logger, .debug, message, category: category, details: details)
    }
}

struct ITerm2Launcher {
    private let runtime = ITerm2RuntimeService()
    private let executor = AppleScriptExecutionService()

    func diagnosticSnapshot(discoveredProfiles: [String], discoverySource: String) -> DiagnosticITermSnapshot {
        runtime.diagnosticSnapshot(profileNames: discoveredProfiles, discoverySource: discoverySource)
    }

    @MainActor
    func launch(plan: PlannedLaunch, logger: LaunchLogger? = nil, observability: ObservabilitySettings = ObservabilitySettings()) throws {
        let delaySeconds = max(0.05, Double(plan.tabLaunchDelayMs) / 1000.0)
        LaunchLoggerBridge.log(logger, .info, "Launching \(plan.items.count) iTerm2 session(s).", category: .iterm, details: "tabDelayMs=\(plan.tabLaunchDelayMs)")
        for (index, item) in plan.items.enumerated() {
            let mode: ITermOpenMode = index == 0 ? item.openMode : .newTab
            LaunchLoggerBridge.debug(
                logger,
                "Dispatching iTerm2 launch item \(index + 1)/\(plan.items.count).",
                category: .iterm,
                details: "profile=\(item.profileName) • mode=\(mode.displayName) • iTermProfile=\(item.iTermProfile.isEmpty ? "<default>" : item.iTermProfile) • commandPreview=\(commandPreview(item.command))"
            )
            try launchRaw(command: item.command, openMode: mode, iTermProfile: item.iTermProfile, logger: logger, observability: observability)
            if index < plan.items.count - 1 {
                Thread.sleep(forTimeInterval: delaySeconds)
            }
        }
    }

    @MainActor
    func launchRaw(command: String, openMode: ITermOpenMode, iTermProfile: String, logger: LaunchLogger? = nil, observability: ObservabilitySettings = ObservabilitySettings()) throws {
        let profileNameForLog = iTermProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "<default>" : iTermProfile
        LaunchLoggerBridge.debug(
            logger,
            "Preparing iTerm2 launch request.",
            category: .iterm,
            details: "mode=\(openMode.displayName) • iTermProfile=\(profileNameForLog) • runningBefore=\(runtime.isRunning()) • commandPreview=\(commandPreview(command))"
        )

        let resolvedURL: URL
        do {
            resolvedURL = try runtime.ensureRunning()
            LaunchLoggerBridge.debug(
                logger,
                "Resolved iTerm2 runtime.",
                category: .iterm,
                details: "appPath=\(resolvedURL.path) • runningAfterEnsure=\(runtime.isRunning())"
            )
        } catch {
            LaunchLoggerBridge.log(logger, .error, "Failed to ensure iTerm2 is running.", category: .iterm, details: error.localizedDescription)
            throw error
        }

        let source = buildAppleScript(command: command, openMode: openMode, iTermProfile: iTermProfile)
        if observability.includeAppleScriptInLogs {
            LaunchLoggerBridge.debug(logger, "Prepared iTerm2 AppleScript payload.", category: .iterm, details: source)
        }

        do {
            let result = try executor.execute(source: source)
            let executionDetails = [
                "appPath=\(resolvedURL.path)",
                result.output.isEmpty ? nil : "stdout=\(result.output)",
                result.errorOutput.isEmpty ? nil : "stderr=\(result.errorOutput)",
                "exitCode=\(result.terminationStatus)"
            ].compactMap { $0 }.joined(separator: " • ")
            LaunchLoggerBridge.debug(logger, "iTerm2 AppleScript execution finished.", category: .iterm, details: executionDetails)
        } catch {
            LaunchLoggerBridge.log(
                logger,
                .error,
                "iTerm2 AppleScript execution failed.",
                category: .iterm,
                details: "mode=\(openMode.displayName) • iTermProfile=\(profileNameForLog) • appPath=\(resolvedURL.path) • error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    func buildAppleScript(plan: PlannedLaunch) -> String {
        let delaySeconds = max(0.05, Double(plan.tabLaunchDelayMs) / 1000.0)
        guard let first = plan.items.first else {
            return """
            tell \(ITerm2RuntimeService.appleScriptApplicationReference)
              activate
            end tell
            """
        }

        var lines: [String] = [
            "tell \(ITerm2RuntimeService.appleScriptApplicationReference)",
            "  activate"
        ]
        lines.append(contentsOf: indentedLines(for: openSnippet(command: first.command, openMode: first.openMode, iTermProfile: first.iTermProfile), spaces: 2))

        for item in plan.items.dropFirst() {
            lines.append(String(format: "  delay %.2f", delaySeconds))
            lines.append(contentsOf: indentedLines(for: openSnippet(command: item.command, openMode: .newTab, iTermProfile: item.iTermProfile), spaces: 2))
        }

        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    func buildAppleScript(command: String, openMode: ITermOpenMode, iTermProfile: String) -> String {
        let openBlock = openSnippet(command: command, openMode: openMode, iTermProfile: iTermProfile)
        var lines = [
            "tell \(ITerm2RuntimeService.appleScriptApplicationReference)",
            "  activate"
        ]
        lines.append(contentsOf: indentedLines(for: openBlock, spaces: 2))
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    private func openSnippet(command: String, openMode: ITermOpenMode, iTermProfile: String) -> String {
        let scriptPath = materializeLaunchScript(command: command)
        let escapedPath = appleScriptQuote(scriptPath)
        let escapedProfile = appleScriptQuote(iTermProfile)
        let useDefaultProfile = iTermProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let createWindow = useDefaultProfile
            ? "create window with default profile command \"\(escapedPath)\""
            : "create window with profile \"\(escapedProfile)\" command \"\(escapedPath)\""
        let createTab = useDefaultProfile
            ? "create tab with default profile command \"\(escapedPath)\""
            : "create tab with profile \"\(escapedProfile)\" command \"\(escapedPath)\""

        switch openMode {
        case .newWindow:
            return createWindow
        case .newTab:
            return """
            if (count of windows) = 0 then
              \(createWindow)
            else
              tell current window
                \(createTab)
              end tell
            end if
            """
        }
    }

    private func materializeLaunchScript(command: String) -> String {
        LaunchScriptMaterializer.materialize(command: command)
    }

    private func commandPreview(_ command: String, limit: Int = 500) -> String {
        let compact = command
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count <= limit {
            return compact
        }
        return String(compact.prefix(limit)) + "…"
    }

    private func indentedLines(for block: String, spaces: Int) -> [String] {
        let prefix = String(repeating: " ", count: spaces)
        return block.split(separator: "\n", omittingEmptySubsequences: false).map { prefix + $0 }
    }

    private func appleScriptQuote(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum LaunchScriptMaterializer {
    static func materialize(command: String) -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let file = dir.appendingPathComponent("clilauncher-launch-\(UUID().uuidString).sh")
        let body = """
        #!/bin/zsh -l
        [ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"
        \(command)
        """
        do {
            try body.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        } catch {
            // If write fails, the terminal will surface the error.
        }
        return file.path
    }
}

struct TerminalAppLauncher {
    private let executor = AppleScriptExecutionService()

    @MainActor
    func launch(plan: PlannedLaunch, logger: LaunchLogger? = nil, observability: ObservabilitySettings = ObservabilitySettings()) throws {
        let delaySeconds = max(0.05, Double(plan.tabLaunchDelayMs) / 1000.0)
        LaunchLoggerBridge.log(logger, .info, "Launching \(plan.items.count) Terminal.app session(s).", category: .iterm, details: "tabDelayMs=\(plan.tabLaunchDelayMs)")
        for (index, item) in plan.items.enumerated() {
            let scriptPath = LaunchScriptMaterializer.materialize(command: item.command)
            let source = buildAppleScript(scriptPath: scriptPath)
            do {
                _ = try executor.execute(source: source)
                LaunchLoggerBridge.debug(logger, "Terminal.app AppleScript executed.", category: .iterm, details: "profile=\(item.profileName) • script=\(scriptPath)")
            } catch {
                LaunchLoggerBridge.log(logger, .error, "Terminal.app AppleScript failed.", category: .iterm, details: error.localizedDescription)
                throw error
            }
            if index < plan.items.count - 1 {
                Thread.sleep(forTimeInterval: delaySeconds)
            }
        }
    }

    private func buildAppleScript(scriptPath: String) -> String {
        let escaped = scriptPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Terminal"
          activate
          do script "\(escaped)"
        end tell
        """
    }
}

struct TerminalLauncherDispatcher {
    private let iterm = ITerm2Launcher()
    private let terminal = TerminalAppLauncher()

    @MainActor
    func launch(plan: PlannedLaunch, logger: LaunchLogger? = nil, observability: ObservabilitySettings = ObservabilitySettings()) throws {
        guard !plan.items.isEmpty else { return }
        let groups = groupContiguous(items: plan.items)
        for group in groups {
            let subPlan = PlannedLaunch(items: group.items, postLaunchActions: [], tabLaunchDelayMs: plan.tabLaunchDelayMs)
            switch group.app {
            case .iterm2:
                try iterm.launch(plan: subPlan, logger: logger, observability: observability)
            case .terminal:
                try terminal.launch(plan: subPlan, logger: logger, observability: observability)
            }
        }
    }

    func buildAppleScript(plan: PlannedLaunch) -> String {
        iterm.buildAppleScript(plan: plan)
    }

    func diagnosticSnapshot(discoveredProfiles: [String], discoverySource: String) -> DiagnosticITermSnapshot {
        iterm.diagnosticSnapshot(discoveredProfiles: discoveredProfiles, discoverySource: discoverySource)
    }

    private struct Group { var app: TerminalApp; var items: [PlannedLaunchItem] }

    private func groupContiguous(items: [PlannedLaunchItem]) -> [Group] {
        var groups: [Group] = []
        for item in items {
            if !groups.isEmpty, groups[groups.count - 1].app == item.terminalApp {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(Group(app: item.terminalApp, items: [item]))
            }
        }
        return groups
    }
}

struct LauncherExportService {
    private let launcher = ITerm2Launcher()

    @MainActor
    func exportLauncherScript(plan: PlannedLaunch, suggestedName: String) throws -> URL {
        guard let chosenURL = FilePanelService.saveFile(suggestedName: suggestedName, allowedContentTypes: [.plainText]) else {
            throw LauncherError.validation("Export cancelled.")
        }

        let finalURL: URL
        if chosenURL.pathExtension.lowercased() == "command" {
            finalURL = chosenURL
        } else {
            finalURL = chosenURL.deletingPathExtension().appendingPathExtension("command")
        }

        let appleScript = launcher.buildAppleScript(plan: plan)
        let script = """
        #!/bin/zsh
        set -e
        /usr/bin/osascript <<'APPLESCRIPT'
        \(appleScript)
        APPLESCRIPT
        """
        try script.write(to: finalURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: finalURL.path)
        return finalURL
    }
}

@MainActor
enum FilePanelService {

    static func chooseDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func chooseFile(allowedContentTypes: [UTType]) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedContentTypes
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func saveFile(suggestedName: String, allowedContentTypes: [UTType]) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = allowedContentTypes
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

enum ClipboardService {
    static func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
