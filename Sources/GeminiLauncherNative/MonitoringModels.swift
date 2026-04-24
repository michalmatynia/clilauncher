import Foundation

enum TerminalTranscriptCaptureMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case outputOnly = "output_only"
    case inputAndOutput = "input_and_output"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .outputOnly: return "Output only"
        case .inputAndOutput: return "Input + output"
        }
    }

    var usesScriptKeyLogging: Bool {
        self == .inputAndOutput
    }
}

struct MongoMonitoringSettings: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var enableMongoWrites: Bool = false
    var connectionURL: String = "mongodb://127.0.0.1:27017"
    var schemaName: String = "clilauncher_monitor"
    var transcriptDirectory: String = AppPaths.defaultTranscriptDirectoryPath
    var captureMode: TerminalTranscriptCaptureMode = .outputOnly
    var mongoshExecutable: String = "mongosh"
    var mongodExecutable: String = "mongod"
    var scriptExecutable: String = "/usr/bin/script"
    var pollingIntervalMs: Int = 700
    var previewCharacterLimit: Int = 1_200
    var keepLocalTranscriptFiles: Bool = true
    var recentHistoryLimit: Int = 50
    var recentHistoryLookbackDays: Int = 7
    var detailEventLimit: Int = 80
    var detailChunkLimit: Int = 120
    var transcriptPreviewByteLimit: Int = 180_000
    var databaseRetentionDays: Int = 30
    var localTranscriptRetentionDays: Int = 30
    var localDataDirectory: String = AppPaths.mongoDataDirectoryPath

    init() {}

    enum CodingKeys: String, CodingKey {
        case enabled, enableMongoWrites = "enablePostgresWrites", connectionURL, schemaName, transcriptDirectory
        case captureMode, mongoshExecutable = "psqlExecutable", mongodExecutable, scriptExecutable, pollingIntervalMs
        case previewCharacterLimit, keepLocalTranscriptFiles
        case recentHistoryLimit, recentHistoryLookbackDays
        case detailEventLimit, detailChunkLimit
        case transcriptPreviewByteLimit
        case databaseRetentionDays, localTranscriptRetentionDays
        case localDataDirectory
    }

    init(from decoder: Decoder) throws {
        let defaults = Self()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        enabled = try container.decodeDefault(Bool.self, forKey: .enabled, default: defaults.enabled)
        enableMongoWrites = try container.decodeDefault(Bool.self, forKey: .enableMongoWrites, default: defaults.enableMongoWrites)
        connectionURL = try container.decodeDefault(String.self, forKey: .connectionURL, default: defaults.connectionURL)
        schemaName = try container.decodeDefault(String.self, forKey: .schemaName, default: defaults.schemaName)
        transcriptDirectory = try container.decodeDefault(String.self, forKey: .transcriptDirectory, default: defaults.transcriptDirectory)
        captureMode = try container.decodeDefault(TerminalTranscriptCaptureMode.self, forKey: .captureMode, default: defaults.captureMode)
        mongoshExecutable = try container.decodeDefault(String.self, forKey: .mongoshExecutable, default: defaults.mongoshExecutable)
        mongodExecutable = try container.decodeDefault(String.self, forKey: .mongodExecutable, default: defaults.mongodExecutable)
        scriptExecutable = try container.decodeDefault(String.self, forKey: .scriptExecutable, default: defaults.scriptExecutable)
        pollingIntervalMs = try container.decodeDefault(Int.self, forKey: .pollingIntervalMs, default: defaults.pollingIntervalMs)
        previewCharacterLimit = try container.decodeDefault(Int.self, forKey: .previewCharacterLimit, default: defaults.previewCharacterLimit)
        keepLocalTranscriptFiles = try container.decodeDefault(Bool.self, forKey: .keepLocalTranscriptFiles, default: defaults.keepLocalTranscriptFiles)
        recentHistoryLimit = try container.decodeDefault(Int.self, forKey: .recentHistoryLimit, default: defaults.recentHistoryLimit)
        recentHistoryLookbackDays = try container.decodeDefault(Int.self, forKey: .recentHistoryLookbackDays, default: defaults.recentHistoryLookbackDays)
        detailEventLimit = try container.decodeDefault(Int.self, forKey: .detailEventLimit, default: defaults.detailEventLimit)
        detailChunkLimit = try container.decodeDefault(Int.self, forKey: .detailChunkLimit, default: defaults.detailChunkLimit)
        transcriptPreviewByteLimit = try container.decodeDefault(Int.self, forKey: .transcriptPreviewByteLimit, default: defaults.transcriptPreviewByteLimit)
        databaseRetentionDays = try container.decodeDefault(Int.self, forKey: .databaseRetentionDays, default: defaults.databaseRetentionDays)
        localTranscriptRetentionDays = try container.decodeDefault(Int.self, forKey: .localTranscriptRetentionDays, default: defaults.localTranscriptRetentionDays)
        localDataDirectory = try container.decodeDefault(String.self, forKey: .localDataDirectory, default: defaults.localDataDirectory)
    }

    var expandedLocalDataDirectory: String {
        NSString(string: localDataDirectory).expandingTildeInPath
    }

    var trimmedConnectionURL: String {
        connectionURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var mongoConnection: MongoConnectionDescriptor {
        MongoConnectionDescriptor(rawValue: trimmedConnectionURL)
    }

    var trimmedDatabaseName: String {
        let trimmed = schemaName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "clilauncher_monitor" : trimmed
    }

    var trimmedSchemaName: String {
        let value = schemaName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "launcher_monitor" : value
    }

    var expandedTranscriptDirectory: String {
        NSString(string: transcriptDirectory).expandingTildeInPath
    }

    var redactedConnectionDescription: String {
        mongoConnection.redactedString
    }

    var clampedRecentHistoryLimit: Int {
        max(10, min(200, recentHistoryLimit))
    }

    var clampedRecentHistoryLookbackDays: Int {
        max(1, min(365, recentHistoryLookbackDays))
    }

    var clampedDetailEventLimit: Int {
        max(10, min(500, detailEventLimit))
    }

    var clampedDetailChunkLimit: Int {
        max(10, min(500, detailChunkLimit))
    }

    var clampedTranscriptPreviewByteLimit: Int {
        max(10_000, min(2_000_000, transcriptPreviewByteLimit))
    }

    var clampedDatabaseRetentionDays: Int {
        max(1, min(3_650, databaseRetentionDays))
    }

    var clampedLocalTranscriptRetentionDays: Int {
        max(1, min(3_650, localTranscriptRetentionDays))
    }
}

