import AppKit
import Foundation

@MainActor
final class LaunchLogger: ObservableObject {
    @Published var entries: [LogEntry] = []

    private let fileManager = FileManager.default
    private let logFileURL: URL = AppPaths.runtimeLogFileURL
    private var settings = ObservabilitySettings()
    private let diskDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var runtimeLogFileURL: URL { logFileURL }
    var logDirectoryURL: URL { AppPaths.logsDirectoryURL }

    init() {
        ensureLogDirectoryExists()
    }

    func apply(settings: ObservabilitySettings) {
        self.settings = settings
        trimInMemoryEntriesIfNeeded()
        ensureLogDirectoryExists()
    }

    func log(_ level: LogLevel, _ message: String, category: LogCategory = .app, details: String? = nil) {
        if level == .debug, !settings.verboseLogging {
            return
        }

        ensureLogDirectoryExists()
        let normalizedDetails = details?.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        if settings.deduplicateRepeatedEntries,
           !entries.isEmpty,
           entries[0].level == level,
           entries[0].category == category,
           entries[0].message == message,
           entries[0].details == normalizedDetails,
           now.timeIntervalSince(entries[0].timestamp) < 2.0 {
            entries[0].timestamp = now
            entries[0].repeatCount += 1
        } else {
            entries.insert(LogEntry(timestamp: now, level: level, category: category, message: message, details: normalizedDetails, repeatCount: 1), at: 0)
        }

        trimInMemoryEntriesIfNeeded()
        persistLine(level: level, category: category, message: message, details: normalizedDetails, timestamp: now)
    }

    func debug(_ message: String, category: LogCategory = .app, details: String? = nil) {
        log(.debug, message, category: category, details: details)
    }

    func clear() {
        entries.removeAll()
        do {
            if fileManager.fileExists(atPath: logFileURL.path) {
                try fileManager.removeItem(at: logFileURL)
            }
        } catch {
            print("Failed to clear runtime log file: \(error)")
        }
    }

    func revealLogDirectory() {
        ensureLogDirectoryExists()
        NSWorkspace.shared.activateFileViewerSelecting([logDirectoryURL])
    }

    private func ensureLogDirectoryExists() {
        try? fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
    }

    private func trimInMemoryEntriesIfNeeded() {
        let limit = max(100, settings.maxInMemoryEntries)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
    }

    private func persistLine(level: LogLevel, category: LogCategory, message: String, details: String?, timestamp: Date) {
        guard settings.persistLogsToDisk else { return }
        rotateLogFileIfNeeded()
        let line = formattedLine(level: level, category: category, message: message, details: details, timestamp: timestamp)
        guard let data = (line + "\n").data(using: .utf8) else { return }

        do {
            if !fileManager.fileExists(atPath: logFileURL.path) {
                try data.write(to: logFileURL, options: [.atomic])
                return
            }
            let handle = try FileHandle(forWritingTo: logFileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            print("Failed to persist runtime log: \(error)")
        }
    }

    private func formattedLine(level: LogLevel, category: LogCategory, message: String, details: String?, timestamp: Date) -> String {
        var line = "[\(diskDateFormatter.string(from: timestamp))] [\(level.rawValue.uppercased())] [\(category.rawValue.uppercased())] \(message)"
        if let details, !details.isEmpty {
            let flattened = details.replacingOccurrences(of: "\n", with: " ⏎ ")
            line += " | \(flattened)"
        }
        return line
    }

    private func rotateLogFileIfNeeded() {
        guard settings.persistLogsToDisk,
              let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 5_000_000 else {
            return
        }

        let backupURL = logDirectoryURL.appendingPathComponent("runtime.previous.log")
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            if fileManager.fileExists(atPath: logFileURL.path) {
                try fileManager.moveItem(at: logFileURL, to: backupURL)
            }
        } catch {
            print("Failed to rotate runtime log: \(error)")
        }
    }
}
