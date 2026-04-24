import SwiftUI
import UniformTypeIdentifiers

private enum MonitorSessionSourceFilter: String, CaseIterable, Identifiable {
    case all
    case liveOnly
    case postgresHistory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All sources"
        case .liveOnly: return "Live only"
        case .postgresHistory: return "Mongo history"
        }
    }

    func matches(_ session: TerminalMonitorSession) -> Bool {
        switch self {
        case .all: return true
        case .liveOnly: return !session.isHistorical
        case .postgresHistory: return session.isHistorical
        }
    }
}

private enum MonitorSessionStatusFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case completed
    case failed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All statuses"
        case .active: return "Active"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    func matches(_ session: TerminalMonitorSession) -> Bool {
        switch self {
        case .all:
            return true

        case .active:
            return [.prepared, .launching, .monitoring, .idle].contains(session.status)

        case .completed:
            return session.status == .completed

        case .failed:
            return session.status == .failed || session.status == .stopped
        }
    }
}

private struct MonitorSessionExportPayload: Codable {
    var exportedAt: Date
    var session: TerminalMonitorSession
    var details: TerminalMonitorSessionDetails?
}

private struct MonitorSessionSearchIndexEntry {
    var fingerprint: String
    var blob: String
}

private struct MonitorSessionRefreshInputs: Equatable {
    var sessions: [TerminalMonitorSession]
    var query: String
    var sourceFilter: MonitorSessionSourceFilter
    var statusFilter: MonitorSessionStatusFilter
}

@MainActor
private struct MonitorSessionRowView: View, Equatable {
    let session: TerminalMonitorSession

    nonisolated static func == (lhs: MonitorSessionRowView, rhs: MonitorSessionRowView) -> Bool {
        lhs.session == rhs.session
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: session.status.systemImage)
                    .foregroundStyle(statusColor(for: session.status))
                    .frame(width: 16)

                Text(session.profileName)
                    .font(.headline)

                Spacer()

                if session.isHistorical {
                    Text("DB")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                }

