import AppKit
import Foundation
import UniformTypeIdentifiers

enum LaunchScriptMaterializer {
    static func materialize(command: String) -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let file = dir.appendingPathComponent("clilauncher-launch-\(UUID().uuidString).sh")
        let body = """
        #!/bin/zsh
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