enum MongoTranscriptSyncState: String, CaseIterable, Codable, Identifiable, Sendable {
    case streaming
    case complete

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .streaming: return "Streaming to MongoDB"
        case .complete: return "Verified in MongoDB"
        }
    }
}

enum MongoInputSyncState: String, CaseIterable, Codable, Identifiable, Sendable {
    case streaming
    case complete

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .streaming: return "Streaming raw input to MongoDB"
        case .complete: return "Verified raw input in MongoDB"
        }
    }
}

enum TerminalMonitorStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case prepared
    case launching
    case monitoring
    case idle
    case completed
    case failed
    case stopped

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prepared: return "Prepared"
        case .launching: return "Launching"
        case .monitoring: return "Monitoring"
        case .idle: return "Idle"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        }
    }

    var systemImage: String {
        switch self {
        case .prepared: return "clock"
        case .launching: return "paperplane"
        case .monitoring: return "waveform.path.ecg"
        case .idle: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .stopped: return "stop.circle"
        }
    }
}

struct TerminalMonitorSession: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var profileID: UUID?
    var profileName: String
    var agentKind: AgentKind
    var accountIdentifier: String?
    var providerSessionID: String?
    var providerAuthMethod: String?
    var providerTier: String?
    var providerCLIVersion: String? = nil
    var providerRunnerPath: String? = nil
    var providerRunnerBuild: String? = nil
    var providerWrapperResolvedPath: String? = nil
    var providerWrapperKind: String? = nil
    var providerLaunchMode: String? = nil
    var providerShellFallbackExecutable: String? = nil
    var providerAutoContinueMode: String? = nil
    var providerPTYBackend: String? = nil
    var providerStartupClearCommand: String? = nil
    var providerStartupClearCommandSource: String? = nil
    var providerStartupClearCompleted: Bool? = nil
    var providerStartupClearReason: String?
    var providerStartupStatsCommand: String? = nil
    var providerStartupStatsCommandSource: String? = nil
    var providerModelUsageNote: String?
    var providerModelUsage: [GeminiSessionStatsModelUsageRow]?
    var providerStartupModelCommand: String? = nil
    var providerStartupModelCommandSource: String? = nil
    var providerCurrentModel: String?
    var providerModelCapacity: [GeminiModelCapacityRow]?
    var providerModelCapacityRawLines: [String]?
    var mongoTranscriptSyncState: MongoTranscriptSyncState? = nil
    var mongoTranscriptSyncSource: String? = nil
    var mongoTranscriptChunkCount: Int?
    var mongoTranscriptByteCount: Int?
    var mongoTranscriptSynchronizedAt: Date?
    var mongoInputSyncState: MongoInputSyncState? = nil
    var mongoInputSyncSource: String? = nil
    var mongoInputChunkCount: Int?
    var mongoInputByteCount: Int?
    var mongoInputSynchronizedAt: Date?
    var providerFreshSessionPrepared: Bool? = nil
    var providerFreshSessionResetReason: String?
    var providerFreshSessionRemovedPathCount: Int?
    var observedSlashCommands: [String]?
    var observedPromptSubmissions: [String]?
    var observedInteractions: [ObservedTranscriptInteractionSummary]?
    var prompt: String = ""
    var workingDirectory: String
    var transcriptPath: String
    var inputCapturePath: String? = nil
    var launchCommand: String
    var captureMode: TerminalTranscriptCaptureMode
    var startedAt = Date()
    var lastActivityAt: Date?
    var endedAt: Date?
    var chunkCount: Int = 0
    var byteCount: Int = 0
    var inputChunkCount: Int = 0
    var inputByteCount: Int = 0
    var status: TerminalMonitorStatus = .prepared
    var lastPreview: String = ""
    var lastDatabaseMessage: String = ""
    var lastError: String?
    var statusReason: String?
    var exitCode: Int?
    var isHistorical: Bool = false
    var isYolo: Bool = false

    var hasLocalTranscriptFile: Bool {
        let expanded = NSString(string: transcriptPath).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }

    var hasLocalInputCaptureFile: Bool {
        guard let inputCapturePath else { return false }
        let expanded = NSString(string: inputCapturePath).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }

    var activityDate: Date {
        lastActivityAt ?? endedAt ?? startedAt
    }

    var duration: TimeInterval? {
        guard let endDate = endedAt ?? lastActivityAt else { return nil }
        return max(0, endDate.timeIntervalSince(startedAt))
    }

    var mongoTranscriptSyncSourceDisplayName: String? {
        guard let mongoTranscriptSyncSource else { return nil }
        switch mongoTranscriptSyncSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "live_chunk_capture":
            return "Live chunk capture"
        case "local_transcript_file":
            return "Local transcript file"
        case "local_transcript_directory_scan":
            return "Recovered local transcript file"
        default:
            return mongoTranscriptSyncSource
        }
    }

    var mongoInputSyncSourceDisplayName: String? {
        guard let mongoInputSyncSource else { return nil }
        switch mongoInputSyncSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "live_input_capture":
            return "Live raw input capture"
        case "local_input_capture_file":
            return "Local raw input capture file"
        default:
            return mongoInputSyncSource
        }
    }
}

