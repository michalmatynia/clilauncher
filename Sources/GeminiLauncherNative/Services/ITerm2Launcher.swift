import AppKit
import Foundation

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

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
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
            .split { $0.isNewline || $0 == "," }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(Set(pieces)).sorted()
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
        let delaySeconds = max(0.05, Double(plan.tabLaunchDelayMs) / 1_000.0)
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
            ].compactMap(\.self).joined(separator: " • ")
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
        let delaySeconds = max(0.05, Double(plan.tabLaunchDelayMs) / 1_000.0)
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
