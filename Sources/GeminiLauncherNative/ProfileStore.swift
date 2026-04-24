import AppKit
import Combine
import Foundation

enum StatePersistenceMode {
    case automatic
    case fileOnly
}

private enum ActivePersistenceBackend {
    case mongo
    case file
}

@MainActor
final class ProfileStore: ObservableObject {
    private let fileManager = FileManager.default
    private let persistenceMode: StatePersistenceMode
    private let mongoStateStore: MongoStateStore?
    private(set) var stateURL: URL
    private var activePersistenceBackend: ActivePersistenceBackend
    private var isApplyingStateNormalization = false
    private var pendingSaveTask: Task<Void, Never>?
    private static let saveDebounceNanoseconds: UInt64 = 400_000_000
    nonisolated(unsafe) private var terminationObserver: NSObjectProtocol?

    @Published var profiles: [LaunchProfile] { didSet { stateDidChange() } }
    @Published var selectedProfileID: UUID? { didSet { stateDidChange() } }
    @Published var settings: AppSettings { didSet { stateDidChange() } }
    @Published var history: [LaunchHistoryItem] { didSet { stateDidChange() } }
    @Published var bookmarks: [WorkspaceBookmark] { didSet { stateDidChange() } }
    @Published var workbenches: [LaunchWorkbench] { didSet { stateDidChange() } }

    var persistenceLocationDescription: String {
        switch activePersistenceBackend {
        case .mongo:
            return mongoStateStore?.locationDescription ?? stateURL.path
        case .file:
            return stateURL.path
        }
    }

    var persistenceBackendDescription: String {
        switch activePersistenceBackend {
        case .mongo: return "Local MongoDB"
        case .file: return "JSON file fallback"
        }
    }

    var persistenceContainerPath: String {
        switch activePersistenceBackend {
        case .mongo:
            return mongoStateStore?.dataDirectoryPath ?? stateURL.deletingLastPathComponent().path
        case .file:
            return stateURL.deletingLastPathComponent().path
        }
    }

