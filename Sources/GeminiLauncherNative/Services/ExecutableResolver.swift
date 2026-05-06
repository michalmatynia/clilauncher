import Darwin
import Foundation

struct ExecutableResolution: Sendable {
    var requested: String
    var resolved: String?
    var source: String?
    var detail: String
    var searchedLocations: [String] = []

    var isResolved: Bool {
        resolved != nil
    }
}

struct ExecutableResolverSnapshot: Sendable {
    var processPath: String
    var pathHelperPath: String
    var loginShellPath: String
    var pathHelperStatus: String
    var loginShellStatus: String
    var sourceSummary: [String]
}

private struct ExecutableSearchRoot: Hashable, Sendable {
    var path: String
    var source: String
}

private struct ExecutableSearchContext: Sendable {
    var roots: [ExecutableSearchRoot]
    var sourceSummary: [String]
    var processPath: String
    var pathHelperPath: String
    var pathHelperStatus: String
    var loginShellPath: String
    var loginShellStatus: String
    var processPathDirectories: [String]
    var pathHelperPathDirectories: [String]
    var loginShellPathDirectories: [String]
    var commonPathDirectories: [String]
}

struct ExecutableResolver {
    private let fileManager = FileManager.default

    func snapshot() -> ExecutableResolverSnapshot {
        let context = ExecutableSearchContextCache.current()
        return ExecutableResolverSnapshot(
            processPath: context.processPath,
            pathHelperPath: context.pathHelperPath,
            loginShellPath: context.loginShellPath,
            pathHelperStatus: context.pathHelperStatus,
            loginShellStatus: context.loginShellStatus,
            sourceSummary: context.sourceSummary
        )
    }

    func preferredLaunchPath(including existingPath: String? = nil) -> String {
        let context = ExecutableSearchContextCache.current()
        var seen: Set<String> = []
        var directories: [String] = []

        func appendDirectories(_ values: [String]) {
            for value in values {
                let normalized = expand(value)
                guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                directories.append(normalized)
            }
        }

        if let existingPath {
            appendDirectories(
                existingPath
                    .split(separator: ":")
                    .map { String($0) }
            )
        }
        appendDirectories(context.loginShellPathDirectories)
        appendDirectories(context.processPathDirectories)
        appendDirectories(context.pathHelperPathDirectories)
        appendDirectories(context.commonPathDirectories)

        return directories.joined(separator: ":")
    }

    func resolve(_ command: String, workingDirectory: String? = nil) -> ExecutableResolution {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ExecutableResolution(
                requested: command,
                resolved: nil,
                source: "not configured",
                detail: "No executable was configured."
            )
        }

        if trimmed.contains("/") {
            let expanded = expand(trimmed)
            if fileManager.isExecutableFile(atPath: expanded) {
                return ExecutableResolution(
                    requested: trimmed,
                    resolved: expanded,
                    source: "configured path",
                    detail: "Resolved from the configured absolute or relative path.",
                    searchedLocations: [expanded]
                )
            }

            if !expanded.hasPrefix("/"), let workingDirectory {
                let expandedWorkingDirectory = expand(workingDirectory)
                let relativeResolved = URL(fileURLWithPath: expandedWorkingDirectory)
                    .appendingPathComponent(expanded)
                    .path
                if fileManager.isExecutableFile(atPath: relativeResolved) {
                    return ExecutableResolution(
                        requested: trimmed,
                        resolved: relativeResolved,
                        source: "working directory relative path",
                        detail: "Resolved from configured relative path under working directory.",
                        searchedLocations: [expanded, relativeResolved]
                    )
                }
                let missingPathDetail = "Configured relative path under working directory not executable: \(relativeResolved)"
                return ExecutableResolution(
                    requested: trimmed,
                    resolved: nil,
                    source: "configured path",
                    detail: "Configured path is missing or not executable: \(expanded). \(missingPathDetail)",
                    searchedLocations: [expanded, relativeResolved]
                )
            }

            return ExecutableResolution(
                requested: trimmed,
                resolved: nil,
                source: "configured path",
                detail: "Configured path is missing or not executable: \(expanded)",
                searchedLocations: [expanded]
            )
        }

        let commandName = trimmed
        var candidateRoots: [ExecutableSearchRoot] = []

        appendRoots(from: workspaceSearchRoots(for: workingDirectory).map(\.path), into: &candidateRoots, source: "workspace node_modules/.bin")
        appendRoots(from: appBundledWrapperDirectories(), into: &candidateRoots, source: "app wrapper directory")

        let globalContext = ExecutableSearchContextCache.current()
        appendRoots(from: globalContext.processPathDirectories, into: &candidateRoots, source: "process PATH")
        appendRoots(from: globalContext.pathHelperPathDirectories, into: &candidateRoots, source: "/usr/libexec/path_helper")
        appendRoots(from: globalContext.loginShellPathDirectories, into: &candidateRoots, source: "login-shell PATH")
        appendRoots(from: globalContext.commonPathDirectories, into: &candidateRoots, source: "common user bin directories")