                if session.isYolo {
                    Text("YOLO")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .cornerRadius(4)
                }
            }

            Text("\(session.agentKind.displayName) • \(session.workingDirectory)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let accountIdentifier = session.accountIdentifier, !accountIdentifier.isEmpty {
                Text("Account: \(accountIdentifier)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !session.prompt.isEmpty {
                Text(session.prompt.count > 140 ? String(session.prompt.prefix(140)) + "…" : session.prompt)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
            }

            if !session.lastPreview.isEmpty {
                Text(session.lastPreview)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
            }

            HStack(spacing: 12) {
                Label("\(session.chunkCount)", systemImage: "waveform")
                    .font(.caption2)
                Label(byteCountString(session.byteCount), systemImage: "internaldrive")
                    .font(.caption2)
                if let exitCode = session.exitCode {
                    Label("exit \(exitCode)", systemImage: exitCode == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                }
                Spacer()
                Text(session.activityDate.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func byteCountString(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private func statusColor(for status: TerminalMonitorStatus) -> Color {
        switch status {
        case .prepared, .launching:
            return .blue
        case .monitoring:
            return .green
        case .idle:
            return .orange
        case .completed:
            return .green
        case .failed, .stopped:
            return .red
        }
    }
}

@MainActor
private struct MonitorSessionListPaneView: View, Equatable {
    let sessions: [TerminalMonitorSession]
    let selectedSessionID: UUID?
    let setSelectedSessionID: @MainActor @Sendable (UUID?) -> Void

    nonisolated static func == (lhs: MonitorSessionListPaneView, rhs: MonitorSessionListPaneView) -> Bool {
        lhs.sessions == rhs.sessions && lhs.selectedSessionID == rhs.selectedSessionID
    }

    var body: some View {
        GroupBox("Sessions") {
            List(selection: Binding(get: { selectedSessionID }, set: setSelectedSessionID)) {
                if sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No monitored terminal sessions found.")
                            .font(.headline)
                        Text("Launch a profile or workbench through the app. Session recording runs automatically while monitoring remains enabled, and MongoDB-backed history appears here when database writes are on.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                } else {
                    ForEach(sessions) { session in
                        MonitorSessionRowView(session: session)
                            .equatable()
                            .tag(Optional(session.id))
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private enum MonitorDetailSection: String, Hashable {
    case transcript
    case ioTimeline
    case inputStream
    case events
    case chunks

    var displayName: String {
        switch self {
        case .transcript:
            return "Transcript"
        case .ioTimeline:
            return "Session I/O Timeline"
        case .inputStream:
            return "Stdin Stream"
        case .events:
            return "Event Timeline"
        case .chunks:
            return "Recent Transcript Chunks"
        }
    }

    var requiresHistoryLoad: Bool {
        true
    }
}

struct MonitoringDashboardView: View {
    let isVisible: Bool

    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var logger: LaunchLogger
    @EnvironmentObject private var terminalMonitor: TerminalMonitorStore

    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var sessionRefreshDebounceTask: Task<Void, Never>?
    @State private var detailLoadDebounceTask: Task<Void, Never>?
    @State private var autoRefreshTask: Task<Void, Never>?
    @State private var selectedSessionID: UUID?
    @State private var sourceFilter: MonitorSessionSourceFilter = .all
    @State private var statusFilter: MonitorSessionStatusFilter = .all
    @State private var showingPruneConfirmation = false
    @State private var filteredSessionsCache: [TerminalMonitorSession] = []
    @State private var filteredSessionIndex: [UUID: TerminalMonitorSession] = [:]
    @State private var allLiveSessionCount = 0
    @State private var allHistoricalSessionCount = 0
    @State private var allCompletedSessionCount = 0
    @State private var allFailedSessionCount = 0
    @State private var searchIndexCache: [UUID: MonitorSessionSearchIndexEntry] = [:]
    @State private var lastSessionRefreshInputs: MonitorSessionRefreshInputs?
    @State private var expandedDetailSections: Set<MonitorDetailSection> = []

    private var filteredSessions: [TerminalMonitorSession] {
        filteredSessionsCache
    }

    private var selectedSession: TerminalMonitorSession? {
        guard let selectedSessionID else { return nil }
        return filteredSessionIndex[selectedSessionID]
    }

    private var selectedDetails: TerminalMonitorSessionDetails? {
        guard let selectedSession else { return nil }
        return terminalMonitor.details(for: selectedSession.id)
    }

    private var liveSessionCount: Int {
        sessionCounts.live
    }

    private var historicalSessionCount: Int {
        sessionCounts.historical
    }

    private var completedSessionCount: Int {
        sessionCounts.completed
    }

    private var failedSessionCount: Int {
        sessionCounts.failed
    }

    private var sessionCounts: (live: Int, historical: Int, completed: Int, failed: Int) {
        (live: allLiveSessionCount, historical: allHistoricalSessionCount, completed: allCompletedSessionCount, failed: allFailedSessionCount)
    }

    private let autoRefreshIntervalNanoseconds: UInt64 = 4_000_000_000
    private let sessionRefreshDebounceNanoseconds: UInt64 = 120_000_000
    private let detailLoadDebounceNanoseconds: UInt64 = 80_000_000

    private func logMonitoringViewTiming(_ operation: String, startedAt: CFTimeInterval, details: String? = nil) {
        let elapsedMs = Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded())
        let mergedDetails = [details, "elapsed_ms=\(elapsedMs)"].compactMap(\.self).joined(separator: " • ")
        logger.debug("Monitoring view timing: \(operation)", category: .monitoring, details: mergedDetails)
    }

    nonisolated static func geminiStartupCommandSourceDisplayName(_ source: String) -> String {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "runner_banner":
            return "Runner banner"
        case "echoed_command":
            return "Echoed transcript command"
        default:
            return source
        }
    }

    nonisolated static func geminiRunnerBuildStatusText(
        sessionRunnerBuild: String?,
        bundledRunnerBuild: String? = BundledGeminiAutomationRunner.buildID
    ) -> String? {
        let sessionBuild = sessionRunnerBuild?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sessionBuild.isEmpty else { return nil }

        let bundledBuild = bundledRunnerBuild?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !bundledBuild.isEmpty else { return "Bundled app runner build is unavailable" }

        if sessionBuild == bundledBuild {
            return "Matches bundled app runner"
        }

        return "Differs from bundled app runner (\(bundledBuild))"
    }

    nonisolated static func geminiRunnerPathStatusText(
        sessionRunnerPath: String?,
        bundledRunnerPath: String? = BundledGeminiAutomationRunner.displayPath
    ) -> String? {
        let sessionPath = sessionRunnerPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sessionPath.isEmpty else { return nil }

        let bundledPath = bundledRunnerPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !bundledPath.isEmpty else { return "Bundled app runner path is unavailable" }

        if sessionPath == bundledPath {
            return "Matches bundled app runner path"
        }

        return "Differs from bundled app runner path"
    }

    nonisolated static func normalizedSessionSearchBlob(for session: TerminalMonitorSession) -> String {
        var parts: [String] = []
        parts.reserveCapacity(48)

        func append(_ value: String?) {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return
            }
            parts.append(trimmed)
        }

        append(session.profileName)
        append(session.workingDirectory)
        append(session.transcriptPath)
        append(session.inputCapturePath)
        append(session.lastPreview)
        append(session.lastDatabaseMessage)
        append(session.accountIdentifier)
        append(session.providerSessionID)
        append(session.providerAuthMethod)
        append(session.providerTier)
        append(session.providerCLIVersion)
        append(session.providerRunnerPath)
        append(Self.geminiRunnerPathStatusText(sessionRunnerPath: session.providerRunnerPath))
        append(session.providerRunnerBuild)
        append(Self.geminiRunnerBuildStatusText(sessionRunnerBuild: session.providerRunnerBuild))
        append(session.providerWrapperResolvedPath)
        append(session.providerWrapperKind)
        append(session.providerLaunchMode)
        append(session.providerShellFallbackExecutable)
        append(session.providerAutoContinueMode)
        append(session.providerPTYBackend)
        append(session.providerStartupClearCommand)
        append(session.providerStartupClearCommandSource)
        append(session.providerStartupClearCommandSource.map(Self.geminiStartupCommandSourceDisplayName))
        append(session.providerStartupClearReason)
        append(session.providerStartupStatsCommand)
        append(session.providerStartupStatsCommandSource)
        append(session.providerStartupStatsCommandSource.map(Self.geminiStartupCommandSourceDisplayName))
        append(session.providerStartupModelCommand)
        append(session.providerStartupModelCommandSource)
        append(session.providerStartupModelCommandSource.map(Self.geminiStartupCommandSourceDisplayName))
        append(session.providerCurrentModel)
        append(session.mongoTranscriptSyncState?.rawValue)
        append(session.mongoTranscriptSyncState?.displayName)
        append(session.mongoTranscriptSyncSource)
        append(session.mongoTranscriptSyncSourceDisplayName)
        append(session.mongoInputSyncState?.rawValue)
        append(session.mongoInputSyncState?.displayName)
        append(session.mongoInputSyncSource)
        append(session.mongoInputSyncSourceDisplayName)
        append(session.providerFreshSessionResetReason)
        append(session.providerModelUsageNote)
        append(session.prompt)
        append(session.statusReason)
        append(session.lastError)
        append(session.agentKind.displayName)
        append(session.status.displayName)
        append(session.id.uuidString)

        session.observedSlashCommands?.forEach { append($0) }
        session.observedPromptSubmissions?.forEach { append($0) }
        session.providerModelUsage?.forEach { row in
            append(row.model)
            append(row.label)
        }
        session.providerModelCapacity?.forEach { row in
            append(row.model)
            append(row.resetTime)
            append(row.rawText)
            if let usedPercentage = row.usedPercentage {
                append("\(usedPercentage)%")
            }
        }
        session.providerModelCapacityRawLines?.forEach { append($0) }

        return parts.joined(separator: "\u{1F}").lowercased()
    }

    private func sessionSearchBlob(for session: TerminalMonitorSession) -> String {
        let fingerprint = Self.normalizedSessionSearchBlob(for: session)
        if let cached = searchIndexCache[session.id], cached.fingerprint == fingerprint {
            return cached.blob
        }
        let entry = MonitorSessionSearchIndexEntry(fingerprint: fingerprint, blob: fingerprint)
        searchIndexCache[session.id] = entry
        return entry.blob
    }

    var body: some View {
        Group {
            if isVisible {
                visibleDashboardBody
            } else {
                hiddenDashboardPlaceholder
            }
        }
        .padding(isVisible ? 16 : 0)
        .onAppear {
            debouncedSearchText = searchText
            resetDetailSectionExpansion()
            refreshFilteredSessions(force: true)
            handleVisibilityChange(isVisible)
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            sessionRefreshDebounceTask?.cancel()
            detailLoadDebounceTask?.cancel()
            stopAutoRefresh()
        }
        .onChange(of: terminalMonitor.sessions) { _ in
            debounceSessionRefresh()
        }
        .onChange(of: store.settings.mongoMonitoring) { _ in
            performVisibleRefresh(
                forceRecentSessions: true,
                recentSessionsWorkload: .maintenance,
                includeStorageSummary: true,
                forceDetails: false,
                detailWorkload: .summary
            )
        }
        .onChange(of: searchText) { _ in
            debounceSearchFilter()
        }
        .onChange(of: sourceFilter) { _ in
            refreshFilteredSessions()
        }
        .onChange(of: statusFilter) { _ in
            refreshFilteredSessions()
        }
        .onChange(of: selectedSessionID) { _ in
            resetDetailSectionExpansion()
            debounceSelectedDetailsLoad(forceRefresh: false, workload: .summary)
        }
        .onChange(of: isVisible) { newValue in
            handleVisibilityChange(newValue)
        }
        .confirmationDialog(
            "Prune stored monitoring history?",
            isPresented: $showingPruneConfirmation,
            titleVisibility: .visible
        ) {
            Button("Prune Older than Retention", role: .destructive) {
                terminalMonitor.pruneStoredHistory(settings: store.settings, logger: logger)
            }
            Button("Clear All History", role: .destructive) {
                terminalMonitor.clearStoredHistory(settings: store.settings, logger: logger)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Pruning removes history older than the configured retention period. Clearing all history wipes all monitoring data."
            )
        }
    }

    private var visibleDashboardBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryCard
            storageCard
            filterBar
            HSplitView {
                sessionListPane
                    .frame(minWidth: 360, idealWidth: 420, maxWidth: 520, maxHeight: .infinity)
                sessionDetailPane
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var hiddenDashboardPlaceholder: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private var summaryCard: some View {
        GroupBox("Terminal Transcript Monitor") {
            VStack(alignment: .leading, spacing: 12) {
                Text(terminalMonitor.databaseStatus)
                    .font(.headline)

                HStack(spacing: 14) {
                    Label("\(terminalMonitor.sessions.count) total", systemImage: "list.bullet.rectangle")
                    Label("\(liveSessionCount) live", systemImage: "waveform.path.ecg")
                    if store.settings.mongoMonitoring.enableMongoWrites {
                        Label("\(historicalSessionCount) from MongoDB", systemImage: "externaldrive.badge.icloud")
                    }
                    Label("\(completedSessionCount) completed", systemImage: "checkmark.circle")
                    Label("\(failedSessionCount) failed", systemImage: "xmark.octagon")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    if !terminalMonitor.lastConnectionCheck.isEmpty {
                        Label("Last checked \(terminalMonitor.lastConnectionCheck)", systemImage: "clock")
                    }
                    if store.settings.mongoMonitoring.enableMongoWrites {
                        Label(store.settings.mongoMonitoring.redactedConnectionDescription, systemImage: "externaldrive.badge.icloud")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Label("Local transcript capture only", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("This dashboard refreshes automatically while the Monitoring tab stays open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Test MongoDB Connection") {
                        terminalMonitor.testConnection(settings: store.settings, logger: logger)
                    }
                    .disabled(!store.settings.mongoMonitoring.enabled)

                    Button("Refresh Recent Sessions") {
                        terminalMonitor.refreshRecentSessions(
                            settings: store.settings,
                            logger: logger,
                            force: true,
                            workload: .maintenance
                        )
                        terminalMonitor.refreshStorageSummary(settings: store.settings, logger: logger, force: true)
                        loadSelectedDetails(forceRefresh: true, workload: .history)
                    }
                    .disabled(!store.settings.mongoMonitoring.enabled || !store.settings.mongoMonitoring.enableMongoWrites)

                    Button("Reveal Capture Folder") {
                        terminalMonitor.revealTranscriptDirectory(settings: store.settings)
                    }

                    Button("Clear Completed / Failed") {
                        terminalMonitor.clearCompleted()
                        syncSelection()
                    }
                }
            }
        }
    }

    private var storageCard: some View {
        GroupBox("Storage & Retention") {
            VStack(alignment: .leading, spacing: 12) {
                if let summary = terminalMonitor.storageSummary {
                    HStack(spacing: 12) {
                        metricPill(title: "DB sessions", value: "\(summary.sessionCount)", systemImage: "externaldrive.badge.icloud")
                        metricPill(title: "TX complete", value: "\(summary.transcriptCompleteSessionCount)", systemImage: "checkmark.seal")
                        metricPill(title: "TX streaming", value: "\(summary.transcriptStreamingSessionCount)", systemImage: "arrow.triangle.2.circlepath")
                        metricPill(title: "TX unknown", value: "\(summary.transcriptCoverageUnknownSessionCount)", systemImage: "questionmark.circle")
                    }

                    HStack(spacing: 12) {
                        metricPill(title: "IN complete", value: "\(summary.inputCompleteSessionCount)", systemImage: "checkmark.seal")
                        metricPill(title: "IN streaming", value: "\(summary.inputStreamingSessionCount)", systemImage: "arrow.triangle.2.circlepath")
                        metricPill(title: "IN unknown", value: "\(summary.inputCoverageUnknownSessionCount)", systemImage: "questionmark.circle")
                    }

                    HStack(spacing: 12) {
                        metricPill(title: "TX chunks", value: "\(summary.chunkCount)", systemImage: "waveform")
                        metricPill(title: "IN chunks", value: "\(summary.inputChunkCount)", systemImage: "keyboard")
                        metricPill(title: "Events", value: "\(summary.eventCount)", systemImage: "list.bullet.clipboard")
                        metricPill(title: "Local transcripts", value: "\(summary.transcriptFileCount)", systemImage: "doc.text")
                    }

                    HStack(spacing: 12) {
                        metricPill(title: "Local inputs", value: "\(summary.inputCaptureFileCount)", systemImage: "keyboard")
                        metricPill(title: "DB size", value: byteCountString(summary.totalDatabaseBytes), systemImage: "cylinder.split.1x2")
                        metricPill(title: "Known total", value: byteCountString(summary.totalKnownBytes), systemImage: "sum")
                    }

                    HStack(spacing: 12) {
                        metricPill(title: "Logical DB", value: byteCountString(summary.logicalDatabaseBytes), systemImage: "externaldrive")
                        metricPill(title: "Logical TX", value: byteCountString(summary.logicalTranscriptBytes), systemImage: "text.justify")
                        metricPill(title: "Logical IN", value: byteCountString(summary.logicalInputBytes), systemImage: "keyboard")
                    }

                    HStack(spacing: 12) {
                        metricPill(title: "Transcript size", value: byteCountString(summary.transcriptFileBytes), systemImage: "folder")
                        metricPill(title: "Input size", value: byteCountString(summary.inputCaptureFileBytes), systemImage: "keyboard")
                    }

                    if summary.hasAnyData {
                        VStack(alignment: .leading, spacing: 8) {
                            if summary.hasPhysicalDatabaseBreakdown {
                                detailLine(label: "Mongo session rows", value: byteCountString(summary.sessionTableBytes))
                                detailLine(label: "Mongo transcript chunks", value: byteCountString(summary.chunkTableBytes))
                                detailLine(label: "Mongo raw input chunks", value: byteCountString(summary.inputChunkTableBytes))
                                detailLine(label: "Mongo event rows", value: byteCountString(summary.eventTableBytes))
                            }
                            if let oldestSessionAt = summary.oldestSessionAt {
                                detailLine(label: "Oldest Mongo session", value: oldestSessionAt.formatted(date: .abbreviated, time: .standard))
                            }
                            if let newestSessionAt = summary.newestSessionAt {
                                detailLine(label: "Newest MongoDB activity", value: newestSessionAt.formatted(date: .abbreviated, time: .standard))
                            }
                            if let oldestTranscriptAt = summary.oldestTranscriptFileAt {
                                detailLine(label: "Oldest local transcript", value: oldestTranscriptAt.formatted(date: .abbreviated, time: .standard))
                            }
                            if let newestTranscriptAt = summary.newestTranscriptFileAt {
                                detailLine(label: "Newest local transcript", value: newestTranscriptAt.formatted(date: .abbreviated, time: .standard))
                            }
                            if let oldestInputCaptureAt = summary.oldestInputCaptureFileAt {
                                detailLine(label: "Oldest local raw input", value: oldestInputCaptureAt.formatted(date: .abbreviated, time: .standard))
                            }
                            if let newestInputCaptureAt = summary.newestInputCaptureFileAt {
                                detailLine(label: "Newest local raw input", value: newestInputCaptureAt.formatted(date: .abbreviated, time: .standard))
                            }
                        }
                    }
                } else if terminalMonitor.isLoadingStorageSummary {
                    ProgressView("Loading storage summary…")
                } else {
                    Text("No storage summary has been loaded yet.")
                        .foregroundStyle(.secondary)
                }

                if !terminalMonitor.storageSummaryStatus.isEmpty {
                    Text(terminalMonitor.storageSummaryStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text(
                        "Retention: DB \(store.settings.mongoMonitoring.clampedDatabaseRetentionDays) day(s) • local captures \(store.settings.mongoMonitoring.clampedLocalTranscriptRetentionDays) day(s)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    if terminalMonitor.isLoadingStorageSummary || terminalMonitor.isPruningStoredHistory {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if !terminalMonitor.lastPruneSummary.isEmpty {
                    Text(terminalMonitor.lastPruneSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Refresh Storage Stats") {
                        terminalMonitor.refreshStorageSummary(settings: store.settings, logger: logger, force: true)
                    }
                    .disabled(!store.settings.mongoMonitoring.enabled)

                    Button("Prune Stored History…") {
                        showingPruneConfirmation = true
                    }
                    .disabled(!store.settings.mongoMonitoring.enabled || terminalMonitor.isPruningStoredHistory)

                    Button("Backup Database…") {
                        terminalMonitor.performBackup(settings: store.settings, logger: logger)
                    }
                    .disabled(!store.settings.mongoMonitoring.enabled || !store.settings.mongoMonitoring.enableMongoWrites)
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            TextField("Search monitored sessions", text: $searchText)

            Picker("Source", selection: $sourceFilter) {
                ForEach(MonitorSessionSourceFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Picker("Status", selection: $statusFilter) {
                ForEach(MonitorSessionStatusFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Spacer()

            Text(store.settings.mongoMonitoring.captureMode.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.settings.mongoMonitoring.enableMongoWrites {
                Text(
                    "Recent DB history: \(store.settings.mongoMonitoring.clampedRecentHistoryLookbackDays) day(s) / \(store.settings.mongoMonitoring.clampedRecentHistoryLimit) sessions"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(
                    "Detail load: \(store.settings.mongoMonitoring.clampedDetailEventLimit) events / \(store.settings.mongoMonitoring.clampedDetailChunkLimit) chunks"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sessionListPane: some View {
        MonitorSessionListPaneView(
            sessions: filteredSessions,
            selectedSessionID: selectedSessionID,
            setSelectedSessionID: { selectedSessionID = $0 }
        )
        .equatable()
    }

    @ViewBuilder
    private var sessionDetailPane: some View {
        if let session = selectedSession {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    detailHeader(session)
                    overviewCard(for: session)
                    observedInputsCard(for: session)
                    ioTimelineCard(for: session)
                    inputStreamCard(for: session)
                    actionsCard(for: session)
                    transcriptCard(for: session)
                    eventsCard(for: session)
                    chunksCard(for: session)
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }
        } else {
            emptyDetailPlaceholder
        }
    }

    private func detailHeader(_ session: TerminalMonitorSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(session.profileName)
                            .font(.title2.bold())

                        if session.isYolo {
                            Text("YOLO")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.15))
                                .foregroundStyle(.red)
                                .cornerRadius(4)
                        }
                    }
                    Text(session.id.uuidString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                if terminalMonitor.isLoadingDetails(for: session.id) {
                    ProgressView()
                        .controlSize(.small)
                }
                Label(session.status.displayName, systemImage: session.status.systemImage)
                    .font(.caption)
                    .foregroundStyle(statusColor(for: session.status))
            }

            if let details = selectedDetails, !details.loadSummary.isEmpty {
                Text(details.loadSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Details refreshed \(details.loadedAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if terminalMonitor.isLoadingDetails(for: session.id) {
                        Text("Loading MongoDB detail data…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func overviewCard(for session: TerminalMonitorSession) -> some View {
        GroupBox("Overview") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    metricPill(title: "Chunks", value: "\(session.chunkCount)", systemImage: "waveform")
                    metricPill(title: "Bytes", value: byteCountString(session.byteCount), systemImage: "internaldrive")
                    if session.inputChunkCount > 0 {
                        metricPill(title: "Input chunks", value: "\(session.inputChunkCount)", systemImage: "keyboard")
                    }
                    if let duration = session.duration {
                        metricPill(title: "Duration", value: durationString(duration), systemImage: "timer")
                    }
                    if let exitCode = session.exitCode {
                        metricPill(title: "Exit", value: String(exitCode), systemImage: exitCode == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                    }
                }

                detailLine(label: "Source", value: session.isHistorical ? "Loaded from MongoDB history" : "Live local session")
                detailLine(label: "Agent", value: session.agentKind.displayName)
                detailLine(label: "Capture mode", value: session.captureMode.displayName)
                if let accountIdentifier = session.accountIdentifier, !accountIdentifier.isEmpty {
                    detailLine(label: "Account", value: accountIdentifier)
                }
                if let providerSessionID = session.providerSessionID, !providerSessionID.isEmpty {
                    detailLine(label: "Provider session", value: providerSessionID)
                }
                if let providerAuthMethod = session.providerAuthMethod, !providerAuthMethod.isEmpty {
                    detailLine(label: "Auth method", value: providerAuthMethod)
                }
                if let providerTier = session.providerTier, !providerTier.isEmpty {
                    detailLine(label: "Tier", value: providerTier)
                }
                if let providerCLIVersion = session.providerCLIVersion, !providerCLIVersion.isEmpty {
                    detailLine(label: "CLI version", value: providerCLIVersion)
                }
                if let providerRunnerPath = session.providerRunnerPath, !providerRunnerPath.isEmpty {
                    detailLine(label: "Runner path", value: providerRunnerPath)
                }
                if let runnerPathStatus = Self.geminiRunnerPathStatusText(sessionRunnerPath: session.providerRunnerPath) {
                    detailLine(label: "Runner path status", value: runnerPathStatus)
                }
                if let providerRunnerBuild = session.providerRunnerBuild, !providerRunnerBuild.isEmpty {
                    detailLine(label: "Runner build", value: providerRunnerBuild)
                }
                if let runnerBuildStatus = Self.geminiRunnerBuildStatusText(sessionRunnerBuild: session.providerRunnerBuild) {
                    detailLine(label: "Runner build status", value: runnerBuildStatus)
                }
                if let providerWrapperResolvedPath = session.providerWrapperResolvedPath, !providerWrapperResolvedPath.isEmpty {
                    detailLine(label: "Wrapper resolved", value: providerWrapperResolvedPath)
                }
                if let providerWrapperKind = session.providerWrapperKind, !providerWrapperKind.isEmpty {
                    detailLine(label: "Wrapper kind", value: providerWrapperKind)
                }
                if let providerLaunchMode = session.providerLaunchMode, !providerLaunchMode.isEmpty {
                    detailLine(label: "Launch mode", value: providerLaunchMode)
                }
                if let providerShellFallbackExecutable = session.providerShellFallbackExecutable, !providerShellFallbackExecutable.isEmpty {
                    detailLine(label: "Shell fallback", value: providerShellFallbackExecutable)
                }
                if let providerAutoContinueMode = session.providerAutoContinueMode, !providerAutoContinueMode.isEmpty {
                    detailLine(label: "Auto-continue", value: providerAutoContinueMode)
                }
                if let providerPTYBackend = session.providerPTYBackend, !providerPTYBackend.isEmpty {
                    detailLine(label: "PTY backend", value: providerPTYBackend)
                }
                if let providerStartupClearCommand = session.providerStartupClearCommand, !providerStartupClearCommand.isEmpty {
                    detailLine(label: "Startup clear cmd", value: providerStartupClearCommand)
                }
                if let providerStartupClearCommandSource = session.providerStartupClearCommandSource, !providerStartupClearCommandSource.isEmpty {
                    detailLine(label: "Startup clear src", value: Self.geminiStartupCommandSourceDisplayName(providerStartupClearCommandSource))
                }
                if let providerStartupClearCompleted = session.providerStartupClearCompleted {
                    detailLine(label: "Startup clear", value: providerStartupClearCompleted ? "Completed" : "Sent")
                }
                if let providerStartupClearReason = session.providerStartupClearReason, !providerStartupClearReason.isEmpty {
                    detailLine(label: "Startup clear note", value: providerStartupClearReason)
                }
                if let providerStartupStatsCommand = session.providerStartupStatsCommand, !providerStartupStatsCommand.isEmpty {
                    detailLine(label: "Startup stats cmd", value: providerStartupStatsCommand)
                }
                if let providerStartupStatsCommandSource = session.providerStartupStatsCommandSource, !providerStartupStatsCommandSource.isEmpty {
                    detailLine(label: "Startup stats src", value: Self.geminiStartupCommandSourceDisplayName(providerStartupStatsCommandSource))
                }
                if let providerStartupModelCommand = session.providerStartupModelCommand, !providerStartupModelCommand.isEmpty {
                    detailLine(label: "Startup model cmd", value: providerStartupModelCommand)
                }
                if let providerStartupModelCommandSource = session.providerStartupModelCommandSource, !providerStartupModelCommandSource.isEmpty {
                    detailLine(label: "Startup model src", value: Self.geminiStartupCommandSourceDisplayName(providerStartupModelCommandSource))
                }
                if let providerCurrentModel = session.providerCurrentModel, !providerCurrentModel.isEmpty {
                    detailLine(label: "Current model", value: providerCurrentModel)
                }
                if let mongoTranscriptSyncState = session.mongoTranscriptSyncState {
                    detailLine(label: "Mongo transcript", value: mongoTranscriptSyncState.displayName)
                }
                if let mongoTranscriptSyncSource = session.mongoTranscriptSyncSourceDisplayName, !mongoTranscriptSyncSource.isEmpty {
                    detailLine(label: "Mongo transcript src", value: mongoTranscriptSyncSource)
                }
                if let mongoTranscriptChunkCount = session.mongoTranscriptChunkCount {
                    detailLine(label: "Mongo chunks", value: String(mongoTranscriptChunkCount))
                }
                if let mongoTranscriptByteCount = session.mongoTranscriptByteCount {
                    detailLine(label: "Mongo bytes", value: byteCountString(Int64(mongoTranscriptByteCount)))
                }
                if let mongoTranscriptSynchronizedAt = session.mongoTranscriptSynchronizedAt {
                    detailLine(label: "Mongo synced", value: mongoTranscriptSynchronizedAt.formatted(date: .abbreviated, time: .standard))
                }
                if let mongoInputSyncState = session.mongoInputSyncState {
                    detailLine(label: "Mongo input", value: mongoInputSyncState.displayName)
                }
                if let mongoInputSyncSource = session.mongoInputSyncSourceDisplayName, !mongoInputSyncSource.isEmpty {
                    detailLine(label: "Mongo input src", value: mongoInputSyncSource)
                }
                if let mongoInputChunkCount = session.mongoInputChunkCount {
                    detailLine(label: "Mongo input chunks", value: String(mongoInputChunkCount))
                }
                if let mongoInputByteCount = session.mongoInputByteCount {
                    detailLine(label: "Mongo input bytes", value: byteCountString(Int64(mongoInputByteCount)))
                }
                if let mongoInputSynchronizedAt = session.mongoInputSynchronizedAt {
                    detailLine(label: "Mongo input synced", value: mongoInputSynchronizedAt.formatted(date: .abbreviated, time: .standard))
                }
                if let providerFreshSessionPrepared = session.providerFreshSessionPrepared {
                    detailLine(label: "Fresh session prep", value: providerFreshSessionPrepared ? "Prepared" : "Not cleared")
                }
                if let providerFreshSessionRemovedPathCount = session.providerFreshSessionRemovedPathCount {
                    detailLine(label: "Session aliases cleared", value: String(providerFreshSessionRemovedPathCount))
                }
                if let providerFreshSessionResetReason = session.providerFreshSessionResetReason, !providerFreshSessionResetReason.isEmpty {
                    detailLine(label: "Fresh session note", value: providerFreshSessionResetReason)
                }
                if let providerModelUsageNote = session.providerModelUsageNote, !providerModelUsageNote.isEmpty {
                    detailLine(label: "Model usage note", value: providerModelUsageNote)
                }
                if let providerModelUsage = session.providerModelUsage, !providerModelUsage.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model usage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(providerModelUsage.enumerated()), id: \.offset) { _, row in
                            Text(geminiModelUsageSummary(row))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if let providerModelCapacity = session.providerModelCapacity, !providerModelCapacity.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model capacity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(providerModelCapacity.enumerated()), id: \.offset) { _, row in
                            Text(geminiModelCapacitySummary(row))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if let observedSlashCommands = session.observedSlashCommands, !observedSlashCommands.isEmpty {
                    detailLine(label: "Observed slash cmds", value: observedSlashCommands.joined(separator: " | "))
                }
                if let observedPromptSubmissions = session.observedPromptSubmissions, !observedPromptSubmissions.isEmpty {
                    detailLine(label: "Observed prompts", value: observedPromptSubmissions.joined(separator: " | "))
                }
                if let inputCapturePath = session.inputCapturePath, !inputCapturePath.isEmpty {
                    detailLine(label: "Input capture path", value: inputCapturePath)
                }
                if session.inputChunkCount > 0 {
                    detailLine(label: "Input chunk count", value: String(session.inputChunkCount))
                }
                if session.inputByteCount > 0 {
                    detailLine(label: "Input bytes", value: byteCountString(Int64(session.inputByteCount)))
                }
                detailLine(label: "Working directory", value: session.workingDirectory)
                detailLine(label: "Transcript path", value: session.transcriptPath)
                detailLine(label: "Started", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
                if let lastActivityAt = session.lastActivityAt {
                    detailLine(label: "Last activity", value: lastActivityAt.formatted(date: .abbreviated, time: .standard))
                }
                if let endedAt = session.endedAt {
                    detailLine(label: "Ended", value: endedAt.formatted(date: .abbreviated, time: .standard))
                }
                if let statusReason = session.statusReason, !statusReason.isEmpty {
                    detailLine(label: "Status reason", value: humanizedEventName(statusReason))
                }
                if !session.lastDatabaseMessage.isEmpty {
                    detailLine(label: "Monitor message", value: session.lastDatabaseMessage)
                }
                if let lastError = session.lastError, !lastError.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last error")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Launch command")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(session.launchCommand)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                }

                if !session.prompt.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch prompt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(session.prompt)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionsCard(for session: TerminalMonitorSession) -> some View {
        GroupBox("Actions") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Reload Details") {
                        loadSelectedDetails(forceRefresh: true, workload: .history)
                    }

                    if session.hasLocalTranscriptFile {
                        Button("Reveal Transcript") {
                            store.reveal(session.transcriptPath)
                        }
                    }

                    Button("Export Session JSON…") {
                        exportSession(session, details: selectedDetails)
                    }
                }

                HStack {
                    Button("Copy Launch Command") {
                        ClipboardService.copy(session.launchCommand)
                    }

                    Button("Copy Session ID") {
                        ClipboardService.copy(session.id.uuidString)
                    }

                    Button("Copy Transcript") {
                        ClipboardService.copy(selectedDetails?.transcriptText ?? "")
                    }
                    .disabled(selectedDetails?.transcriptText.isEmpty != false)
                }
            }
        }
    }

    private func observedInputsCard(for session: TerminalMonitorSession) -> some View {
        GroupBox("Observed Inputs") {
            VStack(alignment: .leading, spacing: 10) {
                if let details = selectedDetails, details.historyLoaded {
                    let observedEvents = details.events.compactMap { event -> (TerminalSessionEvent, ObservedTranscriptInteraction)? in
                        guard let interaction = event.observedTranscriptInteraction else { return nil }
                        return (event, interaction)
                    }
                    let summaryInteractions = session.observedInteractions ?? []

                    if observedEvents.isEmpty {
                        if summaryInteractions.isEmpty {
                            Text("No echoed prompts or slash commands were reconstructed for this session.")
                                .foregroundStyle(.secondary)
                        } else {
                            if session.captureMode == .outputOnly {
                                Text("Output-only sessions only retain commands or prompts that Gemini echoed back into the transcript.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(Array(summaryInteractions.enumerated()), id: \.offset) { _, interaction in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(interaction.kind.displayName)
                                            .font(.caption.weight(.semibold))
                                        Text(interaction.sourceDisplayName)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.secondary.opacity(0.12))
                                            .cornerRadius(6)
                                        if interaction.observationCount > 1 {
                                            Text("x\(interaction.observationCount)")
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.orange.opacity(0.15))
                                                .cornerRadius(6)
                                        }
                                        Spacer()
                                        Text(interaction.lastObservedAt.formatted(date: .omitted, time: .standard))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(interaction.text)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.secondary.opacity(0.08))
                                        .cornerRadius(8)
                                }

                                if interaction != summaryInteractions.last {
                                    Divider()
                                }
                            }
                        }
                    } else {
                        if session.captureMode == .outputOnly {
                            Text("Output-only sessions only retain commands or prompts that Gemini echoed back into the transcript.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(Array(observedEvents.enumerated()), id: \.offset) { _, item in
                            let event = item.0
                            let interaction = item.1

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(interaction.kind.displayName)
                                        .font(.caption.weight(.semibold))
                                    Text(interaction.sourceDisplayName)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.12))
                                        .cornerRadius(6)
                                    Spacer()
                                    Text(event.eventAt.formatted(date: .omitted, time: .standard))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(interaction.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.08))
                                    .cornerRadius(8)
                            }

                            if event.id != observedEvents.last?.0.id {
                                Divider()
                            }
                        }
                    }
                } else if let observedInteractions = session.observedInteractions, !observedInteractions.isEmpty {
                    if session.captureMode == .outputOnly {
                        Text("Output-only sessions only retain commands or prompts that Gemini echoed back into the transcript.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(Array(observedInteractions.enumerated()), id: \.offset) { _, interaction in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(interaction.kind.displayName)
                                    .font(.caption.weight(.semibold))
                                Text(interaction.sourceDisplayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(6)
                                if interaction.observationCount > 1 {
                                    Text("x\(interaction.observationCount)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.15))
                                        .cornerRadius(6)
                                }
                                Spacer()
                                Text(interaction.lastObservedAt.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(interaction.text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08))
                                .cornerRadius(8)
                        }

                        if interaction != observedInteractions.last {
                            Divider()
                        }
                    }
                } else if terminalMonitor.isLoadingDetails(for: session.id) {
                    ProgressView("Loading observed inputs…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Reload details to reconstruct prompts and slash commands from session history.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func transcriptCard(for session: TerminalMonitorSession) -> some View {
        detailSectionCard(.transcript, for: session) {
            VStack(alignment: .leading, spacing: 8) {
                if let details = selectedDetails {
                    HStack(alignment: .firstTextBaseline) {
                        Text(details.transcriptSourceDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if session.captureMode.usesScriptKeyLogging {
                            Text("Input + output")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(7)
                        }
                        if details.transcriptTruncated {
                            Text("Partial transcript")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(7)
                        }
                    }

                    if details.transcriptText.isEmpty {
                        Text("No transcript content is available yet for this session.")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            Text(details.transcriptText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(minHeight: 220, idealHeight: 280)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                    }
                } else if terminalMonitor.isLoadingDetails(for: session.id) {
                    ProgressView("Loading transcript…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Select Reload Details to fetch transcript content for this session.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func ioTimelineCard(for session: TerminalMonitorSession) -> some View {
        detailSectionCard(.ioTimeline, for: session) {
            VStack(alignment: .leading, spacing: 10) {
                if let details = selectedDetails, details.historyLoaded {
                    let entries = Array(details.ioTimelineEntries.suffix(40))

                    if entries.isEmpty {
                        Text("No transcript or stdin chunks are available for this session yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        if details.chunksTruncated || details.inputChunksTruncated {
                            Text("Showing the latest \(entries.count) merged I/O entries from the loaded detail window.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(entries) { entry in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let message = entry.sessionMessage, !message.isEmpty {
                                        Text(message)
                                            .font(.caption)
                                            .textSelection(.enabled)
                                    }

                                    if let statusReason = entry.sessionStatusReason, !statusReason.isEmpty {
                                        Text("Reason: \(statusReason)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    if let promptSnapshot = entry.promptSnapshot,
                                       !promptSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Prompt Snapshot")
                                                .font(.caption.weight(.semibold))
                                            Text(promptSnapshot)
                                                .font(.system(.caption, design: .monospaced))
                                                .textSelection(.enabled)
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color.secondary.opacity(0.08))
                                                .cornerRadius(8)
                                        }
                                    }

                                    Text(entry.text.isEmpty ? entry.previewText : entry.text)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.secondary.opacity(0.08))
                                        .cornerRadius(8)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Label(entry.kind.displayName, systemImage: entry.kind.systemImage)
                                            .font(.headline)
                                        Text(entry.sourceDisplayName)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.secondary.opacity(0.12))
                                            .cornerRadius(6)
                                        if let status = entry.sessionStatus {
                                            Label(status.displayName, systemImage: status.systemImage)
                                                .font(.caption2)
                                                .foregroundStyle(statusColor(for: status))
                                        }
                                        Spacer()
                                        Label(byteCountString(entry.byteCount), systemImage: "internaldrive")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(entry.capturedAt.formatted(date: .omitted, time: .standard))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(entry.previewText.isEmpty ? "No preview text available." : entry.previewText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                    if let message = entry.sessionMessage, !message.isEmpty {
                                        Text(message)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .padding(.vertical, 2)

                            if entry.id != entries.last?.id {
                                Divider()
                            }
                        }
                    }
                } else if terminalMonitor.isLoadingDetails(for: session.id) {
                    ProgressView("Loading merged I/O timeline…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Reload details to reconstruct the merged stdin/transcript timeline for this session.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func inputStreamCard(for session: TerminalMonitorSession) -> some View {
        detailSectionCard(.inputStream, for: session) {
            VStack(alignment: .leading, spacing: 8) {
                if session.captureMode == .outputOnly {
                    Text("This session was recorded in output-only mode, so no separate stdin stream was captured.")
                        .foregroundStyle(.secondary)
                } else if let details = selectedDetails, details.historyLoaded {
                    if details.inputChunks.isEmpty {
                        Text("No stdin chunks are available for this session yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        if details.inputChunksTruncated {
                            Text("Showing the latest \(details.inputChunks.count) stdin chunk(s).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(details.inputChunks) { chunk in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(chunk.sourceDisplayName)
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(chunk.capturedAt.formatted(date: .omitted, time: .standard))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(chunk.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.08))
                                    .cornerRadius(8)
                            }
                            if chunk.id != details.inputChunks.last?.id {
                                Divider()
                            }
                        }
                    }
                } else if terminalMonitor.isLoadingDetails(for: session.id) {
                    ProgressView("Loading stdin stream…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Reload details to fetch the separate stdin stream for this session.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func eventsCard(for session: TerminalMonitorSession) -> some View {
        detailSectionCard(.events, for: session) {
            VStack(alignment: .leading, spacing: 10) {
                if let details = selectedDetails, details.historyLoaded {
                    if details.events.isEmpty {
                        Text("No MongoDB event rows were returned for this session yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        if details.eventsTruncated {
                            Text("Showing the latest \(details.events.count) event(s).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(details.events) { event in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(humanizedEventName(event.eventType))
                                        .font(.headline)
                                    Spacer()
                                    Label(event.status.displayName, systemImage: event.status.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(statusColor(for: event.status))
                                }
                                Text(event.eventAt.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let message = event.message, !message.isEmpty {
                                    Text(message)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                                if let metadataJSON = event.metadataJSON, !metadataJSON.isEmpty {
                                    DisclosureGroup("Metadata") {
                                        Text(prettyPrintedJSON(metadataJSON))
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.secondary.opacity(0.08))
                                            .cornerRadius(8)
                                    }
                                    .font(.caption)
                                }
                            }
                            .padding(.vertical, 4)
                            if event.id != details.events.last?.id {
                                Divider()
                            }
                        }
                    }
                } else if terminalMonitor.isLoadingDetails(for: session.id) {
                    ProgressView("Loading session events…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No event timeline loaded yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chunksCard(for session: TerminalMonitorSession) -> some View {
        detailSectionCard(.chunks, for: session) {
            VStack(alignment: .leading, spacing: 10) {
                if let details = selectedDetails, details.historyLoaded {
                    if details.chunks.isEmpty {
                        Text("No MongoDB transcript chunks were loaded for this session.")
                            .foregroundStyle(.secondary)
                    } else {
                        if details.chunksTruncated {
                            Text("Showing the latest \(details.chunks.count) of \(session.chunkCount) chunk(s).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(details.chunks.reversed().prefix(20)), id: \.id) { chunk in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let message = chunk.sessionMessage, !message.isEmpty {
                                        Text(message)
                                            .font(.caption)
                                            .textSelection(.enabled)
                                    }

                                    if let statusReason = chunk.sessionStatusReason, !statusReason.isEmpty {
                                        Text("Reason: \(statusReason)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    if let promptSnapshot = chunk.promptSnapshot,
                                       !promptSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Prompt Snapshot")
                                                .font(.caption.weight(.semibold))
                                            Text(promptSnapshot)
                                                .font(.system(.caption, design: .monospaced))
                                                .textSelection(.enabled)
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color.secondary.opacity(0.08))
                                                .cornerRadius(8)
                                        }
                                    }

                                    Text(chunk.text.isEmpty ? chunk.previewText : chunk.text)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.secondary.opacity(0.08))
                                        .cornerRadius(8)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("Chunk \(chunk.chunkIndex)")
                                            .font(.headline)
                                        Text(chunk.sourceDisplayName)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.secondary.opacity(0.12))
                                            .cornerRadius(6)
                                        if let status = chunk.sessionStatus {
                                            Label(status.displayName, systemImage: status.systemImage)
                                                .font(.caption2)
                                                .foregroundStyle(statusColor(for: status))
                                        }
                                        Spacer()
                                        Label(byteCountString(chunk.byteCount), systemImage: "internaldrive")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(chunk.capturedAt.formatted(date: .omitted, time: .standard))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(chunk.previewText.isEmpty ? "No preview text available." : chunk.previewText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                    if let message = chunk.sessionMessage, !message.isEmpty {
                                        Text(message)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                } else if terminalMonitor.isLoadingDetails(for: session.id) {
                    ProgressView("Loading transcript chunks…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No chunk detail loaded yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyDetailPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Select a monitored session")
                .font(.title3.weight(.semibold))
                Text("Choose a row on the left to inspect the session timeline, transcript content, and MongoDB chunk history.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func syncSelection() {
        let visibleIDs = Set(filteredSessions.map(\.id))
        if let pendingFocusedSessionID = terminalMonitor.consumePendingFocusedSessionID(ifContainedIn: visibleIDs) {
            selectedSessionID = pendingFocusedSessionID
            return
        }

        if let selectedSessionID, visibleIDs.contains(selectedSessionID) {
            return
        }

        selectedSessionID = filteredSessions.first?.id
    }

    private func handleVisibilityChange(_ isVisible: Bool) {
        if isVisible {
            applyPendingMonitoringNavigationStateIfNeeded()
            refreshFilteredSessions(force: true)
            performVisibleRefresh(
                forceRecentSessions: true,
                recentSessionsWorkload: .interactive,
                includeStorageSummary: true,
                forceDetails: false,
                detailWorkload: .summary
            )
            startAutoRefresh()
        } else {
            sessionRefreshDebounceTask?.cancel()
            sessionRefreshDebounceTask = nil
            detailLoadDebounceTask?.cancel()
            detailLoadDebounceTask = nil
            stopAutoRefresh()
        }
    }

    private func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: autoRefreshIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                guard isVisible else { continue }
                performVisibleRefresh(
                    forceRecentSessions: false,
                    recentSessionsWorkload: .interactive,
                    includeStorageSummary: false,
                    forceDetails: false,
                    detailWorkload: .summary
                )
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    private func performVisibleRefresh(
        forceRecentSessions: Bool,
        recentSessionsWorkload: RecentSessionRefreshWorkload,
        includeStorageSummary: Bool,
        forceDetails: Bool,
        detailWorkload: MonitorDetailLoadWorkload
    ) {
        guard isVisible else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        terminalMonitor.refreshRecentSessions(
            settings: store.settings,
            logger: logger,
            force: forceRecentSessions,
            workload: recentSessionsWorkload
        )
        if includeStorageSummary {
            terminalMonitor.refreshStorageSummary(settings: store.settings, logger: logger, force: forceRecentSessions)
        }
        loadSelectedDetails(forceRefresh: forceDetails, workload: detailWorkload)
        logMonitoringViewTiming(
            "performVisibleRefresh",
            startedAt: startedAt,
            details: "force_recent=\(forceRecentSessions) • workload=\(recentSessionsWorkload.rawValue) • include_storage=\(includeStorageSummary) • force_details=\(forceDetails) • detail_workload=\(detailWorkload.rawValue)"
        )
    }

    private func applyPendingMonitoringNavigationStateIfNeeded() {
        guard terminalMonitor.consumePendingMonitoringFilterReset() else { return }

        searchDebounceTask?.cancel()
        searchText = ""
        debouncedSearchText = ""
        sourceFilter = .all
        statusFilter = .all
        refreshFilteredSessions()
    }

    private func debounceSearchFilter() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            debouncedSearchText = searchText
            refreshFilteredSessions()
        }
    }

    private func debounceSessionRefresh() {
        guard isVisible else { return }
        sessionRefreshDebounceTask?.cancel()
        sessionRefreshDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: sessionRefreshDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            refreshFilteredSessions()
        }
    }

    private func debounceSelectedDetailsLoad(forceRefresh: Bool, workload: MonitorDetailLoadWorkload) {
        guard isVisible else { return }
        detailLoadDebounceTask?.cancel()
        detailLoadDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: detailLoadDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            loadSelectedDetails(forceRefresh: forceRefresh, workload: workload)
        }
    }

    private func refreshFilteredSessions(force: Bool = false) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allSessions = terminalMonitor.sessions
        let refreshInputs = MonitorSessionRefreshInputs(
            sessions: allSessions,
            query: query,
            sourceFilter: sourceFilter,
            statusFilter: statusFilter
        )

        if !force, refreshInputs == lastSessionRefreshInputs {
            logMonitoringViewTiming(
                "refreshFilteredSessions",
                startedAt: startedAt,
                details: "skipped=true • query_len=\(query.count) • total_sessions=\(allSessions.count) • source_filter=\(sourceFilter.rawValue) • status_filter=\(statusFilter.rawValue)"
            )
            return
        }

        lastSessionRefreshInputs = refreshInputs
        let visibleSessionIDs = Set(allSessions.map(\.id))
        searchIndexCache = searchIndexCache.filter { visibleSessionIDs.contains($0.key) }
        var visible: [TerminalMonitorSession] = []
        visible.reserveCapacity(allSessions.count)

        var visibleLookup: [UUID: TerminalMonitorSession] = [:]
        visibleLookup.reserveCapacity(allSessions.count)

        var liveCount = 0
        var historicalCount = 0
        var completedCount = 0
        var failedCount = 0

        for session in allSessions {
            if session.isHistorical {
                historicalCount += 1
            } else {
                liveCount += 1
            }

            switch session.status {
            case .completed:
                completedCount += 1
            case .failed, .stopped:
                failedCount += 1
            default:
                break
            }

            let matchesSearch = query.isEmpty || sessionSearchBlob(for: session).contains(query)
            guard sourceFilter.matches(session), statusFilter.matches(session), matchesSearch else {
                continue
            }

            visibleLookup[session.id] = session
            visible.append(session)
        }

        filteredSessionsCache = visible
        filteredSessionIndex = visibleLookup
        allLiveSessionCount = liveCount
        allHistoricalSessionCount = historicalCount
        allCompletedSessionCount = completedCount
        allFailedSessionCount = failedCount
        syncSelection()
        logMonitoringViewTiming(
            "refreshFilteredSessions",
            startedAt: startedAt,
            details: "query_len=\(query.count) • total_sessions=\(allSessions.count) • visible_sessions=\(visible.count) • source_filter=\(sourceFilter.rawValue) • status_filter=\(statusFilter.rawValue)"
        )
    }

    private func loadSelectedDetails(forceRefresh: Bool, workload: MonitorDetailLoadWorkload) {
        guard let session = selectedSession else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        terminalMonitor.loadDetails(
            for: session,
            settings: store.settings,
            logger: logger,
            forceRefresh: forceRefresh,
            workload: workload
        )
        logMonitoringViewTiming(
            "loadSelectedDetails",
            startedAt: startedAt,
            details: "session_id=\(session.id.uuidString) • force=\(forceRefresh) • workload=\(workload.rawValue)"
        )
    }

    private func resetDetailSectionExpansion() {
        expandedDetailSections.removeAll()
    }

    private func isDetailSectionExpanded(_ section: MonitorDetailSection) -> Bool {
        expandedDetailSections.contains(section)
    }

    private func toggleDetailSection(_ section: MonitorDetailSection) {
        if expandedDetailSections.contains(section) {
            expandedDetailSections.remove(section)
        } else {
            expandedDetailSections.insert(section)
        }
    }

    @ViewBuilder
    private func detailSectionCard<Content: View>(
        _ section: MonitorDetailSection,
        for session: TerminalMonitorSession,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isExpanded = isDetailSectionExpanded(section)
        let summary = collapsedDetailSectionSummary(for: session, section: section)

        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(section.displayName)
                        .font(.headline)

                    if !isExpanded, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        if !isExpanded && section.requiresHistoryLoad {
                            loadSelectedDetails(forceRefresh: false, workload: .history)
                        }
                        toggleDetailSection(section)
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down.circle" : "chevron.right.circle")
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse \(section.displayName)" : "Expand \(section.displayName)")
                }

                if isExpanded {
                    content()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func collapsedDetailSectionSummary(for session: TerminalMonitorSession, section: MonitorDetailSection) -> String {
        if terminalMonitor.isLoadingDetails(for: session.id) {
            return "Loading…"
        }

        switch section {
        case .transcript:
            guard let details = selectedDetails else {
                return "Expand to inspect transcript text."
            }
            guard details.historyLoaded else {
                return "Expand to load transcript history."
            }
            if details.transcriptText.isEmpty {
                return "No transcript content loaded."
            }
            return details.transcriptTruncated ? "Partial transcript loaded." : "Transcript loaded."

        case .ioTimeline:
            guard let details = selectedDetails else {
                return "Expand to inspect merged stdin and transcript history."
            }
            guard details.historyLoaded else {
                return "Expand to load merged I/O history."
            }
            return details.ioTimelineEntries.isEmpty
                ? "No merged I/O history loaded."
                : "\(details.ioTimelineEntries.count) merged I/O entr\(details.ioTimelineEntries.count == 1 ? "y" : "ies") loaded."

        case .inputStream:
            if session.captureMode == .outputOnly {
                return "No separate stdin stream in output-only mode."
            }
            guard let details = selectedDetails else {
                return "Expand to inspect raw stdin capture."
            }
            guard details.historyLoaded else {
                return "Expand to load raw stdin history."
            }
            return details.inputChunks.isEmpty
                ? "No stdin chunks loaded."
                : "\(details.inputChunks.count) stdin chunk\(details.inputChunks.count == 1 ? "" : "s") loaded."

        case .events:
            guard let details = selectedDetails else {
                return "Expand to inspect MongoDB event history."
            }
            guard details.historyLoaded else {
                return "Expand to load event history."
            }
            return details.events.isEmpty
                ? "No events loaded."
                : "\(details.events.count) event\(details.events.count == 1 ? "" : "s") loaded."

        case .chunks:
            guard let details = selectedDetails else {
                return "Expand to inspect transcript chunk history."
            }
            guard details.historyLoaded else {
                return "Expand to load transcript chunk history."
            }
            return details.chunks.isEmpty
                ? "No transcript chunks loaded."
                : "\(details.chunks.count) chunk\(details.chunks.count == 1 ? "" : "s") loaded."
        }
    }

    private func exportSession(_ session: TerminalMonitorSession, details: TerminalMonitorSessionDetails?) {
        guard let url = FilePanelService.saveFile(
            suggestedName: safeFilename(for: session.profileName) + "-session.json",
            allowedContentTypes: [UTType.json]
        ) else {
            return
        }

        do {
            let payload = MonitorSessionExportPayload(exportedAt: Date(), session: session, details: details)
            let data = try JSONEncoder.pretty.encode(payload)
            try data.write(to: url, options: [.atomic])
            logger.log(.success, "Exported monitor session report to \(url.path).")
        } catch {
            logger.log(.error, "Failed to export monitor session report: \(error.localizedDescription)")
        }
    }

    private func safeFilename(for raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let collapsed = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.reduce(into: "") { $0.append($1) }
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "monitor-session" : trimmed
    }

    private func detailLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricPill(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }

    private func byteCountString(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private func byteCountString(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func durationString(_ value: TimeInterval) -> String {
        Self.durationFormatter.string(from: value) ?? "—"
    }

    private func geminiModelUsageSummary(_ row: GeminiSessionStatsModelUsageRow) -> String {
        let nameParts = [row.model] + (row.label.map { [$0] } ?? [])

        return [
            nameParts.joined(separator: " / "),
            "reqs \(row.requests ?? 0)",
            "in \(row.inputTokens ?? 0)",
            "cache \(row.cacheReads ?? 0)",
            "out \(row.outputTokens ?? 0)",
        ].joined(separator: "  ")
    }

    private func geminiModelCapacitySummary(_ row: GeminiModelCapacityRow) -> String {
        var parts = [row.model]
        if let usedPercentage = row.usedPercentage {
            parts.append("\(usedPercentage)% used")
        }
        if let resetTime = row.resetTime?.trimmingCharacters(in: .whitespacesAndNewlines), !resetTime.isEmpty {
            parts.append("resets \(resetTime)")
        }
        return parts.joined(separator: "  ")
    }

    private func humanizedEventName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func prettyPrintedJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: prettyData, encoding: .utf8)
        else {
            return raw
        }
        return pretty
    }

    private func statusColor(for status: TerminalMonitorStatus) -> Color {
        switch status {
        case .prepared, .launching:
            return .blue

        case .monitoring:
            return .green

        case .idle:
            return .orange

        case .completed:
            return .green

        case .failed, .stopped:
            return .red
        }
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
        return formatter
    }()
}
