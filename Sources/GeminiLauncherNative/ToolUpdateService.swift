import Foundation

@MainActor
struct ToolUpdateService {
    static func launchInTerminal(
        command: String,
        toolName: String,
        profile: LaunchProfile?,
        settings: AppSettings,
        logger: LaunchLogger
    ) {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else {
            logger.log(.error, "No update command is configured for \(toolName).", category: .diagnostics)
            return
        }

        let workingDirectory = resolvedWorkingDirectory(profile: profile, settings: settings)
        let terminalApp = profile?.terminalApp ?? settings.defaultTerminalApp
        let plan = PlannedLaunch(
            items: [
                PlannedLaunchItem(
                    profileID: profile?.id ?? UUID(),
                    profileName: "\(toolName) Update",
                    command: buildTerminalUpdateCommand(
                        updateCommand: normalizedCommand,
                        workingDirectory: workingDirectory,
                        toolName: toolName
                    ),
                    openMode: profile?.openMode ?? settings.defaultOpenMode,
                    terminalApp: terminalApp,
                    iTermProfile: resolvedITermProfile(profile: profile, settings: settings),
                    description: "Run \(toolName) update command in \(terminalApp.displayName)."
                )
            ],
            tabLaunchDelayMs: max(50, profile?.tabLaunchDelayMs ?? settings.defaultTabLaunchDelayMs)
        )

        do {
            try TerminalLauncherDispatcher().launch(plan: plan, logger: logger, observability: settings.observability)
            logger.log(
                .info,
                "Opened \(terminalApp.displayName) for \(toolName) update.",
                category: .diagnostics,
                details: "cwd=\(workingDirectory) • command=\(normalizedCommand)"
            )
        } catch {
            logger.log(
                .error,
                "Failed to open \(terminalApp.displayName) for \(toolName) update.",
                category: .diagnostics,
                details: error.localizedDescription
            )
        }
    }

    private static func resolvedWorkingDirectory(profile: LaunchProfile?, settings: AppSettings) -> String {
        let candidates = [
            profile?.expandedWorkingDirectory,
            NSString(string: settings.defaultWorkingDirectory).expandingTildeInPath
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in candidates {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }

        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    private static func resolvedITermProfile(profile: LaunchProfile?, settings: AppSettings) -> String {
        let profileValue = profile?.trimmedITermProfile ?? ""
        if !profileValue.isEmpty {
            return profileValue
        }
        return settings.defaultITermProfile.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func buildTerminalUpdateCommand(updateCommand: String, workingDirectory: String, toolName: String) -> String {
        let helperPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("clilauncher-update-\(UUID().uuidString).sh")
        let hereDocMarker = "__CLILAUNCHER_UPDATE_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))__"
        let helperScript = """
        #!/bin/zsh
        emulate -L zsh
        setopt pipefail
        cd \(shellQuotePath(workingDirectory))
        \(updateCommand)
        __clilauncher_update_status=$?
        /usr/bin/printf '\\n'
        if [ $__clilauncher_update_status -eq 0 ]; then
          /usr/bin/printf '%s\\n' \(shellQuoteLiteral("\(toolName) update finished successfully."))
        else
          /usr/bin/printf '%s %s\\n' \(shellQuoteLiteral("\(toolName) update failed with exit code")) "$__clilauncher_update_status"
        fi
        /usr/bin/printf '%s\\n' \(shellQuoteLiteral("This shell will remain open so you can review the update output."))
        exec /bin/zsh -il
        """

        return """
        /bin/rm -f \(shellQuotePath(helperPath))
        /bin/cat > \(shellQuotePath(helperPath)) <<'\(hereDocMarker)'
        \(helperScript)
        \(hereDocMarker)
        /bin/chmod 755 \(shellQuotePath(helperPath)) || exit 1
        trap '/bin/rm -f \(shellQuotePath(helperPath))' EXIT
        /bin/zsh -ilc \(shellQuotePath(helperPath))
        """
    }

    private static func shellQuotePath(_ raw: String) -> String {
        shellQuoteLiteral(NSString(string: raw).expandingTildeInPath)
    }

    private static func shellQuoteLiteral(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
