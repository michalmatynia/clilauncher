import Foundation

enum BundledGeminiAutomationRunner {
    static var defaultPath: String {
        resourceURL?.path ?? ""
    }

    static var displayPath: String {
        defaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var buildID: String {
        guard let resourceURL,
              let source = try? String(contentsOf: resourceURL, encoding: .utf8) else {
            return ""
        }
        return extractBuildID(from: source) ?? ""
    }

    static func normalizedConfiguredPath(_ rawPath: String, fillBlankWithDefault: Bool) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return fillBlankWithDefault ? defaultPath : rawPath
        }

        let expanded = NSString(string: trimmed).expandingTildeInPath
        let currentDefault = defaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentDefault.isEmpty else {
            return rawPath
        }

        guard isLauncherBundledRunnerPath(expanded), expanded != currentDefault else {
            return rawPath
        }

        return currentDefault
    }

    private static func isLauncherBundledRunnerPath(_ path: String) -> Bool {
        guard URL(fileURLWithPath: path).lastPathComponent == "gemini-automation-runner.mjs" else {
            return false
        }

        if path.contains("CLILauncherNative_GeminiLauncherNative.bundle") ||
            path.contains("GeminiLauncherNative_GeminiLauncherNative.bundle") {
            return true
        }

        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        return extractBuildID(from: source) != nil
    }

    private static var resourceURL: URL? {
        Bundle.module.url(
            forResource: "gemini-automation-runner",
            withExtension: "mjs",
            subdirectory: "Resources"
        ) ?? Bundle.module.url(
            forResource: "gemini-automation-runner",
            withExtension: "mjs"
        )
    }

    private static func extractBuildID(from source: String) -> String? {
        guard let match = source.range(
            of: #"const\s+RUNNER_BUILD_ID\s*=\s*['"]([^'"]+)['"]"#,
            options: .regularExpression
        ) else {
            return nil
        }

        let declaration = String(source[match])
        guard let capture = declaration.range(
            of: #"['"]([^'"]+)['"]"#,
            options: .regularExpression
        ) else {
            return nil
        }

        return String(declaration[capture])
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