struct TerminalSessionEvent: Codable, Identifiable, Equatable, Sendable {
    var id: Int64
    var sessionID: UUID
    var eventType: String
    var status: TerminalMonitorStatus
    var eventAt: Date
    var message: String?
    var metadataJSON: String?
}

struct ObservedTranscriptInteractionSummary: Codable, Equatable, Sendable {
    var text: String
    var kind: ObservedTranscriptInteraction.Kind
    var source: String
    var firstObservedAt: Date
    var lastObservedAt: Date
    var observationCount: Int

    var sourceDisplayName: String {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "echoed_transcript":
            return "Echoed transcript"
        case "local_transcript_file":
            return "Full local transcript"
        case "local_transcript_preview":
            return "Local transcript preview"
        default:
            return source
        }
    }
}

struct ObservedTranscriptInteraction: Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case slashCommand = "slash_command"
        case prompt = "prompt"

        var displayName: String {
            switch self {
            case .slashCommand:
                return "Slash command"
            case .prompt:
                return "Prompt"
            }
        }
    }

    var text: String
    var kind: Kind
    var source: String

    var sourceDisplayName: String {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "echoed_transcript":
            return "Echoed transcript"
        case "local_transcript_file":
            return "Full local transcript"
        case "local_transcript_preview":
            return "Local transcript preview"
        default:
            return source
        }
    }
}