        let roots = uniqueRoots(candidateRoots)
        var searchedLocations: [String] = []

        for root in roots {
            let candidate = URL(fileURLWithPath: root.path, isDirectory: true)
                .appendingPathComponent(trimmed)
                .path
            searchedLocations.append(candidate)
            if fileManager.isExecutableFile(atPath: candidate) {
                return ExecutableResolution(
                    requested: commandName,
                    resolved: candidate,
                    source: root.source,
                    detail: "Resolved via \(root.source).",
                    searchedLocations: Array(searchedLocations.prefix(20))
                )
            }
        }

        if let whichResolved = whichResolvedPath(for: trimmed) {
            searchedLocations.append(whichResolved)
            return ExecutableResolution(
                requested: commandName,
                resolved: whichResolved,
                source: "which",
                detail: "Resolved via /usr/bin/which.",
                searchedLocations: Array(searchedLocations.prefix(20))
            )
        }

        let sources = uniqueStrings(roots.map(\.source) + ["/usr/bin/which"])
        let summary = sources.isEmpty ? "known executable search locations" : sources.joined(separator: ", ")
        return ExecutableResolution(
            requested: commandName,
            resolved: nil,
            source: summary,
            detail: "Executable not found. Checked \(summary).",
            searchedLocations: Array(searchedLocations.prefix(20))
        )
    }

    private func workspaceSearchRoots(for workingDirectory: String?) -> [ExecutableSearchRoot] {
        guard let workingDirectory else { return [] }

        let expanded = expand(workingDirectory)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        var roots: [ExecutableSearchRoot] = []
        var currentURL = URL(fileURLWithPath: expanded, isDirectory: true)

        while true {
            let nodeModulesBin = currentURL.appendingPathComponent("node_modules/.bin", isDirectory: true).path
            if fileManager.fileExists(atPath: nodeModulesBin, isDirectory: &isDirectory), isDirectory.boolValue {
                roots.append(ExecutableSearchRoot(path: nodeModulesBin, source: "workspace node_modules/.bin"))
            }

            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL.path == currentURL.path {
                break
            }
            currentURL = parentURL
        }

        return uniqueRoots(roots)
    }

    private func appBundledWrapperDirectories() -> [String] {
        var directories: [String] = []

        if let resourceURL = Bundle.main.resourceURL {
            directories.append(resourceURL.appendingPathComponent("Wrappers", isDirectory: true).path)
            directories.append(resourceURL.appendingPathComponent("Contents/Resources/Wrappers", isDirectory: true).path)
        }

        let supportWrapperDirectory = AppPaths.containerDirectory.appendingPathComponent("Wrappers", isDirectory: true).path
        directories.append(supportWrapperDirectory)

        return directories.filter { directory in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: directory, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private func expand(_ value: String) -> String {
        NSString(string: value).expandingTildeInPath
    }

    private func appendRoots(from directories: [String], into roots: inout [ExecutableSearchRoot], source: String) {
        for directory in directories {
            roots.append(ExecutableSearchRoot(path: directory, source: source))
        }
    }

    private func uniqueRoots(_ roots: [ExecutableSearchRoot]) -> [ExecutableSearchRoot] {
        var seen: Set<String> = []
        var result: [ExecutableSearchRoot] = []
        for root in roots {
            let normalized = expand(root.path)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(ExecutableSearchRoot(path: normalized, source: root.source))
        }
        return result
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            guard !value.isEmpty, !seen.contains(value) else { return false }
            seen.insert(value)
            return true
        }
    }

    private func whichResolvedPath(for command: String) -> String? {
        guard fileManager.isExecutableFile(atPath: "/usr/bin/which") else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let lines = output.split { $0 == "\n" || $0 == "\r" }
        guard let firstLine = lines.first else { return nil }

        let trimmed = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, fileManager.isExecutableFile(atPath: trimmed) else {
            return nil
        }
        return trimmed
    }
}

private enum ExecutableSearchContextCache {
    private static let queue = DispatchQueue(label: "ExecutableSearchContextCache")
    private static let ttl: TimeInterval = 5
    nonisolated(unsafe) private static var cachedContext: ExecutableSearchContext?
    nonisolated(unsafe) private static var cachedAt: Date?

    static func current() -> ExecutableSearchContext {
        queue.sync {
            let now = Date()
            if let cachedContext, let cachedAt, now.timeIntervalSince(cachedAt) < ttl {
                return cachedContext
            }

            let fresh = buildContext()
            cachedContext = fresh
            cachedAt = now
            return fresh
        }
    }