    init(persistenceMode: StatePersistenceMode = .automatic) {
        self.persistenceMode = persistenceMode
        mongoStateStore = persistenceMode == .automatic ? MongoStateStore() : nil
        activePersistenceBackend = persistenceMode == .automatic ? .mongo : .file
        let folder = AppPaths.containerDirectory
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let resolvedStateURL = AppPaths.stateFileURL

        let initialProfiles: [LaunchProfile]
        let initialSelectedProfileID: UUID?
        let initialSettings: AppSettings
        let initialHistory: [LaunchHistoryItem]
        let initialBookmarks: [WorkspaceBookmark]
        let initialWorkbenches: [LaunchWorkbench]

        let loadedBackend: ActivePersistenceBackend?
        if let (state, backend) = Self.loadPersistedState(
            primaryStore: mongoStateStore,
            stateURL: resolvedStateURL,
            appSupport: AppPaths.applicationSupportDirectory
        ) {
            activePersistenceBackend = backend
            loadedBackend = backend
            initialProfiles = state.profiles
            initialSelectedProfileID = state.selectedProfileID ?? state.profiles.first?.id
            initialSettings = state.settings
            initialHistory = state.history
            initialBookmarks = state.bookmarks
            initialWorkbenches = state.workbenches
        } else {
            loadedBackend = nil
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
        if persistenceMode == .automatic, loadedBackend == nil {
            flushPendingSave()
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushPendingSave()
            }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
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

    private static func loadPersistedState(
        primaryStore: MongoStateStore?,
        stateURL: URL,
        appSupport: URL
    ) -> (PersistedState, ActivePersistenceBackend)? {
        if let primaryStore,
           let state = try? primaryStore.loadState() {
            return (state, .mongo)
        }

        if let state = loadState(at: stateURL) {
            if let primaryStore {
                if let _ = try? primaryStore.saveState(state) {
                    return (state, .mongo)
                }
            }
            return (state, .file)
        }

        if let state = loadLegacyState(from: appSupport) {
            if let primaryStore {
                if let _ = try? primaryStore.saveState(state) {
                    return (state, .mongo)
                }
            }
            return (state, .file)
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
        return profiles.firstIndex { $0.id == selectedProfileID }
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

    func updateProfiles(_ mutation: (inout [LaunchProfile]) -> Void) {
        performBatchedMutation {
            mutation(&profiles)
        }
    }

    func applySettings(_ newSettings: AppSettings, mutatingProfiles mutation: ((inout [LaunchProfile]) -> Void)? = nil) {
        performBatchedMutation {
            settings = newSettings
            mutation?(&profiles)
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

    private func uniqueMonitorSessionIDs(from plan: PlannedLaunch) -> [UUID] {
        let sessionIDs = plan.items.compactMap(\.monitorSessionID)
        return Array(NSOrderedSet(array: sessionIDs)) as? [UUID] ?? sessionIDs
    }

    func recordLaunch(profile: LaunchProfile, plan: PlannedLaunch) {
        performBatchedMutation {
            history.insert(
                LaunchHistoryItem(
                    profileID: profile.id,
                    profileName: profile.name,
                    description: (plan.items.first?.description ?? profile.name) + (plan.postLaunchActions.isEmpty ? "" : " • +\(plan.postLaunchActions.count) post-launch"),
                    command: plan.items.first?.command ?? "",
                    companionCount: max(plan.items.count - 1, 0),
                    monitorSessionIDs: uniqueMonitorSessionIDs(from: plan)
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
                    workbenchID: workbench.id,
                    profileName: workbench.name,
                    description: "Workbench • \(workbench.role.displayName) • \(plan.items.count) tab(s), startup delay \(workbench.startupDelayMs)ms" + (plan.postLaunchActions.isEmpty ? "" : " • +\(plan.postLaunchActions.count) post-launch"),
                    command: plan.combinedCommandPreview,
                    companionCount: max(plan.items.count - 1, 0),
                    monitorSessionIDs: uniqueMonitorSessionIDs(from: plan)
                ),
                at: 0
            )
        }
    }

    func relaunchTarget(for item: LaunchHistoryItem) -> LaunchHistoryTarget? {
        if let profileID = item.profileID,
           let profile = profiles.first(where: { $0.id == profileID }) {
            return .profile(profile)
        }
        if let workbenchID = item.workbenchID,
           let workbench = workbenches.first(where: { $0.id == workbenchID }) {
            return .workbench(workbench)
        }
        return nil
    }

    func relaunchLastItem() -> LaunchHistoryItem? {
        history.first(where: { self.relaunchTarget(for: $0) != nil })
    }

    func relaunchLastTarget() -> LaunchHistoryTarget? {
        relaunchLastItem().flatMap { self.relaunchTarget(for: $0) }
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
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.saveDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.performPendingSave()
        }
    }

    private func performPendingSave() {
        pendingSaveTask = nil
        writeStateToDisk()
    }

    func flushPendingSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        writeStateToDisk()
    }

    private func writeStateToDisk() {
        let state = currentPersistedState()
        if let mongoStateStore,
           let _ = try? mongoStateStore.saveState(state) {
            activePersistenceBackend = .mongo
            return
        }

        do {
            let data = try JSONEncoder.pretty.encode(state)
            try data.write(to: stateURL, options: [.atomic])
            activePersistenceBackend = .file
        } catch {
            print("Failed to save state: \(error)")
        }
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
        normalizedSettings.bootstrapSessionRecordingIfNeeded()
        normalizedSettings.maxHistoryItems = max(1, min(1_000, normalizedSettings.maxHistoryItems))
        normalizedSettings.maxBookmarks = max(1, min(1_000, normalizedSettings.maxBookmarks))

        var monitoring = normalizedSettings.mongoMonitoring
        monitoring.pollingIntervalMs = max(100, min(60_000, monitoring.pollingIntervalMs))
        monitoring.previewCharacterLimit = max(100, min(20_000, monitoring.previewCharacterLimit))
        monitoring.recentHistoryLimit = monitoring.clampedRecentHistoryLimit
        monitoring.recentHistoryLookbackDays = monitoring.clampedRecentHistoryLookbackDays
        monitoring.detailEventLimit = monitoring.clampedDetailEventLimit
        monitoring.detailChunkLimit = monitoring.clampedDetailChunkLimit
        monitoring.transcriptPreviewByteLimit = monitoring.clampedTranscriptPreviewByteLimit
        monitoring.databaseRetentionDays = monitoring.clampedDatabaseRetentionDays
        monitoring.localTranscriptRetentionDays = monitoring.clampedLocalTranscriptRetentionDays
        normalizedSettings.mongoMonitoring = monitoring

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
        flushPendingSave()
    }

    func setStateURLForTesting(_ url: URL) {
        stateURL = url
    }

    nonisolated static func propagateGeminiWorkingDirectoryChange(
        in profiles: inout [LaunchProfile],
        replacing oldWorkingDirectory: String,
        with newWorkingDirectory: String,
        excluding profileID: UUID? = nil
    ) -> Int {
        let oldPath = oldWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPath = newWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldPath.isEmpty, !newPath.isEmpty, oldPath != newPath else { return 0 }

        var updatedCount = 0
        for index in profiles.indices {
            guard profiles[index].agentKind == .gemini else { continue }
            guard profiles[index].id != profileID else { continue }
            guard profiles[index].workingDirectory == oldPath else { continue }
            profiles[index].workingDirectory = newPath
            updatedCount += 1
        }
        return updatedCount
    }

    private static func uniquePreservingOrder<T: Hashable>(_ items: [T]) -> [T] {
        var seen: Set<T> = []
        return items.filter { seen.insert($0).inserted }
    }
}