extension TerminalSessionEvent {
    var observedTranscriptInteraction: ObservedTranscriptInteraction? {
        let kind: ObservedTranscriptInteraction.Kind
        switch eventType {
        case "slash_command_observed":
            kind = .slashCommand
        case "prompt_observed":
            kind = .prompt
        default:
            return nil
        }

        guard let metadataJSON,
              let data = metadataJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let text = (object["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = (object["source"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, !source.isEmpty else { return nil }

        return ObservedTranscriptInteraction(text: text, kind: kind, source: source)
    }
}

struct TerminalTranscriptChunk: Codable, Identifiable, Equatable, Sendable {
    var id: Int64
    var sessionID: UUID
    var chunkIndex: Int
    var source: String
    var capturedAt: Date
    var byteCount: Int
    var previewText: String
    var text: String
    var promptSnapshot: String? = nil
    var sessionStatus: TerminalMonitorStatus? = nil
    var sessionStatusReason: String? = nil
    var sessionMessage: String? = nil

    var sourceDisplayName: String {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "terminal_transcript_input_output":
            return "Transcript capture (input + output)"
        case "terminal_transcript_output_only":
            return "Transcript capture (output only)"
        case "terminal_transcript":
            return "Transcript capture"
        default:
            return source
        }
    }
}

struct TerminalInputChunk: Codable, Identifiable, Equatable, Sendable {
    var id: Int64
    var sessionID: UUID
    var inputIndex: Int
    var source: String
    var capturedAt: Date
    var byteCount: Int
    var previewText: String
    var text: String
    var promptSnapshot: String? = nil
    var sessionStatus: TerminalMonitorStatus? = nil
    var sessionStatusReason: String? = nil
    var sessionMessage: String? = nil

    var sourceDisplayName: String {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "terminal_stdin_raw_capture":
            return "Raw stdin capture"
        case "terminal_stdin_raw_file":
            return "Recovered raw stdin capture"
        default:
            return source
        }
    }
}

enum TerminalSessionIOTimelineEntryKind: String, Codable, Equatable, Sendable {
    case stdin
    case transcript

    var displayName: String {
        switch self {
        case .stdin:
            return "Stdin"
        case .transcript:
            return "Transcript"
        }
    }

    var systemImage: String {
        switch self {
        case .stdin:
            return "arrow.down.circle"
        case .transcript:
            return "arrow.up.circle"
        }
    }
}

struct TerminalSessionIOTimelineEntry: Identifiable, Equatable, Sendable {
    var id: String
    var kind: TerminalSessionIOTimelineEntryKind
    var sequenceNumber: Int
    var capturedAt: Date
    var byteCount: Int
    var sourceDisplayName: String
    var previewText: String
    var text: String
    var promptSnapshot: String? = nil
    var sessionStatus: TerminalMonitorStatus? = nil
    var sessionStatusReason: String? = nil
    var sessionMessage: String? = nil
}

