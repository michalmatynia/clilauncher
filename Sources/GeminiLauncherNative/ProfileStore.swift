import AppKit
import Combine
import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    private let fileManager = FileManager.default
    private(set) var stateURL: URL
    private var isApplyingStateNormalization = false

    @Published var profiles: [LaunchProfile] { didSet { stateDidChange() } }
    @Published var selectedProfileID: UUID? { didSet { stateDidChange() } }
    @Published var settings: AppSettings { didSet { stateDidChange() } }
    @Published var history: [LaunchHistoryItem] { didSet { stateDidChange() } }
    @Published var bookmarks: [WorkspaceBookmark] { didSet { stateDidChange() } }
    @Published var workbenches: [LaunchWorkbench] { didSet { stateDidChange() } }

    init() {
        let folder = AppPaths.containerDirectory
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let resolvedStateURL = AppPaths.stateFileURL

        let initialProfiles: [LaunchProfile]
        let initialSelectedProfileID: UUID?
        let initialSettings: AppSettings
        let initialHistory: [LaunchHistoryItem]
        let initialBookmarks: [WorkspaceBookmark]
        let initialWorkbenches: [LaunchWorkbench]

        if let state = Self.loadState(at: resolvedStateURL) ?? Self.loadLegacyState(from: AppPaths.applicationSupportDirectory) {
            initialProfiles = state.profiles
            initialSelectedProfileID = state.selectedProfileID ?? state.profiles.first?.id
            initialSettings = state.settings
            initialHistory = state.history
            initialBookmarks = state.bookmarks
            initialWorkbenches = state.workbenches
        } else {
            let defaultSettings = AppSettings()
            let starters = Self.defaultProfiles(settings: defaultSettings)
            initialProfiles = starters
            initialSelectedProfileID = starters.first?.id
            initialSettings = defaultSettings
            initialHistory = []
            initialBookmarks = []
            initialWorkbenches = Self.defaultWorkbenches(profiles: starters)
        }

        stateURL = resolvedStateURL
        profiles = initialProfiles
        selectedProfileID = initialSelectedProfileID
        settings = initialSettings
        history = initialHistory
        bookmarks = initialBookmarks
        workbenches = initialWorkbenches
        normalizeState()
    }

    private static func loadState(at url: URL) -> PersistedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.pretty.decode(PersistedState.self, from: data)
    }

    private static func loadLegacyState(from appSupport: URL) -> PersistedState? {
        let candidates = AppPaths.legacyFolderNames.map {
            appSupport.appendingPathComponent($0, isDirectory: true).appendingPathComponent("state.json")
        }
        for candidate in candidates {
            if let state = loadState(at: candidate), !state.profiles.isEmpty {
                return state
            }
        }
        return nil
    }

    static func defaultProfiles(settings: AppSettings) -> [LaunchProfile] {
        let starters = LaunchTemplateCatalog.defaultProfiles(using: settings)
        return starters.isEmpty ? [LaunchProfile.starter(kind: .gemini, settings: settings)] : starters
    }

    static func defaultWorkbenches(profiles: [LaunchProfile]) -> [LaunchWorkbench] {
        WorkbenchTemplateCatalog.defaultWorkbenches(using: profiles)
    }

    static func fallbackStarterProfile(settings: AppSettings) -> LaunchProfile {
        defaultProfiles(settings: settings).first ?? LaunchProfile.starter(kind: .gemini, settings: settings)
    }

    var selectedIndex: Int? {
        guard let selectedProfileID else { return nil }
        return profiles.firstIndex(where: { $0.id == selectedProfileID })
    }

    var selectedProfile: LaunchProfile? {
        guard let index = selectedIndex else { return nil }
        return profiles[index]
    }

    func updateSelected(_ mutation: (inout LaunchProfile) -> Void) {
        guard let index = selectedIndex else { return }
        performBatchedMutation {
            var value = profiles[index]
            mutation(&value)
            profiles[index] = value
        }
    }

    func addProfile(kind: AgentKind) {
        performBatchedMutation {
            let profile = LaunchProfile.starter(kind: kind, settings: settings)
            profiles.append(profile)
            selectedProfileID = profile.id
        }
    }

    func duplicateSelectedProfile() {
        guard let selectedProfile else { return }
        performBatchedMutation {
            var copy = selectedProfile
            copy.id = UUID()
            copy.name = selectedProfile.name + " Copy"
            profiles.append(copy)
            selectedProfileID = copy.id
        }
    }

    func removeSelectedProfile() {
        guard let selectedIndex else { return }
        performBatchedMutation {
            let removedID = profiles[selectedIndex].id
            profiles.remove(at: selectedIndex)

            for index in profiles.indices {
                profiles[index].companionProfileIDs.removeAll { $0 == removedID }
            }
            for index in workbenches.indices {
                workbenches[index].profileIDs.removeAll { $0 == removedID }
            }
            for index in bookmarks.indices where bookmarks[index].defaultProfileID == removedID {
                bookmarks[index].defaultProfileID = nil
            }

            if profiles.isEmpty {
                let replacement = Self.fallbackStarterProfile(settings: settings)
                profiles = [replacement]
                selectedProfileID = replacement.id
            } else {
                selectedProfileID = profiles[min(selectedIndex, profiles.count - 1)].id
            }
        }
    }

    func addWorkbench(seedProfileID: UUID? = nil, sharedBookmarkID: UUID? = nil) -> LaunchWorkbench {
        var workbench = LaunchWorkbench()
        performBatchedMutation {
            workbench.name = "New Workbench"
            workbench.sharedBookmarkID = sharedBookmarkID
            if let seedProfileID {
                workbench.profileIDs = [seedProfileID]
            }
            workbenches.insert(workbench, at: 0)
        }
        return workbench
    }

    func duplicateWorkbench(_ id: UUID) -> LaunchWorkbench? {
        guard let existing = workbenches.first(where: { $0.id == id }) else { return nil }
        var copy = existing
        performBatchedMutation {
            copy.id = UUID()
            copy.name += " Copy"
            copy.lastLaunchedAt = nil
            workbenches.insert(copy, at: 0)
        }
        return copy
    }

    func removeWorkbench(_ id: UUID) {
        performBatchedMutation {
            workbenches.removeAll { $0.id == id }
        }
    }

    func touchWorkbench(_ id: UUID) {
        guard let index = workbenches.firstIndex(where: { $0.id == id }) else { return }
        performBatchedMutation {
            workbenches[index].lastLaunchedAt = Date()
        }
    }

    func recordLaunch(profile: LaunchProfile, plan: PlannedLaunch) {
        performBatchedMutation {
            history.insert(
                LaunchHistoryItem(
                    profileID: profile.id,
                    profileName: profile.name,
                    description: (plan.items.first?.description ?? profile.name) + (plan.postLaunchActions.isEmpty ? "" : " • +\(plan.postLaunchActions.count) post-launch"),
                    command: plan.items.first?.command ?? "",
                    companionCount: max(plan.items.count - 1, 0)
                ),
                at: 0
            )
        }
    }

    func recordLaunch(workbench: LaunchWorkbench, plan: PlannedLaunch) {
        performBatchedMutation {
            history.insert(
                LaunchHistoryItem(
                    profileID: nil,
                    profileName: workbench.name,
                    description: "Workbench • \(workbench.role.displayName) • \(plan.items.count) tab(s), startup delay \(workbench.startupDelayMs)ms" + (plan.postLaunchActions.isEmpty ? "" : " • +\(plan.postLaunchActions.count) post-launch"),
                    command: plan.combinedCommandPreview,
                    companionCount: max(plan.items.count - 1, 0)
                ),
                at: 0
            )
        }
    }

    func relaunchLast() -> LaunchProfile? {
        guard let latest = history.first else { return nil }
        if let profileID = latest.profileID, let profile = profiles.first(where: { $0.id == profileID }) {
            return profile
        }
        return nil
    }

    func addBookmark(from profile: LaunchProfile) {
        performBatchedMutation {
            let bookmark = WorkspaceBookmark(
                name: profile.name,
                path: profile.workingDirectory,
                tags: profile.tags,
                notes: profile.notes,
                defaultProfileID: profile.id,
                createdAt: Date(),
                lastUsedAt: nil
            )
            bookmarks.insert(bookmark, at: 0)
        }
    }

    func addBookmark(name: String, path: String, defaultProfileID: UUID? = nil) {
        performBatchedMutation {
            let bookmark = WorkspaceBookmark(name: name, path: path, tags: [], notes: "", defaultProfileID: defaultProfileID, createdAt: Date(), lastUsedAt: nil)
            bookmarks.insert(bookmark, at: 0)
        }
    }

    func apply(bookmark: WorkspaceBookmark, to profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        performBatchedMutation {
            profiles[index].workingDirectory = bookmark.path
            profiles[index].tags = Array(Set(profiles[index].tags + bookmark.tags)).sorted()
        }
    }

    func touchBookmark(_ id: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        performBatchedMutation {
            bookmarks[index].lastUsedAt = Date()
        }
    }

    func removeBookmark(_ bookmark: WorkspaceBookmark) {
        performBatchedMutation {
            bookmarks.removeAll { $0.id == bookmark.id }
            for index in workbenches.indices where workbenches[index].sharedBookmarkID == bookmark.id {
                workbenches[index].sharedBookmarkID = nil
            }
        }
    }

    func exportState(to url: URL) throws {
        let data = try JSONEncoder.pretty.encode(currentPersistedState())
        try data.write(to: url, options: [.atomic])
    }

    func importState(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let state = try JSONDecoder.pretty.decode(PersistedState.self, from: data)
        performBatchedMutation {
            profiles = state.profiles
            selectedProfileID = state.selectedProfileID ?? state.profiles.first?.id
            settings = state.settings
            history = state.history
            bookmarks = state.bookmarks
            workbenches = state.workbenches
        }
    }

    func reveal(_ path: String) {
        let expanded = NSString(string: path).expandingTildeInPath
        NSWorkspace.shared.selectFile(expanded, inFileViewerRootedAtPath: "")
    }

    private func stateDidChange() {
        guard !isApplyingStateNormalization else { return }
        normalizeState()
    }

    private func normalizeState() {
        performNormalizationSuppressed {
            clampSettingLimitsWithoutNotifications()
            trimCollectionsWithoutNotifications()
            sanitizeReferencesWithoutNotifications()
            clampSelectionWithoutNotifications()
        }
        save()
    }

    private func performNormalizationSuppressed(_ mutation: () -> Void) {
        let wasAlreadyApplying = isApplyingStateNormalization
        isApplyingStateNormalization = true
        defer { isApplyingStateNormalization = wasAlreadyApplying }
        mutation()
    }

    private func performBatchedMutation(_ mutation: () -> Void) {
        let wasAlreadyApplying = isApplyingStateNormalization
        performNormalizationSuppressed(mutation)
        guard !wasAlreadyApplying else { return }
        normalizeState()
    }

    private func clampSettingLimitsWithoutNotifications() {
        var normalizedSettings = settings
        normalizedSettings.maxHistoryItems = max(1, min(1_000, normalizedSettings.maxHistoryItems))
        normalizedSettings.maxBookmarks = max(1, min(1_000, normalizedSettings.maxBookmarks))

        var monitoring = normalizedSettings.postgresMonitoring
        monitoring.pollingIntervalMs = max(100, min(60_000, monitoring.pollingIntervalMs))
        monitoring.previewCharacterLimit = max(100, min(20_000, monitoring.previewCharacterLimit))
        monitoring.recentHistoryLimit = monitoring.clampedRecentHistoryLimit
        monitoring.recentHistoryLookbackDays = monitoring.clampedRecentHistoryLookbackDays
        monitoring.detailEventLimit = monitoring.clampedDetailEventLimit
        monitoring.detailChunkLimit = monitoring.clampedDetailChunkLimit
        monitoring.transcriptPreviewByteLimit = monitoring.clampedTranscriptPreviewByteLimit
        monitoring.databaseRetentionDays = monitoring.clampedDatabaseRetentionDays
        monitoring.localTranscriptRetentionDays = monitoring.clampedLocalTranscriptRetentionDays
        normalizedSettings.postgresMonitoring = monitoring

        var observability = normalizedSettings.observability
        observability.maxInMemoryEntries = max(100, min(10_000, observability.maxInMemoryEntries))
        normalizedSettings.observability = observability

        if normalizedSettings != settings {
            settings = normalizedSettings
        }
    }

    private func trimCollectionsWithoutNotifications() {
        let historyLimit = max(1, settings.maxHistoryItems)
        if history.count > historyLimit {
            history = Array(history.prefix(historyLimit))
        }

        let bookmarkLimit = max(1, settings.maxBookmarks)
        if bookmarks.count > bookmarkLimit {
            bookmarks = Array(bookmarks.prefix(bookmarkLimit))
        }

        if workbenches.count > 60 {
            workbenches = Array(workbenches.prefix(60))
        }
    }

    private func sanitizeReferencesWithoutNotifications() {
        let profileIDs = Set(profiles.map(\.id))
        let bookmarkIDs = Set(bookmarks.map(\.id))
        let environmentPresetIDs = Set(settings.environmentPresets.map(\.id))
        let bootstrapPresetIDs = Set(settings.shellBootstrapPresets.map(\.id))

        var normalizedProfiles = profiles
        for index in normalizedProfiles.indices {
            normalizedProfiles[index].agentKind.providerDefinition.normalizeMissingFields?(&normalizedProfiles[index])

            let currentID = normalizedProfiles[index].id
            let companionIDs = normalizedProfiles[index].companionProfileIDs.filter { $0 != currentID && profileIDs.contains($0) }
            let dedupedCompanionIDs = Self.uniquePreservingOrder(companionIDs)
            if normalizedProfiles[index].companionProfileIDs != dedupedCompanionIDs {
                normalizedProfiles[index].companionProfileIDs = dedupedCompanionIDs
            }

            if let presetID = normalizedProfiles[index].environmentPresetID, !environmentPresetIDs.contains(presetID) {
                normalizedProfiles[index].environmentPresetID = nil
            }
            if let presetID = normalizedProfiles[index].bootstrapPresetID, !bootstrapPresetIDs.contains(presetID) {
                normalizedProfiles[index].bootstrapPresetID = nil
            }
        }
        if normalizedProfiles != profiles {
            profiles = normalizedProfiles
        }

        var normalizedBookmarks = bookmarks
        for index in normalizedBookmarks.indices {
            if let defaultProfileID = normalizedBookmarks[index].defaultProfileID, !profileIDs.contains(defaultProfileID) {
                normalizedBookmarks[index].defaultProfileID = nil
            }
        }
        if normalizedBookmarks != bookmarks {
            bookmarks = normalizedBookmarks
        }

        var normalizedWorkbenches = workbenches
        for index in normalizedWorkbenches.indices {
            let filteredProfileIDs = normalizedWorkbenches[index].profileIDs.filter { profileIDs.contains($0) }
            let dedupedProfileIDs = Self.uniquePreservingOrder(filteredProfileIDs)
            if normalizedWorkbenches[index].profileIDs != dedupedProfileIDs {
                normalizedWorkbenches[index].profileIDs = dedupedProfileIDs
            }

            if let sharedBookmarkID = normalizedWorkbenches[index].sharedBookmarkID, !bookmarkIDs.contains(sharedBookmarkID) {
                normalizedWorkbenches[index].sharedBookmarkID = nil
            }
        }
        if normalizedWorkbenches != workbenches {
            workbenches = normalizedWorkbenches
        }
    }

    private func clampSelectionWithoutNotifications() {
        if profiles.isEmpty {
            let replacement = Self.fallbackStarterProfile(settings: settings)
            profiles = [replacement]
            selectedProfileID = replacement.id
            return
        }

        if let selectedProfileID, profiles.contains(where: { $0.id == selectedProfileID }) {
            return
        }

        selectedProfileID = profiles.first?.id
    }

    private func currentPersistedState() -> PersistedState {
        let historyLimit = max(1, settings.maxHistoryItems)
        let bookmarkLimit = max(1, settings.maxBookmarks)
        return PersistedState(
            profiles: profiles,
            selectedProfileID: selectedProfileID,
            settings: settings,
            history: Array(history.prefix(historyLimit)),
            bookmarks: Array(bookmarks.prefix(bookmarkLimit)),
            workbenches: Array(workbenches.prefix(60))
        )
    }

    func save() {
        do {
            let data = try JSONEncoder.pretty.encode(currentPersistedState())
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            print("Failed to save state: \(error)")
        }
    }

    private static func uniquePreservingOrder<T: Hashable>(_ items: [T]) -> [T] {
        var seen: Set<T> = []
        return items.filter { seen.insert($0).inserted }
    }
}

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
        if level == .debug && !settings.verboseLogging {
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
