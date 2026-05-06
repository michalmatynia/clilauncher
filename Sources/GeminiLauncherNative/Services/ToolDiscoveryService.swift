import Foundation

struct ToolDiscoveryService {
    private let builder = CommandBuilder()
    private let companionLauncher = WorkspaceCompanionLauncher()
    private let iTermRuntime = ITerm2RuntimeService()

    private struct GeminiCLICompatibility {
        let packageName: String
        let version: String
        let packageJSONPath: String
        let startupStatsSupported: Bool
        let startupStatsDisabledReason: String
        let selfUpdateCompatibilityOverrideReason: String
    }

    private struct GeminiCLIPackageMetadata: Decodable {
        let name: String
        let version: String
    }

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
            .first { !$0.isEmpty }
    }

    private func normalizedVersionString(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^v"#, with: "", options: .regularExpression)
    }

    private func findNearestPackageJSON(startingAt path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let resolvedURL = URL(fileURLWithPath: trimmed).resolvingSymlinksInPath()
        let fileManager = FileManager.default
        var candidateURL = resolvedURL

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            candidateURL.deleteLastPathComponent()
        }

        while true {
            let packageURL = candidateURL.appendingPathComponent("package.json", isDirectory: false)
            if fileManager.fileExists(atPath: packageURL.path) {
                return packageURL.path
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            if parentURL.path == candidateURL.path { break }
            candidateURL = parentURL
        }

        return nil
    }

    private func inspectGeminiCLICompatibility(executablePath: String) -> GeminiCLICompatibility? {
        guard let packageJSONPath = findNearestPackageJSON(startingAt: executablePath) else { return nil }
        guard let data = FileManager.default.contents(atPath: packageJSONPath) else { return nil }
        guard let metadata = try? JSONDecoder().decode(GeminiCLIPackageMetadata.self, from: data) else { return nil }
        guard metadata.name == "@google/gemini-cli" else { return nil }

        let version = normalizedVersionString(metadata.version)
        let disabledReason: String
        let selfUpdateCompatibilityOverrideReason: String
        if version == "0.32.1" {
            disabledReason = ""
            selfUpdateCompatibilityOverrideReason = "Gemini CLI 0.32.1 self-update checks are disabled for launcher-started sessions."
        } else {
            disabledReason = ""
            selfUpdateCompatibilityOverrideReason = "Gemini CLI \(version) self-update checks are disabled for launcher-started sessions."
        }

        return GeminiCLICompatibility(
            packageName: metadata.name,
            version: version,
            packageJSONPath: packageJSONPath,
            startupStatsSupported: disabledReason.isEmpty,
            startupStatsDisabledReason: disabledReason,
            selfUpdateCompatibilityOverrideReason: selfUpdateCompatibilityOverrideReason
        )
    }

    private func appendGeminiCompatibilityStatus(
        executable: String,
        updateCommand: String?,
        installDocumentation: String,
        providerRiskLevel: ProviderRiskLevel,
        statuses: inout [ToolStatus],
        warnings: inout [String]
    ) {
        guard let compatibility = inspectGeminiCLICompatibility(executablePath: executable) else { return }

        let detail: String
        if compatibility.startupStatsSupported {
            let compatibilityNotes = [
                "Detected \(compatibility.packageName) \(compatibility.version). Startup /clear -> /stats -> /model automation is enabled.",
                compatibility.selfUpdateCompatibilityOverrideReason
            ].filter { !$0.isEmpty }
            detail = compatibilityNotes.joined(separator: " ")
        } else {
            let compatibilityNotes = [
                compatibility.startupStatsDisabledReason,
                compatibility.selfUpdateCompatibilityOverrideReason,
            ].filter { !$0.isEmpty }
            detail = "\(compatibilityNotes.joined(separator: " ")) Fire & Forget prompt injection stays blocked until Gemini CLI is updated."
        }

        statuses.append(
            ToolStatus(
                name: "Gemini CLI compatibility",
                requested: executable,
                resolved: compatibility.version,
                detail: "\(detail)\nPackage metadata: \(compatibility.packageJSONPath)",
                isError: false,
                resolutionSource: "package metadata",
                updateCommand: updateCommand,
                installDocumentation: installDocumentation,
                providerRiskLevel: providerRiskLevel
            )
        )
    }

    private func appendProviderHealthChecks(
        profile: LaunchProfile,
        executable: String,
        statusAppendBlock: (ToolStatus) -> Void,
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
                resolutionSource: resolution?.source,
                updateCommand: profile.resolvedUpdateCommand,
                installDocumentation: definition.installDocumentation,
                providerRiskLevel: definition.riskLevel
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

        if !hasConfig, !hasEnv {
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
        while process.isRunning, Date().timeIntervalSince(start) < timeoutSeconds {
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
        let pythonResolution = builder.resolveExecutable("python3", workingDirectory: workingDirectory)
        let pythonExecutable = pythonResolution.resolved
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
            warnings.append(
                pythonExecutable == nil
                ? "Could not verify Gemini PTY backend availability from Node. Automation runner may still fall back to direct child-process mode."
                : "Could not verify Gemini PTY backend availability from Node. Automation runner may still fall back to the bundled `python3` PTY bridge."
            )
            return
        }

        if probe.timedOut {
            warnings.append(
                pythonExecutable == nil
                ? "Gemini PTY backend check timed out. Automation runner may still fall back to direct child-process mode."
                : "Gemini PTY backend check timed out. Automation runner may still fall back to the bundled `python3` PTY bridge."
            )
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

        if let pythonExecutable {
            statuses.append(
                ToolStatus(
                    name: "Gemini PTY backend",
                    requested: "@lydell/node-pty or node-pty",
                    resolved: "python3 PTY bridge",
                    detail: "No workspace PTY package was found. Automation runner will fall back to the bundled `python3` PTY bridge via \(pythonExecutable), so prompt automation and hotkeys remain available. Install `@lydell/node-pty` or `node-pty` in the workspace if you want the primary PTY backend.",
                    isError: false,
                    resolutionSource: "runtime probe"
                )
            )
            warnings.append("Gemini automation runner could not find `@lydell/node-pty` or `node-pty` in `\(workingDirectory)`. It can still use the bundled `python3` PTY bridge, but installing a workspace PTY package keeps the primary backend available.")
            return
        }

        statuses.append(
            ToolStatus(
                name: "Gemini PTY backend",
                requested: "@lydell/node-pty or node-pty",
                resolved: nil,
                detail: """
                No PTY package was found from the workspace, and no `python3` PTY fallback was available. Automation runner will fall back to plain child-process mode, so hotkeys and prompt automation will be unavailable.
                Install one of these in the launch workspace:
                cd \(workingDirectory)
                npm install @lydell/node-pty
                or
                cd \(workingDirectory)
                npm install node-pty
                """,
                isError: false,
                resolutionSource: "runtime probe"
            )
        )
        warnings.append("Gemini automation runner could not find `@lydell/node-pty` or `node-pty`, and no `python3` PTY fallback was available. Run `npm install @lydell/node-pty` (or `npm install node-pty`) in `\(workingDirectory)` to enable PTY automation and hotkeys.")
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
            let effectiveProfile = profile.preparedForLaunch()
            let workingDirectory = effectiveProfile.expandedWorkingDirectory
            let wrapperResolution = builder.resolveGeminiWrapper(profile: effectiveProfile, workingDirectory: workingDirectory)
            let runnerResolution = builder.resolveAutomationRunner(profile: effectiveProfile, settings: settings, workingDirectory: workingDirectory)
            statuses.append(
                ToolStatus(
                    name: "Gemini wrapper",
                    requested: wrapperResolution.requested,
                    resolved: wrapperResolution.resolved,
                    detail: expandedResolutionDetail(wrapperResolution),
                    isError: !wrapperResolution.isResolved,
                    resolutionSource: wrapperResolution.source,
                    updateCommand: effectiveProfile.resolvedUpdateCommand,
                    installDocumentation: profile.agentKind.providerDefinition.installDocumentation,
                    providerRiskLevel: profile.agentKind.providerDefinition.riskLevel
                )
            )
            if let wrapperResolved = wrapperResolution.resolved {
                appendGeminiCompatibilityStatus(
                    executable: wrapperResolved,
                    updateCommand: effectiveProfile.resolvedUpdateCommand,
                    installDocumentation: profile.agentKind.providerDefinition.installDocumentation,
                    providerRiskLevel: profile.agentKind.providerDefinition.riskLevel,
                    statuses: &statuses,
                    warnings: &warnings
                )
                appendProviderHealthChecks(
                    profile: effectiveProfile,
                    executable: wrapperResolved,
                    statusAppendBlock: { statuses.append($0) },
                    warnings: &warnings
                )
            }
            let node = builder.resolvedNodeExecutable(profile: effectiveProfile, settings: settings)
            let resolvedRunner = builder.resolvedRunnerPath(profile: effectiveProfile, settings: settings)
            let runner = resolvedRunner.isEmpty ? "Not configured" : resolvedRunner
            let runnerResolved = runnerResolution.resolved
            let nodeResolution = builder.resolveExecutable(node, workingDirectory: workingDirectory)
            let runnerConfigured = !resolvedRunner.isEmpty
            let runnerAvailable = runnerResolution.isResolved

            if effectiveProfile.geminiLaunchMode == .automationRunner {
                statuses.append(
                    ToolStatus(
                        name: "Automation runner",
                        requested: runnerConfigured ? runner : "Not configured",
                        resolved: runnerResolved,
                        detail: runnerAvailable
                            ? "Automation runner will be used."
                            : (runnerConfigured
                                ? "Runner not found. Automation launch is blocked until the runner is available; prompt launches must run startup /clear, /stats, and /model before prompt injection.\n\(expandedResolutionDetail(runnerResolution))"
                                : "No runner configured. Automation launch is blocked until a runner is configured."),
                        isError: !runnerAvailable,
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
                            : "Required after the automation runner is available.",
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
            if profile.agentKind == .ollamaLaunch, let resolved {
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