enum MonitorDetailLoadWorkload: String, Codable, Equatable, Sendable {
    case summary
    case history

    var includesHistory: Bool {
        self == .history
    }

    func merged(with other: MonitorDetailLoadWorkload) -> MonitorDetailLoadWorkload {
        includesHistory || other.includesHistory ? .history : .summary
    }
}

struct TerminalMonitorSessionDetails: Codable, Equatable, Sendable {
    var sessionID: UUID
    var loadedAt = Date()
    var workload: MonitorDetailLoadWorkload = .summary
    var sessionStatus: TerminalMonitorStatus
    var sessionChunkCount: Int
    var sessionByteCount: Int
    var sessionInputChunkCount: Int = 0
    var sessionInputByteCount: Int = 0
    var sessionEndedAt: Date?
    var transcriptText: String = ""
    var transcriptSourceDescription: String = ""
    var transcriptTruncated: Bool = false
    var events: [TerminalSessionEvent] = []
    var chunks: [TerminalTranscriptChunk] = []
    var inputChunks: [TerminalInputChunk] = []
    var eventsTruncated: Bool = false
    var chunksTruncated: Bool = false
    var inputChunksTruncated: Bool = false
    var loadSummary: String = ""

    var historyLoaded: Bool {
        workload.includesHistory
    }

    var ioTimelineEntries: [TerminalSessionIOTimelineEntry] {
        let inputEntries = inputChunks.map { chunk in
            TerminalSessionIOTimelineEntry(
                id: "stdin-\(chunk.inputIndex)",
                kind: .stdin,
                sequenceNumber: chunk.inputIndex,
                capturedAt: chunk.capturedAt,
                byteCount: chunk.byteCount,
                sourceDisplayName: chunk.sourceDisplayName,
                previewText: chunk.previewText,
                text: chunk.text,
                promptSnapshot: chunk.promptSnapshot,
                sessionStatus: chunk.sessionStatus,
                sessionStatusReason: chunk.sessionStatusReason,
                sessionMessage: chunk.sessionMessage
            )
        }

        let transcriptEntries = chunks.map { chunk in
            TerminalSessionIOTimelineEntry(
                id: "transcript-\(chunk.chunkIndex)",
                kind: .transcript,
                sequenceNumber: chunk.chunkIndex,
                capturedAt: chunk.capturedAt,
                byteCount: chunk.byteCount,
                sourceDisplayName: chunk.sourceDisplayName,
                previewText: chunk.previewText,
                text: chunk.text,
                promptSnapshot: chunk.promptSnapshot,
                sessionStatus: chunk.sessionStatus,
                sessionStatusReason: chunk.sessionStatusReason,
                sessionMessage: chunk.sessionMessage
            )
        }

        return (inputEntries + transcriptEntries).sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt {
                return lhs.capturedAt < rhs.capturedAt
            }
            if lhs.kind != rhs.kind {
                return lhs.kind == .stdin
            }
            if lhs.sequenceNumber != rhs.sequenceNumber {
                return lhs.sequenceNumber < rhs.sequenceNumber
            }
            return lhs.id < rhs.id
        }
    }

    func matches(_ session: TerminalMonitorSession) -> Bool {
        sessionID == session.id &&
        sessionStatus == session.status &&
        sessionChunkCount == session.chunkCount &&
        sessionByteCount == session.byteCount &&
        sessionInputChunkCount == session.inputChunkCount &&
        sessionInputByteCount == session.inputByteCount &&
        sessionEndedAt == session.endedAt
    }

    func satisfies(_ requestedWorkload: MonitorDetailLoadWorkload) -> Bool {
        requestedWorkload == .summary || historyLoaded
    }
}

