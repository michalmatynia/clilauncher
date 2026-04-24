import Foundation

struct CommandBuilder {
    private static let geminiHoldOpenExitCode = 86
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
        let effectiveProfile = profile.preparedForLaunch()
        let workingDirectory = effectiveProfile.expandedWorkingDirectory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LauncherError.validation("Working directory does not exist: \(workingDirectory)")
        }

        let env = buildEnvironment(profile: effectiveProfile, settings: settings)
        let executableAndArgs = try buildExecutableAndArgs(profile: effectiveProfile, settings: settings)

        let prefix = env.isEmpty ? "" : "env " + env
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(shellQuote($0.value))" }
            .joined(separator: " ") + " "

        let joinedArgs = executableAndArgs.arguments.map(shellQuotePreservingFlags).joined(separator: " ")
        let probe = "printf '%s %s\\n' \"$(date -u +%FT%TZ)\" 'shell-reached-exec' >> /tmp/clilauncher_probe.txt && "
        let launchCommand = "\(probe)\(prefix)\(shellQuote(executableAndArgs.executable))" + (joinedArgs.isEmpty ? "" : " \(joinedArgs)")

        let bootstrapCommands = [
            settings.defaultShellBootstrapCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedBootstrapPreset(profile: effectiveProfile, settings: settings)?.trimmedCommand ?? "",
            effectiveProfile.trimmedShellBootstrapCommand
        ].filter { !$0.isEmpty }

        let bootstrapPrefix = bootstrapCommands.isEmpty ? "" : bootstrapCommands.joined(separator: " && ") + " && "

        let commandCore = bootstrapPrefix + launchCommand
        if effectiveProfile.agentKind == .gemini {
            return "cd \(shellQuote(workingDirectory)) && \(guardShellCommandOnFailure(commandCore, workingDirectory: workingDirectory))"
        }

        let execLaunchCommand = "\(probe)exec \(prefix)\(shellQuote(executableAndArgs.executable))" + (joinedArgs.isEmpty ? "" : " \(joinedArgs)")
        return "cd \(shellQuote(workingDirectory)) && \(bootstrapPrefix)\(execLaunchCommand)"
    }

    func buildEnvironment(profile: LaunchProfile, settings: AppSettings) -> [String: String] {
        let effectiveProfile = profile.preparedForLaunch()
        var env = selectedEnvironmentPreset(profile: effectiveProfile, settings: settings)?.environmentMap ?? [:]
        for (key, value) in effectiveProfile.environmentMap {
            env[key] = value
        }
        let preferredLaunchPath = executableResolver.preferredLaunchPath(including: env["PATH"])
        if !preferredLaunchPath.isEmpty {
            env["PATH"] = preferredLaunchPath
        }

        switch effectiveProfile.agentKind {
        case .gemini:
            let resolvedWrapper = resolveGeminiAutomationTarget(profile: effectiveProfile, workingDirectory: effectiveProfile.expandedWorkingDirectory).resolved
            env["CLI_FLAVOR"] = effectiveProfile.geminiFlavor.cliFlavorValue
            env["GEMINI_CLI_HOME"] = effectiveProfile.expandedGeminiISOHome
            env["GEMINI_WRAPPER"] = resolvedWrapper ?? preferredGeminiAutomationTarget(profile: effectiveProfile)
            env["GEMINI_ISO_HOME"] = effectiveProfile.expandedGeminiISOHome
            env["RESUME_LATEST"] = effectiveProfile.geminiResumeLatest ? "1" : "0"
            env["KEEP_TRY_MAX"] = String(effectiveProfile.geminiKeepTryMax)
            if effectiveProfile.geminiAutoContinueMode == .yolo {
                env["AUTO_CONTINUE_MODE"] = "always"
                env["AUTO_CONTINUE_MAX_PER_EVENT"] = "20"
            } else {
                env["AUTO_CONTINUE_MODE"] = effectiveProfile.geminiAutoContinueMode.rawValue
            }
            env["AUTO_ALLOW_SESSION_PERMISSIONS"] = effectiveProfile.geminiAutoAllowSessionPermissions ? "1" : "0"
            env["AUTOMATION_ENABLED"] = effectiveProfile.geminiAutomationEnabled ? "1" : "0"
            env["NEVER_SWITCH"] = effectiveProfile.geminiNeverSwitch ? "1" : "0"
            env["GEMINI_YOLO"] = effectiveProfile.effectiveGeminiYolo ? "1" : "0"
            env["PTY_SET_HOME_TO_ISO"] = effectiveProfile.geminiSetHomeToIso ? "1" : "0"
            env["QUIET_CHILD_NODE_WARNINGS"] = effectiveProfile.geminiQuietChildNodeWarnings ? "1" : "0"
            env["RAW_OUTPUT"] = effectiveProfile.geminiRawOutput ? "1" : "0"
            env["MANUAL_OVERRIDE_MS"] = String(effectiveProfile.geminiManualOverrideMs)
            env["CAPACITY_RETRY_MS"] = String(effectiveProfile.geminiCapacityRetryMs)
            env["HOTKEY_PREFIX"] = effectiveProfile.geminiHotkeyPrefix
            let initialModel = effectiveProfile.geminiInitialModel.trimmingCharacters(in: .whitespacesAndNewlines)
            var models = effectiveProfile.geminiModelChain.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !initialModel.isEmpty {
                if let index = models.firstIndex(of: initialModel) {
                    models.remove(at: index)
                }
                models.insert(initialModel, at: 0)
            }
            env["MODEL_CHAIN"] = models.joined(separator: ",")
            env["GEMINI_INITIAL_PROMPT"] = effectiveProfile.geminiInitialPrompt
            if env["RUNNER_LOG_FILE"] == nil || env["RUNNER_LOG_FILE"]?.isEmpty == true {
                env["RUNNER_LOG_FILE"] = "/tmp/clilauncher.log"
            }
            switch effectiveProfile.geminiFlavor {
            case .stable:
                env["GEMINI_HOME"] = effectiveProfile.expandedGeminiISOHome

            case .preview:
                env["GEMINI_PREVIEW_ISO_HOME"] = effectiveProfile.expandedGeminiISOHome

            case .nightly:
                env["GEMINI_NIGHTLY_ISO_HOME"] = effectiveProfile.expandedGeminiISOHome
            }

        case .copilot:
            let home = effectiveProfile.expandedCopilotHome.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return settings.environmentPresets.first { $0.id == presetID }
    }

    func selectedBootstrapPreset(profile: LaunchProfile, settings: AppSettings) -> ShellBootstrapPreset? {
        guard let presetID = profile.bootstrapPresetID else { return nil }
        return settings.shellBootstrapPresets.first { $0.id == presetID }
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
        let effectiveProfile = profile.preparedForLaunch()

        switch effectiveProfile.geminiLaunchMode {
        case .automationRunner:
            let runnerResolution = resolveAutomationRunner(profile: effectiveProfile, settings: settings, workingDirectory: effectiveProfile.expandedWorkingDirectory)
            guard runnerResolution.isResolved else {
                throw LauncherError.validation(
                    """
                    Gemini automation runner was not found. Automation launches require the runner so startup /clear, /stats, and /model can run before prompt injection. \(runnerResolution.detail)
                    """
                )
            }
            _ = try resolveGeminiAutomationTargetOrThrow(
                profile: effectiveProfile,
                workingDirectory: effectiveProfile.expandedWorkingDirectory
            )
            let node = try resolvedExecutableOrThrow(
                resolvedNodeExecutable(profile: effectiveProfile, settings: settings),
                displayName: "Node",
                workingDirectory: effectiveProfile.expandedWorkingDirectory
            )
            return (node, [runnerResolution.resolved ?? ""])

        case .directWrapper:
            return try buildGeminiDirectWrapperExecutableAndArgs(profile: effectiveProfile)
        }
    }

    private func buildGeminiDirectWrapperExecutableAndArgs(profile: LaunchProfile) throws -> (String, [String]) {
        let wrapper = try resolveProviderExecutableOrThrow(
            profile: profile,
            workingDirectory: profile.expandedWorkingDirectory
        )
        var args: [String] = []
        let initialModel = profile.geminiInitialModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialPrompt = profile.geminiInitialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldResumeLatest = profile.geminiResumeLatest && initialPrompt.isEmpty
        if !initialModel.isEmpty {
            args += ["--model", initialModel]
        }
        if shouldResumeLatest {
            args.append("--resume")
            args.append("latest")
        }
        if !initialPrompt.isEmpty {
            args += ["--prompt-interactive", initialPrompt]
        }
        if profile.effectiveGeminiYolo {
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
        if profile.copilotMode.isAutonomous, profile.copilotMaxAutopilotContinues > 0 {
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
        var args = profile.codexMode.cliArguments
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
        profile.agentKind.providerDefinition.description(profile)
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
        var candidates = profile.providerExecutableCandidates

        // Legacy stable profiles often point at `gemini-iso`, which in turn may
        // delegate to an arbitrary PATH-selected Gemini install. Prefer the
        // dedicated stable wrapper when it exists, while keeping `gemini-iso`
        // as a fallback for older environments.
        if profile.agentKind == .gemini, profile.geminiFlavor == .stable {
            let configured = profile.geminiWrapperCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if configured.isEmpty || configured == "gemini-iso" {
                candidates.insert("gemini-stable", at: 0)
            }
        }

        var unique: [String] = []
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !unique.contains(trimmed) else { continue }
            unique.append(trimmed)
        }

        if !unique.isEmpty {
            return unique
        }
        return [resolvedGeminiWrapper(profile: profile)]
    }

    private func shouldPreferDirectGeminiBinaryForAutomation(profile: LaunchProfile) -> Bool {
        guard profile.agentKind == .gemini else { return false }
        guard profile.geminiLaunchMode == .automationRunner else { return false }
        guard !profile.geminiInitialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let configured = profile.geminiWrapperCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configured.isEmpty else { return true }
        return GeminiFlavor.allCases.contains { $0.wrapperAliasNames.contains(configured) }
    }

    private func preferredGeminiAutomationTarget(profile: LaunchProfile) -> String {
        if shouldPreferDirectGeminiBinaryForAutomation(profile: profile) {
            return profile.geminiFlavor.directExecutableCandidates.first ?? resolvedGeminiWrapper(profile: profile)
        }
        return resolvedGeminiWrapper(profile: profile)
    }

    func resolveGeminiAutomationTarget(profile: LaunchProfile, workingDirectory: String) -> ExecutableResolution {
        if shouldPreferDirectGeminiBinaryForAutomation(profile: profile) {
            if profile.geminiFlavor == .stable {
                for workspaceCandidate in ["gemini", "gemini-cli"] {
                    let resolution = resolveExecutable(workspaceCandidate, workingDirectory: workingDirectory)
                    if resolution.isResolved, resolution.source == "workspace node_modules/.bin" {
                        return resolution
                    }
                }
            }

            for candidate in profile.geminiFlavor.directExecutableCandidates {
                let resolution = resolveExecutable(candidate, workingDirectory: workingDirectory)
                if resolution.isResolved {
                    return resolution
                }
            }
        }

        return resolveGeminiWrapper(profile: profile, workingDirectory: workingDirectory)
    }

    func resolveGeminiAutomationTargetOrThrow(profile: LaunchProfile, workingDirectory: String) throws -> String {
        let resolution = resolveGeminiAutomationTarget(profile: profile, workingDirectory: workingDirectory)
        if let resolved = resolution.resolved {
            return resolved
        }
        throw LauncherError.validation(
            "Gemini automation target was not found: \(preferredGeminiAutomationTarget(profile: profile)). \(resolution.detail)"
        )
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
                searchedLocations: Array(failedResolutions.flatMap(\.searchedLocations).prefix(40))
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
        let normalizedProfileRunnerPath = BundledGeminiAutomationRunner.normalizedConfiguredPath(
            profile.geminiAutomationRunnerPath,
            fillBlankWithDefault: false
        )
        let raw = NSString(string: normalizedProfileRunnerPath)
            .expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            return raw
        }

        let normalizedDefaultRunnerPath = BundledGeminiAutomationRunner.normalizedConfiguredPath(
            settings.defaultGeminiRunnerPath,
            fillBlankWithDefault: false
        )
        let defaultRunner = NSString(string: normalizedDefaultRunnerPath)
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
                detail: "Automation runner is not configured."
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

    private func guardShellCommandOnFailure(_ command: String, workingDirectory: String) -> String {
        "{ \(command); }; __clilauncher_status=$?; if [ \"$__clilauncher_status\" -eq \(Self.geminiHoldOpenExitCode) ]; then printf '\\n[clilauncher] Gemini session finished. Opening an interactive shell. Type exit when done.\\n'; export CLILAUNCHER_LAST_STATUS='0'; export CLILAUNCHER_LAST_REASON='gemini-session-finished'; cd \(shellQuote(workingDirectory)); exec /bin/zsh -il; fi; if [ \"$__clilauncher_status\" -ne 0 ]; then printf '\\n[clilauncher] Process exited with status %s.\\n' \"$__clilauncher_status\"; printf '[clilauncher] Opening an interactive shell for inspection. Type exit when done.\\n'; export CLILAUNCHER_LAST_STATUS=\"$__clilauncher_status\"; cd \(shellQuote(workingDirectory)); exec /bin/zsh -il; fi; exit \"$__clilauncher_status\""
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
        raw.split { $0.isWhitespace }.map(String.init)
    }
}