    private static func buildContext() -> ExecutableSearchContext {
        let fileManager = FileManager.default
        let processPath = processPathValue()
        let pathHelperInfo = pathHelperProbe()
        let loginShellInfo = loginShellProbe()
        let pathHelperPath = pathHelperInfo.path
        let loginShellPath = loginShellInfo.path

        let processPathDirectories = splitPathDirectories(processPath)
        let pathHelperPathDirectories = splitPathDirectories(pathHelperPath)
        let loginShellPathDirectories = splitPathDirectories(loginShellPath)
        let commonPathDirectories = commonUserDirectories(fileManager: fileManager)

        var roots: [ExecutableSearchRoot] = []
        var sources: [String] = []

        appendRoots(from: processPathDirectories, into: &roots, sources: &sources, source: "process PATH")
        appendRoots(from: pathHelperPathDirectories, into: &roots, sources: &sources, source: "/usr/libexec/path_helper")
        appendRoots(from: loginShellPathDirectories, into: &roots, sources: &sources, source: "login-shell PATH")
        appendRoots(from: commonPathDirectories, into: &roots, sources: &sources, source: "common user bin directories")

        return ExecutableSearchContext(
            roots: uniqueRoots(roots),
            sourceSummary: uniqueStrings(sources),
            processPath: processPath,
            pathHelperPath: pathHelperPath,
            pathHelperStatus: pathHelperInfo.status,
            loginShellPath: loginShellPath,
            loginShellStatus: loginShellInfo.status,
            processPathDirectories: processPathDirectories,
            pathHelperPathDirectories: pathHelperPathDirectories,
            loginShellPathDirectories: loginShellPathDirectories,
            commonPathDirectories: commonPathDirectories
        )
    }

    private static func appendRoots(
        from directories: [String],
        into roots: inout [ExecutableSearchRoot],
        sources: inout [String],
        source: String
    ) {
        guard !directories.isEmpty else { return }
        sources.append(source)
        roots.append(contentsOf: directories.map { ExecutableSearchRoot(path: $0, source: source) })
    }

    private static func processPathValue() -> String {
        ProcessInfo.processInfo.environment["PATH"] ?? ""
    }

    private static func pathHelperProbe() -> (path: String, status: String) {
        guard FileManager.default.isExecutableFile(atPath: "/usr/libexec/path_helper") else {
            return ("", "path helper binary unavailable")
        }

        guard let output = runProcess(
            executable: "/usr/libexec/path_helper",
            arguments: ["-s"],
            timeout: 0.5
        ) else {
            return ("", "path helper command failed")
        }

        for component in output.components(separatedBy: ";") {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("PATH=") else { continue }
            let path = String(trimmed.dropFirst("PATH=".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return (path, "path helper succeeded")
        }

        return ("", "path helper output missing PATH assignment")
    }

    private static func loginShellProbe() -> (path: String, status: String) {
        guard let shell = currentUserShellPath() else { return ("", "no login shell available") }

        let marker = "__CLI_LAUNCHER_PATH__"
        let script = "printf '\\n\(marker)\\n'; printf '%s' \"$PATH\""
        guard let output = runProcess(executable: shell, arguments: ["-l", "-c", script], timeout: 1.0),
              let markerRange = output.range(of: marker) else {
            return ("", "login shell probe did not expose PATH")
        }

        return (String(output[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines), "login shell probe succeeded")
    }

    private static func currentUserShellPath() -> String? {
        if let shell = ProcessInfo.processInfo.environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !shell.isEmpty,
           FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }

        if let userRecord = getpwuid(getuid()) {
            let shellPointer = userRecord.pointee.pw_shell
            if let shellPointer {
                let shell = String(cString: shellPointer)
                if !shell.isEmpty, FileManager.default.isExecutableFile(atPath: shell) {
                    return shell
                }
            }
        }

        let fallback = "/bin/zsh"
        return FileManager.default.isExecutableFile(atPath: fallback) ? fallback : nil
    }

    private static func commonUserDirectories(fileManager: FileManager) -> [String] {
        let home = fileManager.homeDirectoryForCurrentUser.path
        var directories: [String] = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.volta/bin",
            "\(home)/.bun/bin",
            "\(home)/Library/pnpm",
            "\(home)/.nvm/current/bin"
        ]

        directories += versionedNodeDirectories(root: "\(home)/.nvm/versions/node", fileManager: fileManager)

        return directories.filter { path in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private static func versionedNodeDirectories(root: String, fileManager: FileManager) -> [String] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else { return [] }
        return entries
            .sorted(by: >)
            .map { URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent($0).appendingPathComponent("bin", isDirectory: true).path }
    }

    private static func splitPathDirectories(_ value: String) -> [String] {
        value
            .split(separator: ":")
            .map { NSString(string: String($0)).expandingTildeInPath }
            .filter { !$0.isEmpty }
    }

    private static func runProcess(executable: String, arguments: [String], timeout: TimeInterval = 1.0) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                process.terminate()
                return nil
            }
            guard process.terminationStatus == 0 else { return nil }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }

    private static func uniqueRoots(_ roots: [ExecutableSearchRoot]) -> [ExecutableSearchRoot] {
        var seen: Set<String> = []
        var result: [ExecutableSearchRoot] = []
        for root in roots {
            let normalized = NSString(string: root.path).expandingTildeInPath
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(ExecutableSearchRoot(path: normalized, source: root.source))
        }
        return result
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            guard !value.isEmpty, !seen.contains(value) else { return false }
            seen.insert(value)
            return true
        }
    }
}