struct MongoStorageSummary: Codable, Equatable, Sendable {
    var sessionCount: Int = 0
    var activeSessionCount: Int = 0
    var completedSessionCount: Int = 0
    var failedSessionCount: Int = 0
    var transcriptCompleteSessionCount: Int = 0
    var transcriptStreamingSessionCount: Int = 0
    var transcriptCoverageUnknownSessionCount: Int = 0
    var inputCompleteSessionCount: Int = 0
    var inputStreamingSessionCount: Int = 0
    var inputCoverageUnknownSessionCount: Int = 0
    var chunkCount: Int = 0
    var inputChunkCount: Int = 0
    var eventCount: Int = 0
    var logicalTranscriptBytes: Int64 = 0
    var logicalInputBytes: Int64 = 0
    var sessionTableBytes: Int64 = 0
    var chunkTableBytes: Int64 = 0
    var inputChunkTableBytes: Int64 = 0
    var eventTableBytes: Int64 = 0
    var oldestSessionAt: Date?
    var newestSessionAt: Date?
    var transcriptFileCount: Int = 0
    var transcriptFileBytes: Int64 = 0
    var oldestTranscriptFileAt: Date?
    var newestTranscriptFileAt: Date?
    var inputCaptureFileCount: Int = 0
    var inputCaptureFileBytes: Int64 = 0
    var oldestInputCaptureFileAt: Date?
    var newestInputCaptureFileAt: Date?

    var totalDatabaseBytes: Int64 {
        sessionTableBytes + chunkTableBytes + inputChunkTableBytes + eventTableBytes
    }

    var hasPhysicalDatabaseBreakdown: Bool {
        sessionTableBytes > 0 || chunkTableBytes > 0 || inputChunkTableBytes > 0 || eventTableBytes > 0
    }

    var logicalDatabaseBytes: Int64 {
        logicalTranscriptBytes + logicalInputBytes
    }

    var effectiveDatabaseBytes: Int64 {
        max(totalDatabaseBytes, logicalDatabaseBytes)
    }

    var totalKnownBytes: Int64 {
        effectiveDatabaseBytes + transcriptFileBytes + inputCaptureFileBytes
    }

    var hasAnyData: Bool {
        sessionCount > 0 || chunkCount > 0 || inputChunkCount > 0 || eventCount > 0 || transcriptFileCount > 0 || inputCaptureFileCount > 0
    }
}

struct MongoPruneSummary: Codable, Equatable, Sendable {
    var executedAt = Date()
    var cutoffDate: Date
    var deletedSessions: Int = 0
    var deletedChunks: Int = 0
    var deletedInputChunks: Int = 0
    var deletedEvents: Int = 0
    var deletedChunkBytes: Int64 = 0
    var deletedInputChunkBytes: Int64 = 0
    var deletedTranscriptFiles: Int = 0
    var deletedTranscriptBytes: Int64 = 0
    var deletedInputCaptureFiles: Int = 0
    var deletedInputCaptureBytes: Int64 = 0

    var didDeleteAnything: Bool {
        deletedSessions > 0 || deletedChunks > 0 || deletedInputChunks > 0 || deletedEvents > 0 || deletedTranscriptFiles > 0 || deletedInputCaptureFiles > 0
    }
}

struct MongoClearSummary: Codable, Equatable, Sendable {
    var deletedSessions: Int = 0
    var deletedChunks: Int = 0
    var deletedInputChunks: Int = 0
    var deletedEvents: Int = 0

    var didDeleteAnything: Bool {
        deletedSessions > 0 || deletedChunks > 0 || deletedInputChunks > 0 || deletedEvents > 0
    }
}

// Backward-compatible aliases preserved temporarily for builds that still reference legacy type names.
@available(*, deprecated, renamed: "MongoMonitoringSettings")
typealias PostgresMonitoringSettings = MongoMonitoringSettings
@available(*, deprecated, renamed: "MongoStorageSummary")
typealias PostgresStorageSummary = MongoStorageSummary
@available(*, deprecated, renamed: "MongoPruneSummary")
typealias PostgresPruneSummary = MongoPruneSummary
