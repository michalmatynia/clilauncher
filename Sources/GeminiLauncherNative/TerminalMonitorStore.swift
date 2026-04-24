import AppKit
import Combine
import Foundation

private struct PreparedMonitoringContext: Sendable {
    var session: TerminalMonitorSession
    var wrappedCommand: String
    var completionMarkerPath: String
    var inputCapturePath: String?
    var launchScriptPath: String?
}

private struct SessionCompletionMarker: Sendable {
    var exitCode: Int
    var endedAt: Date
    var reason: String
}

private struct TranscriptPreviewSnapshot: Sendable {
    var text: String
    var sourceDescription: String
    var isTruncated: Bool
}

private struct LocalDetailArtifacts: Sendable {
    var transcriptText: String = ""
    var transcriptSource: String = ""
    var transcriptTruncated: Bool = false
    var loadNotes: [String] = []
    var inputChunks: [TerminalInputChunk] = []
}

struct ScriptRecordingRecord: Sendable {
    var dataLength: Int
    var capturedAt: Date
    var direction: Character
    var data: Data
}

private struct LocalTranscriptInventory: Sendable {
    var transcriptFileCount: Int = 0
    var transcriptFileBytes: Int64 = 0
    var oldestTranscriptFileAt: Date?
    var newestTranscriptFileAt: Date?
    var inputCaptureFileCount: Int = 0
    var inputCaptureFileBytes: Int64 = 0
    var oldestInputCaptureFileAt: Date?
    var newestInputCaptureFileAt: Date?
}

private struct LocalTranscriptPruneResult: Sendable {
    var deletedTranscriptFileCount: Int = 0
    var deletedTranscriptBytes: Int64 = 0
    var deletedInputCaptureFileCount: Int = 0
    var deletedInputCaptureBytes: Int64 = 0
}

enum TranscriptSynchronizationContext: Sendable {
    case completionSuccess
    case completionFailure
    case monitoringFailure
    case recentSessionRefresh
    case directoryRecovery
}

enum RecentSessionRefreshWorkload: String, Sendable {
    case interactive
    case maintenance

    var includesMaintenance: Bool {
        self == .maintenance
    }
}

struct GeminiSessionStatsModelUsageRow: Codable, Equatable, Sendable {
    var model: String
    var label: String?
    var requests: Int?
    var inputTokens: Int?
    var cacheReads: Int?
    var outputTokens: Int?

    var metadata: [String: Any] {
        var result: [String: Any] = ["model": model]
        if let label, !label.isEmpty {
            result["label"] = label
        }
        if let requests {
            result["requests"] = requests
        }
        if let inputTokens {
            result["input_tokens"] = inputTokens
        }
        if let cacheReads {
            result["cache_reads"] = cacheReads
        }
        if let outputTokens {
            result["output_tokens"] = outputTokens
        }
        return result
    }
}

struct GeminiModelCapacityRow: Codable, Equatable, Sendable {
    var model: String
    var usedPercentage: Int?
    var resetTime: String?
    var rawText: String?

    var metadata: [String: Any] {
        var result: [String: Any] = ["model": model]
        if let usedPercentage {
            result["used_percentage"] = usedPercentage
        }
        if let resetTime, !resetTime.isEmpty {
            result["reset_time"] = resetTime
        }
        if let rawText, !rawText.isEmpty {
            result["raw_text"] = rawText
        }
        return result
    }
}

struct GeminiModelCapacitySnapshot: Codable, Equatable, Sendable {
    var startupModelCommand: String?
    var startupModelCommandSource: String?
    var currentModel: String?
    var rows: [GeminiModelCapacityRow] = []
    var rawLines: [String] = []

    var metadata: [String: Any] {
        var result: [String: Any] = [:]
        if let startupModelCommand, !startupModelCommand.isEmpty {
            result["startup_model_command"] = startupModelCommand
        }
        if let startupModelCommandSource, !startupModelCommandSource.isEmpty {
            result["startup_model_command_source"] = startupModelCommandSource
        }
        if let currentModel, !currentModel.isEmpty {
            result["current_model"] = currentModel
        }
        if !rows.isEmpty {
            result["rows"] = rows.map(\.metadata)
        }
        if !rawLines.isEmpty {
            result["raw_lines"] = rawLines
        }
        return result
    }
}

struct GeminiSessionStatsSnapshot: Codable, Equatable, Sendable {
    var sessionID: String
    var authMethod: String?
    var accountIdentifier: String?
    var tier: String?
    var toolCalls: String?
    var successRate: String?
    var wallTime: String?
    var agentActive: String?
    var apiTime: String?
    var toolTime: String?
    var startupStatsCommand: String? = nil
    var startupStatsCommandSource: String? = nil
    var modelUsageNote: String?
    var modelUsage: [GeminiSessionStatsModelUsageRow] = []

    var metadata: [String: Any] {
        var result: [String: Any] = ["session_id": sessionID]
        if let authMethod, !authMethod.isEmpty {
            result["auth_method"] = authMethod
        }
        if let accountIdentifier, !accountIdentifier.isEmpty {
            result["account_identifier"] = accountIdentifier
        }
        if let tier, !tier.isEmpty {
            result["tier"] = tier
        }
        if let toolCalls, !toolCalls.isEmpty {
            result["tool_calls"] = toolCalls
        }
        if let successRate, !successRate.isEmpty {
            result["success_rate"] = successRate
        }
        if let wallTime, !wallTime.isEmpty {
            result["wall_time"] = wallTime
        }
        if let agentActive, !agentActive.isEmpty {
            result["agent_active"] = agentActive
        }
        if let apiTime, !apiTime.isEmpty {
            result["api_time"] = apiTime
        }
        if let toolTime, !toolTime.isEmpty {
            result["tool_time"] = toolTime
        }
        if let startupStatsCommand, !startupStatsCommand.isEmpty {
            result["startup_stats_command"] = startupStatsCommand
        }
        if let startupStatsCommandSource, !startupStatsCommandSource.isEmpty {
            result["startup_stats_command_source"] = startupStatsCommandSource
        }
        if let modelUsageNote, !modelUsageNote.isEmpty {
            result["model_usage_note"] = modelUsageNote
        }
        if !modelUsage.isEmpty {
            result["model_usage"] = modelUsage.map(\.metadata)
        }
        return result
    }
}

private struct GeminiSessionStatsCapture: Equatable, Sendable {
    var fingerprint: String
    var snapshot: GeminiSessionStatsSnapshot
}

private struct GeminiModelCapacityCapture: Equatable, Sendable {
    var fingerprint: String
    var snapshot: GeminiModelCapacitySnapshot
}

struct GeminiLaunchContextSnapshot: Equatable, Sendable {
    var cliVersion: String?
    var runnerPath: String?
    var runnerBuild: String?
    var wrapperResolvedPath: String?
    var wrapperKind: String?
    var launchMode: String?
    var shellFallbackExecutable: String?
    var autoContinueMode: String?
    var ptyBackend: String?

    var metadata: [String: Any] {
        var result: [String: Any] = [:]
        if let cliVersion, !cliVersion.isEmpty {
            result["cli_version"] = cliVersion
        }
        if let runnerPath, !runnerPath.isEmpty {
            result["runner_path"] = runnerPath
        }
        if let runnerBuild, !runnerBuild.isEmpty {
            result["runner_build"] = runnerBuild
        }
        if let wrapperResolvedPath, !wrapperResolvedPath.isEmpty {
            result["wrapper_resolved_path"] = wrapperResolvedPath
        }
        if let wrapperKind, !wrapperKind.isEmpty {
            result["wrapper_kind"] = wrapperKind
        }
        if let launchMode, !launchMode.isEmpty {
            result["launch_mode"] = launchMode
        }
        if let shellFallbackExecutable, !shellFallbackExecutable.isEmpty {
            result["shell_fallback_executable"] = shellFallbackExecutable
        }
        if let autoContinueMode, !autoContinueMode.isEmpty {
            result["auto_continue_mode"] = autoContinueMode
        }
        if let ptyBackend, !ptyBackend.isEmpty {
            result["pty_backend"] = ptyBackend
        }
        return result
    }
}

private struct GeminiLaunchContextNotice: Equatable, Sendable {
    var fingerprint: String
    var snapshot: GeminiLaunchContextSnapshot
}

enum GeminiTranscriptInteractionKind: String, Equatable, Sendable {
    case slashCommand = "slash_command"
    case prompt = "prompt"

    var asObservedInteractionKind: ObservedTranscriptInteraction.Kind {
        switch self {
        case .slashCommand:
            return .slashCommand
        case .prompt:
            return .prompt
        }
    }
}

struct GeminiTranscriptInteractionNotice: Equatable, Sendable {
    var fingerprint: String
    var text: String
    var kind: GeminiTranscriptInteractionKind
    var source: String

    var eventType: String {
        switch kind {
        case .slashCommand:
            return "slash_command_observed"
        case .prompt:
            return "prompt_observed"
        }
    }

    var message: String {
        switch kind {
        case .slashCommand:
            return "Observed Gemini slash command \(text) in transcript."
        case .prompt:
            return "Observed Gemini prompt submission: \(text)"
        }
    }

    var metadata: [String: Any] {
        [
            "text": text,
            "kind": kind.rawValue,
            "source": source,
        ]
    }
}

private struct GeminiSessionStatsSkipNotice: Equatable, Sendable {
    var fingerprint: String
    var reason: String

    var metadata: [String: Any] {
        [
            "reason": reason,
            "source": "runner_banner"
        ]
    }
}

private struct GeminiSessionStatsBlockedNotice: Equatable, Sendable {
    var fingerprint: String
    var reason: String

    var metadata: [String: Any] {
        [
            "reason": reason,
            "source": "runner_banner",
            "prompt_injection_blocked": true
        ]
    }
}

private struct GeminiCompatibilityOverrideNotice: Equatable, Sendable {
    var fingerprint: String
    var reason: String

    var metadata: [String: Any] {
        [
            "reason": reason,
            "source": "runner_banner"
        ]
    }
}

struct GeminiStartupClearNotice: Equatable, Sendable {
    var fingerprint: String
    var command: String
    var completed: Bool
    var reason: String?
    var source: String = "runner_banner"

    var metadata: [String: Any] {
        var result: [String: Any] = [
            "source": source,
            "command": command,
            "completed": completed
        ]
        if let reason, !reason.isEmpty {
            result["reason"] = reason
        }
        return result
    }
}

struct GeminiFreshSessionResetNotice: Equatable, Sendable {
    var fingerprint: String
    var reason: String
    var cleared: Bool
    var removedPathCount: Int?

    var metadata: [String: Any] {
        var result: [String: Any] = [
            "reason": reason,
            "source": "runner_banner",
            "cleared": cleared
        ]
        if let removedPathCount {
            result["removed_path_count"] = removedPathCount
        }
        return result
    }
}

private struct GeminiSessionStatsFallbackNotice: Equatable, Sendable {
    var fingerprint: String
    var fromCommand: String
    var toCommand: String

    var metadata: [String: Any] {
        [
            "source": "runner_banner",
            "from_command": fromCommand,
            "to_command": toCommand
        ]
    }
}

private struct GeminiStartupCommandMatch: Equatable, Sendable {
    var command: String
    var source: String
}

private enum MonitorTimestamp {
    private static func makeFractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makePlainFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    static func string(from date: Date) -> String {
        makeFractionalFormatter().string(from: date)
    }

    static func parse(_ value: String?) -> Date? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return makeFractionalFormatter().date(from: trimmed) ?? makePlainFormatter().date(from: trimmed)
    }
}

@MainActor
final class TerminalMonitorStore: ObservableObject {
    @Published var sessions: [TerminalMonitorSession] = []
    @Published var databaseStatus: String = "Monitoring disabled"
    @Published var lastConnectionCheck: String = ""
    @Published var storageSummaryStatus: String = ""
    @Published var lastPruneSummary: String = ""
    @Published private(set) var sessionDetailsByID: [UUID: TerminalMonitorSessionDetails] = [:]
    @Published private(set) var detailLoadingSessionIDs: Set<UUID> = []
    @Published private(set) var storageSummary: MongoStorageSummary?
    @Published private(set) var lastPruneResult: MongoPruneSummary?
    @Published private(set) var isLoadingStorageSummary: Bool = false
    @Published private(set) var isPruningStoredHistory: Bool = false
    @Published private(set) var isLoadingRecentSessions: Bool = false

    private let minimumDetailRefreshInterval: TimeInterval = 1.5
    private let minimumRecentSessionsRefreshInterval: TimeInterval = 2.5
    private let minimumRecentSessionMaintenanceInterval: TimeInterval = 20
    private let minimumStorageSummaryRefreshInterval: TimeInterval = 12
    private let deferredRecentSessionMaintenanceDelayNanoseconds: UInt64 = 1_500_000_000
    private static let maxVisibleSessions = 200
    private static let sessionStatsBufferLimit = 120_000
    private static let sessionStatsFingerprintLimit = 12
    nonisolated private static let transcriptChunkByteLimit = 12_000

    private var preparedContexts: [UUID: PreparedMonitoringContext] = [:]
    private var pollTasks: [UUID: Task<Void, Never>] = [:]
    private var sessionStatsBuffersByID: [UUID: String] = [:]
    private var sessionStatsFingerprintsByID: [UUID: [String]] = [:]
    private var sessionStatsSkipFingerprintsByID: [UUID: [String]] = [:]
    private var sessionStatsBlockedFingerprintsByID: [UUID: [String]] = [:]
    private var sessionStatsFallbackFingerprintsByID: [UUID: [String]] = [:]
    private var modelCapacityFingerprintsByID: [UUID: [String]] = [:]
    private var launchContextFingerprintsByID: [UUID: [String]] = [:]
    private var startupClearFingerprintsByID: [UUID: [String]] = [:]
    private var startupClearCompletedFingerprintsByID: [UUID: [String]] = [:]
    private var compatibilityOverrideFingerprintsByID: [UUID: [String]] = [:]
    private var freshSessionResetFingerprintsByID: [UUID: [String]] = [:]
    private var transcriptInteractionHistoryByID: [UUID: [String]] = [:]
    private var nextDetailRefreshAt: [UUID: Date] = [:]
    private var requestedDetailWorkloadsByID: [UUID: MonitorDetailLoadWorkload] = [:]
    private var activeDetailWorkloadsByID: [UUID: MonitorDetailLoadWorkload] = [:]
    private var lastRecentSessionsRefreshAt: Date?
    private var lastRecentSessionMaintenanceAt: Date?
    private var lastStorageSummaryRefreshAt: Date?
    private var sessionIndexByID: [UUID: Int] = [:]
    private var pendingFocusedSessionID: UUID?
    private var pendingMonitoringFilterReset = false
    private var recentSessionMaintenanceTask: Task<Void, Never>?
    private var isRunningRecentSessionMaintenance = false
    private let writer = MongoMonitoringWriter()
    private let backupService = DatabaseBackupService()
    private let diagnostics = MonitoringDiagnosticsService()

