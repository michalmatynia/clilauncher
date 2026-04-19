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

struct MonitoringDashboardView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var logger: LaunchLogger
    @EnvironmentObject private var terminalMonitor: TerminalMonitorStore

    @State private var searchText: String = ""
    @State private var selectedSessionID: UUID?
    @State private var sourceFilter: MonitorSessionSourceFilter = .all
    @State private var statusFilter: MonitorSessionStatusFilter = .all
    @State private var showingPruneConfirmation = false

    private var filteredSessions: [TerminalMonitorSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return terminalMonitor.sessions.filter { session in
            guard sourceFilter.matches(session), statusFilter.matches(session) else { return false }
            guard !query.isEmpty else { return true }
            return session.profileName.lowercased().contains(query) ||
                session.workingDirectory.lowercased().contains(query) ||
                session.transcriptPath.lowercased().contains(query) ||
                session.lastPreview.lowercased().contains(query) ||
                session.lastDatabaseMessage.lowercased().contains(query) ||
                (session.statusReason?.lowercased().contains(query) ?? false) ||
                (session.lastError?.lowercased().contains(query) ?? false) ||
                session.agentKind.displayName.lowercased().contains(query) ||
                session.status.displayName.lowercased().contains(query) ||
                session.id.uuidString.lowercased().contains(query)
        }
    }

    private var selectedSession: TerminalMonitorSession? {
        guard let selectedSessionID else { return nil }
        return terminalMonitor.sessions.first(where: { $0.id == selectedSessionID })
    }

    private var selectedDetails: TerminalMonitorSessionDetails? {
        guard let selectedSession else { return nil }
        return terminalMonitor.details(for: selectedSession.id)
    }

    private var liveSessionCount: Int {
        terminalMonitor.sessions.filter { !$0.isHistorical }.count
    }

    private var historicalSessionCount: Int {
        terminalMonitor.sessions.filter(\.isHistorical).count
    }

    private var completedSessionCount: Int {
        terminalMonitor.sessions.filter { $0.status == .completed }.count
    }

    private var failedSessionCount: Int {
        terminalMonitor.sessions.filter { $0.status == .failed || $0.status == .stopped }.count
    }

    var body: some View {
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
        .padding()
        .onAppear {
            terminalMonitor.refreshRecentSessions(settings: store.settings, logger: logger)
            terminalMonitor.refreshStorageSummary(settings: store.settings, logger: logger)
            syncSelection()
            loadSelectedDetails(forceRefresh: false)
        }
        .onChange(of: terminalMonitor.sessions) { _ in
            syncSelection()
            loadSelectedDetails(forceRefresh: false)
        }
        .onChange(of: store.settings.postgresMonitoring) { _ in
            terminalMonitor.refreshStorageSummary(settings: store.settings, logger: logger)
        }
        .onChange(of: searchText) { _ in
            syncSelection()
        }
        .onChange(of: sourceFilter) { _ in
            syncSelection()
        }
        .onChange(of: statusFilter) { _ in
            syncSelection()
        }
        .onChange(of: selectedSessionID) { _ in
            loadSelectedDetails(forceRefresh: false)
        }
        .confirmationDialog(
            "Prune stored monitoring history?",
            isPresented: $showingPruneConfirmation,
            titleVisibility: .visible
        ) {
            Button("Prune Now", role: .destructive) {
                terminalMonitor.pruneStoredHistory(settings: store.settings, logger: logger)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes completed and failed MongoDB session history older than \(store.settings.postgresMonitoring.clampedDatabaseRetentionDays) day(s) and local transcript files older than \(store.settings.postgresMonitoring.clampedLocalTranscriptRetentionDays) day(s)."
            )
        }
    }

    private var summaryCard: some View {
        GroupBox("Terminal Transcript Monitor") {
            VStack(alignment: .leading, spacing: 12) {
                Text(terminalMonitor.databaseStatus)
                    .font(.headline)

                HStack(spacing: 14) {
                    Label("\(terminalMonitor.sessions.count) total", systemImage: "list.bullet.rectangle")
                    Label("\(liveSessionCount) live", systemImage: "waveform.path.ecg")
                    if store.settings.postgresMonitoring.enablePostgresWrites {
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
                    if store.settings.postgresMonitoring.enablePostgresWrites {
                        Label(store.settings.postgresMonitoring.redactedConnectionDescription, systemImage: "externaldrive.badge.icloud")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Label("Local transcript capture only", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Button("Test MongoDB Connection") {
                        terminalMonitor.testConnection(settings: store.settings, logger: logger)
                    }
                    .disabled(!store.settings.postgresMonitoring.enabled)

                    Button("Refresh Recent Sessions") {
                        terminalMonitor.refreshRecentSessions(settings: store.settings, logger: logger)
                        terminalMonitor.refreshStorageSummary(settings: store.settings, logger: logger)
                        loadSelectedDetails(forceRefresh: true)
                    }
                    .disabled(!store.settings.postgresMonitoring.enabled || !store.settings.postgresMonitoring.enablePostgresWrites)

                    Button("Reveal Transcript Folder") {
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
                        metricPill(title: "Chunks", value: "\(summary.chunkCount)", systemImage: "waveform")
                        metricPill(title: "Events", value: "\(summary.eventCount)", systemImage: "list.bullet.clipboard")
                        metricPill(title: "Local transcripts", value: "\(summary.transcriptFileCount)", systemImage: "doc.text")
                    }

                    HStack(spacing: 12) {
                        metricPill(title: "DB size", value: byteCountString(summary.totalDatabaseBytes), systemImage: "cylinder.split.1x2")
                        metricPill(title: "Logical transcript", value: byteCountString(summary.logicalTranscriptBytes), systemImage: "text.justify")
                        metricPill(title: "Local size", value: byteCountString(summary.transcriptFileBytes), systemImage: "folder")
                    }

                    if summary.hasAnyData {
                        VStack(alignment: .leading, spacing: 8) {
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
                        "Retention: DB \(store.settings.postgresMonitoring.clampedDatabaseRetentionDays) day(s) • local transcripts \(store.settings.postgresMonitoring.clampedLocalTranscriptRetentionDays) day(s)"
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
                        terminalMonitor.refreshStorageSummary(settings: store.settings, logger: logger)
                    }
                    .disabled(!store.settings.postgresMonitoring.enabled)

                    Button("Prune Stored History…") {
                        showingPruneConfirmation = true
                    }
                    .disabled(!store.settings.postgresMonitoring.enabled || terminalMonitor.isPruningStoredHistory)
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

            Text(store.settings.postgresMonitoring.captureMode.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.settings.postgresMonitoring.enablePostgresWrites {
                Text(
                    "Recent DB history: \(store.settings.postgresMonitoring.clampedRecentHistoryLookbackDays) day(s) / \(store.settings.postgresMonitoring.clampedRecentHistoryLimit) sessions"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(
                    "Detail load: \(store.settings.postgresMonitoring.clampedDetailEventLimit) events / \(store.settings.postgresMonitoring.clampedDetailChunkLimit) chunks"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sessionListPane: some View {
        GroupBox("Sessions") {
            List(selection: $selectedSessionID) {
                if filteredSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No monitored terminal sessions found.")
                            .font(.headline)
                        Text("Launch a profile or workbench through the app after enabling monitoring. MongoDB-backed history appears here when database writes are enabled and recent rows are available.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                } else {
                    ForEach(filteredSessions) { session in
                        sessionRow(session)
                            .tag(Optional(session.id))
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: TerminalMonitorSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.profileName)
                    .font(.headline)
                if session.isHistorical {
                        Text("MongoDB")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(7)
                }
                Spacer()
                Label(session.status.displayName, systemImage: session.status.systemImage)
                    .font(.caption)
                    .foregroundStyle(statusColor(for: session.status))
            }

            Text(session.agentKind.displayName + " • " + session.workingDirectory)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !session.lastPreview.isEmpty {
                Text(session.lastPreview)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
            }

            HStack(spacing: 10) {
                Label("\(session.chunkCount)", systemImage: "waveform")
                Label(byteCountString(session.byteCount), systemImage: "internaldrive")
                Label(session.activityDate.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                if let exitCode = session.exitCode {
                    Label("exit \(exitCode)", systemImage: exitCode == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var sessionDetailPane: some View {
        if let session = selectedSession {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    detailHeader(session)
                    overviewCard(for: session)
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
                    Text(session.profileName)
                        .font(.title2.bold())
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
                    if let duration = session.duration {
                        metricPill(title: "Duration", value: durationString(duration), systemImage: "timer")
                    }
                    if let exitCode = session.exitCode {
                        metricPill(title: "Exit", value: String(exitCode), systemImage: exitCode == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                    }
                }

                detailLine(label: "Source", value: session.isHistorical ? "Loaded from MongoDB history" : "Live local session")
                detailLine(label: "Agent", value: session.agentKind.displayName)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionsCard(for session: TerminalMonitorSession) -> some View {
        GroupBox("Actions") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Reload Details") {
                        loadSelectedDetails(forceRefresh: true)
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

    private func transcriptCard(for session: TerminalMonitorSession) -> some View {
        GroupBox("Transcript") {
            VStack(alignment: .leading, spacing: 8) {
                if let details = selectedDetails {
                    HStack(alignment: .firstTextBaseline) {
                        Text(details.transcriptSourceDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func eventsCard(for session: TerminalMonitorSession) -> some View {
        GroupBox("Event Timeline") {
            VStack(alignment: .leading, spacing: 10) {
                if let details = selectedDetails {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chunksCard(for session: TerminalMonitorSession) -> some View {
        GroupBox("Recent Transcript Chunks") {
            VStack(alignment: .leading, spacing: 10) {
                if let details = selectedDetails {
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
                                Text(chunk.text.isEmpty ? chunk.previewText : chunk.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.08))
                                    .cornerRadius(8)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("Chunk \(chunk.chunkIndex)")
                                            .font(.headline)
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
        if let selectedSessionID, visibleIDs.contains(selectedSessionID) {
            return
        }
        selectedSessionID = filteredSessions.first?.id
    }

    private func loadSelectedDetails(forceRefresh: Bool) {
        guard let session = selectedSession else { return }
        terminalMonitor.loadDetails(for: session, settings: store.settings, logger: logger, forceRefresh: forceRefresh)
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