    private func logMonitoringTiming(_ operation: String, startedAt: CFTimeInterval, logger: LaunchLogger, details: String? = nil) {
        let elapsedMs = Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded())
        let mergedDetails = [details, "elapsed_ms=\(elapsedMs)"].compactMap(\.self).joined(separator: " • ")
        logger.debug("Monitoring timing: \(operation)", category: .monitoring, details: mergedDetails)
    }

    private func setDatabaseStatusIfChanged(_ value: String) {
        guard databaseStatus != value else { return }
        databaseStatus = value
    }

    private func setLastConnectionCheckIfChanged(_ value: String) {
        guard lastConnectionCheck != value else { return }
        lastConnectionCheck = value
    }

    private func setStorageSummaryIfChanged(_ value: MongoStorageSummary?) {
        guard storageSummary != value else { return }
        storageSummary = value
    }

    private func setStorageSummaryStatusIfChanged(_ value: String) {
        guard storageSummaryStatus != value else { return }
        storageSummaryStatus = value
    }

    private func setIsLoadingStorageSummaryIfChanged(_ value: Bool) {
        guard isLoadingStorageSummary != value else { return }
        isLoadingStorageSummary = value
    }

    private func setIsLoadingRecentSessionsIfChanged(_ value: Bool) {
        guard isLoadingRecentSessions != value else { return }
        isLoadingRecentSessions = value
    }

    private func replaceSessionDetailsIfChanged(_ details: TerminalMonitorSessionDetails) {
        guard sessionDetailsByID[details.sessionID] != details else { return }
        sessionDetailsByID[details.sessionID] = details
    }

    private func insertDetailLoadingSessionIDIfNeeded(_ sessionID: UUID) {
        guard !detailLoadingSessionIDs.contains(sessionID) else { return }
        var updated = detailLoadingSessionIDs
        updated.insert(sessionID)
        detailLoadingSessionIDs = updated
    }

    private func removeDetailLoadingSessionIDIfPresent(_ sessionID: UUID) {
        guard detailLoadingSessionIDs.contains(sessionID) else { return }
        var updated = detailLoadingSessionIDs
        updated.remove(sessionID)
        detailLoadingSessionIDs = updated
    }

    private func pruneSessionDetailState(for sessionIDs: some Sequence<UUID>) {
        var updatedDetails = sessionDetailsByID
        var detailsChanged = false
        var updatedLoading = detailLoadingSessionIDs
        var loadingChanged = false

        for sessionID in sessionIDs {
            if updatedDetails.removeValue(forKey: sessionID) != nil {
                detailsChanged = true
            }
            if updatedLoading.remove(sessionID) != nil {
                loadingChanged = true
            }
            nextDetailRefreshAt.removeValue(forKey: sessionID)
        }

        if detailsChanged {
            sessionDetailsByID = updatedDetails
        }
        if loadingChanged {
            detailLoadingSessionIDs = updatedLoading
        }
    }

    func prepare(plan: PlannedLaunch, profiles: [LaunchProfile], settings: AppSettings, logger: LaunchLogger) throws -> PlannedLaunch {
        guard settings.mongoMonitoring.enabled else {
            return plan
        }

        let transcriptDirectory = settings.mongoMonitoring.expandedTranscriptDirectory
        try FileManager.default.createDirectory(atPath: transcriptDirectory, withIntermediateDirectories: true, attributes: nil)

        var updatedPlan = plan
        let profileLookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        for index in updatedPlan.items.indices {
            let item = updatedPlan.items[index]
            guard let profile = profileLookup[item.profileID] else { continue }

            let context = try buildPreparedContext(item: item, profile: profile, settings: settings.mongoMonitoring)
            preparedContexts[context.session.id] = context
            updatedPlan.items[index].command = context.wrappedCommand
            updatedPlan.items[index].monitorSessionID = context.session.id
            logger.debug(
                "Prepared monitored launch helper.",
                category: .monitoring,
                details: "session=\(context.session.id.uuidString) • transcript=\(context.session.transcriptPath) • helper=\(context.launchScriptPath ?? "<none>") • helperExists=\(context.launchScriptPath.map { FileManager.default.fileExists(atPath: $0) } ?? false)"
            )
        }

        setDatabaseStatusIfChanged(
            settings.mongoMonitoring.enableMongoWrites
                ? "Prepared \(updatedPlan.items.count) monitored launch(es)."
                : "Local transcript monitoring prepared."
        )
        logger.log(.info, "Prepared \(updatedPlan.items.count) monitored iTerm2 launch(es).", category: .monitoring)
        return updatedPlan
    }

    func activatePreparedSessions(for plan: PlannedLaunch, settings: AppSettings, logger: LaunchLogger) {
        guard settings.mongoMonitoring.enabled else { return }

        for item in plan.items {
            guard let sessionID = item.monitorSessionID,
                  let context = preparedContexts.removeValue(forKey: sessionID)
            else { continue }

            var session = context.session
            session.status = .launching
            session.lastDatabaseMessage = settings.mongoMonitoring.enableMongoWrites ? "Awaiting first MongoDB sync." : "Local transcript capture started."
            upsert(session)
            noteSessionForInspection(session.id)

            if settings.mongoMonitoring.enableMongoWrites {
                Task {
                    do {
                        try await writer.ensureSchema(settings: settings.mongoMonitoring)
                        try await writer.recordSessionStart(session, settings: settings.mongoMonitoring)
                        await MainActor.run {
                            self.setDatabaseStatusIfChanged("MongoDB session logging active.")
                            self.setLastConnectionCheckIfChanged(Date().formatted(date: .abbreviated, time: .standard))
                        }
                    } catch {
                        await MainActor.run {
                            if let index = self.sessionIndex(for: session.id) {
                                self.sessions[index].lastDatabaseMessage = "MongoDB unavailable: \(error.localizedDescription)"
                            }
                            self.setDatabaseStatusIfChanged("MongoDB write error")
                            logger.log(.warning, "MongoDB monitor setup failed; local transcript capture is still running: \(error.localizedDescription)", category: .monitoring)
                        }
                    }
                }
            }

            startPolling(context: context, settings: settings.mongoMonitoring)
        }
    }

    func cancelPreparedSessions(for plan: PlannedLaunch, reason: String, settings: AppSettings, logger: LaunchLogger) {
        for item in plan.items {
            guard let sessionID = item.monitorSessionID else { continue }
            let context = preparedContexts.removeValue(forKey: sessionID)
            stopPolling(sessionID: sessionID)
            if let launchScriptPath = context?.launchScriptPath {
                try? FileManager.default.removeItem(atPath: launchScriptPath)
            }

            var cancelled = session(for: sessionID) ?? TerminalMonitorSession(
                id: sessionID,
                profileID: item.profileID,
                profileName: item.profileName,
                agentKind: .gemini,
                workingDirectory: "",
                transcriptPath: context?.session.transcriptPath ?? "",
                launchCommand: item.command,
                captureMode: settings.mongoMonitoring.captureMode
            )
            cancelled.status = .failed
            cancelled.endedAt = Date()
            cancelled.lastError = reason
            cancelled.statusReason = "launch_cancelled"
            cancelled.lastDatabaseMessage = settings.mongoMonitoring.enableMongoWrites ? "Launch failed before monitoring could start." : "Launch failed before monitoring could start."
            upsert(cancelled)

            if settings.mongoMonitoring.enableMongoWrites {
                Task {
                    try? await writer.recordStatus(
                        session: cancelled,
                        status: .failed,
                        eventType: "session_launch_cancelled",
                        message: reason,
                        eventAt: Date(),
                        endedAt: Date(),
                        statusReason: "launch_cancelled",
                        exitCode: nil,
                        settings: settings.mongoMonitoring
                    )
                }
            }
        }
        if !plan.items.isEmpty {
            logger.log(.warning, "Cancelled prepared terminal monitoring sessions because launch failed.", category: .monitoring)
        }
    }

    func clearCompleted() {
        let removedIDs = Set(sessions.filter { $0.status == .failed || $0.status == .stopped || $0.status == .completed }.map(\.id))
        sessions.removeAll { removedIDs.contains($0.id) }
        pruneSessionDetailState(for: removedIDs)
        for id in removedIDs {
            sessionIndexByID.removeValue(forKey: id)
        }

        rebuildSessionIndex()
    }

    func revealTranscriptDirectory(settings: AppSettings) {
        let path = settings.mongoMonitoring.expandedTranscriptDirectory
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func testConnection(settings: AppSettings, logger: LaunchLogger) {
        guard settings.mongoMonitoring.enabled else {
            setDatabaseStatusIfChanged("Monitoring disabled")
            logger.log(.warning, "Enable terminal monitoring before testing MongoDB connectivity.", category: .monitoring)
            return
        }
        guard settings.mongoMonitoring.enableMongoWrites else {
            setDatabaseStatusIfChanged("Local capture monitoring only")
            logger.log(.info, "MongoDB writes are disabled; local transcript and raw input capture monitoring is still available.", category: .monitoring)
            return
        }

        setDatabaseStatusIfChanged("Testing connection...")
        Task {
            do {
                let result = try await writer.testConnection(settings: settings.mongoMonitoring)
                await MainActor.run {
                    self.setLastConnectionCheckIfChanged(Date().formatted(date: .abbreviated, time: .standard))
                    self.setDatabaseStatusIfChanged("Connected • \(result)")
                    logger.log(.success, "MongoDB monitoring connection OK: \(result)", category: .monitoring)
                }
            } catch {
                await MainActor.run {
                    self.setDatabaseStatusIfChanged("Connection failed: \(error.localizedDescription)")
                    logger.log(.error, "MongoDB monitoring connection failed: \(error.localizedDescription)", category: .monitoring)
                }
            }
        }
    }

    @discardableResult
    private func scheduleRecentSessionMaintenanceIfNeeded(settings: AppSettings, logger: LaunchLogger, force: Bool) -> Bool {
        let now = Date()
        guard Self.shouldScheduleDeferredRecentSessionMaintenance(
            enableMongoWrites: settings.mongoMonitoring.enabled && settings.mongoMonitoring.enableMongoWrites,
            isLoadingRecentSessions: isLoadingRecentSessions,
            isRunningRecentSessionMaintenance: isRunningRecentSessionMaintenance,
            hasPendingMaintenanceTask: recentSessionMaintenanceTask != nil,
            force: force,
            lastRecentSessionMaintenanceAt: lastRecentSessionMaintenanceAt,
            now: now,
            minimumRecentSessionMaintenanceInterval: minimumRecentSessionMaintenanceInterval
        ) else {
            return false
        }

        recentSessionMaintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.recentSessionMaintenanceTask = nil }

            try? await Task.sleep(nanoseconds: self.deferredRecentSessionMaintenanceDelayNanoseconds)
            guard !Task.isCancelled else { return }

            self.refreshRecentSessions(
                settings: settings,
                logger: logger,
                force: true,
                workload: .maintenance
            )
        }
        return true
    }

    nonisolated static func shouldScheduleDeferredRecentSessionMaintenance(
        enableMongoWrites: Bool,
        isLoadingRecentSessions: Bool,
        isRunningRecentSessionMaintenance: Bool,
        hasPendingMaintenanceTask: Bool,
        force: Bool,
        lastRecentSessionMaintenanceAt: Date?,
        now: Date,
        minimumRecentSessionMaintenanceInterval: TimeInterval
    ) -> Bool {
        guard enableMongoWrites else { return false }
        guard !isLoadingRecentSessions, !isRunningRecentSessionMaintenance, !hasPendingMaintenanceTask else {
            return false
        }
        if !force,
           let lastRecentSessionMaintenanceAt,
           now.timeIntervalSince(lastRecentSessionMaintenanceAt) < minimumRecentSessionMaintenanceInterval {
            return false
        }
        return true
    }

    func refreshRecentSessions(
        settings: AppSettings,
        logger: LaunchLogger,
        force: Bool = false,
        workload: RecentSessionRefreshWorkload = .maintenance
    ) {
        let refreshStartedAt = CFAbsoluteTimeGetCurrent()
        guard settings.mongoMonitoring.enabled else {
            setDatabaseStatusIfChanged("Monitoring disabled")
            setStorageSummaryIfChanged(nil)
            setStorageSummaryStatusIfChanged("")
            setIsLoadingRecentSessionsIfChanged(false)
            recentSessionMaintenanceTask?.cancel()
            recentSessionMaintenanceTask = nil
            isRunningRecentSessionMaintenance = false
            return
        }
        guard settings.mongoMonitoring.enableMongoWrites else {
            setDatabaseStatusIfChanged("Local transcript monitoring only")
            setIsLoadingRecentSessionsIfChanged(false)
            recentSessionMaintenanceTask?.cancel()
            recentSessionMaintenanceTask = nil
            isRunningRecentSessionMaintenance = false
            return
        }
        let now = Date()
        if isLoadingRecentSessions {
            return
        }
        if !force {
            if let lastRefresh = lastRecentSessionsRefreshAt,
               now.timeIntervalSince(lastRefresh) < minimumRecentSessionsRefreshInterval {
                return
            }
            if workload.includesMaintenance,
               let lastRecentSessionMaintenanceAt,
               now.timeIntervalSince(lastRecentSessionMaintenanceAt) < minimumRecentSessionMaintenanceInterval {
                return
            }
        }

        setIsLoadingRecentSessionsIfChanged(true)
        if workload.includesMaintenance {
            isRunningRecentSessionMaintenance = true
            recentSessionMaintenanceTask?.cancel()
            recentSessionMaintenanceTask = nil
        }
        Task {
            do {
                let databaseSessions = try await writer.fetchRecentSessions(
                    settings: settings.mongoMonitoring,
                    limit: settings.mongoMonitoring.clampedRecentHistoryLimit,
                    lookbackHours: settings.mongoMonitoring.clampedRecentHistoryLookbackDays * 24
                )
                if !workload.includesMaintenance {
                    let mergedSessions = Self.mergedDistinctSessions(databaseSessions)
                    await MainActor.run {
                        self.synchronizeHistoricalSessions(mergedSessions)
                        self.setLastConnectionCheckIfChanged(Date().formatted(date: .abbreviated, time: .standard))
                        let scheduledMaintenance = self.scheduleRecentSessionMaintenanceIfNeeded(
                            settings: settings,
                            logger: logger,
                            force: force
                        )
                        self.setDatabaseStatusIfChanged(
                            scheduledMaintenance
                                ? "Loaded \(mergedSessions.count) recent session(s) from MongoDB. Background reconciliation scheduled."
                                : "Loaded \(mergedSessions.count) recent session(s) from MongoDB."
                        )
                        self.lastRecentSessionsRefreshAt = now
                        self.setIsLoadingRecentSessionsIfChanged(false)
                        self.logMonitoringTiming(
                            "refreshRecentSessions",
                            startedAt: refreshStartedAt,
                            logger: logger,
                            details: "workload=\(workload.rawValue) • sessions=\(mergedSessions.count) • scheduled_maintenance=\(scheduledMaintenance)"
                        )
                    }
                    return
                }
                let recovered = await recoverOrphanedLocalTranscriptSessionsToMongoIfNeeded(
                    existingSessions: databaseSessions,
                    settings: settings.mongoMonitoring,
                    logger: logger
                )
                let mergedSessions = Self.mergedDistinctSessions(databaseSessions + recovered.sessions)
                let transcriptReconciliation = await reconcileRecentSessionTranscriptsToMongoIfNeeded(
                    mergedSessions,
                    settings: settings.mongoMonitoring,
                    logger: logger
                )
                let inputReconciliation = await reconcileRecentSessionInputCapturesToMongoIfNeeded(
                    transcriptReconciliation.sessions,
                    settings: settings.mongoMonitoring,
                    logger: logger
                )
                let transcriptCoverageBackfill = await backfillMongoTranscriptCoverageIfNeeded(
                    inputReconciliation.sessions,
                    settings: settings.mongoMonitoring,
                    logger: logger
                )
                let inputCoverageBackfill = await backfillMongoInputCoverageIfNeeded(
                    transcriptCoverageBackfill.sessions,
                    settings: settings.mongoMonitoring,
                    logger: logger
                )
                await MainActor.run {
                    self.synchronizeHistoricalSessions(inputCoverageBackfill.sessions)
                    self.setLastConnectionCheckIfChanged(Date().formatted(date: .abbreviated, time: .standard))
                    if recovered.recoveredSessionCount > 0 ||
                        transcriptReconciliation.synchronizedSessionCount > 0 ||
                        inputReconciliation.synchronizedSessionCount > 0 ||
                        transcriptCoverageBackfill.completedSessionCount > 0 ||
                        inputCoverageBackfill.completedSessionCount > 0 {
                        let recoverySummary = recovered.recoveredSessionCount > 0
                            ? "recovered \(recovered.recoveredSessionCount) orphaned local transcript(s)"
                            : nil
                        let syncSummary = transcriptReconciliation.synchronizedSessionCount > 0
                            ? "synchronized \(transcriptReconciliation.synchronizedSessionCount) local transcript(s)"
                            : nil
                        let inputSyncSummary = inputReconciliation.synchronizedSessionCount > 0
                            ? "synchronized \(inputReconciliation.synchronizedSessionCount) local raw input capture(s)"
                            : nil
                        let coverageSummary = transcriptCoverageBackfill.completedSessionCount > 0
                            ? "marked \(transcriptCoverageBackfill.completedSessionCount) MongoDB session(s) transcript-complete"
                            : nil
                        let inputCoverageSummary = inputCoverageBackfill.completedSessionCount > 0
                            ? "marked \(inputCoverageBackfill.completedSessionCount) MongoDB session(s) input-complete"
                            : nil
                        let summary = [recoverySummary, syncSummary, inputSyncSummary, coverageSummary, inputCoverageSummary].compactMap(\.self).joined(separator: " and ")
                        self.setDatabaseStatusIfChanged("Loaded \(inputCoverageBackfill.sessions.count) session(s) and \(summary).")
                        logger.log(
                            .success,
                            "Loaded \(inputCoverageBackfill.sessions.count) monitored session(s) and \(summary).",
                            category: .monitoring,
                            details: "recovered_chunks=\(recovered.importedChunkCount) • synchronized_transcript_chunks=\(transcriptReconciliation.importedChunkCount) • synchronized_input_chunks=\(inputReconciliation.importedChunkCount)"
                        )
                    } else {
                        self.setDatabaseStatusIfChanged("Loaded \(inputCoverageBackfill.sessions.count) recent session(s) from MongoDB.")
                        logger.log(.success, "Loaded \(inputCoverageBackfill.sessions.count) recent monitored session(s) from MongoDB.", category: .monitoring)
                    }
                    self.lastRecentSessionMaintenanceAt = now
                    self.lastRecentSessionsRefreshAt = now
                    self.setIsLoadingRecentSessionsIfChanged(false)
                    self.isRunningRecentSessionMaintenance = false
                    self.logMonitoringTiming(
                        "refreshRecentSessions",
                        startedAt: refreshStartedAt,
                        logger: logger,
                        details: "workload=\(workload.rawValue) • sessions=\(inputCoverageBackfill.sessions.count) • recovered=\(recovered.recoveredSessionCount) • transcript_sync=\(transcriptReconciliation.synchronizedSessionCount) • input_sync=\(inputReconciliation.synchronizedSessionCount) • transcript_complete=\(transcriptCoverageBackfill.completedSessionCount) • input_complete=\(inputCoverageBackfill.completedSessionCount)"
                    )
                }
            } catch {
                await MainActor.run {
                    self.setDatabaseStatusIfChanged("Recent session refresh failed")
                    logger.log(.error, "Failed to load recent MongoDB-backed sessions: \(error.localizedDescription)", category: .monitoring)
                    if workload.includesMaintenance {
                        self.lastRecentSessionMaintenanceAt = now
                    }
                    self.lastRecentSessionsRefreshAt = now
                    self.setIsLoadingRecentSessionsIfChanged(false)
                    self.isRunningRecentSessionMaintenance = false
                    self.logMonitoringTiming(
                        "refreshRecentSessions_failed",
                        startedAt: refreshStartedAt,
                        logger: logger,
                        details: "workload=\(workload.rawValue) • error=\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func recoverOrphanedLocalTranscriptSessionsToMongoIfNeeded(
        existingSessions: [TerminalMonitorSession],
        settings: MongoMonitoringSettings,
        logger: LaunchLogger
    ) async -> (sessions: [TerminalMonitorSession], recoveredSessionCount: Int, importedChunkCount: Int) {
        guard settings.enableMongoWrites else {
            return ([], 0, 0)
        }

        let activeStatuses: Set<TerminalMonitorStatus> = [.prepared, .launching, .monitoring, .idle]
        let activeLocalSessionIDs = Set(
            sessions
                .filter { activeStatuses.contains($0.status) && !$0.isHistorical }
                .map(\.id)
        )
        let recoveredCandidates = Self.recoveredTranscriptSessions(
            at: settings.expandedTranscriptDirectory,
            excludingSessionIDs: activeLocalSessionIDs
        )
        guard !recoveredCandidates.isEmpty else {
            return ([], 0, 0)
        }

        let existingSessionIDs = Set(existingSessions.map(\.id))
        let candidateLookup = Dictionary(uniqueKeysWithValues: recoveredCandidates.map { ($0.id, $0) })
        let unresolvedCandidateIDs = recoveredCandidates
            .map(\.id)
            .filter { !existingSessionIDs.contains($0) }
        guard !unresolvedCandidateIDs.isEmpty else {
            return ([], 0, 0)
        }

        let knownDatabaseSessions: [TerminalMonitorSession]
        do {
            knownDatabaseSessions = try await writer.fetchSessions(sessionIDs: unresolvedCandidateIDs, settings: settings)
        } catch {
            logger.log(
                .warning,
                "Failed to check MongoDB for orphaned transcript session rows: \(error.localizedDescription)",
                category: .monitoring
            )
            return ([], 0, 0)
        }

        let knownDatabaseSessionIDs = Set(knownDatabaseSessions.map(\.id))
        var recoveredSessions: [TerminalMonitorSession] = []
        var importedChunkCount = 0

        for sessionID in unresolvedCandidateIDs where !knownDatabaseSessionIDs.contains(sessionID) {
            guard var recoveredSession = candidateLookup[sessionID] else { continue }

            do {
                let transcriptData = try await Self.readTranscriptDataInBackground(at: recoveredSession.transcriptPath)
                let importedChunks = try await backfillTranscriptFileToMongo(
                    session: recoveredSession,
                    transcriptData: transcriptData,
                    settings: settings,
                    syncSource: "local_transcript_directory_scan"
                )
                let inputSync = try await synchronizeSessionInputCaptureToMongoIfNeeded(
                    session: recoveredSession,
                    settings: settings,
                    syncSource: "local_input_capture_file"
                )
                recoveredSession = inputSync.session
                if !transcriptData.isEmpty {
                    recoveredSession = Self.sessionByBackfillingObservedTranscriptInteractions(
                        fromTranscriptText: String(decoding: transcriptData, as: UTF8.self),
                        source: "local_transcript_file",
                        observedAt: recoveredSession.activityDate,
                        to: recoveredSession
                    )
                }
                recoveredSession = Self.sessionByApplyingMongoTranscriptSyncProgress(
                    source: "local_transcript_directory_scan",
                    chunkCount: importedChunks.count,
                    byteCount: transcriptData.count,
                    synchronizedAt: recoveredSession.activityDate,
                    verifiedComplete: true,
                    to: recoveredSession
                )
                recoveredSession.chunkCount = max(recoveredSession.chunkCount, importedChunks.count)
                recoveredSession.byteCount = max(recoveredSession.byteCount, transcriptData.count)
                recoveredSession.lastPreview = importedChunks.last?.previewText ?? recoveredSession.lastPreview
                recoveredSession.lastDatabaseMessage = Self.transcriptSynchronizationMessage(
                    for: .directoryRecovery,
                    importedChunkCount: importedChunks.count
                )

                try await writer.recordStatus(
                    session: recoveredSession,
                    status: recoveredSession.status,
                    eventType: "session_transcript_recovered",
                    message: recoveredSession.lastDatabaseMessage,
                    eventAt: recoveredSession.activityDate,
                    endedAt: recoveredSession.endedAt,
                    statusReason: recoveredSession.statusReason,
                    exitCode: recoveredSession.exitCode,
                    metadata: [
                        "source": "local_transcript_directory_scan",
                        "recovered_without_database_session": true,
                        "imported_chunks": importedChunks.count,
                        "total_chunks": recoveredSession.chunkCount,
                        "total_bytes": recoveredSession.byteCount,
                        "imported_input_chunks": inputSync.importedChunkCount ?? 0,
                        "total_input_chunks": recoveredSession.inputChunkCount,
                        "total_input_bytes": recoveredSession.inputByteCount
                    ],
                    settings: settings
                )
                recoveredSession = try await recordInputSynchronizationStatusIfNeeded(
                    session: recoveredSession,
                    context: .directoryRecovery,
                    syncSource: "local_input_capture_file",
                    trigger: nil,
                    recoveredWithoutDatabaseSession: true,
                    importedChunkCount: inputSync.importedChunkCount,
                    settings: settings
                )

                recoveredSessions.append(recoveredSession)
                importedChunkCount += importedChunks.count
            } catch {
                logger.log(
                    .warning,
                    "Failed to recover orphaned local transcript into MongoDB: \(error.localizedDescription)",
                    category: .monitoring,
                    details: "\(recoveredSession.profileName) • \(recoveredSession.id.uuidString)"
                )
            }
        }

        return (recoveredSessions, recoveredSessions.count, importedChunkCount)
    }

    private func reconcileRecentSessionTranscriptsToMongoIfNeeded(
        _ sessions: [TerminalMonitorSession],
        settings: MongoMonitoringSettings,
        logger: LaunchLogger
    ) async -> (sessions: [TerminalMonitorSession], synchronizedSessionCount: Int, importedChunkCount: Int) {
        guard settings.enableMongoWrites else {
            return (sessions, 0, 0)
        }

        var reconciledSessions = sessions
        var synchronizedSessionCount = 0
        var importedChunkCount = 0

        for index in reconciledSessions.indices {
            let session = reconciledSessions[index]
            guard session.hasLocalTranscriptFile else { continue }

            do {
                let transcriptSync = try await synchronizeSessionTranscriptToMongoIfNeeded(
                    session: session,
                    settings: settings,
                    syncSource: "local_transcript_file"
                )
                var syncedSession = transcriptSync.session
                guard let importedChunks = transcriptSync.importedChunkCount else {
                    if syncedSession != session {
                        try await writer.recordSessionSnapshot(syncedSession, settings: settings)
                        reconciledSessions[index] = syncedSession
                    }
                    continue
                }
                syncedSession.lastDatabaseMessage = Self.transcriptSynchronizationMessage(
                    for: .recentSessionRefresh,
                    importedChunkCount: importedChunks
                )

                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: "session_transcript_synchronized",
                    message: syncedSession.lastDatabaseMessage,
                    eventAt: syncedSession.activityDate,
                    endedAt: syncedSession.endedAt,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: [
                        "source": "local_transcript_file",
                        "trigger": "recent_session_refresh",
                        "imported_chunks": importedChunks,
                        "total_chunks": syncedSession.chunkCount,
                        "total_bytes": syncedSession.byteCount
                    ],
                    settings: settings
                )

                reconciledSessions[index] = syncedSession
                synchronizedSessionCount += 1
                importedChunkCount += importedChunks
            } catch {
                logger.log(
                    .warning,
                    "Failed to synchronize a recent local transcript into MongoDB during refresh: \(error.localizedDescription)",
                    category: .monitoring,
                    details: "\(session.profileName) • \(session.id.uuidString)"
                )
            }
        }

        return (reconciledSessions, synchronizedSessionCount, importedChunkCount)
    }

    private func reconcileRecentSessionInputCapturesToMongoIfNeeded(
        _ sessions: [TerminalMonitorSession],
        settings: MongoMonitoringSettings,
        logger: LaunchLogger
    ) async -> (sessions: [TerminalMonitorSession], synchronizedSessionCount: Int, importedChunkCount: Int) {
        guard settings.enableMongoWrites else {
            return (sessions, 0, 0)
        }

        var reconciledSessions = sessions
        var synchronizedSessionCount = 0
        var importedChunkCount = 0

        for index in reconciledSessions.indices {
            let session = reconciledSessions[index]
            guard session.hasLocalInputCaptureFile else { continue }

            do {
                let inputSync = try await synchronizeSessionInputCaptureToMongoIfNeeded(
                    session: session,
                    settings: settings,
                    syncSource: "local_input_capture_file"
                )
                var syncedSession = inputSync.session
                guard let importedChunks = inputSync.importedChunkCount else {
                    if syncedSession != session {
                        try await writer.recordSessionSnapshot(syncedSession, settings: settings)
                        reconciledSessions[index] = syncedSession
                    }
                    continue
                }
                syncedSession = try await recordInputSynchronizationStatusIfNeeded(
                    session: syncedSession,
                    context: .recentSessionRefresh,
                    syncSource: "local_input_capture_file",
                    trigger: "recent_session_refresh",
                    recoveredWithoutDatabaseSession: false,
                    importedChunkCount: importedChunks,
                    settings: settings
                )

                reconciledSessions[index] = syncedSession
                synchronizedSessionCount += 1
                importedChunkCount += importedChunks
            } catch {
                logger.log(
                    .warning,
                    "Failed to synchronize a recent local raw input capture into MongoDB during refresh: \(error.localizedDescription)",
                    category: .monitoring,
                    details: "\(session.profileName) • \(session.id.uuidString)"
                )
            }
        }

        return (reconciledSessions, synchronizedSessionCount, importedChunkCount)
    }

    private func backfillMongoTranscriptCoverageIfNeeded(
        _ sessions: [TerminalMonitorSession],
        settings: MongoMonitoringSettings,
        logger: LaunchLogger
    ) async -> (sessions: [TerminalMonitorSession], completedSessionCount: Int) {
        guard settings.enableMongoWrites else {
            return (sessions, 0)
        }

        var updatedSessions = sessions
        var completedSessionCount = 0

        for index in updatedSessions.indices {
            let session = updatedSessions[index]
            guard session.mongoTranscriptSyncState != .complete else { continue }

            do {
                let summary = try await writer.fetchSessionChunkSummary(sessionID: session.id, settings: settings)
                let completedSession = Self.sessionByApplyingMongoTranscriptCompletionFromDatabaseSummaryIfNeeded(
                    summary,
                    to: session
                )
                guard completedSession != session else { continue }

                try await writer.recordSessionSnapshot(completedSession, settings: settings)
                updatedSessions[index] = completedSession
                completedSessionCount += 1
            } catch {
                logger.log(
                    .warning,
                    "Failed to backfill MongoDB transcript coverage for recent session \(session.id.uuidString): \(error.localizedDescription)",
                    category: .monitoring,
                    details: session.profileName
                )
            }
        }

        return (updatedSessions, completedSessionCount)
    }

    private func backfillMongoInputCoverageIfNeeded(
        _ sessions: [TerminalMonitorSession],
        settings: MongoMonitoringSettings,
        logger: LaunchLogger
    ) async -> (sessions: [TerminalMonitorSession], completedSessionCount: Int) {
        guard settings.enableMongoWrites else {
            return (sessions, 0)
        }

        var updatedSessions = sessions
        var completedSessionCount = 0

        for index in updatedSessions.indices {
            let session = updatedSessions[index]
            guard session.mongoInputSyncState != .complete else { continue }

            do {
                let summary = try await writer.fetchSessionInputChunkSummary(sessionID: session.id, settings: settings)
                let completedSession = Self.sessionByApplyingMongoInputSyncCompletionFromDatabaseSummaryIfNeeded(
                    summary,
                    to: session
                )
                guard completedSession != session else { continue }

                try await writer.recordSessionSnapshot(completedSession, settings: settings)
                updatedSessions[index] = completedSession
                completedSessionCount += 1
            } catch {
                logger.log(
                    .warning,
                    "Failed to backfill MongoDB raw input coverage for recent session \(session.id.uuidString): \(error.localizedDescription)",
                    category: .monitoring,
                    details: session.profileName
                )
            }
        }

        return (updatedSessions, completedSessionCount)
    }

    private func synchronizePrunableLocalTranscriptsToMongoIfNeeded(
        settings: MongoMonitoringSettings,
        olderThanDays: Int,
        protectedPaths: Set<String>,
        logger: LaunchLogger
    ) async -> (synchronizedSessionCount: Int, importedChunkCount: Int) {
        guard settings.enableMongoWrites else {
            return (0, 0)
        }

        let activeStatuses: Set<TerminalMonitorStatus> = [.prepared, .launching, .monitoring, .idle]
        let activeLocalSessionIDs = Set(
            sessions
                .filter { activeStatuses.contains($0.status) && !$0.isHistorical }
                .map(\.id)
        )
        let candidates = Self.recoveredTranscriptSessions(
            at: settings.expandedTranscriptDirectory,
            olderThanDays: olderThanDays,
            protectedPaths: protectedPaths,
            excludingSessionIDs: activeLocalSessionIDs
        )
        guard !candidates.isEmpty else {
            return (0, 0)
        }

        let knownDatabaseSessions: [TerminalMonitorSession]
        do {
            knownDatabaseSessions = try await writer.fetchSessions(sessionIDs: candidates.map(\.id), settings: settings)
        } catch {
            logger.log(
                .warning,
                "Failed to check MongoDB before pruning local transcripts: \(error.localizedDescription)",
                category: .monitoring
            )
            return (0, 0)
        }

        let knownDatabaseSessionIDs = Set(knownDatabaseSessions.map(\.id))
        var synchronizedSessionCount = 0
        var importedChunkCount = 0

        for candidate in candidates {
            do {
                let recoveredWithoutSessionRow = !knownDatabaseSessionIDs.contains(candidate.id)
                let transcriptSync = try await synchronizeSessionTranscriptToMongoIfNeeded(
                    session: candidate,
                    settings: settings,
                    syncSource: recoveredWithoutSessionRow ? "local_transcript_directory_scan" : "local_transcript_file"
                )
                let inputSync = try await synchronizeSessionInputCaptureToMongoIfNeeded(
                    session: transcriptSync.session,
                    settings: settings,
                    syncSource: "local_input_capture_file"
                )
                var syncedSession = inputSync.session
                guard let importedChunks = transcriptSync.importedChunkCount else {
                    if syncedSession != candidate {
                        try await writer.recordSessionSnapshot(syncedSession, settings: settings)
                    }
                    continue
                }
                syncedSession.lastDatabaseMessage = Self.transcriptSynchronizationMessage(
                    for: recoveredWithoutSessionRow ? .directoryRecovery : .recentSessionRefresh,
                    importedChunkCount: importedChunks
                )

                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: recoveredWithoutSessionRow ? "session_transcript_recovered" : "session_transcript_synchronized",
                    message: syncedSession.lastDatabaseMessage,
                    eventAt: syncedSession.activityDate,
                    endedAt: syncedSession.endedAt,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: [
                        "source": recoveredWithoutSessionRow ? "local_transcript_directory_scan" : "local_transcript_file",
                        "trigger": "local_retention_prune",
                        "recovered_without_database_session": recoveredWithoutSessionRow,
                        "imported_chunks": importedChunks,
                        "total_chunks": syncedSession.chunkCount,
                        "total_bytes": syncedSession.byteCount,
                        "imported_input_chunks": inputSync.importedChunkCount ?? 0,
                        "total_input_chunks": syncedSession.inputChunkCount,
                        "total_input_bytes": syncedSession.inputByteCount
                    ],
                    settings: settings
                )
                syncedSession = try await recordInputSynchronizationStatusIfNeeded(
                    session: syncedSession,
                    context: recoveredWithoutSessionRow ? .directoryRecovery : .recentSessionRefresh,
                    syncSource: "local_input_capture_file",
                    trigger: "local_retention_prune",
                    recoveredWithoutDatabaseSession: recoveredWithoutSessionRow,
                    importedChunkCount: inputSync.importedChunkCount,
                    settings: settings
                )

                synchronizedSessionCount += 1
                importedChunkCount += importedChunks
            } catch {
                logger.log(
                    .warning,
                    "Failed to synchronize a prunable local transcript into MongoDB: \(error.localizedDescription)",
                    category: .monitoring,
                    details: "\(candidate.profileName) • \(candidate.id.uuidString)"
                )
            }
        }

        return (synchronizedSessionCount, importedChunkCount)
    }

    func ensureSessionVisible(sessionID: UUID, settings: AppSettings, logger: LaunchLogger, resetFilters: Bool = false) {
        ensureSessionsVisible(sessionIDs: [sessionID], settings: settings, logger: logger, resetFilters: resetFilters)
    }

    func ensureSessionsVisible(sessionIDs: [UUID], settings: AppSettings, logger: LaunchLogger, resetFilters: Bool = false) {
        let uniqueSessionIDs = Array(NSOrderedSet(array: sessionIDs)) as? [UUID] ?? sessionIDs
        guard let focusedSessionID = uniqueSessionIDs.first else {
            return
        }
        noteSessionForInspection(focusedSessionID, resetFilters: resetFilters)

        let missingSessionIDs = uniqueSessionIDs.filter { sessionIndex(for: $0) == nil }
        if missingSessionIDs.isEmpty {
            return
        }
        guard settings.mongoMonitoring.enabled, settings.mongoMonitoring.enableMongoWrites else {
            setDatabaseStatusIfChanged("Linked session history is unavailable without MongoDB.")
            logger.log(.warning, "Cannot load linked monitored sessions because MongoDB history is disabled.", category: .monitoring, details: uniqueSessionIDs.map(\.uuidString).joined(separator: ", "))
            return
        }

        Task {
            do {
                let fetchedSessions = try await writer.fetchSessions(sessionIDs: missingSessionIDs, settings: settings.mongoMonitoring)
                let transcriptCoverageBackfill = await backfillMongoTranscriptCoverageIfNeeded(
                    fetchedSessions,
                    settings: settings.mongoMonitoring,
                    logger: logger
                )
                let inputCoverageBackfill = await backfillMongoInputCoverageIfNeeded(
                    transcriptCoverageBackfill.sessions,
                    settings: settings.mongoMonitoring,
                    logger: logger
                )
                let fetchedSessionIDs = Set(fetchedSessions.map(\.id))
                let missingFromDatabase = missingSessionIDs.filter { !fetchedSessionIDs.contains($0) }

                await MainActor.run {
                    self.presentHistoricalSessions(inputCoverageBackfill.sessions, focusedSessionID: focusedSessionID)
                    self.setLastConnectionCheckIfChanged(Date().formatted(date: .abbreviated, time: .standard))
                    if fetchedSessions.isEmpty {
                        self.setDatabaseStatusIfChanged("Linked monitored sessions were not found.")
                        logger.log(.warning, "Linked monitored sessions could not be found in MongoDB.", category: .monitoring, details: missingSessionIDs.map(\.uuidString).joined(separator: ", "))
                    } else {
                        let sessionLoadSummary = inputCoverageBackfill.sessions.count == 1
                            ? "Loaded linked monitored session."
                            : "Loaded \(inputCoverageBackfill.sessions.count) linked monitored sessions."
                        let transcriptCoverageSummary = transcriptCoverageBackfill.completedSessionCount > 0
                            ? "Marked \(transcriptCoverageBackfill.completedSessionCount) transcript-complete."
                            : nil
                        let inputCoverageSummary = inputCoverageBackfill.completedSessionCount > 0
                            ? "Marked \(inputCoverageBackfill.completedSessionCount) input-complete."
                            : nil
                        self.setDatabaseStatusIfChanged(
                            [String(sessionLoadSummary.dropLast()), transcriptCoverageSummary, inputCoverageSummary]
                                .compactMap(\.self)
                                .joined(separator: " ")
                        )
                        let fetchedDetails = inputCoverageBackfill.sessions.map(\.id.uuidString).joined(separator: ", ")
                        let missingDetails = missingFromDatabase.isEmpty ? nil : "Missing: " + missingFromDatabase.map(\.uuidString).joined(separator: ", ")
                        let transcriptCoverageDetails = transcriptCoverageBackfill.completedSessionCount > 0
                            ? "transcript_complete=\(transcriptCoverageBackfill.completedSessionCount)"
                            : nil
                        let inputCoverageDetails = inputCoverageBackfill.completedSessionCount > 0
                            ? "input_complete=\(inputCoverageBackfill.completedSessionCount)"
                            : nil
                        logger.log(.success, "Loaded linked monitored session set from MongoDB.", category: .monitoring, details: [fetchedDetails, missingDetails, transcriptCoverageDetails, inputCoverageDetails].compactMap(\.self).joined(separator: " | "))
                    }
                }
            } catch {
                await MainActor.run {
                    self.setDatabaseStatusIfChanged("Linked monitored session lookup failed")
                    logger.log(.error, "Failed to load linked monitored sessions from MongoDB: \(error.localizedDescription)", category: .monitoring, details: uniqueSessionIDs.map(\.uuidString).joined(separator: ", "))
                }
            }
        }
    }

    func refreshStorageSummary(settings: AppSettings, logger: LaunchLogger, force: Bool = false) {
        let refreshStartedAt = CFAbsoluteTimeGetCurrent()
        guard settings.mongoMonitoring.enabled else {
            setStorageSummaryIfChanged(nil)
            setStorageSummaryStatusIfChanged("")
            setIsLoadingStorageSummaryIfChanged(false)
            return
        }
        let now = Date()
        if !force {
            if isLoadingStorageSummary {
                return
            }
            if let lastRefresh = lastStorageSummaryRefreshAt,
               now.timeIntervalSince(lastRefresh) < minimumStorageSummaryRefreshInterval {
                return
            }
        }

        setIsLoadingStorageSummaryIfChanged(true)
        let monitoringSettings = settings.mongoMonitoring

        Task { [weak self] in
            guard let self else { return }

            var summary = await Self.scanTranscriptDirectoryInBackground(at: monitoringSettings.expandedTranscriptDirectory)
            var notes: [String] = []

            if monitoringSettings.enableMongoWrites {
                do {
                    let databaseSummary = try await writer.fetchStorageSummary(settings: monitoringSettings)
                    summary.sessionCount = databaseSummary.sessionCount
                    summary.activeSessionCount = databaseSummary.activeSessionCount
                    summary.completedSessionCount = databaseSummary.completedSessionCount
                    summary.failedSessionCount = databaseSummary.failedSessionCount
                    summary.transcriptCompleteSessionCount = databaseSummary.transcriptCompleteSessionCount
                    summary.transcriptStreamingSessionCount = databaseSummary.transcriptStreamingSessionCount
                    summary.transcriptCoverageUnknownSessionCount = databaseSummary.transcriptCoverageUnknownSessionCount
                    summary.inputCompleteSessionCount = databaseSummary.inputCompleteSessionCount
                    summary.inputStreamingSessionCount = databaseSummary.inputStreamingSessionCount
                    summary.inputCoverageUnknownSessionCount = databaseSummary.inputCoverageUnknownSessionCount
                    summary.chunkCount = databaseSummary.chunkCount
                    summary.inputChunkCount = databaseSummary.inputChunkCount
                    summary.eventCount = databaseSummary.eventCount
                    summary.logicalTranscriptBytes = databaseSummary.logicalTranscriptBytes
                    summary.logicalInputBytes = databaseSummary.logicalInputBytes
                    summary.sessionTableBytes = databaseSummary.sessionTableBytes
                    summary.chunkTableBytes = databaseSummary.chunkTableBytes
                    summary.inputChunkTableBytes = databaseSummary.inputChunkTableBytes
                    summary.eventTableBytes = databaseSummary.eventTableBytes
                    summary.oldestSessionAt = databaseSummary.oldestSessionAt
                    summary.newestSessionAt = databaseSummary.newestSessionAt
                    notes.append("Loaded MongoDB storage totals.")
                    notes.append(
                        "Mongo stored \(databaseSummary.chunkCount) transcript chunk(s) and \(databaseSummary.inputChunkCount) raw input chunk(s)."
                    )
                    notes.append(
                        "Known stored bytes: \(ByteCountFormatter.string(fromByteCount: summary.totalKnownBytes, countStyle: .file)) total (\(ByteCountFormatter.string(fromByteCount: summary.logicalDatabaseBytes, countStyle: .file)) logical MongoDB data plus local capture files)."
                    )
                    if summary.hasPhysicalDatabaseBreakdown {
                        notes.append(
                            "Mongo physical storage: sessions \(ByteCountFormatter.string(fromByteCount: summary.sessionTableBytes, countStyle: .file)), transcript chunks \(ByteCountFormatter.string(fromByteCount: summary.chunkTableBytes, countStyle: .file)), raw input chunks \(ByteCountFormatter.string(fromByteCount: summary.inputChunkTableBytes, countStyle: .file)), events \(ByteCountFormatter.string(fromByteCount: summary.eventTableBytes, countStyle: .file))."
                        )
                    }
                    notes.append(
                        "Mongo transcript coverage: \(databaseSummary.transcriptCompleteSessionCount) complete, \(databaseSummary.transcriptStreamingSessionCount) streaming, \(databaseSummary.transcriptCoverageUnknownSessionCount) unknown."
                    )
                    notes.append(
                        "Mongo raw input coverage: \(databaseSummary.inputCompleteSessionCount) complete, \(databaseSummary.inputStreamingSessionCount) streaming, \(databaseSummary.inputCoverageUnknownSessionCount) unknown."
                    )
                } catch {
                    notes.append("MongoDB storage summary failed: \(error.localizedDescription)")
                    logger.log(.warning, "Failed to load MongoDB storage summary: \(error.localizedDescription)", category: .monitoring)
                }
            } else {
                notes.append("MongoDB writes are disabled; showing local transcript and raw input storage only.")
            }

            if summary.transcriptFileCount > 0 || summary.inputCaptureFileCount > 0 {
                notes.append(
                    "Scanned \(summary.transcriptFileCount) local transcript file(s) and \(summary.inputCaptureFileCount) local raw input capture(s)."
                )
            } else {
                notes.append("No local transcript or raw input capture files were found.")
            }

            await MainActor.run {
                self.setStorageSummaryIfChanged(summary)
                self.setStorageSummaryStatusIfChanged(notes.joined(separator: " "))
                self.setIsLoadingStorageSummaryIfChanged(false)
                self.lastStorageSummaryRefreshAt = now
                self.logMonitoringTiming(
                    "refreshStorageSummary",
                    startedAt: refreshStartedAt,
                    logger: logger,
                    details: "sessions=\(summary.sessionCount) • transcript_files=\(summary.transcriptFileCount) • input_files=\(summary.inputCaptureFileCount) • db_chunks=\(summary.chunkCount) • db_input_chunks=\(summary.inputChunkCount)"
                )
            }
        }
    }

    func clearStoredHistory(settings: AppSettings, logger: LaunchLogger) {
        guard settings.mongoMonitoring.enabled else {
            lastPruneSummary = "Monitoring is disabled."
            return
        }
        guard !isPruningStoredHistory else { return }

        isPruningStoredHistory = true
        let monitoringSettings = settings.mongoMonitoring

        Task { [weak self] in
            guard let self else { return }

            var notes: [String] = []
            var databaseClearSucceeded = !monitoringSettings.enableMongoWrites
            if monitoringSettings.enableMongoWrites {
                do {
                    let clearSummary = try await writer.clearAllHistory(settings: monitoringSettings)
                    databaseClearSucceeded = true
                    notes.append(
                        "Cleared MongoDB history: \(clearSummary.deletedSessions) session row(s), \(clearSummary.deletedChunks) transcript chunk(s), \(clearSummary.deletedInputChunks) raw input chunk(s), and \(clearSummary.deletedEvents) event row(s)."
                    )
                } catch {
                    notes.append("MongoDB clear failed: \(error.localizedDescription)")
                    logger.log(.error, "Failed to clear MongoDB history: \(error.localizedDescription)", category: .monitoring)
                }
            }

            if Self.shouldDeleteLocalCaptureFilesAfterClear(
                enableMongoWrites: monitoringSettings.enableMongoWrites,
                databaseClearSucceeded: databaseClearSucceeded
            ) {
                let localPrune = Self.pruneTranscriptDirectory(
                    at: monitoringSettings.expandedTranscriptDirectory,
                    olderThanDays: 0,
                    protectedPaths: []
                )
                notes.append(
                    "Cleared all local transcript files: \(localPrune.deletedTranscriptFileCount) files. Cleared all local raw input captures: \(localPrune.deletedInputCaptureFileCount) files."
                )
            } else {
                notes.append("Retained local transcript and raw input capture files because MongoDB clear did not complete successfully.")
            }

            let logLevel: LogLevel = notes.contains { $0.localizedCaseInsensitiveContains("failed") } ? .warning : .success

            await MainActor.run {
                self.isPruningStoredHistory = false
                self.refreshRecentSessions(settings: settings, logger: logger, force: true)
                self.refreshStorageSummary(settings: settings, logger: logger, force: true)
                logger.log(logLevel, notes.joined(separator: " "), category: .monitoring)
            }
        }
    }

    func pruneStoredHistory(settings: AppSettings, logger: LaunchLogger) {
        guard settings.mongoMonitoring.enabled else {
            lastPruneSummary = "Monitoring is disabled."
            return
        }
        guard !isPruningStoredHistory else { return }

        isPruningStoredHistory = true
        let monitoringSettings = settings.mongoMonitoring
        let databaseRetentionDays = monitoringSettings.clampedDatabaseRetentionDays
        let localRetentionDays = monitoringSettings.clampedLocalTranscriptRetentionDays

        Task { [weak self] in
            guard let self else { return }

            var pruneSummary = MongoPruneSummary(
                cutoffDate: Date().addingTimeInterval(-TimeInterval(databaseRetentionDays) * 86_400)
            )
            var notes: [String] = []
            var databasePruneSucceeded = !monitoringSettings.enableMongoWrites
            let protectedPaths = protectedTranscriptPaths()

            if monitoringSettings.enableMongoWrites {
                do {
                    pruneSummary = try await writer.pruneCompletedHistory(
                        settings: monitoringSettings,
                        retentionDays: databaseRetentionDays
                    )
                    databasePruneSucceeded = true
                    notes.append("Deleted \(pruneSummary.deletedSessions) MongoDB session row(s).")
                } catch {
                    notes.append("MongoDB prune failed: \(error.localizedDescription)")
                    logger.log(.error, "Failed to prune MongoDB monitor history: \(error.localizedDescription)", category: .monitoring)
                }
            } else {
                pruneSummary.cutoffDate = Date().addingTimeInterval(-TimeInterval(localRetentionDays) * 86_400)
                notes.append("MongoDB writes are disabled; pruning local transcript and raw input capture files only.")
            }

            if monitoringSettings.enableMongoWrites && databasePruneSucceeded {
                let transcriptSync = await synchronizePrunableLocalTranscriptsToMongoIfNeeded(
                    settings: monitoringSettings,
                    olderThanDays: localRetentionDays,
                    protectedPaths: protectedPaths,
                    logger: logger
                )
                if transcriptSync.synchronizedSessionCount > 0 {
                    notes.append(
                        "Synchronized \(transcriptSync.synchronizedSessionCount) prunable local transcript(s) into MongoDB (\(transcriptSync.importedChunkCount) chunk(s)) before deletion."
                    )
                }
            }

            if !monitoringSettings.enableMongoWrites || databasePruneSucceeded {
                let localPrune = Self.pruneTranscriptDirectory(
                    at: monitoringSettings.expandedTranscriptDirectory,
                    olderThanDays: localRetentionDays,
                    protectedPaths: protectedPaths
                )
                pruneSummary.deletedTranscriptFiles = localPrune.deletedTranscriptFileCount
                pruneSummary.deletedTranscriptBytes = localPrune.deletedTranscriptBytes
                pruneSummary.deletedInputCaptureFiles = localPrune.deletedInputCaptureFileCount
                pruneSummary.deletedInputCaptureBytes = localPrune.deletedInputCaptureBytes
                if localPrune.deletedTranscriptFileCount > 0 || localPrune.deletedInputCaptureFileCount > 0 {
                    notes.append(
                        "Deleted \(localPrune.deletedTranscriptFileCount) local transcript file(s) and \(localPrune.deletedInputCaptureFileCount) local raw input capture(s)."
                    )
                } else {
                    notes.append("No local transcript or raw input capture files matched the retention cutoff.")
                }
            } else {
                notes.append("Retained local transcript and raw input capture files because MongoDB prune did not complete successfully.")
            }

            let logLevel: LogLevel = notes.contains { $0.localizedCaseInsensitiveContains("failed") } ? .warning : .success

            await MainActor.run {
                self.lastPruneResult = pruneSummary
                self.lastPruneSummary = Self.describe(pruneSummary: pruneSummary)
                self.setDatabaseStatusIfChanged(
                    monitoringSettings.enableMongoWrites
                        ? "Stored monitoring history pruned."
                        : "Local capture history pruned."
                )
                self.isPruningStoredHistory = false
                if monitoringSettings.enableMongoWrites {
                    self.refreshRecentSessions(settings: settings, logger: logger, force: true)
                }
                self.refreshStorageSummary(settings: settings, logger: logger, force: true)
                logger.log(logLevel, notes.joined(separator: " "), category: .monitoring)
            }
        }
    }

    func performBackup(settings: AppSettings, logger: LaunchLogger) {
        guard settings.mongoMonitoring.enabled, settings.mongoMonitoring.enableMongoWrites else {
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Select Backup Destination"
        savePanel.nameFieldStringValue = "clilauncher-backup-\(Date().formatted(date: .numeric, time: .omitted))"
        savePanel.canCreateDirectories = true

        savePanel.begin { [weak self] response in
            guard let self, response == .OK, let url = savePanel.directoryURL else { return }
            
            Task {
                do {
                    let backupURL = try await self.backupService.performBackup(settings: settings.mongoMonitoring, destinationFolder: url)
                    await MainActor.run {
                        logger.log(.success, "Backup completed successfully at: \(backupURL.path)", category: .monitoring)
                    }
                } catch {
                    await MainActor.run {
                        logger.log(.error, "Backup failed: \(error.localizedDescription)", category: .monitoring)
                    }
                }
            }
        }
    }

    func details(for sessionID: UUID) -> TerminalMonitorSessionDetails? {
        sessionDetailsByID[sessionID]
    }

    func isLoadingDetails(for sessionID: UUID) -> Bool {
        detailLoadingSessionIDs.contains(sessionID)
    }

    func loadDetails(
        for session: TerminalMonitorSession,
        settings: AppSettings,
        logger: LaunchLogger,
        forceRefresh: Bool = false,
        workload: MonitorDetailLoadWorkload = .history
    ) {
        let detailLoadStartedAt = CFAbsoluteTimeGetCurrent()
        let now = Date()
        let mergedRequestedWorkload = requestedDetailWorkloadsByID[session.id]?.merged(with: workload) ?? workload
        requestedDetailWorkloadsByID[session.id] = mergedRequestedWorkload

        if detailLoadingSessionIDs.contains(session.id) {
            return
        }

        if !forceRefresh,
           mergedRequestedWorkload == .summary,
           let nextRefresh = nextDetailRefreshAt[session.id],
           nextRefresh > now {
            return
        }

        if !forceRefresh,
           let cached = sessionDetailsByID[session.id],
           cached.matches(session),
           cached.satisfies(mergedRequestedWorkload) {
            nextDetailRefreshAt[session.id] = now.addingTimeInterval(minimumDetailRefreshInterval)
            return
        }

        if !forceRefresh {
            nextDetailRefreshAt[session.id] = now.addingTimeInterval(minimumDetailRefreshInterval)
        }

        insertDetailLoadingSessionIDIfNeeded(session.id)
        activeDetailWorkloadsByID[session.id] = mergedRequestedWorkload

        Task { [weak self] in
            guard let self else { return }

            var transcriptText = ""
            var transcriptSource = ""
            var transcriptTruncated = false
            var events: [TerminalSessionEvent] = []
            var chunks: [TerminalTranscriptChunk] = []
            var inputChunks: [TerminalInputChunk] = []
            var loadNotes: [String] = []
            var resolvedSession = session
            var shouldPersistObservedInteractionBackfill = false
            var shouldPersistChunkSourceBackfill = false
            var shouldPersistSessionSnapshot = false
            var localTranscriptData: Data?
            var localInputCaptureChunks: [TerminalInputChunk] = []
            let effectiveWorkload = self.requestedDetailWorkloadsByID[session.id]?.merged(with: mergedRequestedWorkload) ?? mergedRequestedWorkload

            let localArtifacts = await Self.loadLocalDetailArtifacts(
                for: session,
                settings: settings.mongoMonitoring,
                includesHistory: effectiveWorkload.includesHistory
            )
            transcriptText = localArtifacts.transcriptText
            transcriptSource = localArtifacts.transcriptSource
            transcriptTruncated = localArtifacts.transcriptTruncated
            loadNotes.append(contentsOf: localArtifacts.loadNotes)
            localInputCaptureChunks = localArtifacts.inputChunks

            if effectiveWorkload.includesHistory,
               settings.mongoMonitoring.enabled,
               settings.mongoMonitoring.enableMongoWrites {
                do {
                    async let fetchedEvents = writer.fetchSessionEvents(
                        sessionID: session.id,
                        settings: settings.mongoMonitoring,
                        limit: settings.mongoMonitoring.clampedDetailEventLimit
                    )
                    async let fetchedChunkSummary = writer.fetchSessionChunkSummary(
                        sessionID: session.id,
                        settings: settings.mongoMonitoring
                    )
                    async let fetchedInputChunkSummary = writer.fetchSessionInputChunkSummary(
                        sessionID: session.id,
                        settings: settings.mongoMonitoring
                    )
                    async let fetchedChunks = writer.fetchSessionChunks(
                        sessionID: session.id,
                        settings: settings.mongoMonitoring,
                        limit: settings.mongoMonitoring.clampedDetailChunkLimit
                    )
                    async let fetchedInputChunks = writer.fetchSessionInputChunks(
                        sessionID: session.id,
                        settings: settings.mongoMonitoring,
                        limit: settings.mongoMonitoring.clampedDetailChunkLimit
                    )
                    events = try await fetchedEvents
                    let existingChunkSummary = try await fetchedChunkSummary
                    let existingInputChunkSummary = try await fetchedInputChunkSummary
                    chunks = try await fetchedChunks
                    inputChunks = try await fetchedInputChunks
                    loadNotes.append("Loaded \(events.count) event(s), \(chunks.count) transcript chunk(s), and \(inputChunks.count) stdin chunk(s) from MongoDB.")

                    if session.hasLocalTranscriptFile {
                        do {
                            localTranscriptData = try await Self.readTranscriptDataInBackground(at: session.transcriptPath)
                            if let localTranscriptData,
                               Self.shouldBackfillTranscriptToMongo(
                                localChunkCount: Self.transcriptDataChunks(localTranscriptData, byteLimit: Self.transcriptChunkByteLimit).count,
                                localByteCount: localTranscriptData.count,
                                databaseSummary: existingChunkSummary
                               ) {
                                let importedChunks = try await backfillTranscriptFileToMongo(
                                    session: resolvedSession,
                                    transcriptData: localTranscriptData,
                                    settings: settings.mongoMonitoring,
                                    syncSource: "local_transcript_file"
                                )
                                resolvedSession = Self.sessionByApplyingMongoTranscriptSyncProgress(
                                    source: "local_transcript_file",
                                    chunkCount: importedChunks.count,
                                    byteCount: localTranscriptData.count,
                                    synchronizedAt: Date(),
                                    verifiedComplete: true,
                                    to: resolvedSession
                                )
                                shouldPersistSessionSnapshot = true
                                loadNotes.append("Backfilled \(importedChunks.count) transcript chunk(s) from the local transcript file into MongoDB.")
                                if !importedChunks.isEmpty {
                                    let visibleImportedChunks = Array(importedChunks.suffix(settings.mongoMonitoring.clampedDetailChunkLimit))
                                    if chunks.isEmpty || chunks.count < visibleImportedChunks.count {
                                        chunks = visibleImportedChunks
                                    }
                                }
                            }
                        } catch {
                            loadNotes.append("Local transcript database backfill failed: \(error.localizedDescription)")
                            logger.log(.warning, "Failed to backfill local transcript file into MongoDB for \(session.profileName): \(error.localizedDescription)", category: .monitoring)
                        }
                    }

                    if !localInputCaptureChunks.isEmpty {
                        do {
                            let inputSync = try await synchronizeSessionInputCaptureToMongoIfNeeded(
                                session: resolvedSession,
                                settings: settings.mongoMonitoring,
                                syncSource: "local_input_capture_file"
                            )
                            resolvedSession = inputSync.session
                            if let importedInputChunkCount = inputSync.importedChunkCount {
                                shouldPersistSessionSnapshot = true
                                loadNotes.append("Backfilled \(importedInputChunkCount) stdin chunk(s) from the local raw stdin capture into MongoDB.")
                            }
                        } catch {
                            loadNotes.append("Local stdin database backfill failed: \(error.localizedDescription)")
                            logger.log(.warning, "Failed to backfill local stdin capture into MongoDB for \(session.profileName): \(error.localizedDescription)", category: .monitoring)
                        }
                    }

                    let inputCompletedSession = Self.sessionByApplyingMongoInputSyncCompletionFromDatabaseSummaryIfNeeded(
                        existingInputChunkSummary,
                        to: resolvedSession
                    )
                    if inputCompletedSession != resolvedSession {
                        resolvedSession = inputCompletedSession
                        shouldPersistSessionSnapshot = true
                        loadNotes.append("Marked raw stdin capture as verified in MongoDB from stored chunk coverage.")
                    }

                    let completedSession = Self.sessionByApplyingMongoTranscriptCompletionFromDatabaseSummaryIfNeeded(
                        existingChunkSummary,
                        to: resolvedSession
                    )
                    if completedSession != resolvedSession {
                        resolvedSession = completedSession
                        shouldPersistSessionSnapshot = true
                        loadNotes.append("Marked session transcript as verified in MongoDB from stored chunk coverage.")
                    }

                    let normalizedChunks = Self.normalizedTranscriptChunks(chunks, captureMode: resolvedSession.captureMode)
                    if normalizedChunks != chunks {
                        chunks = normalizedChunks
                        shouldPersistChunkSourceBackfill = true
                        loadNotes.append("Backfilled legacy transcript chunk source labels from session capture mode.")
                    }

                    if transcriptText.isEmpty, !chunks.isEmpty {
                        transcriptText = chunks.map(\.text).joined()
                        transcriptTruncated = resolvedSession.chunkCount > chunks.count
                        transcriptSource = Self.mongoTranscriptSourceDescription(
                            for: chunks,
                            truncated: transcriptTruncated
                        )
                    }

                    let eventBackfilledSession = Self.sessionByBackfillingObservedTranscriptInteractions(from: events, to: resolvedSession)
                    if eventBackfilledSession != resolvedSession {
                        resolvedSession = eventBackfilledSession
                        shouldPersistObservedInteractionBackfill = true
                        loadNotes.append("Backfilled observed input summary from MongoDB event history.")
                    } else if Self.needsObservedInteractionBackfill(resolvedSession) {
                        var chunkBackfillSource = chunks
                        var scannedFullChunkHistory = Self.observedInteractionChunkBackfillIsComplete(
                            scannedChunkCount: chunkBackfillSource.count,
                            sessionChunkCount: resolvedSession.chunkCount
                        )

                        if !scannedFullChunkHistory && resolvedSession.chunkCount > chunkBackfillSource.count {
                            let backfillLimit = Self.observedInteractionChunkBackfillLimit(for: resolvedSession.chunkCount)
                            if backfillLimit > chunkBackfillSource.count {
                                do {
                                    let backfillChunks = try await writer.fetchSessionChunksForObservedInteractionBackfill(
                                        sessionID: session.id,
                                        settings: settings.mongoMonitoring,
                                        limit: backfillLimit
                                    )
                                    let normalizedBackfillChunks = Self.normalizedTranscriptChunks(
                                        backfillChunks,
                                        captureMode: resolvedSession.captureMode
                                    )
                                    if normalizedBackfillChunks != backfillChunks {
                                        shouldPersistChunkSourceBackfill = true
                                    }
                                    chunkBackfillSource = normalizedBackfillChunks
                                    scannedFullChunkHistory = Self.observedInteractionChunkBackfillIsComplete(
                                        scannedChunkCount: chunkBackfillSource.count,
                                        sessionChunkCount: resolvedSession.chunkCount
                                    )
                                    loadNotes.append("Scanned \(chunkBackfillSource.count) MongoDB chunk(s) for observed input backfill.")
                                } catch {
                                    loadNotes.append("Expanded MongoDB chunk scan for observed input backfill failed: \(error.localizedDescription)")
                                    logger.log(.warning, "Failed to expand chunk scan for observed input backfill in \(session.profileName): \(error.localizedDescription)", category: .monitoring)
                                }
                            }
                        }

                        let chunkBackfilledSession = Self.sessionByBackfillingObservedTranscriptInteractions(from: chunkBackfillSource, to: resolvedSession)
                        if chunkBackfilledSession != resolvedSession {
                            resolvedSession = chunkBackfilledSession
                            if scannedFullChunkHistory {
                                shouldPersistObservedInteractionBackfill = true
                                loadNotes.append("Backfilled observed input summary from full MongoDB transcript chunk history.")
                            } else {
                                loadNotes.append("Reconstructed observed inputs from the latest \(chunkBackfillSource.count) MongoDB transcript chunk(s); summary was not persisted because the full chunk history was not scanned.")
                            }
                        }
                    }
                } catch {
                    loadNotes.append("MongoDB detail fetch failed: \(error.localizedDescription)")
                    logger.log(.warning, "Failed to load detailed monitor data for \(session.profileName): \(error.localizedDescription)", category: .monitoring)
                }
            } else if effectiveWorkload.includesHistory && (session.isHistorical || !session.hasLocalTranscriptFile) {
                loadNotes.append("MongoDB detail loading is unavailable in the current settings.")
            }

            if effectiveWorkload.includesHistory, inputChunks.isEmpty, !localInputCaptureChunks.isEmpty {
                inputChunks = Array(localInputCaptureChunks.suffix(settings.mongoMonitoring.clampedDetailChunkLimit))
                loadNotes.append("Loaded \(inputChunks.count) stdin chunk(s) from the local raw stdin capture.")
            }

            if Self.needsObservedInteractionBackfill(resolvedSession),
               !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let transcriptSourceKey = transcriptTruncated ? "local_transcript_preview" : "local_transcript_file"
                let transcriptBackfilledSession = Self.sessionByBackfillingObservedTranscriptInteractions(
                    fromTranscriptText: transcriptText,
                    source: transcriptSourceKey,
                    observedAt: resolvedSession.activityDate,
                    to: resolvedSession
                )
                if transcriptBackfilledSession != resolvedSession {
                    resolvedSession = transcriptBackfilledSession
                    if transcriptTruncated {
                        loadNotes.append("Reconstructed observed inputs from the latest local transcript preview; summary was not persisted because the local transcript was truncated.")
                    } else {
                        if settings.mongoMonitoring.enabled, settings.mongoMonitoring.enableMongoWrites {
                            shouldPersistObservedInteractionBackfill = true
                        }
                        loadNotes.append("Backfilled observed input summary from the full local transcript file.")
                    }
                }
            }

            if transcriptSource.isEmpty {
                transcriptSource = transcriptText.isEmpty
                    ? "No transcript content is currently available for this session."
                    : "Transcript loaded."
            }

            if !effectiveWorkload.includesHistory {
                loadNotes.append("Session summary loaded. Expand a history section or reload details to fetch full MongoDB-backed history.")
            }

            if effectiveWorkload.includesHistory,
               shouldPersistObservedInteractionBackfill,
               settings.mongoMonitoring.enabled,
               settings.mongoMonitoring.enableMongoWrites {
                do {
                    try await writer.recordObservedInteractionSummary(resolvedSession, settings: settings.mongoMonitoring)
                } catch {
                    loadNotes.append("Observed input summary backfill sync failed: \(error.localizedDescription)")
                    logger.log(.warning, "Failed to persist observed input summary backfill for \(resolvedSession.profileName): \(error.localizedDescription)", category: .monitoring)
                }
            }

            if effectiveWorkload.includesHistory,
               shouldPersistChunkSourceBackfill,
               settings.mongoMonitoring.enabled,
               settings.mongoMonitoring.enableMongoWrites {
                do {
                    try await writer.recordChunkSourceBackfill(
                        sessionID: resolvedSession.id,
                        normalizedSource: Self.normalizedLegacyTranscriptChunkSource(for: resolvedSession.captureMode),
                        settings: settings.mongoMonitoring
                    )
                } catch {
                    loadNotes.append("Transcript chunk source backfill sync failed: \(error.localizedDescription)")
                    logger.log(.warning, "Failed to persist transcript chunk source backfill for \(resolvedSession.profileName): \(error.localizedDescription)", category: .monitoring)
                }
            }

            if effectiveWorkload.includesHistory,
               shouldPersistSessionSnapshot,
               settings.mongoMonitoring.enabled,
               settings.mongoMonitoring.enableMongoWrites {
                do {
                    try await writer.recordSessionSnapshot(resolvedSession, settings: settings.mongoMonitoring)
                } catch {
                    loadNotes.append("Mongo transcript coverage snapshot sync failed: \(error.localizedDescription)")
                    logger.log(.warning, "Failed to persist Mongo transcript coverage snapshot for \(resolvedSession.profileName): \(error.localizedDescription)", category: .monitoring)
                }
            }

            let details = TerminalMonitorSessionDetails(
                sessionID: resolvedSession.id,
                loadedAt: Date(),
                workload: effectiveWorkload,
                sessionStatus: resolvedSession.status,
                sessionChunkCount: resolvedSession.chunkCount,
                sessionByteCount: resolvedSession.byteCount,
                sessionInputChunkCount: resolvedSession.inputChunkCount,
                sessionInputByteCount: resolvedSession.inputByteCount,
                sessionEndedAt: resolvedSession.endedAt,
                transcriptText: transcriptText,
                transcriptSourceDescription: transcriptSource,
                transcriptTruncated: transcriptTruncated,
                events: events,
                chunks: chunks,
                inputChunks: inputChunks,
                eventsTruncated: events.count >= settings.mongoMonitoring.clampedDetailEventLimit,
                chunksTruncated: resolvedSession.chunkCount > chunks.count,
                inputChunksTruncated: resolvedSession.inputChunkCount > inputChunks.count,
                loadSummary: loadNotes.isEmpty ? "Session details loaded." : loadNotes.joined(separator: " ")
            )

            await MainActor.run {
                self.upsert(resolvedSession)
                self.replaceSessionDetailsIfChanged(details)
                self.removeDetailLoadingSessionIDIfPresent(resolvedSession.id)
                self.activeDetailWorkloadsByID.removeValue(forKey: resolvedSession.id)
                self.logMonitoringTiming(
                    "loadDetails",
                    startedAt: detailLoadStartedAt,
                    logger: logger,
                    details: "session_id=\(resolvedSession.id.uuidString) • workload=\(effectiveWorkload.rawValue) • history_loaded=\(details.historyLoaded) • transcript_chars=\(transcriptText.count) • events=\(events.count) • chunks=\(chunks.count) • input_chunks=\(inputChunks.count)"
                )

                let latestRequestedWorkload = self.requestedDetailWorkloadsByID[resolvedSession.id] ?? details.workload
                if latestRequestedWorkload.includesHistory && !details.historyLoaded {
                    self.loadDetails(
                        for: resolvedSession,
                        settings: settings,
                        logger: logger,
                        forceRefresh: true,
                        workload: .history
                    )
                    return
                }

                self.requestedDetailWorkloadsByID[resolvedSession.id] = details.workload
            }
        }
    }

    private func buildPreparedContext(item: PlannedLaunchItem, profile: LaunchProfile, settings: MongoMonitoringSettings) throws -> PreparedMonitoringContext {
        let transcriptDirectory = settings.expandedTranscriptDirectory
        try FileManager.default.createDirectory(atPath: transcriptDirectory, withIntermediateDirectories: true, attributes: nil)

        let sessionID = UUID()
        let timestamp = Self.fileTimestampFormatter.string(from: Date())
        let transcriptFilename = "\(timestamp)-\(profile.agentKind.rawValue)-\(sessionID.uuidString).typescript"
        let transcriptPath = (transcriptDirectory as NSString).appendingPathComponent(transcriptFilename)
        let inputCapturePath = settings.captureMode.usesScriptKeyLogging ? transcriptPath + ".stdinrec" : nil
        let completionMarkerPath = transcriptPath + ".exit"
        let hereDocMarker = "__CLILAUNCHER_MONITOR_\(sessionID.uuidString.replacingOccurrences(of: "-", with: "_"))__"
        let wrappedCommand = wrapCommand(
            originalCommand: item.command,
            transcriptPath: transcriptPath,
            inputCapturePath: inputCapturePath,
            completionMarkerPath: completionMarkerPath,
            settings: settings,
            hereDocMarker: hereDocMarker,
            workingDirectory: profile.expandedWorkingDirectory
        )

        let session = TerminalMonitorSession(
            id: sessionID,
            profileID: item.profileID,
            profileName: item.profileName,
            agentKind: profile.agentKind,
            accountIdentifier: Self.currentAccountIdentifier(for: profile),
            prompt: Self.recordedPrompt(for: profile, command: item.command),
            workingDirectory: profile.expandedWorkingDirectory,
            transcriptPath: transcriptPath,
            inputCapturePath: inputCapturePath,
            launchCommand: item.command,
            captureMode: settings.captureMode,
            startedAt: Date(),
            lastActivityAt: nil,
            endedAt: nil,
            chunkCount: 0,
            byteCount: 0,
            status: .prepared,
            lastPreview: "",
            lastDatabaseMessage: settings.enableMongoWrites ? "Session prepared for MongoDB tracking." : "Local transcript capture only.",
            lastError: nil,
            statusReason: nil,
            exitCode: nil,
            isHistorical: false,
            isYolo: profile.agentKind == .gemini && profile.effectiveGeminiYolo
        )
        return PreparedMonitoringContext(
            session: session,
            wrappedCommand: wrappedCommand,
            completionMarkerPath: completionMarkerPath,
            inputCapturePath: inputCapturePath,
            launchScriptPath: nil
        )
    }

    private func wrapCommand(
        originalCommand: String,
        transcriptPath: String,
        inputCapturePath: String?,
        completionMarkerPath: String,
        settings: MongoMonitoringSettings,
        hereDocMarker: String,
        workingDirectory: String
    ) -> String {
        let builder = CommandBuilder()
        let scriptExecutable = builder.resolvedExecutable(settings.scriptExecutable) ?? settings.scriptExecutable
        let transcriptDirectory = URL(fileURLWithPath: transcriptPath).deletingLastPathComponent().path
        let keyFlag = settings.captureMode.usesScriptKeyLogging ? "-k " : ""
        return """
        emulate -L zsh
        setopt pipefail
        __clilauncher_monitor_helper_path="$(/usr/bin/mktemp -t clilauncher-monitor-launch)" || exit 1
        trap '/bin/rm -f "$__clilauncher_monitor_helper_path"' EXIT
        /bin/cat > "$__clilauncher_monitor_helper_path" <<'\(hereDocMarker)'
        #!/bin/zsh
        \(originalCommand)
        \(hereDocMarker)
        /bin/chmod 755 "$__clilauncher_monitor_helper_path" || { /bin/rm -f "$__clilauncher_monitor_helper_path"; exit 1; }
        mkdir -p \(shellQuote(transcriptDirectory)) || exit 1
        if [ -t 0 ] || [ -t 1 ] || [ -t 2 ]; then
          if [ -n \(shellQuote(inputCapturePath ?? "")) ]; then
            \(shellQuote(scriptExecutable)) -q -r \(shellQuote(inputCapturePath ?? "")) \(shellQuote(scriptExecutable)) -q \(keyFlag)-t 0 \(shellQuote(transcriptPath)) "$__clilauncher_monitor_helper_path"
          else
            \(shellQuote(scriptExecutable)) -q \(keyFlag)-t 0 \(shellQuote(transcriptPath)) "$__clilauncher_monitor_helper_path"
          fi
          __launcher_exit_code=$?
        else
          "$__clilauncher_monitor_helper_path" 2>&1 | /usr/bin/tee \(shellQuote(transcriptPath))
          __launcher_exit_code=${pipestatus[1]}
        fi
        __launcher_reason="command_finished"
        if [ "$__launcher_exit_code" -ne 0 ]; then
          __launcher_reason="monitor_wrapper_failed"
        fi
        /usr/bin/printf 'exit_code=%s\\nended_at=%s\\nreason=%s\\n' "$__launcher_exit_code" "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$__launcher_reason" > \(shellQuote(completionMarkerPath))
        if [ "$__launcher_exit_code" -ne 0 ]; then
          printf '\\n[clilauncher] Transcript capture failed before the session could attach (status %s).\\n' "$__launcher_exit_code"
          printf '[clilauncher] Opening an interactive shell for inspection. Type exit when done.\\n'
          export CLILAUNCHER_LAST_STATUS="$__launcher_exit_code"
          export CLILAUNCHER_LAST_REASON='monitor-wrapper-failed'
          export CLILAUNCHER_TRANSCRIPT_PATH=\(shellQuote(transcriptPath))
          cd \(shellQuote(workingDirectory))
          exec /bin/zsh -il
        fi
        exit $__launcher_exit_code
        """
    }

    private func startPolling(context: PreparedMonitoringContext, settings: MongoMonitoringSettings) {
        let sessionID = context.session.id
        stopPolling(sessionID: sessionID)

        pollTasks[sessionID] = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let basePollingDelay = UInt64(max(250, settings.pollingIntervalMs)) * 1_000_000
            let maxPollingDelay = UInt64(5_000_000_000)
            let chunkByteLimit = 12_000
            let idleThreshold: TimeInterval = 120
            let transcriptGraceDeadline = Date().addingTimeInterval(20)
            let transcriptPath = context.session.transcriptPath
            let inputCapturePath = context.inputCapturePath
            var offset: UInt64 = 0
            var chunkIndex = 0
            var inputOffset: UInt64 = 0
            var inputChunkIndex = 0
            var pendingInputRecordingData = Data()
            var lastObservedWrite = Date()
            var pollingDelay = basePollingDelay
            var transcriptHandle: FileHandle?
            var inputHandle: FileHandle?
            defer { try? transcriptHandle?.close() }
            defer { try? inputHandle?.close() }

            while !Task.isCancelled {
                do {
                    if transcriptHandle == nil {
                        transcriptHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: transcriptPath))
                        offset = 0
                    }

                    let endOffset = try transcriptHandle!.seekToEnd()
                    if endOffset < offset {
                        offset = 0
                    }

                    let hasNewData = endOffset > offset
                    if hasNewData {
                        pollingDelay = basePollingDelay
                        try transcriptHandle!.seek(toOffset: offset)
                        let data = try transcriptHandle!.readToEnd() ?? Data()
                        offset = endOffset
                        var sliceStart = 0
                        while sliceStart < data.count {
                            let sliceEnd = min(sliceStart + chunkByteLimit, data.count)
                            let slice = data.subdata(in: sliceStart..<sliceEnd)
                            chunkIndex += 1
                            lastObservedWrite = Date()
                            let preview = Self.cleanedPreview(from: slice, limit: settings.previewCharacterLimit)
                            await consumeChunk(
                                sessionID: sessionID,
                                data: slice,
                                preview: preview,
                                chunkIndex: chunkIndex,
                                timestamp: lastObservedWrite,
                                settings: settings
                            )
                            sliceStart = sliceEnd
                        }
                    }

                    if let inputCapturePath {
                        if inputHandle == nil {
                            inputHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: inputCapturePath))
                            inputOffset = 0
                        }

                        let inputEndOffset = try inputHandle!.seekToEnd()
                        if inputEndOffset < inputOffset {
                            inputOffset = 0
                            pendingInputRecordingData = Data()
                        }

                        if inputEndOffset > inputOffset {
                            pollingDelay = basePollingDelay
                            try inputHandle!.seek(toOffset: inputOffset)
                            let inputData = try inputHandle!.readToEnd() ?? Data()
                            inputOffset = inputEndOffset
                            if !inputData.isEmpty {
                                pendingInputRecordingData.append(inputData)
                                let parsed = Self.parseScriptRecordingData(pendingInputRecordingData)
                                pendingInputRecordingData = parsed.trailingData
                                for record in parsed.records where record.direction == "i" && !record.data.isEmpty {
                                    inputChunkIndex += 1
                                    lastObservedWrite = max(lastObservedWrite, record.capturedAt)
                                    let preview = Self.cleanedPreview(from: record.data, limit: settings.previewCharacterLimit)
                                    await consumeInputChunk(
                                        sessionID: sessionID,
                                        data: record.data,
                                        preview: preview,
                                        inputIndex: inputChunkIndex,
                                        timestamp: record.capturedAt,
                                        settings: settings
                                    )
                                }
                            }
                        }
                    }

                    if let completion = Self.readCompletionMarker(at: context.completionMarkerPath) {
                        await markCompleted(
                            sessionID: sessionID,
                            completion: completion,
                            completionMarkerPath: context.completionMarkerPath,
                            inputCapturePath: context.inputCapturePath,
                            launchScriptPath: context.launchScriptPath,
                            settings: settings
                        )
                        return
                    }

                    if endOffset > 0, Date().timeIntervalSince(lastObservedWrite) > idleThreshold {
                        await markIdleIfNeeded(sessionID: sessionID, at: lastObservedWrite, settings: settings)
                    }

                    if !hasNewData {
                        pollingDelay = min(maxPollingDelay, pollingDelay * 2)
                    }
                } catch {
                    if let handle = transcriptHandle {
                        try? handle.close()
                    }
                    transcriptHandle = nil
                    if let handle = inputHandle {
                        try? handle.close()
                    }
                    inputHandle = nil

                    if Self.isMissingFileError(error), Date() < transcriptGraceDeadline {
                        pollingDelay = min(maxPollingDelay, pollingDelay * 2)
                    } else {
                        await markMonitoringFailure(
                            sessionID: sessionID,
                            message: error.localizedDescription,
                            completionMarkerPath: context.completionMarkerPath,
                            inputCapturePath: context.inputCapturePath,
                            launchScriptPath: context.launchScriptPath,
                            settings: settings
                        )
                        return
                    }
                }

                try? await Task.sleep(nanoseconds: pollingDelay)
            }
        }
    }

    private func stopPolling(sessionID: UUID) {
        pollTasks[sessionID]?.cancel()
        pollTasks.removeValue(forKey: sessionID)
        sessionStatsBuffersByID.removeValue(forKey: sessionID)
        sessionStatsFingerprintsByID.removeValue(forKey: sessionID)
        sessionStatsSkipFingerprintsByID.removeValue(forKey: sessionID)
        sessionStatsBlockedFingerprintsByID.removeValue(forKey: sessionID)
        sessionStatsFallbackFingerprintsByID.removeValue(forKey: sessionID)
        modelCapacityFingerprintsByID.removeValue(forKey: sessionID)
        launchContextFingerprintsByID.removeValue(forKey: sessionID)
        startupClearFingerprintsByID.removeValue(forKey: sessionID)
        startupClearCompletedFingerprintsByID.removeValue(forKey: sessionID)
        compatibilityOverrideFingerprintsByID.removeValue(forKey: sessionID)
        freshSessionResetFingerprintsByID.removeValue(forKey: sessionID)
        transcriptInteractionHistoryByID.removeValue(forKey: sessionID)
    }

    private func consumeChunk(
        sessionID: UUID,
        data: Data,
        preview: String,
        chunkIndex: Int,
        timestamp: Date,
        settings: MongoMonitoringSettings
    ) async {
        guard let index = sessionIndex(for: sessionID) else { return }
        var session = sessions[index]

        session.status = .monitoring
        session.lastActivityAt = timestamp
        session.chunkCount += 1
        session.byteCount += data.count
        session.lastPreview = preview
        let sessionStatsBuffer = bufferGeminiSessionStatsParsingText(sessionID: sessionID, data: data)
        let launchContextNotice = sessionStatsBuffer.flatMap { captureGeminiLaunchContextIfPresent(sessionID: sessionID, bufferedTranscriptText: $0) }
        let startupClearNotice = sessionStatsBuffer.flatMap { captureGeminiStartupClearIfPresent(sessionID: sessionID, bufferedTranscriptText: $0) }
        let startupClearCompletedNotice = sessionStatsBuffer.flatMap { captureGeminiStartupClearCompletedIfPresent(sessionID: sessionID, bufferedTranscriptText: $0) }
        let sessionStatsCapture = sessionStatsBuffer.flatMap { captureGeminiSessionStatsIfPresent(sessionID: sessionID, bufferedTranscriptText: $0) }
        let modelCapacityCapture = sessionStatsBuffer.flatMap { captureGeminiModelCapacityIfPresent(sessionID: sessionID, bufferedTranscriptText: $0) }
        let sessionStatsSkipNotice = sessionStatsBuffer.flatMap { captureGeminiSessionStatsSkipIfPresent(sessionID: sessionID, bufferedTranscriptText: $0) }
        let sessionStatsBlockedNotice = sessionStatsBuffer.flatMap { captureGeminiSessionStatsBlockedIfPresent(sessionID: sessionID, bufferedTranscriptText: $0) }
        let sessionStatsFallbackNotice = sessionStatsBuffer.flatMap { captureGeminiSessionStatsFallbackIfPresent(sessionID: sessionID, bufferedTranscriptText: $0) }
        let compatibilityOverrideNotice = sessionStatsBuffer.flatMap { captureGeminiCompatibilityOverrideIfPresent(sessionID: sessionID, bufferedTranscriptText: $0) }
        let freshSessionResetNotice = sessionStatsBuffer.flatMap { captureGeminiFreshSessionResetIfPresent(sessionID: sessionID, bufferedTranscriptText: $0) }
        let transcriptInteractionNotices = sessionStatsBuffer.map { captureGeminiTranscriptInteractionsIfPresent(sessionID: sessionID, bufferedTranscriptText: $0) } ?? []
        if let launchContextNotice {
            session = Self.sessionByApplyingGeminiLaunchContext(launchContextNotice.snapshot, to: session)
        }
        if let startupClearNotice {
            session = Self.sessionByApplyingGeminiStartupClear(startupClearNotice, to: session)
        }
        if let startupClearCompletedNotice {
            session = Self.sessionByApplyingGeminiStartupClear(startupClearCompletedNotice, to: session)
        }
        if let freshSessionResetNotice {
            session = Self.sessionByApplyingGeminiFreshSessionReset(freshSessionResetNotice, to: session)
        }
        session = Self.sessionByApplyingGeminiTranscriptInteractions(
            transcriptInteractionNotices,
            observedAt: timestamp,
            to: session
        )
        if let sessionStatsCapture {
            session = Self.sessionByApplyingGeminiSessionStats(sessionStatsCapture.snapshot, to: session)
        }
        if let modelCapacityCapture {
            session = Self.sessionByApplyingGeminiModelCapacity(modelCapacityCapture.snapshot, to: session)
        }
        if let sessionStatsCapture {
            session.lastDatabaseMessage = settings.enableMongoWrites
                ? "\(Self.geminiSessionStatsCaptureMessage(for: sessionStatsCapture.snapshot)); syncing transcript chunk \(session.chunkCount)."
                : "\(Self.geminiSessionStatsCaptureMessage(for: sessionStatsCapture.snapshot)) locally."
        } else if let modelCapacityCapture {
            session.lastDatabaseMessage = settings.enableMongoWrites
                ? "\(Self.geminiModelCapacityCaptureMessage(for: modelCapacityCapture.snapshot)); syncing transcript chunk \(session.chunkCount)."
                : "\(Self.geminiModelCapacityCaptureMessage(for: modelCapacityCapture.snapshot)) locally."
        } else if launchContextNotice != nil {
            session.lastDatabaseMessage = settings.enableMongoWrites
                ? "Captured Gemini launch context and synced transcript chunk \(session.chunkCount)."
                : "Captured Gemini launch context locally."
        } else if startupClearCompletedNotice != nil {
            session.lastDatabaseMessage = settings.enableMongoWrites
                ? "Completed Gemini startup clear and synced transcript chunk \(session.chunkCount)."
                : "Completed Gemini startup clear locally."
        } else if let startupClearNotice {
            session.lastDatabaseMessage = settings.enableMongoWrites
                ? "Sent Gemini startup clear command \(startupClearNotice.command); syncing transcript chunk \(session.chunkCount)."
                : "Sent Gemini startup clear command \(startupClearNotice.command)."
        } else if sessionStatsBlockedNotice != nil {
            session.lastDatabaseMessage = settings.enableMongoWrites
                ? "Blocked Gemini startup automation before prompt injection; syncing transcript chunk \(session.chunkCount)."
                : "Blocked Gemini startup automation before prompt injection."
        } else if sessionStatsSkipNotice != nil {
            session.lastDatabaseMessage = settings.enableMongoWrites
                ? "Skipped Gemini session stats due to CLI compatibility; syncing transcript chunk \(session.chunkCount)."
                : "Skipped Gemini session stats due to CLI compatibility."
        } else if let sessionStatsFallbackNotice {
            session.lastDatabaseMessage = settings.enableMongoWrites
                ? "Retrying Gemini startup session stats with \(sessionStatsFallbackNotice.toCommand); syncing transcript chunk \(session.chunkCount)."
                : "Retrying Gemini startup session stats with \(sessionStatsFallbackNotice.toCommand)."
        } else if compatibilityOverrideNotice != nil {
            session.lastDatabaseMessage = settings.enableMongoWrites
                ? "Applied Gemini CLI compatibility override; syncing transcript chunk \(session.chunkCount)."
                : "Applied Gemini CLI compatibility override locally."
        } else if let freshSessionResetNotice {
            session.lastDatabaseMessage = settings.enableMongoWrites
                ? "Prepared fresh Gemini workspace session; syncing transcript chunk \(session.chunkCount)."
                : "Prepared fresh Gemini workspace session locally (\(freshSessionResetNotice.reason))."
        } else {
            session.lastDatabaseMessage = settings.enableMongoWrites
                ? "Chunk \(session.chunkCount) queued for MongoDB."
                : "Chunk \(session.chunkCount) captured locally."
        }
        session.lastError = nil
        session.statusReason = nil
        upsert(session)

        guard settings.enableMongoWrites else { return }

        do {
            let transcriptChunkSource = session.captureMode.usesScriptKeyLogging
                ? "terminal_transcript_input_output"
                : "terminal_transcript_output_only"
            var syncedSession = Self.sessionByApplyingMongoTranscriptSyncProgress(
                source: "live_chunk_capture",
                chunkCount: session.chunkCount,
                byteCount: session.byteCount,
                synchronizedAt: timestamp,
                verifiedComplete: false,
                to: session
            )
            if sessionStatsCapture != nil {
                syncedSession.lastDatabaseMessage = "Captured Gemini session stats and synced chunk \(syncedSession.chunkCount) to MongoDB."
            } else if modelCapacityCapture != nil {
                syncedSession.lastDatabaseMessage = "Captured Gemini model capacity and synced chunk \(syncedSession.chunkCount) to MongoDB."
            } else if launchContextNotice != nil {
                syncedSession.lastDatabaseMessage = "Recorded Gemini launch context and synced chunk \(syncedSession.chunkCount) to MongoDB."
            } else if startupClearCompletedNotice != nil {
                syncedSession.lastDatabaseMessage = "Recorded Gemini startup clear completion and synced chunk \(syncedSession.chunkCount) to MongoDB."
            } else if startupClearNotice != nil {
                syncedSession.lastDatabaseMessage = "Recorded Gemini startup clear send and synced chunk \(syncedSession.chunkCount) to MongoDB."
            } else if sessionStatsBlockedNotice != nil {
                syncedSession.lastDatabaseMessage = "Recorded Gemini startup automation block reason and synced chunk \(syncedSession.chunkCount) to MongoDB."
            } else if sessionStatsSkipNotice != nil {
                syncedSession.lastDatabaseMessage = "Recorded Gemini session stats skip reason and synced chunk \(syncedSession.chunkCount) to MongoDB."
            } else if sessionStatsFallbackNotice != nil {
                syncedSession.lastDatabaseMessage = "Recorded Gemini startup stats fallback retry and synced chunk \(syncedSession.chunkCount) to MongoDB."
            } else if compatibilityOverrideNotice != nil {
                syncedSession.lastDatabaseMessage = "Recorded Gemini CLI compatibility override and synced chunk \(syncedSession.chunkCount) to MongoDB."
            } else if freshSessionResetNotice != nil {
                syncedSession.lastDatabaseMessage = "Recorded Gemini fresh-session preparation and synced chunk \(syncedSession.chunkCount) to MongoDB."
            } else {
                syncedSession.lastDatabaseMessage = "Synced chunk \(syncedSession.chunkCount) to MongoDB."
            }
            try await writer.recordChunk(
                sessionID: sessionID,
                chunkIndex: chunkIndex,
                data: data,
                source: transcriptChunkSource,
                session: syncedSession,
                prompt: session.prompt,
                preview: preview,
                totalChunks: session.chunkCount,
                totalBytes: session.byteCount,
                capturedAt: timestamp,
                status: .monitoring,
                settings: settings
            )
            if let launchContextNotice {
                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: "launch_context_captured",
                    message: "Captured Gemini launch context.",
                    eventAt: timestamp,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: launchContextNotice.snapshot.metadata,
                    settings: settings
                )
            }
            if let startupClearNotice {
                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: "startup_clear_sent",
                    message: "Sent Gemini startup clear command \(startupClearNotice.command).",
                    eventAt: timestamp,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: startupClearNotice.metadata,
                    settings: settings
                )
            }
            if let startupClearCompletedNotice {
                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: "startup_clear_completed",
                    message: "Completed Gemini startup clear before startup stats.",
                    eventAt: timestamp,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: startupClearCompletedNotice.metadata,
                    settings: settings
                )
            }
            if let sessionStatsCapture {
                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: "session_stats_captured",
                    message: Self.geminiSessionStatsCaptureMessage(for: sessionStatsCapture.snapshot),
                    eventAt: timestamp,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: sessionStatsCapture.snapshot.metadata,
                    settings: settings
                )
            }
            if let modelCapacityCapture {
                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: "model_capacity_captured",
                    message: Self.geminiModelCapacityCaptureMessage(for: modelCapacityCapture.snapshot),
                    eventAt: timestamp,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: modelCapacityCapture.snapshot.metadata,
                    settings: settings
                )
            }
            if let sessionStatsSkipNotice {
                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: "session_stats_skipped",
                    message: "Skipped Gemini startup session stats capture.",
                    eventAt: timestamp,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: sessionStatsSkipNotice.metadata,
                    settings: settings
                )
            }
            if let sessionStatsBlockedNotice {
                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: "session_stats_blocked",
                    message: "Blocked Gemini startup automation before prompt injection.",
                    eventAt: timestamp,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: sessionStatsBlockedNotice.metadata,
                    settings: settings
                )
            }
            if let sessionStatsFallbackNotice {
                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: "session_stats_fallback_retry",
                    message: "Retrying Gemini startup session stats with \(sessionStatsFallbackNotice.toCommand) after \(sessionStatsFallbackNotice.fromCommand) produced no detected output.",
                    eventAt: timestamp,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: sessionStatsFallbackNotice.metadata,
                    settings: settings
                )
            }
            if let compatibilityOverrideNotice {
                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: "gemini_cli_compatibility_override_applied",
                    message: "Applied Gemini CLI compatibility override for launcher-started session.",
                    eventAt: timestamp,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: compatibilityOverrideNotice.metadata,
                    settings: settings
                )
            }
            if let freshSessionResetNotice {
                try await writer.recordStatus(
                    session: syncedSession,
                    status: syncedSession.status,
                    eventType: "fresh_workspace_session_prepared",
                    message: "Prepared fresh Gemini workspace session before launch.",
                    eventAt: timestamp,
                    statusReason: syncedSession.statusReason,
                    exitCode: syncedSession.exitCode,
                    metadata: freshSessionResetNotice.metadata,
                    settings: settings
                )
            }
            if !transcriptInteractionNotices.isEmpty {
                for notice in transcriptInteractionNotices {
                    try await writer.recordStatus(
                        session: syncedSession,
                        status: syncedSession.status,
                        eventType: notice.eventType,
                        message: notice.message,
                        eventAt: timestamp,
                        statusReason: syncedSession.statusReason,
                        exitCode: syncedSession.exitCode,
                        metadata: notice.metadata,
                        settings: settings
                    )
                }
            }
            upsert(syncedSession)
        } catch {
            var failedSession = self.session(for: sessionID) ?? session
            failedSession.lastDatabaseMessage = "MongoDB sync failed: \(error.localizedDescription)"
            upsert(failedSession)
            setDatabaseStatusIfChanged("MongoDB write failed")
        }
    }

    private func consumeInputChunk(
        sessionID: UUID,
        data: Data,
        preview: String,
        inputIndex: Int,
        timestamp: Date,
        settings: MongoMonitoringSettings
    ) async {
        guard let index = sessionIndex(for: sessionID) else { return }
        var session = sessions[index]

        session.status = .monitoring
        session.lastActivityAt = timestamp
        session.inputChunkCount += 1
        session.inputByteCount += data.count
        session.lastDatabaseMessage = settings.enableMongoWrites
            ? "Input chunk \(session.inputChunkCount) queued for MongoDB."
            : "Input chunk \(session.inputChunkCount) captured locally."
        session.lastError = nil
        upsert(session)

        guard settings.enableMongoWrites else { return }

        do {
            var syncedSession = Self.sessionByApplyingMongoInputSyncProgress(
                source: "live_input_capture",
                chunkCount: session.inputChunkCount,
                byteCount: session.inputByteCount,
                synchronizedAt: timestamp,
                verifiedComplete: false,
                to: session
            )
            syncedSession.lastDatabaseMessage = "Synced input chunk \(syncedSession.inputChunkCount) to MongoDB."
            try await writer.recordInputChunk(
                sessionID: sessionID,
                inputIndex: inputIndex,
                data: data,
                source: "terminal_stdin_raw_capture",
                session: syncedSession,
                prompt: session.prompt,
                preview: preview,
                capturedAt: timestamp,
                status: .monitoring,
                settings: settings
            )
            upsert(syncedSession)
        } catch {
            var failedSession = self.session(for: sessionID) ?? session
            failedSession.lastDatabaseMessage = "MongoDB stdin sync failed: \(error.localizedDescription)"
            upsert(failedSession)
            setDatabaseStatusIfChanged("MongoDB write failed")
        }
    }

    private func markIdleIfNeeded(sessionID: UUID, at timestamp: Date, settings: MongoMonitoringSettings) async {
        guard let index = sessionIndex(for: sessionID) else { return }
        guard sessions[index].status != .idle else { return }

        var idleSession = sessions[index]
        idleSession.status = .idle
        idleSession.lastActivityAt = timestamp
        idleSession.lastDatabaseMessage = settings.enableMongoWrites ? "Waiting for additional terminal output." : "No new terminal output detected yet."
        upsert(idleSession)

        guard settings.enableMongoWrites else { return }
        do {
            try await writer.recordStatus(
                session: idleSession,
                status: .idle,
                eventType: "session_idle",
                message: idleSession.lastDatabaseMessage,
                eventAt: timestamp,
                endedAt: nil,
                statusReason: "no_output_detected",
                exitCode: idleSession.exitCode,
                settings: settings
            )
        } catch {
            var failedSession = self.session(for: sessionID) ?? idleSession
            failedSession.lastDatabaseMessage = "MongoDB idle-state sync failed: \(error.localizedDescription)"
            upsert(failedSession)
            setDatabaseStatusIfChanged("MongoDB write failed")
        }
    }

    private func markCompleted(
        sessionID: UUID,
        completion: SessionCompletionMarker,
        completionMarkerPath: String,
        inputCapturePath: String?,
        launchScriptPath: String?,
        settings: MongoMonitoringSettings
    ) async {
        guard let index = sessionIndex(for: sessionID) else {
            stopPolling(sessionID: sessionID)
            try? FileManager.default.removeItem(atPath: completionMarkerPath)
            if let inputCapturePath {
                try? FileManager.default.removeItem(atPath: inputCapturePath)
            }
            if let launchScriptPath {
                try? FileManager.default.removeItem(atPath: launchScriptPath)
            }
            return
        }

        let completedSuccessfully = completion.exitCode == 0
        sessions[index].status = completedSuccessfully ? .completed : .failed
        sessions[index].endedAt = completion.endedAt
        sessions[index].lastActivityAt = completion.endedAt
        sessions[index].exitCode = completion.exitCode
        sessions[index].statusReason = completion.reason
        sessions[index].lastError = completedSuccessfully ? nil : "Process exited with code \(completion.exitCode)."
        sessions[index].lastDatabaseMessage = settings.enableMongoWrites
            ? (completedSuccessfully ? "Session completed and synced to MongoDB." : "Session exited non-zero and was recorded in MongoDB.")
            : (completedSuccessfully ? "Session completed locally." : "Session exited non-zero.")

        var finalSession = sessions[index]
        var mongoCompletionSyncSucceeded = !settings.enableMongoWrites
        upsert(finalSession)
        stopPolling(sessionID: sessionID)
        try? FileManager.default.removeItem(atPath: completionMarkerPath)
        if let launchScriptPath {
            try? FileManager.default.removeItem(atPath: launchScriptPath)
        }

        if settings.enableMongoWrites {
            do {
                try await writer.recordCompletion(session: finalSession, settings: settings)

                let transcriptSync = try await synchronizeSessionTranscriptToMongoIfNeeded(
                    session: finalSession,
                    settings: settings,
                    syncSource: "local_transcript_file"
                )
                finalSession = transcriptSync.session
                upsert(finalSession)
                let inputSync = try await synchronizeSessionInputCaptureToMongoIfNeeded(
                    session: finalSession,
                    settings: settings,
                    syncSource: "local_input_capture_file"
                )
                finalSession = inputSync.session
                upsert(finalSession)
                if let importedChunkCount = transcriptSync.importedChunkCount {
                    finalSession.lastDatabaseMessage = Self.transcriptSynchronizationMessage(
                        for: completedSuccessfully ? .completionSuccess : .completionFailure,
                        importedChunkCount: importedChunkCount
                    )
                    upsert(finalSession)
                    try await writer.recordStatus(
                        session: finalSession,
                        status: finalSession.status,
                        eventType: "session_transcript_synchronized",
                        message: finalSession.lastDatabaseMessage,
                        eventAt: finalSession.endedAt ?? Date(),
                        endedAt: finalSession.endedAt,
                        statusReason: finalSession.statusReason,
                        exitCode: finalSession.exitCode,
                        metadata: [
                            "source": "local_transcript_file",
                            "imported_chunks": importedChunkCount,
                            "total_chunks": finalSession.chunkCount,
                            "total_bytes": finalSession.byteCount
                        ],
                        settings: settings
                    )
                } else if finalSession.mongoTranscriptSyncState == .complete {
                    try await writer.recordSessionSnapshot(finalSession, settings: settings)
                }
                finalSession = try await recordInputSynchronizationStatusIfNeeded(
                    session: finalSession,
                    context: completedSuccessfully ? .completionSuccess : .completionFailure,
                    syncSource: "local_input_capture_file",
                    trigger: nil,
                    recoveredWithoutDatabaseSession: false,
                    importedChunkCount: inputSync.importedChunkCount,
                    settings: settings
                )
                mongoCompletionSyncSucceeded = true
            } catch {
                if let refreshedIndex = sessionIndex(for: sessionID) {
                    sessions[refreshedIndex].lastDatabaseMessage = completedSuccessfully && !settings.keepLocalTranscriptFiles
                        ? Self.completionSyncFailureMessage(
                            error: error.localizedDescription,
                            retainedRawInputCapture: inputCapturePath != nil
                        )
                        : "MongoDB completion sync failed: \(error.localizedDescription)"
                    finalSession = sessions[refreshedIndex]
                    upsert(finalSession)
                }
                setDatabaseStatusIfChanged("MongoDB write failed")
            }
        }

        if Self.shouldDeleteLocalTranscriptAfterCompletion(
            completedSuccessfully: completedSuccessfully,
            keepLocalTranscriptFiles: settings.keepLocalTranscriptFiles,
            enableMongoWrites: settings.enableMongoWrites,
            mongoSyncSucceeded: mongoCompletionSyncSucceeded
        ) {
            try? FileManager.default.removeItem(atPath: finalSession.transcriptPath)
            if let inputCapturePath {
                try? FileManager.default.removeItem(atPath: inputCapturePath)
            }
        }
    }

    private func markMonitoringFailure(
        sessionID: UUID,
        message: String,
        completionMarkerPath: String,
        inputCapturePath: String?,
        launchScriptPath: String?,
        settings: MongoMonitoringSettings
    ) async {
        guard let index = sessionIndex(for: sessionID) else {
            stopPolling(sessionID: sessionID)
            try? FileManager.default.removeItem(atPath: completionMarkerPath)
            if let inputCapturePath {
                try? FileManager.default.removeItem(atPath: inputCapturePath)
            }
            if let launchScriptPath {
                try? FileManager.default.removeItem(atPath: launchScriptPath)
            }
            return
        }

        sessions[index].status = .failed
        sessions[index].endedAt = Date()
        sessions[index].lastError = message
        sessions[index].statusReason = "monitoring_error"
        sessions[index].lastDatabaseMessage = settings.enableMongoWrites ? "Monitoring failed before session data could be fully synchronized." : "Monitoring failed locally."
        var failedSession = sessions[index]
        upsert(failedSession)
        stopPolling(sessionID: sessionID)
        try? FileManager.default.removeItem(atPath: completionMarkerPath)
        if let launchScriptPath {
            try? FileManager.default.removeItem(atPath: launchScriptPath)
        }

        guard settings.enableMongoWrites else { return }
        do {
            try await writer.recordFailure(session: failedSession, message: message, status: .failed, settings: settings)

            let transcriptSync = try await synchronizeSessionTranscriptToMongoIfNeeded(
                session: failedSession,
                settings: settings,
                syncSource: "local_transcript_file"
            )
            failedSession = transcriptSync.session
            upsert(failedSession)
            let inputSync = try await synchronizeSessionInputCaptureToMongoIfNeeded(
                session: failedSession,
                settings: settings,
                syncSource: "local_input_capture_file"
            )
            failedSession = inputSync.session
            upsert(failedSession)
            if let importedChunkCount = transcriptSync.importedChunkCount {
                failedSession.lastDatabaseMessage = Self.transcriptSynchronizationMessage(
                    for: .monitoringFailure,
                    importedChunkCount: importedChunkCount
                )
                upsert(failedSession)
                try await writer.recordStatus(
                    session: failedSession,
                    status: failedSession.status,
                    eventType: "session_transcript_synchronized",
                    message: failedSession.lastDatabaseMessage,
                    eventAt: failedSession.endedAt ?? Date(),
                    endedAt: failedSession.endedAt,
                    statusReason: failedSession.statusReason,
                    exitCode: failedSession.exitCode,
                    metadata: [
                        "source": "local_transcript_file",
                        "imported_chunks": importedChunkCount,
                        "total_chunks": failedSession.chunkCount,
                        "total_bytes": failedSession.byteCount
                        ],
                        settings: settings
                    )
            } else if failedSession.mongoTranscriptSyncState == .complete {
                try await writer.recordSessionSnapshot(failedSession, settings: settings)
            }
            failedSession = try await recordInputSynchronizationStatusIfNeeded(
                session: failedSession,
                context: .monitoringFailure,
                syncSource: "local_input_capture_file",
                trigger: nil,
                recoveredWithoutDatabaseSession: false,
                importedChunkCount: inputSync.importedChunkCount,
                settings: settings
            )
        } catch {
            if let refreshedIndex = sessionIndex(for: sessionID) {
                sessions[refreshedIndex].lastDatabaseMessage = "MongoDB failure sync failed: \(error.localizedDescription)"
            }
            setDatabaseStatusIfChanged("MongoDB write failed")
        }
    }

    private func synchronizeHistoricalSessions(_ databaseSessions: [TerminalMonitorSession]) {
        let databaseSessionIDs = Set(databaseSessions.map(\.id))
        let staleHistoricalIDs = Set(sessions.filter(\.isHistorical).map(\.id)).subtracting(databaseSessionIDs)
        var liveSessions = sessions.filter { !$0.isHistorical }
        var liveSessionIndexByID: [UUID: Int] = [:]
        liveSessionIndexByID.reserveCapacity(liveSessions.count)
        for index in liveSessions.indices {
            liveSessionIndexByID[liveSessions[index].id] = index
        }

        for session in databaseSessions {
            if let index = liveSessionIndexByID[session.id] {
                var merged = liveSessions[index]
                merged.endedAt = session.endedAt ?? merged.endedAt
                merged.statusReason = session.statusReason ?? merged.statusReason
                merged.exitCode = session.exitCode ?? merged.exitCode
                merged.lastActivityAt = max(merged.lastActivityAt ?? .distantPast, session.lastActivityAt ?? .distantPast)
                merged.inputCapturePath = session.inputCapturePath ?? merged.inputCapturePath
                merged.inputChunkCount = max(merged.inputChunkCount, session.inputChunkCount)
                merged.inputByteCount = max(merged.inputByteCount, session.inputByteCount)
                merged.mongoInputSyncState = session.mongoInputSyncState ?? merged.mongoInputSyncState
                merged.mongoInputSyncSource = session.mongoInputSyncSource ?? merged.mongoInputSyncSource
                switch (merged.mongoInputChunkCount, session.mongoInputChunkCount) {
                case let (lhs?, rhs?):
                    merged.mongoInputChunkCount = max(lhs, rhs)
                case (nil, let rhs?):
                    merged.mongoInputChunkCount = rhs
                default:
                    break
                }
                switch (merged.mongoInputByteCount, session.mongoInputByteCount) {
                case let (lhs?, rhs?):
                    merged.mongoInputByteCount = max(lhs, rhs)
                case (nil, let rhs?):
                    merged.mongoInputByteCount = rhs
                default:
                    break
                }
                if let sessionMongoInputSynchronizedAt = session.mongoInputSynchronizedAt {
                    merged.mongoInputSynchronizedAt = max(merged.mongoInputSynchronizedAt ?? .distantPast, sessionMongoInputSynchronizedAt)
                }
                if merged.lastPreview.isEmpty {
                    merged.lastPreview = session.lastPreview
                }
                if merged.lastDatabaseMessage.isEmpty || merged.lastDatabaseMessage.contains("failed") {
                    merged.lastDatabaseMessage = session.lastDatabaseMessage
                }
                liveSessions[index] = merged
            } else {
                liveSessions.append(session)
                liveSessionIndexByID[session.id] = liveSessions.count - 1
            }
        }

        pruneSessionDetailState(for: staleHistoricalIDs)

        var visibleSessions = liveSessions
        if visibleSessions.count > Self.maxVisibleSessions {
            let discardedSessions = visibleSessions.dropFirst(Self.maxVisibleSessions)
            pruneSessionDetailState(for: discardedSessions.map(\.id))
            visibleSessions = Array(visibleSessions.prefix(Self.maxVisibleSessions))
        }
        replaceSessionsIfChanged(with: visibleSessions)
    }

    private func upsert(_ session: TerminalMonitorSession) {
        var updatedSessions = sessions
        var removedSessionIDs: [UUID] = []

        if let index = sessionIndex(for: session.id) {
            if updatedSessions[index] == session {
                return
            }

            updatedSessions[index] = session
            let currentDate = Self.sessionActivityDate(session)
            var adjustedIndex = index

            while adjustedIndex > 0, currentDate > Self.sessionActivityDate(updatedSessions[adjustedIndex - 1]) {
                adjustedIndex -= 1
            }

            while adjustedIndex + 1 < updatedSessions.count, currentDate < Self.sessionActivityDate(updatedSessions[adjustedIndex + 1]) {
                adjustedIndex += 1
            }

            if adjustedIndex != index {
                let movedSession = updatedSessions.remove(at: index)
                updatedSessions.insert(movedSession, at: adjustedIndex)
            }
        } else {
            updatedSessions.insert(session, at: 0)
        }

        if updatedSessions.count > Self.maxVisibleSessions {
            let removed = updatedSessions.removeLast()
            removedSessionIDs = [removed.id]
        }

        if !removedSessionIDs.isEmpty {
            pruneSessionDetailState(for: removedSessionIDs)
        }

        commitSessions(updatedSessions)
    }

    func presentHistoricalSession(_ session: TerminalMonitorSession, queueFocus: Bool = true) {
        var historicalSession = session
        historicalSession.isHistorical = true
        if queueFocus {
            noteSessionForInspection(historicalSession.id)
        }
        upsert(historicalSession)
    }

    func presentHistoricalSessions(_ sessions: [TerminalMonitorSession], focusedSessionID: UUID?) {
        let historicalSessions = sessions.map { session -> TerminalMonitorSession in
            var historicalSession = session
            historicalSession.isHistorical = true
            return historicalSession
        }
        batchUpsert(historicalSessions)
        if let focusedSessionID {
            noteSessionForInspection(focusedSessionID)
        }
    }

    func noteSessionForInspection(_ sessionID: UUID, resetFilters: Bool = false) {
        pendingFocusedSessionID = sessionID
        if resetFilters {
            pendingMonitoringFilterReset = true
        }
    }

    func consumePendingFocusedSessionID(ifContainedIn visibleIDs: Set<UUID>? = nil) -> UUID? {
        guard let sessionID = pendingFocusedSessionID else { return nil }
        if let visibleIDs, !visibleIDs.contains(sessionID) {
            return nil
        }
        pendingFocusedSessionID = nil
        return sessionID
    }

    func consumePendingMonitoringFilterReset() -> Bool {
        let shouldReset = pendingMonitoringFilterReset
        pendingMonitoringFilterReset = false
        return shouldReset
    }

    private func batchUpsert(_ incomingSessions: [TerminalMonitorSession]) {
        guard !incomingSessions.isEmpty else { return }

        var sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        sessionsByID.reserveCapacity(sessions.count + incomingSessions.count)
        for session in incomingSessions {
            sessionsByID[session.id] = session
        }

        var mergedSessions = Array(sessionsByID.values)
        mergedSessions.sort { lhs, rhs in
            let lhsDate = Self.sessionActivityDate(lhs)
            let rhsDate = Self.sessionActivityDate(rhs)
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        if mergedSessions.count > Self.maxVisibleSessions {
            let discardedSessions = mergedSessions.dropFirst(Self.maxVisibleSessions)
            pruneSessionDetailState(for: discardedSessions.map(\.id))
            mergedSessions = Array(mergedSessions.prefix(Self.maxVisibleSessions))
        }

        replaceSessionsIfChanged(with: mergedSessions)
    }

    private func commitSessions(_ newSessions: [TerminalMonitorSession]) {
        sessions = newSessions
        rebuildSessionIndex()
    }

    private func replaceSessionsIfChanged(with newSessions: [TerminalMonitorSession]) {
        guard sessions != newSessions else { return }
        commitSessions(newSessions)
    }

    private func rebuildSessionIndex() {
        sessionIndexByID.removeAll(keepingCapacity: true)
        sessionIndexByID.reserveCapacity(sessions.count)

        for index in sessions.indices {
            sessionIndexByID[sessions[index].id] = index
        }
    }

    private func session(for sessionID: UUID) -> TerminalMonitorSession? {
        guard let index = sessionIndex(for: sessionID) else { return nil }
        return sessions[index]
    }

    private func sessionIndex(for sessionID: UUID) -> Int? {
        guard let index = sessionIndexByID[sessionID],
              sessions.indices.contains(index),
              sessions[index].id == sessionID
        else {
            return nil
        }
        return index
    }

    nonisolated private static func readTranscriptPreview(at path: String, maxBytes: Int) throws -> TranscriptPreviewSnapshot {
        let expanded = NSString(string: path).expandingTildeInPath
        let attributes = try FileManager.default.attributesOfItem(atPath: expanded)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: expanded))
        defer { try? handle.close() }

        let clampedLimit = max(1, maxBytes)
        let isTruncated = size > Int64(clampedLimit)
        if isTruncated {
            try handle.seek(toOffset: UInt64(max(0, size - Int64(clampedLimit))))
        }

        let data = try handle.readToEnd() ?? Data()
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{0000}", with: "")
        let description: String
        if size == 0 {
            description = "The local transcript file exists but is empty."
        } else if isTruncated {
            description = "Showing the last \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) from the local transcript file."
        } else {
            description = "Loaded the full local transcript file."
        }

        return TranscriptPreviewSnapshot(text: text, sourceDescription: description, isTruncated: isTruncated)
    }

    private func backfillTranscriptFileToMongo(
        session: TerminalMonitorSession,
        transcriptData: Data,
        settings: MongoMonitoringSettings,
        syncSource: String
    ) async throws -> [TerminalTranscriptChunk] {
        let chunks = Self.transcriptDataChunks(transcriptData, byteLimit: Self.transcriptChunkByteLimit)
        guard !chunks.isEmpty else { return [] }

        let capturedAtDates = Self.synthesizedTranscriptChunkCapturedAtDates(
            chunkCount: chunks.count,
            startedAt: session.startedAt,
            endedAt: session.activityDate
        )
        let source = session.captureMode.usesScriptKeyLogging
            ? "terminal_transcript_input_output"
            : "terminal_transcript_output_only"

        var persistedChunks: [TerminalTranscriptChunk] = []
        persistedChunks.reserveCapacity(chunks.count)

        for (index, chunkData) in chunks.enumerated() {
            let capturedAt = capturedAtDates[min(index, max(0, capturedAtDates.count - 1))]
            let preview = Self.cleanedPreview(from: chunkData, limit: settings.previewCharacterLimit)
            var chunkSession = Self.sessionByApplyingMongoTranscriptSyncProgress(
                source: syncSource,
                chunkCount: chunks.count,
                byteCount: transcriptData.count,
                synchronizedAt: capturedAt,
                verifiedComplete: true,
                to: session
            )
            chunkSession.chunkCount = chunks.count
            chunkSession.byteCount = transcriptData.count
            chunkSession.lastPreview = preview
            chunkSession.lastActivityAt = session.activityDate
            chunkSession.lastDatabaseMessage = "Backfilled transcript chunk \(index + 1) of \(chunks.count) from the local transcript file to MongoDB."

            try await writer.recordChunk(
                sessionID: session.id,
                chunkIndex: index + 1,
                data: chunkData,
                source: source,
                session: chunkSession,
                prompt: session.prompt,
                preview: preview,
                totalChunks: chunks.count,
                totalBytes: transcriptData.count,
                capturedAt: capturedAt,
                status: session.status,
                settings: settings
            )

            persistedChunks.append(
                TerminalTranscriptChunk(
                    id: Int64(-(index + 1)),
                    sessionID: session.id,
                    chunkIndex: index + 1,
                    source: source,
                    capturedAt: capturedAt,
                    byteCount: chunkData.count,
                    previewText: preview,
                    text: String(decoding: chunkData, as: UTF8.self).replacingOccurrences(of: "\u{0000}", with: ""),
                    promptSnapshot: session.prompt,
                    sessionStatus: session.status,
                    sessionStatusReason: session.statusReason,
                    sessionMessage: chunkSession.lastDatabaseMessage
                )
            )
        }

        return persistedChunks
    }

    private func synchronizeSessionTranscriptToMongoIfNeeded(
        session: TerminalMonitorSession,
        settings: MongoMonitoringSettings,
        syncSource: String
    ) async throws -> (session: TerminalMonitorSession, importedChunkCount: Int?) {
        guard settings.enableMongoWrites, session.hasLocalTranscriptFile else {
            return (session, nil)
        }

        let transcriptPath = NSString(string: session.transcriptPath).expandingTildeInPath
        let attributes = try FileManager.default.attributesOfItem(atPath: transcriptPath)
        let transcriptByteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard transcriptByteCount > 0 else {
            return (session, nil)
        }

        let localChunkCount = Self.transcriptChunkCount(
            forByteCount: transcriptByteCount,
            byteLimit: Self.transcriptChunkByteLimit
        )
        let databaseSummary = try await writer.fetchSessionChunkSummary(sessionID: session.id, settings: settings)
        guard Self.shouldBackfillTranscriptToMongo(
            localChunkCount: localChunkCount,
            localByteCount: Int(transcriptByteCount),
            databaseSummary: databaseSummary
        ) else {
            return (
                Self.sessionByApplyingMongoTranscriptSyncProgress(
                    source: syncSource,
                    chunkCount: databaseSummary.chunkCount,
                    byteCount: Int(databaseSummary.byteCount),
                    synchronizedAt: Date(),
                    verifiedComplete: true,
                    to: session
                ),
                nil
            )
        }

        let transcriptData = try await Self.readTranscriptDataInBackground(at: session.transcriptPath)
        let importedChunks = try await backfillTranscriptFileToMongo(
            session: session,
            transcriptData: transcriptData,
            settings: settings,
            syncSource: syncSource
        )
        guard !importedChunks.isEmpty else {
            return (session, nil)
        }

        var syncedSession = session
        syncedSession.chunkCount = max(session.chunkCount, importedChunks.count)
        syncedSession.byteCount = max(session.byteCount, transcriptData.count)
        syncedSession.lastPreview = importedChunks.last?.previewText ?? session.lastPreview
        syncedSession.lastActivityAt = max(session.lastActivityAt ?? .distantPast, session.activityDate)
        return (syncedSession, importedChunks.count)
    }

    private func backfillInputCaptureFileToMongo(
        session: TerminalMonitorSession,
        inputRecords: [ScriptRecordingRecord],
        settings: MongoMonitoringSettings,
        syncSource: String
    ) async throws {
        guard !inputRecords.isEmpty else { return }

        let totalByteCount = inputRecords.reduce(0) { $0 + $1.data.count }

        for (index, record) in inputRecords.enumerated() {
            let preview = Self.cleanedPreview(from: record.data, limit: settings.previewCharacterLimit)
            var inputSession = session
            inputSession.inputChunkCount = inputRecords.count
            inputSession.inputByteCount = totalByteCount
            inputSession.lastActivityAt = max(session.lastActivityAt ?? .distantPast, record.capturedAt)
            inputSession.lastDatabaseMessage = "Backfilled input chunk \(index + 1) of \(inputRecords.count) from the local raw stdin capture to MongoDB."
            if inputSession.inputCapturePath == nil {
                inputSession.inputCapturePath = session.inputCapturePath
            }

            try await writer.recordInputChunk(
                sessionID: session.id,
                inputIndex: index + 1,
                data: record.data,
                source: syncSource,
                session: inputSession,
                prompt: session.prompt,
                preview: preview,
                capturedAt: record.capturedAt,
                status: session.status,
                settings: settings
            )
        }
    }

    private func synchronizeSessionInputCaptureToMongoIfNeeded(
        session: TerminalMonitorSession,
        settings: MongoMonitoringSettings,
        syncSource: String
    ) async throws -> (session: TerminalMonitorSession, importedChunkCount: Int?) {
        guard settings.enableMongoWrites, session.hasLocalInputCaptureFile, let inputCapturePath = session.inputCapturePath else {
            return (session, nil)
        }

        let inputRecords = try await Self.readInputCaptureRecordsInBackground(at: inputCapturePath)
        guard !inputRecords.isEmpty else {
            return (session, nil)
        }

        let localByteCount = inputRecords.reduce(0) { $0 + $1.data.count }
        let databaseSummary = try await writer.fetchSessionInputChunkSummary(sessionID: session.id, settings: settings)
        guard Self.shouldBackfillTranscriptToMongo(
            localChunkCount: inputRecords.count,
            localByteCount: localByteCount,
            databaseSummary: databaseSummary
        ) else {
            return (
                Self.sessionByApplyingMongoInputSyncProgress(
                    source: syncSource,
                    chunkCount: databaseSummary.chunkCount,
                    byteCount: Int(databaseSummary.byteCount),
                    synchronizedAt: Date(),
                    verifiedComplete: true,
                    to: session
                ),
                nil
            )
        }

        try await backfillInputCaptureFileToMongo(
            session: session,
            inputRecords: inputRecords,
            settings: settings,
            syncSource: syncSource
        )

        var syncedSession = session
        syncedSession.inputChunkCount = max(session.inputChunkCount, inputRecords.count)
        syncedSession.inputByteCount = max(session.inputByteCount, localByteCount)
        syncedSession.lastActivityAt = max(session.lastActivityAt ?? .distantPast, session.activityDate)
        return (
            Self.sessionByApplyingMongoInputSyncProgress(
                source: syncSource,
                chunkCount: syncedSession.inputChunkCount,
                byteCount: syncedSession.inputByteCount,
                synchronizedAt: syncedSession.activityDate,
                verifiedComplete: true,
                to: syncedSession
            ),
            inputRecords.count
        )
    }

    nonisolated private static func readTranscriptData(at path: String) throws -> Data {
        let expanded = NSString(string: path).expandingTildeInPath
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: expanded))
        defer { try? handle.close() }
        return try handle.readToEnd() ?? Data()
    }

    nonisolated private static func readTranscriptDataInBackground(at path: String) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try readTranscriptData(at: path)
        }.value
    }

    nonisolated static func parseScriptRecordingData(_ data: Data) -> (records: [ScriptRecordingRecord], trailingData: Data) {
        var records: [ScriptRecordingRecord] = []
        var offset = 0

        while offset + 24 <= data.count {
            guard let dataLengthValue = littleEndianUInt64(in: data, at: offset),
                  let secondsValue = littleEndianUInt64(in: data, at: offset + 8),
                  let microsecondsValue = littleEndianUInt32(in: data, at: offset + 16),
                  let directionValue = littleEndianUInt32(in: data, at: offset + 20) else {
                break
            }

            let dataLength = Int(dataLengthValue)
            let recordLength = 24 + dataLength
            guard dataLength >= 0, offset + recordLength <= data.count else {
                break
            }

            let capturedAt = Date(
                timeIntervalSince1970: TimeInterval(secondsValue) + (TimeInterval(microsecondsValue) / 1_000_000)
            )
            let directionScalar = UnicodeScalar(Int(directionValue & 0xff)) ?? UnicodeScalar(32)!
            let direction = Character(directionScalar)
            let payload = data.subdata(in: (offset + 24)..<(offset + recordLength))
            records.append(
                ScriptRecordingRecord(
                    dataLength: dataLength,
                    capturedAt: capturedAt,
                    direction: direction,
                    data: payload
                )
            )
            offset += recordLength
        }

        return (records, data.subdata(in: offset..<data.count))
    }

    nonisolated private static func readInputCaptureRecords(at path: String) throws -> [ScriptRecordingRecord] {
        let inputData = try readTranscriptData(at: path)
        let parsed = parseScriptRecordingData(inputData)
        return parsed.records.filter { $0.direction == "i" && !$0.data.isEmpty }
    }

    nonisolated private static func readInputCaptureRecordsInBackground(at path: String) async throws -> [ScriptRecordingRecord] {
        try await Task.detached(priority: .utility) {
            try readInputCaptureRecords(at: path)
        }.value
    }

    nonisolated private static func readInputCaptureChunks(
        at path: String,
        previewCharacterLimit: Int,
        sessionID: UUID,
        prompt: String,
        status: TerminalMonitorStatus,
        statusReason: String?,
        message: String
    ) throws -> [TerminalInputChunk] {
        let records = try readInputCaptureRecords(at: path)
        var inputChunks: [TerminalInputChunk] = []
        inputChunks.reserveCapacity(records.count)

        var inputIndex = 0
        for record in records {
            inputIndex += 1
            let preview = cleanedPreview(from: record.data, limit: previewCharacterLimit)
            inputChunks.append(
                TerminalInputChunk(
                    id: Int64(-inputIndex),
                    sessionID: sessionID,
                    inputIndex: inputIndex,
                    source: "terminal_stdin_raw_file",
                    capturedAt: record.capturedAt,
                    byteCount: record.data.count,
                    previewText: preview,
                    text: String(decoding: record.data, as: UTF8.self).replacingOccurrences(of: "\u{0000}", with: ""),
                    promptSnapshot: prompt,
                    sessionStatus: status,
                    sessionStatusReason: statusReason,
                    sessionMessage: message
                )
            )
        }

        return inputChunks
    }

    nonisolated private static func loadLocalDetailArtifacts(
        for session: TerminalMonitorSession,
        settings: MongoMonitoringSettings,
        includesHistory: Bool
    ) async -> LocalDetailArtifacts {
        await Task.detached(priority: .utility) {
            var artifacts = LocalDetailArtifacts()

            if session.hasLocalTranscriptFile {
                do {
                    let snapshot = try readTranscriptPreview(
                        at: session.transcriptPath,
                        maxBytes: settings.clampedTranscriptPreviewByteLimit
                    )
                    artifacts.transcriptText = snapshot.text
                    artifacts.transcriptSource = snapshot.sourceDescription
                    artifacts.transcriptTruncated = snapshot.isTruncated
                    artifacts.loadNotes.append(snapshot.sourceDescription)
                } catch {
                    artifacts.loadNotes.append("Local transcript read failed: \(error.localizedDescription)")
                }
            } else {
                artifacts.loadNotes.append("No local transcript file was found.")
            }

            if includesHistory,
               session.hasLocalInputCaptureFile,
               let inputCapturePath = session.inputCapturePath {
                do {
                    artifacts.inputChunks = try readInputCaptureChunks(
                        at: inputCapturePath,
                        previewCharacterLimit: settings.previewCharacterLimit,
                        sessionID: session.id,
                        prompt: session.prompt,
                        status: session.status,
                        statusReason: session.statusReason,
                        message: session.lastDatabaseMessage
                    )
                } catch {
                    artifacts.loadNotes.append("Local stdin capture read failed: \(error.localizedDescription)")
                }
            }

            return artifacts
        }.value
    }

    nonisolated private static func littleEndianUInt64(in data: Data, at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << UInt64(index * 8)
        }
        return value
    }

    nonisolated private static func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(data[offset + index]) << UInt32(index * 8)
        }
        return value
    }

    nonisolated static func transcriptDataChunks(_ data: Data, byteLimit: Int) -> [Data] {
        let resolvedByteLimit = max(1, byteLimit)
        guard !data.isEmpty else { return [] }

        var chunks: [Data] = []
        var sliceStart = 0
        while sliceStart < data.count {
            let sliceEnd = min(sliceStart + resolvedByteLimit, data.count)
            chunks.append(data.subdata(in: sliceStart..<sliceEnd))
            sliceStart = sliceEnd
        }
        return chunks
    }

    nonisolated static func transcriptChunkCount(forByteCount byteCount: Int64, byteLimit: Int) -> Int {
        let resolvedByteLimit = max(1, byteLimit)
        guard byteCount > 0 else { return 0 }
        return Int((byteCount + Int64(resolvedByteLimit - 1)) / Int64(resolvedByteLimit))
    }

    nonisolated static func transcriptSynchronizationMessage(
        for context: TranscriptSynchronizationContext,
        importedChunkCount: Int
    ) -> String {
        switch context {
        case .completionSuccess:
            return "Completed session transcript synchronized to MongoDB (\(importedChunkCount) chunks)."
        case .completionFailure:
            return "Non-zero session transcript synchronized to MongoDB (\(importedChunkCount) chunks)."
        case .monitoringFailure:
            return "Monitoring failed, but the session transcript was synchronized to MongoDB (\(importedChunkCount) chunks)."
        case .recentSessionRefresh:
            return "Historical session transcript synchronized to MongoDB (\(importedChunkCount) chunks)."
        case .directoryRecovery:
            return "Recovered local transcript into MongoDB (\(importedChunkCount) chunks)."
        }
    }

    nonisolated static func inputSynchronizationMessage(
        for context: TranscriptSynchronizationContext,
        importedChunkCount: Int
    ) -> String {
        switch context {
        case .completionSuccess:
            return "Completed session raw input synchronized to MongoDB (\(importedChunkCount) chunks)."
        case .completionFailure:
            return "Non-zero session raw input synchronized to MongoDB (\(importedChunkCount) chunks)."
        case .monitoringFailure:
            return "Monitoring failed, but the raw input capture was synchronized to MongoDB (\(importedChunkCount) chunks)."
        case .recentSessionRefresh:
            return "Historical session raw input synchronized to MongoDB (\(importedChunkCount) chunks)."
        case .directoryRecovery:
            return "Recovered local raw input capture into MongoDB (\(importedChunkCount) chunks)."
        }
    }

    nonisolated static func inputSynchronizationEventType(recoveredWithoutDatabaseSession: Bool) -> String {
        recoveredWithoutDatabaseSession ? "session_input_capture_recovered" : "session_input_capture_synchronized"
    }

    nonisolated static func completionSyncFailureMessage(
        error: String,
        retainedRawInputCapture: Bool
    ) -> String {
        if retainedRawInputCapture {
            return "MongoDB completion sync failed; local transcript and raw input files were retained: \(error)"
        }
        return "MongoDB completion sync failed; local transcript file was retained: \(error)"
    }

    nonisolated static func sessionByApplyingMongoTranscriptSyncProgress(
        source: String,
        chunkCount: Int,
        byteCount: Int,
        synchronizedAt: Date,
        verifiedComplete: Bool,
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        var updated = session
        updated.mongoTranscriptSyncState = verifiedComplete ? .complete : .streaming
        updated.mongoTranscriptSyncSource = source
        updated.mongoTranscriptChunkCount = chunkCount
        updated.mongoTranscriptByteCount = byteCount
        updated.mongoTranscriptSynchronizedAt = synchronizedAt
        return updated
    }

    nonisolated static func sessionByApplyingMongoTranscriptCompletionFromDatabaseSummaryIfNeeded(
        _ summary: MongoSessionChunkSummary,
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        guard summary.chunkCount > 0 else { return session }
        guard summary.hasContiguousChunkIndexes else { return session }
        guard summary.chunkCount >= session.chunkCount,
              Int(summary.byteCount) >= session.byteCount else {
            return session
        }

        let completionSource = session.mongoTranscriptSyncSource ?? "live_chunk_capture"
        let completionDate = session.mongoTranscriptSynchronizedAt ?? session.activityDate
        return sessionByApplyingMongoTranscriptSyncProgress(
            source: completionSource,
            chunkCount: summary.chunkCount,
            byteCount: Int(summary.byteCount),
            synchronizedAt: completionDate,
            verifiedComplete: true,
            to: session
        )
    }

    nonisolated static func sessionByApplyingMongoInputSyncProgress(
        source: String,
        chunkCount: Int,
        byteCount: Int,
        synchronizedAt: Date,
        verifiedComplete: Bool,
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        var updated = session
        updated.mongoInputSyncState = verifiedComplete ? .complete : .streaming
        updated.mongoInputSyncSource = source
        updated.mongoInputChunkCount = chunkCount
        updated.mongoInputByteCount = byteCount
        updated.mongoInputSynchronizedAt = synchronizedAt
        return updated
    }

    nonisolated static func sessionByApplyingMongoInputSyncCompletionFromDatabaseSummaryIfNeeded(
        _ summary: MongoSessionChunkSummary,
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        guard summary.chunkCount > 0 else { return session }
        guard summary.hasContiguousChunkIndexes else { return session }
        guard summary.chunkCount >= session.inputChunkCount,
              Int(summary.byteCount) >= session.inputByteCount else {
            return session
        }

        let completionSource = session.mongoInputSyncSource ?? "live_input_capture"
        let completionDate = session.mongoInputSynchronizedAt ?? session.activityDate
        return sessionByApplyingMongoInputSyncProgress(
            source: completionSource,
            chunkCount: summary.chunkCount,
            byteCount: Int(summary.byteCount),
            synchronizedAt: completionDate,
            verifiedComplete: true,
            to: session
        )
    }

    nonisolated static func shouldDeleteLocalTranscriptAfterCompletion(
        completedSuccessfully: Bool,
        keepLocalTranscriptFiles: Bool,
        enableMongoWrites: Bool,
        mongoSyncSucceeded: Bool
    ) -> Bool {
        guard completedSuccessfully, !keepLocalTranscriptFiles else { return false }
        guard enableMongoWrites else { return true }
        return mongoSyncSucceeded
    }

    nonisolated static func shouldDeleteLocalCaptureFilesAfterClear(
        enableMongoWrites: Bool,
        databaseClearSucceeded: Bool
    ) -> Bool {
        guard enableMongoWrites else { return true }
        return databaseClearSucceeded
    }

    private func recordInputSynchronizationStatusIfNeeded(
        session: TerminalMonitorSession,
        context: TranscriptSynchronizationContext,
        syncSource: String,
        trigger: String?,
        recoveredWithoutDatabaseSession: Bool,
        importedChunkCount: Int?,
        settings: MongoMonitoringSettings
    ) async throws -> TerminalMonitorSession {
        var syncedSession = session
        guard let importedChunkCount else {
            if syncedSession.mongoInputSyncState == .complete {
                try await writer.recordSessionSnapshot(syncedSession, settings: settings)
            }
            return syncedSession
        }

        syncedSession.lastDatabaseMessage = Self.inputSynchronizationMessage(
            for: context,
            importedChunkCount: importedChunkCount
        )

        var metadata: [String: Any] = [
            "source": syncSource,
            "imported_chunks": importedChunkCount,
            "total_chunks": syncedSession.inputChunkCount,
            "total_bytes": syncedSession.inputByteCount
        ]
        if let trigger {
            metadata["trigger"] = trigger
        }
        if recoveredWithoutDatabaseSession {
            metadata["recovered_without_database_session"] = true
        }

        try await writer.recordStatus(
            session: syncedSession,
            status: syncedSession.status,
            eventType: Self.inputSynchronizationEventType(recoveredWithoutDatabaseSession: recoveredWithoutDatabaseSession),
            message: syncedSession.lastDatabaseMessage,
            eventAt: syncedSession.activityDate,
            endedAt: syncedSession.endedAt,
            statusReason: syncedSession.statusReason,
            exitCode: syncedSession.exitCode,
            metadata: metadata,
            settings: settings
        )
        return syncedSession
    }

    nonisolated private static func mergedDistinctSessions(_ sessions: [TerminalMonitorSession]) -> [TerminalMonitorSession] {
        var seenIDs: Set<UUID> = []
        var merged: [TerminalMonitorSession] = []
        merged.reserveCapacity(sessions.count)

        for session in sessions.sorted(by: { Self.sessionActivityDate($0) > Self.sessionActivityDate($1) }) {
            guard !seenIDs.contains(session.id) else { continue }
            seenIDs.insert(session.id)
            merged.append(session)
        }

        return merged
    }

    nonisolated static func shouldBackfillTranscriptToMongo(
        localChunkCount: Int,
        localByteCount: Int,
        databaseSummary: MongoSessionChunkSummary
    ) -> Bool {
        guard localChunkCount > 0, localByteCount > 0 else { return false }
        return !databaseSummary.hasContiguousChunkIndexes ||
            databaseSummary.chunkCount < localChunkCount ||
            databaseSummary.byteCount < Int64(localByteCount)
    }

    nonisolated static func synthesizedTranscriptChunkCapturedAtDates(
        chunkCount: Int,
        startedAt: Date,
        endedAt: Date
    ) -> [Date] {
        guard chunkCount > 0 else { return [] }
        guard chunkCount > 1 else { return [endedAt] }

        let startTime = startedAt.timeIntervalSinceReferenceDate
        let endTime = max(startTime, endedAt.timeIntervalSinceReferenceDate)
        let span = endTime - startTime
        guard span > 0 else {
            return Array(repeating: endedAt, count: chunkCount)
        }

        return (0..<chunkCount).map { index in
            let progress = Double(index) / Double(max(1, chunkCount - 1))
            return Date(timeIntervalSinceReferenceDate: startTime + (span * progress))
        }
    }

    nonisolated static func mongoTranscriptSourceDescription(
        for chunks: [TerminalTranscriptChunk],
        truncated: Bool
    ) -> String {
        let sourceLabels = Array(
            NSOrderedSet(array: chunks.map(\.sourceDisplayName).filter { !$0.isEmpty })
        ) as? [String] ?? []
        let sourceSummary: String
        switch sourceLabels.count {
        case 0:
            sourceSummary = "MongoDB transcript chunks"
        case 1:
            sourceSummary = sourceLabels[0]
        default:
            sourceSummary = sourceLabels.joined(separator: ", ")
        }

        if truncated {
            return "Reconstructed from the latest \(chunks.count) MongoDB chunk(s) using \(sourceSummary)."
        }
        return "Reconstructed from MongoDB chunk(s) using \(sourceSummary)."
    }

    nonisolated static func normalizedLegacyTranscriptChunkSource(
        for captureMode: TerminalTranscriptCaptureMode
    ) -> String {
        captureMode.usesScriptKeyLogging
            ? "terminal_transcript_input_output"
            : "terminal_transcript_output_only"
    }

    nonisolated static func normalizedTranscriptChunks(
        _ chunks: [TerminalTranscriptChunk],
        captureMode: TerminalTranscriptCaptureMode
    ) -> [TerminalTranscriptChunk] {
        let normalizedSource = normalizedLegacyTranscriptChunkSource(for: captureMode)
        return chunks.map { chunk in
            let cleanedSource = chunk.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard cleanedSource == "terminal_transcript" else {
                return chunk
            }
            var updatedChunk = chunk
            updatedChunk.source = normalizedSource
            return updatedChunk
        }
    }

    private func protectedTranscriptPaths() -> Set<String> {
        let activeStatuses: Set<TerminalMonitorStatus> = [.prepared, .launching, .monitoring, .idle]
        let activeTranscriptPaths = sessions
            .filter { activeStatuses.contains($0.status) && !$0.isHistorical }
            .map { NSString(string: $0.transcriptPath).expandingTildeInPath }
        let activeInputCapturePaths = sessions
            .filter { activeStatuses.contains($0.status) && !$0.isHistorical }
            .compactMap(\.inputCapturePath)
            .map { NSString(string: $0).expandingTildeInPath }

        var protectedPaths = Set(activeTranscriptPaths + activeInputCapturePaths)
        for path in activeTranscriptPaths {
            protectedPaths.insert(path + ".exit")
        }
        return protectedPaths
    }

    nonisolated private static func scanTranscriptDirectory(at path: String) -> MongoStorageSummary {
        let inventory = transcriptInventory(at: path)
        return MongoStorageSummary(
            transcriptFileCount: inventory.transcriptFileCount,
            transcriptFileBytes: inventory.transcriptFileBytes,
            oldestTranscriptFileAt: inventory.oldestTranscriptFileAt,
            newestTranscriptFileAt: inventory.newestTranscriptFileAt,
            inputCaptureFileCount: inventory.inputCaptureFileCount,
            inputCaptureFileBytes: inventory.inputCaptureFileBytes,
            oldestInputCaptureFileAt: inventory.oldestInputCaptureFileAt,
            newestInputCaptureFileAt: inventory.newestInputCaptureFileAt
        )
    }

    nonisolated private static func scanTranscriptDirectoryInBackground(at path: String) async -> MongoStorageSummary {
        await Task.detached(priority: .utility) {
            scanTranscriptDirectory(at: path)
        }.value
    }

    nonisolated private static func transcriptInventory(at path: String) -> LocalTranscriptInventory {
        let fm = FileManager.default
        let expanded = NSString(string: path).expandingTildeInPath
        var inventory = LocalTranscriptInventory()

        guard fm.fileExists(atPath: expanded),
              let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: expanded),
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return inventory
        }

        for case let fileURL as URL in enumerator {
            guard (isManagedTranscriptFile(fileURL) || isManagedInputCaptureFile(fileURL)),
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]),
                  values.isRegularFile == true
            else {
                continue
            }

            let modifiedAt = values.contentModificationDate ?? values.creationDate ?? Date.distantPast
            let size = Int64(values.fileSize ?? 0)
            if isManagedTranscriptFile(fileURL) {
                inventory.transcriptFileCount += 1
                inventory.transcriptFileBytes += size

                if let oldest = inventory.oldestTranscriptFileAt {
                    inventory.oldestTranscriptFileAt = min(oldest, modifiedAt)
                } else {
                    inventory.oldestTranscriptFileAt = modifiedAt
                }

                if let newest = inventory.newestTranscriptFileAt {
                    inventory.newestTranscriptFileAt = max(newest, modifiedAt)
                } else {
                    inventory.newestTranscriptFileAt = modifiedAt
                }
            } else {
                inventory.inputCaptureFileCount += 1
                inventory.inputCaptureFileBytes += size

                if let oldest = inventory.oldestInputCaptureFileAt {
                    inventory.oldestInputCaptureFileAt = min(oldest, modifiedAt)
                } else {
                    inventory.oldestInputCaptureFileAt = modifiedAt
                }

                if let newest = inventory.newestInputCaptureFileAt {
                    inventory.newestInputCaptureFileAt = max(newest, modifiedAt)
                } else {
                    inventory.newestInputCaptureFileAt = modifiedAt
                }
            }
        }

        return inventory
    }

    nonisolated static func recoveredTranscriptSessions(
        at path: String,
        olderThanDays: Int? = nil,
        protectedPaths: Set<String> = [],
        excludingSessionIDs: Set<UUID> = []
    ) -> [TerminalMonitorSession] {
        let fm = FileManager.default
        let expanded = NSString(string: path).expandingTildeInPath
        let cutoffDate = olderThanDays.map { Date().addingTimeInterval(-TimeInterval(max(1, $0)) * 86_400) }
        let normalizedProtectedPaths = Set(protectedPaths.flatMap { Self.pathAliases(forManagedFilePath: $0) })

        guard fm.fileExists(atPath: expanded),
              let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: expanded),
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        var sessions: [TerminalMonitorSession] = []

        for case let fileURL as URL in enumerator {
            let filePath = fileURL.path
            let filePathAliases = Self.pathAliases(forManagedFilePath: filePath)
            if !normalizedProtectedPaths.isDisjoint(with: filePathAliases) {
                continue
            }
            if let cutoffDate,
               let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]),
               let modifiedAt = values.contentModificationDate ?? values.creationDate,
               modifiedAt >= cutoffDate {
                continue
            }
            guard isManagedTranscriptFile(fileURL),
                  let session = recoveredTranscriptSessionIfManagedFile(fileURL),
                  !excludingSessionIDs.contains(session.id)
            else {
                continue
            }
            sessions.append(session)
        }

        return sessions.sorted(by: { Self.sessionActivityDate($0) > Self.sessionActivityDate($1) })
    }

    nonisolated private static func pruneTranscriptDirectory(at path: String, olderThanDays: Int, protectedPaths: Set<String>) -> LocalTranscriptPruneResult {
        let fm = FileManager.default
        let expanded = NSString(string: path).expandingTildeInPath
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(max(1, olderThanDays)) * 86_400)
        let normalizedProtectedPaths = Set(protectedPaths.flatMap { Self.pathAliases(forManagedFilePath: $0) })
        var result = LocalTranscriptPruneResult()

        guard fm.fileExists(atPath: expanded),
              let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: expanded),
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return result
        }

        for case let fileURL as URL in enumerator {
            let filePath = fileURL.path
            let filePathAliases = Self.pathAliases(forManagedFilePath: filePath)
            guard normalizedProtectedPaths.isDisjoint(with: filePathAliases),
                  isManagedTranscriptFile(fileURL) || isManagedCompletionMarkerFile(fileURL) || isManagedInputCaptureFile(fileURL),
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]),
                  values.isRegularFile == true
            else {
                continue
            }

            let modifiedAt = values.contentModificationDate ?? values.creationDate ?? Date.distantPast
            guard modifiedAt < cutoffDate else { continue }

            do {
                try fm.removeItem(at: fileURL)
                if isManagedTranscriptFile(fileURL) {
                    result.deletedTranscriptFileCount += 1
                    result.deletedTranscriptBytes += Int64(values.fileSize ?? 0)
                } else if isManagedInputCaptureFile(fileURL) {
                    result.deletedInputCaptureFileCount += 1
                    result.deletedInputCaptureBytes += Int64(values.fileSize ?? 0)
                }
            } catch {
                continue
            }
        }

        return result
    }

    nonisolated static func recoveredTranscriptSessionIfManagedFile(_ fileURL: URL) -> TerminalMonitorSession? {
        guard isManagedTranscriptFile(fileURL),
              let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]),
              values.isRegularFile == true
        else {
            return nil
        }

        let filename = fileURL.deletingPathExtension().lastPathComponent
        guard filename.count > 17 else { return nil }

        let timestampEndIndex = filename.index(filename.startIndex, offsetBy: 15)
        let timestampText = String(filename[..<timestampEndIndex])
        guard filename[timestampEndIndex] == "-" else { return nil }

        let remainderStartIndex = filename.index(after: timestampEndIndex)
        let remainder = filename[remainderStartIndex...]
        guard let agentSeparatorIndex = remainder.firstIndex(of: "-") else { return nil }

        let agentRawValue = String(remainder[..<agentSeparatorIndex])
        let sessionIDText = String(remainder[remainder.index(after: agentSeparatorIndex)...])
        guard let agentKind = AgentKind(rawValue: agentRawValue),
              let sessionID = UUID(uuidString: sessionIDText)
        else {
            return nil
        }

        let modifiedAt = values.contentModificationDate ?? values.creationDate ?? Date.distantPast
        let createdAt = values.creationDate ?? modifiedAt
        let startedAt = parseTranscriptFilenameTimestamp(timestampText) ?? createdAt
        let byteCount = values.fileSize ?? 0
        let completion = readCompletionMarker(at: fileURL.path + ".exit")
        let inputCapturePath = fileURL.path + ".stdinrec"
        let hasInputCaptureFile = FileManager.default.fileExists(atPath: inputCapturePath)

        var session = TerminalMonitorSession(
            id: sessionID,
            profileID: nil,
            profileName: "\(agentKind.displayName) (Recovered Transcript)",
            agentKind: agentKind,
            workingDirectory: "",
            transcriptPath: fileURL.path,
            launchCommand: "Recovered from local transcript file",
            captureMode: hasInputCaptureFile ? .inputAndOutput : .outputOnly
        )
        session.inputCapturePath = hasInputCaptureFile ? inputCapturePath : nil
        session.startedAt = startedAt
        session.lastActivityAt = completion?.endedAt ?? modifiedAt
        session.endedAt = completion?.endedAt
        session.chunkCount = transcriptChunkCount(forByteCount: Int64(byteCount), byteLimit: transcriptChunkByteLimit)
        session.byteCount = byteCount
        session.status = completion.map { $0.exitCode == 0 ? .completed : .failed } ?? .idle
        session.lastDatabaseMessage = "Recovered local transcript file pending MongoDB import."
        session.statusReason = completion?.reason ?? "recovered_local_transcript"
        session.exitCode = completion?.exitCode
        session.isHistorical = true
        return session
    }

    nonisolated private static func parseTranscriptFilenameTimestamp(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }

    nonisolated private static func isManagedTranscriptFile(_ fileURL: URL) -> Bool {
        fileURL.lastPathComponent.hasSuffix(".typescript")
    }

    nonisolated private static func isManagedCompletionMarkerFile(_ fileURL: URL) -> Bool {
        fileURL.lastPathComponent.hasSuffix(".typescript.exit")
    }

    nonisolated private static func isManagedInputCaptureFile(_ fileURL: URL) -> Bool {
        fileURL.lastPathComponent.hasSuffix(".typescript.stdinrec")
    }

    nonisolated private static func pathAliases(forManagedFilePath path: String) -> Set<String> {
        let expanded = NSString(string: path).expandingTildeInPath
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        var aliases: Set<String> = [expanded, standardized]

        for alias in Array(aliases) {
            if alias.hasPrefix("/private/var/") {
                aliases.insert(String(alias.dropFirst("/private".count)))
            } else if alias.hasPrefix("/var/") {
                aliases.insert("/private" + alias)
            }
        }

        return aliases
    }

    nonisolated private static func describe(pruneSummary: MongoPruneSummary) -> String {
        let transcriptBytes = ByteCountFormatter.string(fromByteCount: pruneSummary.deletedTranscriptBytes, countStyle: .file)
        let inputBytes = ByteCountFormatter.string(fromByteCount: pruneSummary.deletedInputCaptureBytes, countStyle: .file)
        let chunkBytes = ByteCountFormatter.string(fromByteCount: pruneSummary.deletedChunkBytes, countStyle: .file)
        let inputChunkBytes = ByteCountFormatter.string(fromByteCount: pruneSummary.deletedInputChunkBytes, countStyle: .file)
        return [
            "Pruned data older than \(pruneSummary.cutoffDate.formatted(date: .abbreviated, time: .omitted)).",
            "Deleted \(pruneSummary.deletedSessions) session(s), \(pruneSummary.deletedChunks) transcript chunk(s) (\(chunkBytes)), \(pruneSummary.deletedInputChunks) raw input chunk(s) (\(inputChunkBytes)), and \(pruneSummary.deletedEvents) event row(s) from MongoDB.",
            "Deleted \(pruneSummary.deletedTranscriptFiles) local transcript file(s) (\(transcriptBytes)) and \(pruneSummary.deletedInputCaptureFiles) local raw input capture(s) (\(inputBytes))."
        ].joined(separator: " ")
    }

    nonisolated private static func cleanedPreview(from data: Data, limit: Int) -> String {
        let raw = String(decoding: data, as: UTF8.self)
        var cleaned = String()
        cleaned.reserveCapacity(raw.count)

        for scalar in raw.unicodeScalars {
            if scalar == "\u{0000}" {
                continue
            }
            if scalar.value < 0x20, scalar != "\n", scalar != "\r", scalar != "\t" {
                cleaned.append(" ")
            } else {
                cleaned.unicodeScalars.append(scalar)
            }
        }

        if cleaned.count > limit {
            let end = cleaned.index(cleaned.startIndex, offsetBy: min(limit, cleaned.count))
            return String(cleaned[..<end]) + "…"
        }
        return cleaned
    }

    nonisolated static func extractGeminiSessionStats(fromTranscriptText text: String) -> GeminiSessionStatsSnapshot? {
        extractGeminiSessionStatsCaptures(fromTranscriptText: text).last?.snapshot
    }

    nonisolated static func extractGeminiModelCapacity(fromTranscriptText text: String) -> GeminiModelCapacitySnapshot? {
        extractGeminiModelCapacityCaptures(fromTranscriptText: text).last?.snapshot
    }

    nonisolated static func extractGeminiStartupStatsCommand(fromTranscriptText text: String) -> String? {
        extractLatestGeminiStartupStatsCommandMatch(fromNormalizedLines: normalizedSessionStatsLines(from: text))?.command
    }

    nonisolated static func extractGeminiStartupStatsCommandSource(fromTranscriptText text: String) -> String? {
        extractLatestGeminiStartupStatsCommandMatch(fromNormalizedLines: normalizedSessionStatsLines(from: text))?.source
    }

    nonisolated static func extractGeminiStartupStatsFallbackCommand(fromTranscriptText text: String) -> String? {
        extractGeminiSessionStatsFallbackNotices(fromTranscriptText: text).last?.toCommand
    }

    nonisolated static func sessionByApplyingGeminiSessionStats(
        _ snapshot: GeminiSessionStatsSnapshot,
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        var updatedSession = session
        updatedSession.providerSessionID = snapshot.sessionID
        if let authMethod = snapshot.authMethod?.trimmingCharacters(in: .whitespacesAndNewlines), !authMethod.isEmpty {
            updatedSession.providerAuthMethod = authMethod
        }
        if let tier = snapshot.tier?.trimmingCharacters(in: .whitespacesAndNewlines), !tier.isEmpty {
            updatedSession.providerTier = tier
        }
        if let startupStatsCommand = snapshot.startupStatsCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !startupStatsCommand.isEmpty {
            let existingStartupStatsCommand = updatedSession.providerStartupStatsCommand?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existingStartupStatsCommand.isEmpty {
                updatedSession.providerStartupStatsCommand = startupStatsCommand
            }
        }
        if let startupStatsCommandSource = snapshot.startupStatsCommandSource?.trimmingCharacters(in: .whitespacesAndNewlines), !startupStatsCommandSource.isEmpty {
            let existingStartupStatsCommandSource = updatedSession.providerStartupStatsCommandSource?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existingStartupStatsCommandSource.isEmpty {
                updatedSession.providerStartupStatsCommandSource = startupStatsCommandSource
            }
        }
        if let accountIdentifier = snapshot.accountIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !accountIdentifier.isEmpty {
            updatedSession.accountIdentifier = accountIdentifier
        }
        if let modelUsageNote = snapshot.modelUsageNote?.trimmingCharacters(in: .whitespacesAndNewlines), !modelUsageNote.isEmpty {
            let existingModelUsageNote = updatedSession.providerModelUsageNote?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existingModelUsageNote.isEmpty {
                updatedSession.providerModelUsageNote = modelUsageNote
            }
        }
        if !snapshot.modelUsage.isEmpty {
            if updatedSession.providerModelUsage?.isEmpty ?? true {
                updatedSession.providerModelUsage = snapshot.modelUsage
            }
        }
        return updatedSession
    }

    nonisolated static func sessionByApplyingGeminiModelCapacity(
        _ snapshot: GeminiModelCapacitySnapshot,
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        var updatedSession = session
        if let startupModelCommand = snapshot.startupModelCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !startupModelCommand.isEmpty {
            let existingCommand = updatedSession.providerStartupModelCommand?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existingCommand.isEmpty {
                updatedSession.providerStartupModelCommand = startupModelCommand
            }
        }
        if let startupModelCommandSource = snapshot.startupModelCommandSource?.trimmingCharacters(in: .whitespacesAndNewlines), !startupModelCommandSource.isEmpty {
            let existingSource = updatedSession.providerStartupModelCommandSource?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existingSource.isEmpty {
                updatedSession.providerStartupModelCommandSource = startupModelCommandSource
            }
        }
        if let currentModel = snapshot.currentModel?.trimmingCharacters(in: .whitespacesAndNewlines), !currentModel.isEmpty {
            updatedSession.providerCurrentModel = currentModel
        }
        if !snapshot.rows.isEmpty {
            updatedSession.providerModelCapacity = snapshot.rows
        }
        if !snapshot.rawLines.isEmpty {
            updatedSession.providerModelCapacityRawLines = snapshot.rawLines
        }
        return updatedSession
    }

    nonisolated static func extractGeminiSessionStatsSkipReason(fromTranscriptText text: String) -> String? {
        extractGeminiSessionStatsSkipNotices(fromTranscriptText: text).last?.reason
    }

    nonisolated static func extractGeminiSessionStatsBlockedReason(fromTranscriptText text: String) -> String? {
        extractGeminiSessionStatsBlockedNotices(fromTranscriptText: text).last?.reason
    }

    nonisolated static func extractGeminiCompatibilityOverrideReason(fromTranscriptText text: String) -> String? {
        extractGeminiCompatibilityOverrideNotices(fromTranscriptText: text).last?.reason
    }

    nonisolated static func extractGeminiFreshSessionResetReason(fromTranscriptText text: String) -> String? {
        extractGeminiFreshSessionResetNotices(fromTranscriptText: text).last?.reason
    }

    nonisolated static func extractGeminiLaunchContext(fromTranscriptText text: String) -> GeminiLaunchContextSnapshot? {
        extractGeminiLaunchContextNotices(fromTranscriptText: text).last?.snapshot
    }

    nonisolated static func extractGeminiTranscriptInteractionNotices(fromTranscriptText text: String) -> [GeminiTranscriptInteractionNotice] {
        let lines = normalizedSessionStatsLines(from: text)
        guard !lines.isEmpty else { return [] }

        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(">") else { return nil }

            let interactionText = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !interactionText.isEmpty else { return nil }

            let normalizedText = interactionText.replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            let kind: GeminiTranscriptInteractionKind = normalizedText.hasPrefix("/") ? .slashCommand : .prompt
            return GeminiTranscriptInteractionNotice(
                fingerprint: "\(kind.rawValue):\(normalizedText.lowercased())",
                text: normalizedText,
                kind: kind,
                source: "echoed_transcript"
            )
        }
    }

    nonisolated static func extractGeminiStartupClearCommand(fromTranscriptText text: String) -> String? {
        extractLatestGeminiStartupClearCommandMatch(fromNormalizedLines: normalizedSessionStatsLines(from: text))?.command
    }

    nonisolated static func extractGeminiStartupClearCommandSource(fromTranscriptText text: String) -> String? {
        extractLatestGeminiStartupClearCommandMatch(fromNormalizedLines: normalizedSessionStatsLines(from: text))?.source
    }

    nonisolated static func extractGeminiStartupClearCompletionReason(fromTranscriptText text: String) -> String? {
        extractGeminiStartupClearCompletedNotices(fromTranscriptText: text).last?.reason
    }

    nonisolated static func sessionByApplyingGeminiStartupClear(
        _ notice: GeminiStartupClearNotice,
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        var updatedSession = session
        let existingCommand = updatedSession.providerStartupClearCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedCommand = notice.command.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingCommand.isEmpty, !cleanedCommand.isEmpty {
            updatedSession.providerStartupClearCommand = cleanedCommand
        }
        let existingSource = updatedSession.providerStartupClearCommandSource?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedSource = notice.source.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingSource.isEmpty, !cleanedSource.isEmpty {
            updatedSession.providerStartupClearCommandSource = cleanedSource
        }
        let existingReason = updatedSession.providerStartupClearReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedReason = notice.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingReason.isEmpty, !cleanedReason.isEmpty {
            updatedSession.providerStartupClearReason = cleanedReason
        }
        if notice.completed {
            updatedSession.providerStartupClearCompleted = true
        } else if updatedSession.providerStartupClearCompleted == nil {
            updatedSession.providerStartupClearCompleted = false
        }
        return updatedSession
    }

    nonisolated static func sessionByApplyingGeminiLaunchContext(
        _ snapshot: GeminiLaunchContextSnapshot,
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        var updatedSession = session

        func assignIfEmpty(_ keyPath: WritableKeyPath<TerminalMonitorSession, String?>, from value: String?) {
            let cleanedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let existingValue = updatedSession[keyPath: keyPath]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existingValue.isEmpty, !cleanedValue.isEmpty {
                updatedSession[keyPath: keyPath] = cleanedValue
            }
        }

        assignIfEmpty(\.providerCLIVersion, from: snapshot.cliVersion)
        assignIfEmpty(\.providerRunnerPath, from: snapshot.runnerPath)
        assignIfEmpty(\.providerRunnerBuild, from: snapshot.runnerBuild)
        assignIfEmpty(\.providerWrapperResolvedPath, from: snapshot.wrapperResolvedPath)
        assignIfEmpty(\.providerWrapperKind, from: snapshot.wrapperKind)
        assignIfEmpty(\.providerLaunchMode, from: snapshot.launchMode)
        assignIfEmpty(\.providerShellFallbackExecutable, from: snapshot.shellFallbackExecutable)
        assignIfEmpty(\.providerAutoContinueMode, from: snapshot.autoContinueMode)
        assignIfEmpty(\.providerPTYBackend, from: snapshot.ptyBackend)

        return updatedSession
    }

    nonisolated static func sessionByApplyingGeminiTranscriptInteractions(
        _ notices: [GeminiTranscriptInteractionNotice],
        observedAt: Date,
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        guard !notices.isEmpty else { return session }

        var updatedSession = session
        var slashCommands = updatedSession.observedSlashCommands ?? []
        var promptSubmissions = updatedSession.observedPromptSubmissions ?? []
        var interactionSummaries = updatedSession.observedInteractions ?? []

        for notice in notices {
            let cleanedText = notice.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedSource = notice.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedText.isEmpty else { continue }

            if let summaryIndex = interactionSummaries.firstIndex(where: {
                $0.text == cleanedText &&
                $0.kind == notice.kind.asObservedInteractionKind &&
                $0.source == cleanedSource
            }) {
                interactionSummaries[summaryIndex].lastObservedAt = observedAt
                interactionSummaries[summaryIndex].observationCount += 1
            } else {
                interactionSummaries.append(
                    ObservedTranscriptInteractionSummary(
                        text: cleanedText,
                        kind: notice.kind.asObservedInteractionKind,
                        source: cleanedSource,
                        firstObservedAt: observedAt,
                        lastObservedAt: observedAt,
                        observationCount: 1
                    )
                )
            }

            switch notice.kind {
            case .slashCommand:
                if !slashCommands.contains(cleanedText) {
                    slashCommands.append(cleanedText)
                }
            case .prompt:
                if !promptSubmissions.contains(cleanedText) {
                    promptSubmissions.append(cleanedText)
                }
            }
        }

        updatedSession.observedSlashCommands = slashCommands.isEmpty ? nil : slashCommands
        updatedSession.observedPromptSubmissions = promptSubmissions.isEmpty ? nil : promptSubmissions
        updatedSession.observedInteractions = interactionSummaries.isEmpty ? nil : interactionSummaries
        return updatedSession
    }

    nonisolated static func observedTranscriptInteractionSummaries(
        from events: [TerminalSessionEvent]
    ) -> [ObservedTranscriptInteractionSummary] {
        let relevantEvents = events
            .compactMap { event -> (ObservedTranscriptInteraction, Date)? in
                guard let interaction = event.observedTranscriptInteraction else { return nil }
                return (interaction, event.eventAt)
            }
            .sorted { lhs, rhs in lhs.1 < rhs.1 }

        guard !relevantEvents.isEmpty else { return [] }

        struct SummaryKey: Hashable {
            var text: String
            var kind: ObservedTranscriptInteraction.Kind
            var source: String
        }

        var summaries: [ObservedTranscriptInteractionSummary] = []
        var summaryIndexByKey: [SummaryKey: Int] = [:]

        for (interaction, eventAt) in relevantEvents {
            let key = SummaryKey(text: interaction.text, kind: interaction.kind, source: interaction.source)
            if let existingIndex = summaryIndexByKey[key] {
                summaries[existingIndex].lastObservedAt = eventAt
                summaries[existingIndex].observationCount += 1
            } else {
                summaryIndexByKey[key] = summaries.count
                summaries.append(
                    ObservedTranscriptInteractionSummary(
                        text: interaction.text,
                        kind: interaction.kind,
                        source: interaction.source,
                        firstObservedAt: eventAt,
                        lastObservedAt: eventAt,
                        observationCount: 1
                    )
                )
            }
        }

        return summaries
    }

    nonisolated static func sessionByBackfillingObservedTranscriptInteractions(
        from events: [TerminalSessionEvent],
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        let summaries = observedTranscriptInteractionSummaries(from: events)
        guard !summaries.isEmpty else { return session }

        var updatedSession = session
        if updatedSession.observedInteractions?.isEmpty != false {
            updatedSession.observedInteractions = summaries
        }
        if updatedSession.observedSlashCommands?.isEmpty != false {
            let slashCommands = summaries
                .filter { $0.kind == .slashCommand }
                .map(\.text)
            updatedSession.observedSlashCommands = slashCommands.isEmpty ? nil : slashCommands
        }
        if updatedSession.observedPromptSubmissions?.isEmpty != false {
            let prompts = summaries
                .filter { $0.kind == .prompt }
                .map(\.text)
            updatedSession.observedPromptSubmissions = prompts.isEmpty ? nil : prompts
        }
        return updatedSession
    }

    nonisolated static func sessionByBackfillingObservedTranscriptInteractions(
        from chunks: [TerminalTranscriptChunk],
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        guard needsObservedInteractionBackfill(session) else {
            return session
        }

        let sortedChunks = chunks.sorted {
            if $0.chunkIndex != $1.chunkIndex {
                return $0.chunkIndex < $1.chunkIndex
            }
            return $0.capturedAt < $1.capturedAt
        }

        var updatedSession = session
        for chunk in sortedChunks {
            let transcriptText = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcriptText.isEmpty else { continue }
            let notices = extractGeminiTranscriptInteractionNotices(fromTranscriptText: transcriptText)
            guard !notices.isEmpty else { continue }
            updatedSession = sessionByApplyingGeminiTranscriptInteractions(
                notices,
                observedAt: chunk.capturedAt,
                to: updatedSession
            )
        }

        return updatedSession
    }

    nonisolated static func sessionByBackfillingObservedTranscriptInteractions(
        fromTranscriptText text: String,
        source: String,
        observedAt: Date,
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        guard needsObservedInteractionBackfill(session) else {
            return session
        }

        let cleanedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSource.isEmpty else {
            return session
        }

        let notices = extractGeminiTranscriptInteractionNotices(fromTranscriptText: text).map { notice in
            GeminiTranscriptInteractionNotice(
                fingerprint: notice.fingerprint,
                text: notice.text,
                kind: notice.kind,
                source: cleanedSource
            )
        }
        guard !notices.isEmpty else {
            return session
        }

        return sessionByApplyingGeminiTranscriptInteractions(
            notices,
            observedAt: observedAt,
            to: session
        )
    }

    nonisolated static func needsObservedInteractionBackfill(_ session: TerminalMonitorSession) -> Bool {
        session.observedInteractions?.isEmpty != false ||
        session.observedSlashCommands?.isEmpty != false ||
        session.observedPromptSubmissions?.isEmpty != false
    }

    nonisolated static func observedInteractionChunkBackfillLimit(for sessionChunkCount: Int) -> Int {
        max(1, min(10_000, sessionChunkCount))
    }

    nonisolated static func observedInteractionChunkBackfillIsComplete(
        scannedChunkCount: Int,
        sessionChunkCount: Int
    ) -> Bool {
        sessionChunkCount > 0 && scannedChunkCount >= sessionChunkCount
    }

    nonisolated static func sessionByApplyingGeminiFreshSessionReset(
        _ notice: GeminiFreshSessionResetNotice,
        to session: TerminalMonitorSession
    ) -> TerminalMonitorSession {
        var updatedSession = session
        if updatedSession.providerFreshSessionPrepared == nil {
            updatedSession.providerFreshSessionPrepared = notice.cleared
        }
        let existingReason = updatedSession.providerFreshSessionResetReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedReason = notice.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingReason.isEmpty, !cleanedReason.isEmpty {
            updatedSession.providerFreshSessionResetReason = cleanedReason
        }
        if updatedSession.providerFreshSessionRemovedPathCount == nil {
            updatedSession.providerFreshSessionRemovedPathCount = notice.removedPathCount
        }
        return updatedSession
    }

    private func bufferGeminiSessionStatsParsingText(sessionID: UUID, data: Data) -> String? {
        guard let index = sessionIndex(for: sessionID), sessions[index].agentKind == .gemini else {
            return nil
        }

        let normalizedChunk = Self.normalizedSessionStatsParsingText(from: String(decoding: data, as: UTF8.self))
        guard !normalizedChunk.isEmpty else { return nil }

        let combinedBuffer = (sessionStatsBuffersByID[sessionID] ?? "") + normalizedChunk
        let trimmedBuffer = String(combinedBuffer.suffix(Self.sessionStatsBufferLimit))
        sessionStatsBuffersByID[sessionID] = trimmedBuffer
        return trimmedBuffer
    }

    private func captureGeminiStartupClearIfPresent(sessionID: UUID, bufferedTranscriptText: String) -> GeminiStartupClearNotice? {
        let notices = Self.extractGeminiStartupClearNotices(fromTranscriptText: bufferedTranscriptText)
        guard !notices.isEmpty else { return nil }

        var fingerprints = startupClearFingerprintsByID[sessionID] ?? []
        var latestNotice: GeminiStartupClearNotice?

        for notice in notices where !fingerprints.contains(notice.fingerprint) {
            fingerprints.append(notice.fingerprint)
            if fingerprints.count > Self.sessionStatsFingerprintLimit {
                fingerprints.removeFirst(fingerprints.count - Self.sessionStatsFingerprintLimit)
            }
            latestNotice = notice
        }

        startupClearFingerprintsByID[sessionID] = fingerprints
        return latestNotice
    }

    private func captureGeminiLaunchContextIfPresent(sessionID: UUID, bufferedTranscriptText: String) -> GeminiLaunchContextNotice? {
        let notices = Self.extractGeminiLaunchContextNotices(fromTranscriptText: bufferedTranscriptText)
        guard !notices.isEmpty else { return nil }

        var fingerprints = launchContextFingerprintsByID[sessionID] ?? []
        var latestNotice: GeminiLaunchContextNotice?

        for notice in notices where !fingerprints.contains(notice.fingerprint) {
            fingerprints.append(notice.fingerprint)
            if fingerprints.count > Self.sessionStatsFingerprintLimit {
                fingerprints.removeFirst(fingerprints.count - Self.sessionStatsFingerprintLimit)
            }
            latestNotice = notice
        }

        launchContextFingerprintsByID[sessionID] = fingerprints
        return latestNotice
    }

    private func captureGeminiStartupClearCompletedIfPresent(sessionID: UUID, bufferedTranscriptText: String) -> GeminiStartupClearNotice? {
        let notices = Self.extractGeminiStartupClearCompletedNotices(fromTranscriptText: bufferedTranscriptText)
        guard !notices.isEmpty else { return nil }

        var fingerprints = startupClearCompletedFingerprintsByID[sessionID] ?? []
        var latestNotice: GeminiStartupClearNotice?

        for notice in notices where !fingerprints.contains(notice.fingerprint) {
            fingerprints.append(notice.fingerprint)
            if fingerprints.count > Self.sessionStatsFingerprintLimit {
                fingerprints.removeFirst(fingerprints.count - Self.sessionStatsFingerprintLimit)
            }
            latestNotice = notice
        }

        startupClearCompletedFingerprintsByID[sessionID] = fingerprints
        return latestNotice
    }

    private func captureGeminiSessionStatsIfPresent(sessionID: UUID, bufferedTranscriptText: String) -> GeminiSessionStatsCapture? {
        let captures = Self.extractGeminiSessionStatsCaptures(fromTranscriptText: bufferedTranscriptText)
        guard !captures.isEmpty else { return nil }

        var fingerprints = sessionStatsFingerprintsByID[sessionID] ?? []
        var latestCapture: GeminiSessionStatsCapture?

        for capture in captures where !fingerprints.contains(capture.fingerprint) {
            fingerprints.append(capture.fingerprint)
            if fingerprints.count > Self.sessionStatsFingerprintLimit {
                fingerprints.removeFirst(fingerprints.count - Self.sessionStatsFingerprintLimit)
            }
            latestCapture = capture
        }

        sessionStatsFingerprintsByID[sessionID] = fingerprints
        guard let latestCapture else { return nil }

        applyGeminiSessionStats(latestCapture.snapshot, to: sessionID)
        return latestCapture
    }

    private func captureGeminiModelCapacityIfPresent(sessionID: UUID, bufferedTranscriptText: String) -> GeminiModelCapacityCapture? {
        let captures = Self.extractGeminiModelCapacityCaptures(fromTranscriptText: bufferedTranscriptText)
        guard !captures.isEmpty else { return nil }

        var fingerprints = modelCapacityFingerprintsByID[sessionID] ?? []
        var latestCapture: GeminiModelCapacityCapture?

        for capture in captures where !fingerprints.contains(capture.fingerprint) {
            fingerprints.append(capture.fingerprint)
            if fingerprints.count > Self.sessionStatsFingerprintLimit {
                fingerprints.removeFirst(fingerprints.count - Self.sessionStatsFingerprintLimit)
            }
            latestCapture = capture
        }

        modelCapacityFingerprintsByID[sessionID] = fingerprints
        guard let latestCapture else { return nil }

        applyGeminiModelCapacity(latestCapture.snapshot, to: sessionID)
        return latestCapture
    }

    private func captureGeminiSessionStatsSkipIfPresent(sessionID: UUID, bufferedTranscriptText: String) -> GeminiSessionStatsSkipNotice? {
        let notices = Self.extractGeminiSessionStatsSkipNotices(fromTranscriptText: bufferedTranscriptText)
        guard !notices.isEmpty else { return nil }

        var fingerprints = sessionStatsSkipFingerprintsByID[sessionID] ?? []
        var latestNotice: GeminiSessionStatsSkipNotice?

        for notice in notices where !fingerprints.contains(notice.fingerprint) {
            fingerprints.append(notice.fingerprint)
            if fingerprints.count > Self.sessionStatsFingerprintLimit {
                fingerprints.removeFirst(fingerprints.count - Self.sessionStatsFingerprintLimit)
            }
            latestNotice = notice
        }

        sessionStatsSkipFingerprintsByID[sessionID] = fingerprints
        return latestNotice
    }

    private func captureGeminiSessionStatsBlockedIfPresent(sessionID: UUID, bufferedTranscriptText: String) -> GeminiSessionStatsBlockedNotice? {
        let notices = Self.extractGeminiSessionStatsBlockedNotices(fromTranscriptText: bufferedTranscriptText)
        guard !notices.isEmpty else { return nil }

        var fingerprints = sessionStatsBlockedFingerprintsByID[sessionID] ?? []
        var latestNotice: GeminiSessionStatsBlockedNotice?

        for notice in notices where !fingerprints.contains(notice.fingerprint) {
            fingerprints.append(notice.fingerprint)
            if fingerprints.count > Self.sessionStatsFingerprintLimit {
                fingerprints.removeFirst(fingerprints.count - Self.sessionStatsFingerprintLimit)
            }
            latestNotice = notice
        }

        sessionStatsBlockedFingerprintsByID[sessionID] = fingerprints
        return latestNotice
    }

    private func captureGeminiSessionStatsFallbackIfPresent(sessionID: UUID, bufferedTranscriptText: String) -> GeminiSessionStatsFallbackNotice? {
        let notices = Self.extractGeminiSessionStatsFallbackNotices(fromTranscriptText: bufferedTranscriptText)
        guard !notices.isEmpty else { return nil }

        var fingerprints = sessionStatsFallbackFingerprintsByID[sessionID] ?? []
        var latestNotice: GeminiSessionStatsFallbackNotice?

        for notice in notices where !fingerprints.contains(notice.fingerprint) {
            fingerprints.append(notice.fingerprint)
            if fingerprints.count > Self.sessionStatsFingerprintLimit {
                fingerprints.removeFirst(fingerprints.count - Self.sessionStatsFingerprintLimit)
            }
            latestNotice = notice
        }

        sessionStatsFallbackFingerprintsByID[sessionID] = fingerprints
        return latestNotice
    }

    private func captureGeminiCompatibilityOverrideIfPresent(sessionID: UUID, bufferedTranscriptText: String) -> GeminiCompatibilityOverrideNotice? {
        let notices = Self.extractGeminiCompatibilityOverrideNotices(fromTranscriptText: bufferedTranscriptText)
        guard !notices.isEmpty else { return nil }

        var fingerprints = compatibilityOverrideFingerprintsByID[sessionID] ?? []
        var latestNotice: GeminiCompatibilityOverrideNotice?

        for notice in notices where !fingerprints.contains(notice.fingerprint) {
            fingerprints.append(notice.fingerprint)
            if fingerprints.count > Self.sessionStatsFingerprintLimit {
                fingerprints.removeFirst(fingerprints.count - Self.sessionStatsFingerprintLimit)
            }
            latestNotice = notice
        }

        compatibilityOverrideFingerprintsByID[sessionID] = fingerprints
        return latestNotice
    }

    private func captureGeminiFreshSessionResetIfPresent(sessionID: UUID, bufferedTranscriptText: String) -> GeminiFreshSessionResetNotice? {
        let notices = Self.extractGeminiFreshSessionResetNotices(fromTranscriptText: bufferedTranscriptText)
        guard !notices.isEmpty else { return nil }

        var fingerprints = freshSessionResetFingerprintsByID[sessionID] ?? []
        var latestNotice: GeminiFreshSessionResetNotice?

        for notice in notices where !fingerprints.contains(notice.fingerprint) {
            fingerprints.append(notice.fingerprint)
            if fingerprints.count > Self.sessionStatsFingerprintLimit {
                fingerprints.removeFirst(fingerprints.count - Self.sessionStatsFingerprintLimit)
            }
            latestNotice = notice
        }

        freshSessionResetFingerprintsByID[sessionID] = fingerprints
        return latestNotice
    }

    func captureGeminiTranscriptInteractionsIfPresent(
        sessionID: UUID,
        bufferedTranscriptText: String
    ) -> [GeminiTranscriptInteractionNotice] {
        let notices = Self.extractGeminiTranscriptInteractionNotices(fromTranscriptText: bufferedTranscriptText)
        guard !notices.isEmpty else { return [] }

        let currentSequence = notices.map { "\($0.kind.rawValue):\($0.text)" }
        var history = transcriptInteractionHistoryByID[sessionID] ?? []
        let overlap = Self.longestTranscriptInteractionOverlap(history: history, current: currentSequence)
        let newNotices = Array(notices.dropFirst(overlap))

        guard !newNotices.isEmpty else { return [] }

        history.append(contentsOf: currentSequence.dropFirst(overlap))
        if history.count > Self.sessionStatsFingerprintLimit * 20 {
            history = Array(history.suffix(Self.sessionStatsFingerprintLimit * 20))
        }
        transcriptInteractionHistoryByID[sessionID] = history
        return newNotices
    }

    private func applyGeminiSessionStats(_ snapshot: GeminiSessionStatsSnapshot, to sessionID: UUID) {
        guard let index = sessionIndex(for: sessionID) else { return }

        let session = Self.sessionByApplyingGeminiSessionStats(snapshot, to: sessions[index])
        upsert(session)
    }

    private func applyGeminiModelCapacity(_ snapshot: GeminiModelCapacitySnapshot, to sessionID: UUID) {
        guard let index = sessionIndex(for: sessionID) else { return }

        let session = Self.sessionByApplyingGeminiModelCapacity(snapshot, to: sessions[index])
        upsert(session)
    }

    nonisolated private static func extractGeminiSessionStatsCaptures(fromTranscriptText text: String) -> [GeminiSessionStatsCapture] {
        let lines = normalizedSessionStatsLines(from: text)
        guard !lines.isEmpty else { return [] }

        var captures: [GeminiSessionStatsCapture] = []
        var seenFingerprints = Set<String>()

        for index in lines.indices where lines[index].localizedCaseInsensitiveContains("Session Stats") {
            let endIndex = min(lines.count, index + 40)
            let candidateLines = Array(lines[index..<endIndex])
            guard var capture = parseGeminiSessionStatsCapture(fromLines: candidateLines) else { continue }
            let startupCommandMatch = extractGeminiStartupStatsCommandMatch(
                fromNormalizedLines: lines,
                aroundCaptureLineIndex: index
            )
            capture.snapshot.startupStatsCommand = startupCommandMatch?.command
            capture.snapshot.startupStatsCommandSource = startupCommandMatch?.source
            guard seenFingerprints.insert(capture.fingerprint).inserted else { continue }
            captures.append(capture)
        }

        return captures
    }

    nonisolated private static func extractGeminiModelCapacityCaptures(fromTranscriptText text: String) -> [GeminiModelCapacityCapture] {
        let lines = normalizedSessionStatsLines(from: text)
        guard !lines.isEmpty else { return [] }

        var captures: [GeminiModelCapacityCapture] = []
        var seenFingerprints = Set<String>()

        for index in lines.indices where lines[index].localizedCaseInsensitiveContains("Select Model")
            || lines[index].caseInsensitiveCompare("/model") == .orderedSame
            || lines[index].localizedCaseInsensitiveContains("Model usage") {
            guard let capture = parseGeminiModelCapacityCapture(fromLines: Array(lines[index..<min(lines.count, index + 80)])) else {
                continue
            }
            guard seenFingerprints.insert(capture.fingerprint).inserted else { continue }
            captures.append(capture)
        }

        return captures
    }

    nonisolated private static func extractGeminiLaunchContextNotices(fromTranscriptText text: String) -> [GeminiLaunchContextNotice] {
        let lines = normalizedSessionStatsLines(from: text)
        guard !lines.isEmpty else { return [] }

        var snapshot = GeminiLaunchContextSnapshot()
        for line in lines {
            if let value = geminiLaunchContextValue(from: line, marker: "Gemini CLI version:") {
                snapshot.cliVersion = value
            } else if let value = geminiLaunchContextValue(from: line, marker: "Runner path:") {
                snapshot.runnerPath = value
            } else if let value = geminiLaunchContextValue(from: line, marker: "Runner build:") {
                snapshot.runnerBuild = value
            } else if let value = geminiLaunchContextValue(from: line, marker: "Wrapper resolved:") {
                snapshot.wrapperResolvedPath = value
            } else if let value = geminiLaunchContextValue(from: line, marker: "Wrapper kind:") {
                snapshot.wrapperKind = value
            } else if let value = geminiLaunchContextValue(from: line, marker: "Launch mode:") {
                snapshot.launchMode = value
            } else if let value = geminiLaunchContextValue(from: line, marker: "Shell fallback executable:") {
                snapshot.shellFallbackExecutable = value
            } else if let value = geminiLaunchContextValue(from: line, marker: "Auto-continue mode:") {
                snapshot.autoContinueMode = value
            } else if let value = geminiLaunchContextValue(from: line, marker: "PTY backend:") {
                snapshot.ptyBackend = value
            }
        }

        guard !snapshot.metadata.isEmpty else { return [] }

        let fingerprint = [
            snapshot.cliVersion ?? "",
            snapshot.runnerPath ?? "",
            snapshot.runnerBuild ?? "",
            snapshot.wrapperResolvedPath ?? "",
            snapshot.wrapperKind ?? "",
            snapshot.launchMode ?? "",
            snapshot.shellFallbackExecutable ?? "",
            snapshot.autoContinueMode ?? "",
            snapshot.ptyBackend ?? "",
        ].joined(separator: "|").lowercased()

        return [GeminiLaunchContextNotice(fingerprint: fingerprint, snapshot: snapshot)]
    }

    nonisolated private static func longestTranscriptInteractionOverlap(history: [String], current: [String]) -> Int {
        guard !history.isEmpty, !current.isEmpty else { return 0 }

        let maxOverlap = min(history.count, current.count)
        guard maxOverlap > 0 else { return 0 }

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            let historySuffix = history.suffix(overlap)
            let currentPrefix = current.prefix(overlap)
            if Array(historySuffix) == Array(currentPrefix) {
                return overlap
            }
        }

        return 0
    }

    nonisolated private static func extractGeminiStartupClearNotices(fromTranscriptText text: String) -> [GeminiStartupClearNotice] {
        let lines = normalizedSessionStatsLines(from: text)
        guard !lines.isEmpty else { return [] }

        var notices: [GeminiStartupClearNotice] = []
        var seenFingerprints = Set<String>()

        for line in lines {
            if let command = startupClearCommandFromAutoSentLine(line) {
                let fingerprint = "sent:\(command.lowercased())"
                if seenFingerprints.insert(fingerprint).inserted {
                    notices.append(
                        GeminiStartupClearNotice(
                            fingerprint: fingerprint,
                            command: command,
                            completed: false,
                            reason: nil,
                            source: "runner_banner"
                        )
                    )
                }
                continue
            }

            if let command = startupClearCommandFromEchoedLine(line) {
                let fingerprint = "echoed:\(command.lowercased())"
                if seenFingerprints.insert(fingerprint).inserted {
                    notices.append(
                        GeminiStartupClearNotice(
                            fingerprint: fingerprint,
                            command: command,
                            completed: false,
                            reason: nil,
                            source: "echoed_command"
                        )
                    )
                }
            }
        }

        return notices
    }

    nonisolated private static func extractGeminiStartupClearCompletedNotices(fromTranscriptText text: String) -> [GeminiStartupClearNotice] {
        let normalizedText = normalizedSessionStatsParsingText(from: text)
        guard !normalizedText.isEmpty else { return [] }

        var notices: [GeminiStartupClearNotice] = []
        var seenFingerprints = Set<String>()

        let marker = "Startup clear: completed"
        var searchRange = normalizedText.startIndex..<normalizedText.endIndex

        while let matchRange = normalizedText.range(of: marker, options: [.caseInsensitive], range: searchRange) {
            let reason = extractBalancedParentheticalReason(in: normalizedText, after: matchRange.upperBound)?
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fingerprint = "completed:\((reason ?? "").lowercased())"
            if seenFingerprints.insert(fingerprint).inserted {
                notices.append(
                    GeminiStartupClearNotice(
                        fingerprint: fingerprint,
                        command: "/clear",
                        completed: true,
                        reason: reason,
                        source: "runner_banner"
                    )
                )
            }

            searchRange = matchRange.upperBound..<normalizedText.endIndex
        }

        return notices
    }

    nonisolated private static func extractGeminiSessionStatsSkipNotices(fromTranscriptText text: String) -> [GeminiSessionStatsSkipNotice] {
        let normalizedText = normalizedSessionStatsParsingText(from: text)
        guard !normalizedText.isEmpty else { return [] }

        var notices: [GeminiSessionStatsSkipNotice] = []
        var seenFingerprints = Set<String>()

        let marker = "Startup session stats: skipped"
        var searchRange = normalizedText.startIndex..<normalizedText.endIndex

        while let matchRange = normalizedText.range(of: marker, options: [.caseInsensitive], range: searchRange) {
            if let reason = extractBalancedParentheticalReason(in: normalizedText, after: matchRange.upperBound) {
                let cleanedReason = reason
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanedReason.isEmpty {
                    let fingerprint = cleanedReason.lowercased()
                    if seenFingerprints.insert(fingerprint).inserted {
                        notices.append(
                            GeminiSessionStatsSkipNotice(
                                fingerprint: fingerprint,
                                reason: cleanedReason
                            )
                        )
                    }
                }
            }

            searchRange = matchRange.upperBound..<normalizedText.endIndex
        }

        return notices
    }

    nonisolated private static func extractGeminiSessionStatsBlockedNotices(fromTranscriptText text: String) -> [GeminiSessionStatsBlockedNotice] {
        let normalizedText = normalizedSessionStatsParsingText(from: text)
        guard !normalizedText.isEmpty else { return [] }

        var notices: [GeminiSessionStatsBlockedNotice] = []
        var seenFingerprints = Set<String>()

        var searchRange = normalizedText.startIndex..<normalizedText.endIndex

        while let match = ["Startup sequence: blocked", "Startup session stats: blocked"]
            .compactMap({ marker -> Range<String.Index>? in
                normalizedText.range(of: marker, options: [.caseInsensitive], range: searchRange)
            })
            .min(by: { $0.lowerBound < $1.lowerBound }) {
            if let reason = extractBalancedParentheticalReason(in: normalizedText, after: match.upperBound) {
                let cleanedReason = reason
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanedReason.isEmpty {
                    let fingerprint = cleanedReason.lowercased()
                    if seenFingerprints.insert(fingerprint).inserted {
                        notices.append(
                            GeminiSessionStatsBlockedNotice(
                                fingerprint: fingerprint,
                                reason: cleanedReason
                            )
                        )
                    }
                }
            }

            searchRange = match.upperBound..<normalizedText.endIndex
        }

        return notices
    }

    nonisolated private static func extractGeminiSessionStatsFallbackNotices(fromTranscriptText text: String) -> [GeminiSessionStatsFallbackNotice] {
        let normalizedText = normalizedSessionStatsParsingText(from: text)
        guard !normalizedText.isEmpty else { return [] }

        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(/stats(?:\s+session)?)\s+output\s+was\s+not\s+detected\s+in\s+time\s+[—-]\s+retrying\s+with\s+(/stats(?:\s+session)?)\.?"#
        ) else {
            return []
        }

        let nsRange = NSRange(normalizedText.startIndex..<normalizedText.endIndex, in: normalizedText)
        var notices: [GeminiSessionStatsFallbackNotice] = []
        var seenFingerprints = Set<String>()

        for match in regex.matches(in: normalizedText, range: nsRange) {
            guard
                let fromRange = Range(match.range(at: 1), in: normalizedText),
                let toRange = Range(match.range(at: 2), in: normalizedText)
            else {
                continue
            }

            let fromCommand = normalizedText[fromRange]
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let toCommand = normalizedText[toRange]
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fromCommand.isEmpty, !toCommand.isEmpty else { continue }

            let fingerprint = "\(fromCommand.lowercased())->\(toCommand.lowercased())"
            guard seenFingerprints.insert(fingerprint).inserted else { continue }

            notices.append(
                GeminiSessionStatsFallbackNotice(
                    fingerprint: fingerprint,
                    fromCommand: fromCommand,
                    toCommand: toCommand
                )
            )
        }

        return notices
    }

    nonisolated private static func extractGeminiCompatibilityOverrideNotices(fromTranscriptText text: String) -> [GeminiCompatibilityOverrideNotice] {
        let normalizedText = normalizedSessionStatsParsingText(from: text)
        guard !normalizedText.isEmpty else { return [] }

        var notices: [GeminiCompatibilityOverrideNotice] = []
        var seenFingerprints = Set<String>()

        let marker = "Gemini CLI compatibility override:"
        var searchRange = normalizedText.startIndex..<normalizedText.endIndex

        while let matchRange = normalizedText.range(of: marker, options: [.caseInsensitive], range: searchRange) {
            let lineEnd = normalizedText[matchRange.upperBound...].firstIndex(of: "\n") ?? normalizedText.endIndex
            let cleanedReason = normalizedText[matchRange.upperBound..<lineEnd]
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedReason.isEmpty {
                let fingerprint = cleanedReason.lowercased()
                if seenFingerprints.insert(fingerprint).inserted {
                    notices.append(
                        GeminiCompatibilityOverrideNotice(
                            fingerprint: fingerprint,
                            reason: cleanedReason
                        )
                    )
                }
            }

            searchRange = matchRange.upperBound..<normalizedText.endIndex
        }

        return notices
    }

    nonisolated private static func extractGeminiFreshSessionResetNotices(fromTranscriptText text: String) -> [GeminiFreshSessionResetNotice] {
        let normalizedText = normalizedSessionStatsParsingText(from: text)
        guard !normalizedText.isEmpty else { return [] }

        var notices: [GeminiFreshSessionResetNotice] = []
        var seenFingerprints = Set<String>()

        let marker = "Fresh session prep:"
        var searchRange = normalizedText.startIndex..<normalizedText.endIndex

        while let matchRange = normalizedText.range(of: marker, options: [.caseInsensitive], range: searchRange) {
            let lineEnd = normalizedText[matchRange.upperBound...].firstIndex(of: "\n") ?? normalizedText.endIndex
            let cleanedReason = normalizedText[matchRange.upperBound..<lineEnd]
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedReason.isEmpty {
                let fingerprint = cleanedReason.lowercased()
                if seenFingerprints.insert(fingerprint).inserted {
                    let lowered = cleanedReason.lowercased()
                    let cleared = lowered.hasPrefix("cleared prior workspace session binding")
                    let removedPathCount = parseFreshSessionResetRemovedPathCount(from: cleanedReason)
                    notices.append(
                        GeminiFreshSessionResetNotice(
                            fingerprint: fingerprint,
                            reason: cleanedReason,
                            cleared: cleared,
                            removedPathCount: removedPathCount
                        )
                    )
                }
            }

            searchRange = matchRange.upperBound..<normalizedText.endIndex
        }

        return notices
    }

    nonisolated private static func parseFreshSessionResetRemovedPathCount(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\((\d+)\s+path\s+alias(?:es)?\)"#, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: nsRange),
            let countRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[countRange])
    }

    nonisolated private static func extractBalancedParentheticalReason(in text: String, after lowerBound: String.Index) -> String? {
        guard let openParenIndex = text[lowerBound...].firstIndex(of: "(") else { return nil }

        var depth = 0
        var index = openParenIndex
        let contentStart = text.index(after: openParenIndex)

        while index < text.endIndex {
            let character = text[index]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return String(text[contentStart..<index])
                }
            }
            index = text.index(after: index)
        }

        return nil
    }

    nonisolated private static func normalizedSessionStatsLines(from text: String) -> [String] {
        normalizedSessionStatsParsingText(from: text)
            .components(separatedBy: .newlines)
            .map { cleanedSessionStatsLine($0) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func startupStatsCommandFromAutoSentLine(_ line: String) -> String? {
        guard line.localizedCaseInsensitiveContains("Auto-sending startup"),
              let range = line.range(of: #"/stats(?:\s+session)?"#, options: .regularExpression) else {
            return nil
        }

        let command = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    nonisolated private static func geminiLaunchContextValue(from line: String, marker: String) -> String? {
        guard let range = line.range(of: marker, options: [.caseInsensitive]) else {
            return nil
        }
        let suffix = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else { return nil }
        return suffix
    }

    nonisolated private static func startupClearCommandFromAutoSentLine(_ line: String) -> String? {
        guard line.localizedCaseInsensitiveContains("Auto-sending startup"),
              let range = line.range(of: #"/clear"#, options: .regularExpression) else {
            return nil
        }

        let command = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    nonisolated private static func startupClearCommandFromEchoedLine(_ line: String) -> String? {
        guard let range = line.range(of: #"^>\s*(/clear)$"#, options: .regularExpression) else {
            return nil
        }

        let command = String(line[range])
            .replacingOccurrences(of: #"[>\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    nonisolated private static func startupStatsCommandFromEchoedLine(_ line: String) -> String? {
        guard let range = line.range(of: #"^>\s*(/stats(?:\s+session)?)$"#, options: .regularExpression) else {
            return nil
        }

        let command = String(line[range])
            .replacingOccurrences(of: #"[>\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    nonisolated private static func extractLatestGeminiStartupStatsCommandMatch(
        fromNormalizedLines lines: [String]
    ) -> GeminiStartupCommandMatch? {
        for line in lines.reversed() {
            if let command = startupStatsCommandFromAutoSentLine(line) {
                return GeminiStartupCommandMatch(command: command, source: "runner_banner")
            }
        }

        for line in lines.reversed() {
            if let command = startupStatsCommandFromEchoedLine(line) {
                return GeminiStartupCommandMatch(command: command, source: "echoed_command")
            }
        }

        return nil
    }

    nonisolated private static func extractLatestGeminiStartupClearCommandMatch(
        fromNormalizedLines lines: [String]
    ) -> GeminiStartupCommandMatch? {
        for line in lines.reversed() {
            if let command = startupClearCommandFromAutoSentLine(line) {
                return GeminiStartupCommandMatch(command: command, source: "runner_banner")
            }
        }

        for line in lines.reversed() {
            if let command = startupClearCommandFromEchoedLine(line) {
                return GeminiStartupCommandMatch(command: command, source: "echoed_command")
            }
        }

        return nil
    }

    nonisolated private static func extractGeminiStartupStatsCommandMatch(
        fromNormalizedLines lines: [String],
        aroundCaptureLineIndex captureLineIndex: Int
    ) -> GeminiStartupCommandMatch? {
        guard !lines.isEmpty, captureLineIndex >= 0, captureLineIndex < lines.count else { return nil }

        let lookbehindStart = max(0, captureLineIndex - 24)
        let lookaheadEnd = min(lines.count - 1, captureLineIndex + 8)

        if lookbehindStart <= captureLineIndex {
            for index in stride(from: captureLineIndex, through: lookbehindStart, by: -1) {
                if let command = startupStatsCommandFromAutoSentLine(lines[index]) {
                    return GeminiStartupCommandMatch(command: command, source: "runner_banner")
                }
            }
        }

        if captureLineIndex + 1 <= lookaheadEnd {
            for index in (captureLineIndex + 1)...lookaheadEnd {
                if let command = startupStatsCommandFromAutoSentLine(lines[index]) {
                    return GeminiStartupCommandMatch(command: command, source: "runner_banner")
                }
            }
        }

        if captureLineIndex + 1 <= lookaheadEnd {
            for index in (captureLineIndex + 1)...lookaheadEnd {
                if let command = startupStatsCommandFromEchoedLine(lines[index]) {
                    return GeminiStartupCommandMatch(command: command, source: "echoed_command")
                }
            }
        }

        if lookbehindStart <= captureLineIndex {
            for index in stride(from: captureLineIndex, through: lookbehindStart, by: -1) {
                if let command = startupStatsCommandFromEchoedLine(lines[index]) {
                    return GeminiStartupCommandMatch(command: command, source: "echoed_command")
                }
            }
        }

        return nil
    }

    nonisolated private static func normalizedSessionStatsParsingText(from text: String) -> String {
        let withoutOSC = text.replacingOccurrences(
            of: "\u{001B}\\][^\u{0007}]*\u{0007}",
            with: "",
            options: .regularExpression
        )
        let withoutANSI = withoutOSC
            .replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{001B}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var cleaned = String()
        cleaned.reserveCapacity(withoutANSI.count)

        for scalar in withoutANSI.unicodeScalars {
            if scalar == "\u{0000}" {
                continue
            }
            if scalar.value < 0x20, scalar != "\n", scalar != "\t" {
                cleaned.append(" ")
            } else {
                cleaned.unicodeScalars.append(scalar)
            }
        }

        return cleaned
    }

    nonisolated private static func cleanedSessionStatsLine(_ rawLine: String) -> String {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.range(of: #"^[╭╮╰╯│║┃─━═▀▄▁▂▃▅▆▇█]+$"#, options: .regularExpression) != nil {
            return ""
        }

        let withoutBorders = trimmed
            .replacingOccurrences(of: #"^[│║┃\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[│║┃\s]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if withoutBorders.range(of: #"^[╭╮╰╯│║┃─━═▀▄▁▂▃▅▆▇█]+$"#, options: .regularExpression) != nil {
            return ""
        }

        return withoutBorders
    }

    nonisolated private static func parseGeminiSessionStatsCapture(fromLines lines: [String]) -> GeminiSessionStatsCapture? {
        var sessionID: String?
        var authMethod: String?
        var tier: String?
        var toolCalls: String?
        var successRate: String?
        var wallTime: String?
        var agentActive: String?
        var apiTime: String?
        var toolTime: String?
        var modelUsageNote: String?
        var modelUsage: [GeminiSessionStatsModelUsageRow] = []
        var currentUsageModel: String?
        var sawModelUsageSection = false

        for line in lines {
            if line.localizedCaseInsensitiveContains("Type your message") {
                break
            }

            let lowercasedLine = line.lowercased()
            if lowercasedLine == "session stats"
                || lowercasedLine == "interaction summary"
                || lowercasedLine == "performance"
                || lowercasedLine == "model usage" {
                if lowercasedLine == "model usage" {
                    sawModelUsageSection = true
                }
                continue
            }

            if lowercasedLine.contains("use /model to view model quota information") {
                sawModelUsageSection = true
                modelUsageNote = line
                continue
            }

            if let (key, value) = parseSessionStatsKeyValue(line) {
                switch key {
                case "session id":
                    sessionID = value
                case "auth method":
                    authMethod = value
                case "tier":
                    tier = value
                case "tool calls":
                    toolCalls = value
                case "success rate":
                    successRate = value
                case "wall time":
                    wallTime = value
                case "agent active":
                    agentActive = value
                case "api time":
                    apiTime = value
                case "tool time":
                    toolTime = value
                default:
                    break
                }
                continue
            }

            guard sawModelUsageSection else { continue }
            guard let parsedRow = parseGeminiSessionStatsUsageRow(from: line, currentModel: currentUsageModel) else { continue }
            currentUsageModel = parsedRow.currentModel
            modelUsage.append(parsedRow.row)
        }

        guard let sessionID,
              let authMethod,
              let tier,
              let toolCalls,
              let wallTime else {
            return nil
        }

        let snapshot = GeminiSessionStatsSnapshot(
            sessionID: sessionID,
            authMethod: authMethod,
            accountIdentifier: sessionStatsAccountIdentifier(from: authMethod),
            tier: tier,
            toolCalls: toolCalls,
            successRate: successRate,
            wallTime: wallTime,
            agentActive: agentActive,
            apiTime: apiTime,
            toolTime: toolTime,
            modelUsageNote: modelUsageNote,
            modelUsage: modelUsage
        )
        return GeminiSessionStatsCapture(
            fingerprint: geminiSessionStatsFingerprint(for: snapshot),
            snapshot: snapshot
        )
    }

    nonisolated private static func parseGeminiModelCapacityCapture(fromLines lines: [String]) -> GeminiModelCapacityCapture? {
        var currentModel: String?
        var sawModelDialog = false
        var sawModelUsage = false
        var rows: [GeminiModelCapacityRow] = []
        var rawLines: [String] = []

        for line in lines {
            if line.localizedCaseInsensitiveContains("Type your message") {
                break
            }

            let lowercasedLine = line.lowercased()
            if lowercasedLine == "select model" || lowercasedLine == "/model" {
                sawModelDialog = true
            }
            if lowercasedLine == "model usage" {
                sawModelUsage = true
            }
            if let selectedModel = parseGeminiSelectedModelLine(line) {
                currentModel = selectedModel
            }
            if let row = parseGeminiModelCapacityRow(from: line) {
                rows.append(row)
            }
            rawLines.append(line)
        }

        guard sawModelDialog, sawModelUsage || !rows.isEmpty else { return nil }

        let snapshot = GeminiModelCapacitySnapshot(
            startupModelCommand: "/model",
            startupModelCommandSource: "runner_banner",
            currentModel: currentModel,
            rows: rows,
            rawLines: rawLines
        )
        return GeminiModelCapacityCapture(
            fingerprint: geminiModelCapacityFingerprint(for: snapshot),
            snapshot: snapshot
        )
    }

    nonisolated private static func parseGeminiSelectedModelLine(_ line: String) -> String? {
        let normalized = line
            .replacingOccurrences(of: "[●◉○◌]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*(?:[>▸]\s*)?(?:\d+\.\s*)?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if let range = normalized.range(of: #"^manual\s*\(([^)]+)\)"#, options: [.regularExpression, .caseInsensitive]) {
            let match = String(normalized[range])
            let selected = match
                .replacingOccurrences(of: #"^manual\s*\("#, with: "", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: #"\)$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return selected.isEmpty ? nil : selected
        }

        if normalized.range(of: #"^gemini[-\w.]+"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return normalized.split(whereSeparator: \.isWhitespace).first.map(String.init)
        }
        return nil
    }

    nonisolated private static func parseGeminiModelCapacityRow(from line: String) -> GeminiModelCapacityRow? {
        let trimmed = line
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.range(
            of: #"^(model usage|select model|remember model|press esc|to use a specific|usage limits span|please /auth)"#,
            options: [.regularExpression, .caseInsensitive]
        ) == nil else {
            return nil
        }

        guard let percentRange = trimmed.range(of: #"\b\d{1,3}%"#, options: .regularExpression) else {
            return nil
        }

        let beforePercent = String(trimmed[..<percentRange.lowerBound])
            .replacingOccurrences(of: #"\s*[▬▰█#=\-]+\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "[●◉○◌]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*(?:[>▸]\s*)?(?:\d+\.\s*)?"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !beforePercent.isEmpty else { return nil }

        let percentText = String(trimmed[percentRange]).replacingOccurrences(of: "%", with: "")
        let usedPercentage = Int(percentText).map { max(0, min(100, $0)) }

        var resetTime: String?
        let afterPercent = String(trimmed[percentRange.upperBound...])
        if let resetRange = afterPercent.range(
            of: #"(?:limit\s+)?resets?\s*(?:in|:)?\s*([^)]+)"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            resetTime = String(afterPercent[resetRange])
                .replacingOccurrences(of: #"^(?:limit\s+)?resets?\s*(?:in|:)?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: #"\)$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return GeminiModelCapacityRow(
            model: beforePercent,
            usedPercentage: usedPercentage,
            resetTime: resetTime,
            rawText: trimmed
        )
    }

    nonisolated private static func parseSessionStatsKeyValue(_ line: String) -> (String, String)? {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let key = String(parts[0])
            .replacingOccurrences(of: "»", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (key, value)
    }

    nonisolated private static func parseGeminiSessionStatsUsageRow(
        from line: String,
        currentModel: String?
    ) -> (row: GeminiSessionStatsModelUsageRow, currentModel: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.localizedCaseInsensitiveContains("input tokens"),
              trimmed.range(of: #"^[─━═-]+$"#, options: .regularExpression) == nil else {
            return nil
        }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 5 else { return nil }

        let numericTokens = Array(tokens.suffix(4))
        guard let requests = sessionStatsInteger(from: numericTokens[0]),
              let inputTokens = sessionStatsInteger(from: numericTokens[1]),
              let cacheReads = sessionStatsInteger(from: numericTokens[2]),
              let outputTokens = sessionStatsInteger(from: numericTokens[3]) else {
            return nil
        }

        let name = tokens.dropLast(4).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        if name.hasPrefix("↳") {
            guard let currentModel else { return nil }
            let label = name.replacingOccurrences(of: "↳", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                GeminiSessionStatsModelUsageRow(
                    model: currentModel,
                    label: label.isEmpty ? nil : label,
                    requests: requests,
                    inputTokens: inputTokens,
                    cacheReads: cacheReads,
                    outputTokens: outputTokens
                ),
                currentModel
            )
        }

        return (
            GeminiSessionStatsModelUsageRow(
                model: name,
                label: nil,
                requests: requests,
                inputTokens: inputTokens,
                cacheReads: cacheReads,
                outputTokens: outputTokens
            ),
            name
        )
    }

    nonisolated private static func sessionStatsInteger(from value: String) -> Int? {
        let normalized = value.replacingOccurrences(of: ",", with: "")
        return Int(normalized)
    }

    nonisolated private static func sessionStatsAccountIdentifier(from authMethod: String) -> String {
        let nsRange = NSRange(authMethod.startIndex..<authMethod.endIndex, in: authMethod)
        let pattern = #"\(([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})\)"#
        if let match = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]).firstMatch(in: authMethod, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: authMethod) {
            return String(authMethod[range])
        }
        return authMethod.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func geminiSessionStatsFingerprint(for snapshot: GeminiSessionStatsSnapshot) -> String {
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        guard let data = try? encoder.encode(snapshot),
              let encoded = String(data: data, encoding: .utf8),
              !encoded.isEmpty else {
            return snapshot.sessionID
        }
        return encoded
    }

    nonisolated private static func geminiModelCapacityFingerprint(for snapshot: GeminiModelCapacitySnapshot) -> String {
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        guard let data = try? encoder.encode(snapshot),
              let encoded = String(data: data, encoding: .utf8),
              !encoded.isEmpty else {
            return [
                snapshot.startupModelCommand ?? "",
                snapshot.startupModelCommandSource ?? "",
                snapshot.currentModel ?? "",
                snapshot.rows.map { "\($0.model):\($0.usedPercentage.map(String.init) ?? ""):\($0.resetTime ?? "")" }.joined(separator: "|"),
                snapshot.rawLines.joined(separator: "|"),
            ].joined(separator: "|")
        }
        return encoded
    }

    nonisolated private static func geminiSessionStatsCaptureMessage(for snapshot: GeminiSessionStatsSnapshot) -> String {
        var parts: [String] = ["Captured Gemini session stats"]
        if !snapshot.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("for session \(snapshot.sessionID)")
        }
        if let tier = snapshot.tier?.trimmingCharacters(in: .whitespacesAndNewlines), !tier.isEmpty {
            parts.append("(\(tier))")
        }
        if let startupStatsCommand = snapshot.startupStatsCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !startupStatsCommand.isEmpty {
            parts.append("via \(startupStatsCommand)")
        }
        return parts.joined(separator: " ")
    }

    nonisolated private static func geminiModelCapacityCaptureMessage(for snapshot: GeminiModelCapacitySnapshot) -> String {
        let currentModel = snapshot.currentModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rowSummary = snapshot.rows
            .map { row -> String in
                var parts = [row.model]
                if let usedPercentage = row.usedPercentage {
                    parts.append("\(usedPercentage)% used")
                }
                if let resetTime = row.resetTime?.trimmingCharacters(in: .whitespacesAndNewlines), !resetTime.isEmpty {
                    parts.append("resets \(resetTime)")
                }
                return parts.joined(separator: " ")
            }
            .joined(separator: ", ")

        if !currentModel.isEmpty, !rowSummary.isEmpty {
            return "Captured Gemini model capacity for \(currentModel): \(rowSummary)"
        }
        if !rowSummary.isEmpty {
            return "Captured Gemini model capacity: \(rowSummary)"
        }
        if !currentModel.isEmpty {
            return "Captured Gemini current model: \(currentModel)"
        }
        return "Captured Gemini model capacity"
    }

    nonisolated static func recordedPrompt(for profile: LaunchProfile, command: String) -> String {
        if profile.agentKind == .gemini, !profile.geminiInitialPrompt.isEmpty {
            return profile.geminiInitialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let commandHint = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if profile.agentKind == .copilot {
            return commandHint
        }
        if commandHint.isEmpty {
            return ""
        }
        if commandHint.count > 1_200 {
            let endIndex = commandHint.index(commandHint.startIndex, offsetBy: 1_200)
            return String(commandHint[..<endIndex])
        }
        return commandHint
    }

    nonisolated private static func currentAccountIdentifier(for profile: LaunchProfile) -> String {
        if let configured = candidateAccountFromEnvironment()
            ?? candidateAccountFromGeminiConfig(profile: profile)
            ?? candidateAccountFromCloudSDK() {
            return configured
        }
        return NSUserName()
    }

    nonisolated private static func candidateAccountFromEnvironment() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["GEMINI_ACCOUNT"],
            environment["GEMINI_USER"],
            environment["GEMINI_EMAIL"],
            environment["GOOGLE_ACCOUNT"],
            environment["GOOGLE_EMAIL"],
            environment["GCP_ACCOUNT"],
            environment["USER"],
            environment["LOGNAME"],
            environment["SUDO_USER"],
            environment["C9_USER"],
            environment["USERNAME"]
        ]
        for candidate in candidates where !(candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = candidate!.trimmingCharacters(in: .whitespacesAndNewlines)
            if isLikelyAccountIdentifier(normalized) {
                return normalized
            }
        }
        return nil
    }

    nonisolated private static func candidateAccountFromGeminiConfig(profile: LaunchProfile) -> String? {
        let candidateDirectories = [
            profile.expandedGeminiISOHome,
            profile.geminiFlavor == .stable ? NSString(string: "~/.gemini-home").expandingTildeInPath : nil,
            profile.geminiFlavor == .preview ? NSString(string: "~/.gemini-preview-home").expandingTildeInPath : nil,
            profile.geminiFlavor == .nightly ? NSString(string: "~/.gemini-nightly-home").expandingTildeInPath : nil,
            NSString(string: "~/.config/gemini").expandingTildeInPath
        ]
        for directory in candidateDirectories.compactMap(\.self) {
            let expanded = NSString(string: directory).expandingTildeInPath
            if let account = candidateAccountFromDirectory(expanded) {
                return account
            }
        }
        return nil
    }

    nonisolated private static func candidateAccountFromCloudSDK() -> String? {
        let candidates = [
            "~/.config/gcloud/configurations/config_default",
            "~/.config/gcloud/active_config",
            "~/.config/gcloud/configurations/configurations.properties"
        ]
        for candidate in candidates {
            let path = NSString(string: candidate).expandingTildeInPath
            if let account = candidateAccountFromIniFile(at: path) {
                return account
            }
        }
        return nil
    }

    nonisolated private static func candidateAccountFromDirectory(_ directory: String) -> String? {
        let candidateFiles = [
            "settings.json",
            "config.json",
            "state.json",
            "credential.json",
            "credentials.json",
            "auth.json",
            "tokens.json",
            "session.json"
        ]

        for candidate in candidateFiles {
            let path = NSString(string: directory).appendingPathComponent(candidate)
            if let account = candidateAccountFromJSONObjectFile(at: path) {
                return account
            }
            if let account = candidateAccountFromIniFile(at: path) {
                return account
            }
        }
        return nil
    }

    nonisolated private static func candidateAccountFromJSONObjectFile(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return extractAccountIdentifier(from: data)
    }

    nonisolated private static func candidateAccountFromIniFile(at path: String) -> String? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return extractAccountIdentifier(from: raw)
    }

    nonisolated private static func extractAccountIdentifier(from rawText: String) -> String? {
        let lines = rawText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            if let keyValueRange = line.range(of: "=") {
                let key = String(line[..<keyValueRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = String(line[keyValueRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isLikelyAccountIdentifier(value), isLikelyAccountKey(key) {
                    return value
                }
            }
        }

        guard let data = rawText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return extractAccountIdentifier(from: json)
    }

    nonisolated private static func extractAccountIdentifier(from json: Any, depth: Int = 0) -> String? {
        guard depth <= 4 else { return nil }

        if let text = json as? String {
            if isLikelyAccountIdentifier(text) { return text }
            return nil
        }

        if let dict = json as? [String: Any] {
            for (rawKey, value) in dict {
                let key = rawKey.lowercased()
                if isLikelyAccountKey(key),
                   let valueText = value as? String,
                   isLikelyAccountIdentifier(valueText) {
                    return valueText
                }
                if let nested = extractAccountIdentifier(from: value, depth: depth + 1) {
                    return nested
                }
            }
            return nil
        }

        if let list = json as? [Any] {
            for item in list {
                if let nested = extractAccountIdentifier(from: item, depth: depth + 1) {
                    return nested
                }
            }
        }

        return nil
    }

    nonisolated private static func isLikelyAccountKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens: [String] = [
            "account",
            "user",
            "email",
            "username",
            "subject",
            "principal",
            "sub",
            "email_address"
        ]
        return tokens.contains { normalized == $0 || normalized.contains($0) }
    }

    nonisolated private static func isLikelyAccountIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.contains(" ") { return false }
        if trimmed.contains("/") { return false }
        if trimmed.count < 3 { return false }
        let emailComponents = trimmed.split(separator: "@")
        if emailComponents.count == 2,
           let local = emailComponents.first,
           let domain = emailComponents.last,
           !local.isEmpty,
           domain.contains("."),
           let firstDomainLabel = domain.split(separator: ".").first,
           !firstDomainLabel.isEmpty {
            return true
        }

        return trimmed.contains("_") || trimmed.contains("-") || trimmed.contains(".")
    }

    nonisolated private static func readCompletionMarker(at path: String) -> SessionCompletionMarker? {
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? String(contentsOfFile: path, encoding: .utf8)
        else {
            return nil
        }

        var fields: [String: String] = [:]
        for line in raw.split(whereSeparator: \.isNewline) {
            let pieces = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            fields[pieces[0]] = pieces[1]
        }

        guard let exitCodeText = fields["exit_code"], let exitCode = Int(exitCodeText) else {
            return nil
        }
        let endedAt = MonitorTimestamp.parse(fields["ended_at"]) ?? Date()
        let reason = fields["reason"] ?? "command_finished"
        return SessionCompletionMarker(exitCode: exitCode, endedAt: endedAt, reason: reason)
    }

    nonisolated private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.fileReadNoSuchFile.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == 2 {
            return true
        }
        return false
    }

    private func shellQuote(_ raw: String) -> String {
        let expanded = NSString(string: raw).expandingTildeInPath
        return "'" + expanded.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    nonisolated private static func sessionActivityDate(_ session: TerminalMonitorSession) -> Date {
        session.lastActivityAt ?? session.endedAt ?? session.startedAt
    }
}
