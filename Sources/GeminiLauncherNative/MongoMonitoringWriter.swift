import Foundation

private struct MongoLaunchConfiguration: Sendable {
    var executablePath: String
    var arguments: [String]
    var connectionURL: String
    var environment: [String: String]
}

struct MongoSessionChunkSummary: Equatable, Sendable {
    var chunkCount: Int
    var byteCount: Int64
    var minChunkIndex: Int? = nil
    var maxChunkIndex: Int? = nil

    var hasContiguousChunkIndexes: Bool {
        guard chunkCount > 0,
              let minChunkIndex,
              let maxChunkIndex else {
            return false
        }
        return minChunkIndex == 1 && maxChunkIndex == chunkCount
    }
}

struct DatabaseObservedTranscriptInteractionRow: Decodable {
    var text: String
    var kind: String
    var source: String
    var first_observed_at_epoch: Double
    var last_observed_at_epoch: Double
    var observation_count: Int

    func makeSummary() -> ObservedTranscriptInteractionSummary? {
        guard let resolvedKind = ObservedTranscriptInteraction.Kind(rawValue: kind) else {
            return nil
        }
        return ObservedTranscriptInteractionSummary(
            text: text,
            kind: resolvedKind,
            source: source,
            firstObservedAt: Date(timeIntervalSince1970: first_observed_at_epoch),
            lastObservedAt: Date(timeIntervalSince1970: last_observed_at_epoch),
            observationCount: observation_count
        )
    }
}

struct DatabaseSessionRow: Decodable {
    var session_id: String
    var profile_id: String?
    var profile_name: String
    var agent_kind: String
    var account_identifier: String?
    var provider_session_id: String?
    var provider_auth_method: String?
    var provider_tier: String?
    var provider_cli_version: String?
    var provider_runner_path: String?
    var provider_runner_build: String?
    var provider_wrapper_resolved_path: String?
    var provider_wrapper_kind: String?
    var provider_launch_mode: String?
    var provider_shell_fallback_executable: String?
    var provider_auto_continue_mode: String?
    var provider_pty_backend: String?
    var provider_startup_clear_command: String?
    var provider_startup_clear_command_source: String?
    var provider_startup_clear_completed: Bool?
    var provider_startup_clear_reason: String?
    var provider_startup_stats_command: String?
    var provider_startup_stats_command_source: String?
    var provider_startup_model_command: String?
    var provider_startup_model_command_source: String?
    var provider_current_model: String?
    var provider_model_capacity: [GeminiModelCapacityRow]?
    var provider_model_capacity_raw_lines: [String]?
    var mongo_transcript_sync_state: String?
    var mongo_transcript_sync_source: String?
    var mongo_transcript_chunk_count: Int?
    var mongo_transcript_byte_count: Int?
    var mongo_transcript_synchronized_at_epoch: Double?
    var input_capture_path: String?
    var input_chunk_count: Int?
    var input_byte_count: Int?
    var mongo_input_sync_state: String?
    var mongo_input_sync_source: String?
    var mongo_input_chunk_count: Int?
    var mongo_input_byte_count: Int?
    var mongo_input_synchronized_at_epoch: Double?
    var provider_fresh_session_prepared: Bool?
    var provider_fresh_session_reset_reason: String?
    var provider_fresh_session_removed_path_count: Int?
    var provider_model_usage_note: String?
    var provider_model_usage: [GeminiSessionStatsModelUsageRow]?
    var observed_slash_commands: [String]?
    var observed_prompt_submissions: [String]?
    var observed_interactions: [DatabaseObservedTranscriptInteractionRow]?
    var prompt: String?
    var working_directory: String
    var transcript_path: String
    var launch_command: String
    var capture_mode: String
    var status: String
    var started_at_epoch: Double
    var activity_at_epoch: Double?
    var last_activity_at_epoch: Double?
    var ended_at_epoch: Double?
    var chunk_count: Int
    var byte_count: Int
    var last_error: String?
    var last_preview: String?
    var last_database_message: String?
    var status_reason: String?
    var exit_code: Int?
    var session_payload: String?

    func makeSession() -> TerminalMonitorSession {
        let sessionPayloadJSONDecoder: JSONDecoder = {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return decoder
        }()

        let resolvedSessionID = UUID(uuidString: session_id) ?? UUID()
        let resolvedProfileID = profile_id.flatMap(UUID.init(uuidString:))
        let resolvedAgentKind = AgentKind(rawValue: agent_kind) ?? .gemini
        let resolvedCaptureMode = TerminalTranscriptCaptureMode(rawValue: capture_mode) ?? .outputOnly
        let resolvedStatus = TerminalMonitorStatus(rawValue: status) ?? .failed
        let resolvedStartedAt = Date(timeIntervalSince1970: started_at_epoch)
        let resolvedLastActivityAt = last_activity_at_epoch.map(Date.init(timeIntervalSince1970:))
            ?? activity_at_epoch.map(Date.init(timeIntervalSince1970:))
        let resolvedEndedAt = ended_at_epoch.map(Date.init(timeIntervalSince1970:))

        var fallbackSession = TerminalMonitorSession(
            id: resolvedSessionID,
            profileID: resolvedProfileID,
            profileName: profile_name,
            agentKind: resolvedAgentKind,
            workingDirectory: working_directory,
            transcriptPath: transcript_path,
            launchCommand: launch_command,
            captureMode: resolvedCaptureMode
        )
        fallbackSession.accountIdentifier = account_identifier
        fallbackSession.providerSessionID = provider_session_id
        fallbackSession.providerAuthMethod = provider_auth_method
        fallbackSession.providerTier = provider_tier
        fallbackSession.providerCLIVersion = provider_cli_version
        fallbackSession.providerRunnerPath = provider_runner_path
        fallbackSession.providerRunnerBuild = provider_runner_build
        fallbackSession.providerWrapperResolvedPath = provider_wrapper_resolved_path
        fallbackSession.providerWrapperKind = provider_wrapper_kind
        fallbackSession.providerLaunchMode = provider_launch_mode
        fallbackSession.providerShellFallbackExecutable = provider_shell_fallback_executable
        fallbackSession.providerAutoContinueMode = provider_auto_continue_mode
        fallbackSession.providerPTYBackend = provider_pty_backend
        fallbackSession.providerStartupClearCommand = provider_startup_clear_command
        fallbackSession.providerStartupClearCommandSource = provider_startup_clear_command_source
        fallbackSession.providerStartupClearCompleted = provider_startup_clear_completed
        fallbackSession.providerStartupClearReason = provider_startup_clear_reason
        fallbackSession.providerStartupStatsCommand = provider_startup_stats_command
        fallbackSession.providerStartupStatsCommandSource = provider_startup_stats_command_source
        fallbackSession.providerStartupModelCommand = provider_startup_model_command
        fallbackSession.providerStartupModelCommandSource = provider_startup_model_command_source
        fallbackSession.providerCurrentModel = provider_current_model
        fallbackSession.providerModelCapacity = provider_model_capacity
        fallbackSession.providerModelCapacityRawLines = provider_model_capacity_raw_lines
        fallbackSession.mongoTranscriptSyncState = mongo_transcript_sync_state.flatMap(MongoTranscriptSyncState.init(rawValue:))
        fallbackSession.mongoTranscriptSyncSource = mongo_transcript_sync_source
        fallbackSession.mongoTranscriptChunkCount = mongo_transcript_chunk_count
        fallbackSession.mongoTranscriptByteCount = mongo_transcript_byte_count
        fallbackSession.mongoTranscriptSynchronizedAt = mongo_transcript_synchronized_at_epoch.map(Date.init(timeIntervalSince1970:))
        fallbackSession.inputCapturePath = input_capture_path
        fallbackSession.inputChunkCount = input_chunk_count ?? fallbackSession.inputChunkCount
        fallbackSession.inputByteCount = input_byte_count ?? fallbackSession.inputByteCount
        fallbackSession.mongoInputSyncState = mongo_input_sync_state.flatMap(MongoInputSyncState.init(rawValue:))
        fallbackSession.mongoInputSyncSource = mongo_input_sync_source
        fallbackSession.mongoInputChunkCount = mongo_input_chunk_count
        fallbackSession.mongoInputByteCount = mongo_input_byte_count
        fallbackSession.mongoInputSynchronizedAt = mongo_input_synchronized_at_epoch.map(Date.init(timeIntervalSince1970:))
        fallbackSession.providerFreshSessionPrepared = provider_fresh_session_prepared
        fallbackSession.providerFreshSessionResetReason = provider_fresh_session_reset_reason
        fallbackSession.providerFreshSessionRemovedPathCount = provider_fresh_session_removed_path_count
        fallbackSession.providerModelUsageNote = provider_model_usage_note
        fallbackSession.providerModelUsage = provider_model_usage
        fallbackSession.observedSlashCommands = observed_slash_commands
        fallbackSession.observedPromptSubmissions = observed_prompt_submissions
        fallbackSession.observedInteractions = observed_interactions?.compactMap { $0.makeSummary() }
        fallbackSession.prompt = prompt ?? ""
        fallbackSession.startedAt = resolvedStartedAt
        fallbackSession.lastActivityAt = resolvedLastActivityAt
        fallbackSession.endedAt = resolvedEndedAt
        fallbackSession.chunkCount = chunk_count
        fallbackSession.byteCount = byte_count
        fallbackSession.status = resolvedStatus
        fallbackSession.lastPreview = last_preview ?? ""
        fallbackSession.lastDatabaseMessage = last_database_message ?? "Loaded from MongoDB."
        fallbackSession.lastError = last_error
        fallbackSession.statusReason = status_reason
        fallbackSession.exitCode = exit_code
        fallbackSession.isHistorical = true

        guard var payloadSession = payloadBackfilledSession(decoder: sessionPayloadJSONDecoder) else {
            return fallbackSession
        }

        payloadSession.id = resolvedSessionID
        payloadSession.profileID = resolvedProfileID ?? payloadSession.profileID
        payloadSession.profileName = profile_name
        payloadSession.agentKind = resolvedAgentKind
        payloadSession.accountIdentifier = account_identifier
        payloadSession.providerSessionID = provider_session_id ?? payloadSession.providerSessionID
        payloadSession.providerAuthMethod = provider_auth_method ?? payloadSession.providerAuthMethod
        payloadSession.providerTier = provider_tier ?? payloadSession.providerTier
        payloadSession.providerCLIVersion = provider_cli_version ?? payloadSession.providerCLIVersion
        payloadSession.providerRunnerPath = provider_runner_path ?? payloadSession.providerRunnerPath
        payloadSession.providerRunnerBuild = provider_runner_build ?? payloadSession.providerRunnerBuild
        payloadSession.providerWrapperResolvedPath = provider_wrapper_resolved_path ?? payloadSession.providerWrapperResolvedPath
        payloadSession.providerWrapperKind = provider_wrapper_kind ?? payloadSession.providerWrapperKind
        payloadSession.providerLaunchMode = provider_launch_mode ?? payloadSession.providerLaunchMode
        payloadSession.providerShellFallbackExecutable = provider_shell_fallback_executable ?? payloadSession.providerShellFallbackExecutable
        payloadSession.providerAutoContinueMode = provider_auto_continue_mode ?? payloadSession.providerAutoContinueMode
        payloadSession.providerPTYBackend = provider_pty_backend ?? payloadSession.providerPTYBackend
        payloadSession.providerStartupClearCommand = provider_startup_clear_command ?? payloadSession.providerStartupClearCommand
        payloadSession.providerStartupClearCommandSource = provider_startup_clear_command_source ?? payloadSession.providerStartupClearCommandSource
        payloadSession.providerStartupClearCompleted = provider_startup_clear_completed ?? payloadSession.providerStartupClearCompleted
        payloadSession.providerStartupClearReason = provider_startup_clear_reason ?? payloadSession.providerStartupClearReason
        payloadSession.providerStartupStatsCommand = provider_startup_stats_command ?? payloadSession.providerStartupStatsCommand
        payloadSession.providerStartupStatsCommandSource = provider_startup_stats_command_source ?? payloadSession.providerStartupStatsCommandSource
        payloadSession.providerStartupModelCommand = provider_startup_model_command ?? payloadSession.providerStartupModelCommand
        payloadSession.providerStartupModelCommandSource = provider_startup_model_command_source ?? payloadSession.providerStartupModelCommandSource
        payloadSession.providerCurrentModel = provider_current_model ?? payloadSession.providerCurrentModel
        payloadSession.providerModelCapacity = provider_model_capacity ?? payloadSession.providerModelCapacity
        payloadSession.providerModelCapacityRawLines = provider_model_capacity_raw_lines ?? payloadSession.providerModelCapacityRawLines
        payloadSession.mongoTranscriptSyncState = mongo_transcript_sync_state.flatMap(MongoTranscriptSyncState.init(rawValue:)) ?? payloadSession.mongoTranscriptSyncState
        payloadSession.mongoTranscriptSyncSource = mongo_transcript_sync_source ?? payloadSession.mongoTranscriptSyncSource
        payloadSession.mongoTranscriptChunkCount = mongo_transcript_chunk_count ?? payloadSession.mongoTranscriptChunkCount
        payloadSession.mongoTranscriptByteCount = mongo_transcript_byte_count ?? payloadSession.mongoTranscriptByteCount
        payloadSession.mongoTranscriptSynchronizedAt = mongo_transcript_synchronized_at_epoch.map(Date.init(timeIntervalSince1970:)) ?? payloadSession.mongoTranscriptSynchronizedAt
        payloadSession.inputCapturePath = input_capture_path ?? payloadSession.inputCapturePath
        payloadSession.inputChunkCount = input_chunk_count ?? payloadSession.inputChunkCount
        payloadSession.inputByteCount = input_byte_count ?? payloadSession.inputByteCount
        payloadSession.mongoInputSyncState = mongo_input_sync_state.flatMap(MongoInputSyncState.init(rawValue:)) ?? payloadSession.mongoInputSyncState
        payloadSession.mongoInputSyncSource = mongo_input_sync_source ?? payloadSession.mongoInputSyncSource
        payloadSession.mongoInputChunkCount = mongo_input_chunk_count ?? payloadSession.mongoInputChunkCount
        payloadSession.mongoInputByteCount = mongo_input_byte_count ?? payloadSession.mongoInputByteCount
        payloadSession.mongoInputSynchronizedAt = mongo_input_synchronized_at_epoch.map(Date.init(timeIntervalSince1970:)) ?? payloadSession.mongoInputSynchronizedAt
        payloadSession.providerFreshSessionPrepared = provider_fresh_session_prepared ?? payloadSession.providerFreshSessionPrepared
        payloadSession.providerFreshSessionResetReason = provider_fresh_session_reset_reason ?? payloadSession.providerFreshSessionResetReason
        payloadSession.providerFreshSessionRemovedPathCount = provider_fresh_session_removed_path_count ?? payloadSession.providerFreshSessionRemovedPathCount
        payloadSession.providerModelUsageNote = provider_model_usage_note ?? payloadSession.providerModelUsageNote
        payloadSession.providerModelUsage = provider_model_usage ?? payloadSession.providerModelUsage
        payloadSession.observedSlashCommands = observed_slash_commands ?? payloadSession.observedSlashCommands
        payloadSession.observedPromptSubmissions = observed_prompt_submissions ?? payloadSession.observedPromptSubmissions
        payloadSession.observedInteractions = observed_interactions?.compactMap { $0.makeSummary() } ?? payloadSession.observedInteractions
        if let prompt {
            payloadSession.prompt = prompt
        }
        payloadSession.workingDirectory = working_directory
        payloadSession.transcriptPath = transcript_path
        payloadSession.launchCommand = launch_command
        payloadSession.captureMode = resolvedCaptureMode
        payloadSession.status = resolvedStatus
        payloadSession.startedAt = resolvedStartedAt
        payloadSession.lastActivityAt = resolvedLastActivityAt
        payloadSession.endedAt = resolvedEndedAt
        payloadSession.chunkCount = chunk_count
        payloadSession.byteCount = byte_count
        payloadSession.lastPreview = last_preview ?? payloadSession.lastPreview
        payloadSession.lastDatabaseMessage = last_database_message ?? payloadSession.lastDatabaseMessage
        payloadSession.lastError = last_error
        payloadSession.statusReason = status_reason
        payloadSession.exitCode = exit_code
        payloadSession.isHistorical = true
        return payloadSession
    }

    private func payloadBackfilledSession(decoder: JSONDecoder) -> TerminalMonitorSession? {
        guard let rawPayload = session_payload?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPayload.isEmpty,
              let payloadData = rawPayload.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(TerminalMonitorSession.self, from: payloadData)
    }
}

private struct DatabaseSessionEventRow: Decodable {
    var id: Int64
    var session_id: String
    var event_type: String
    var status: String
    var event_at_epoch: Double
    var message: String?
    var metadata_json: String?

    func makeEvent() -> TerminalSessionEvent {
        TerminalSessionEvent(
            id: id,
            sessionID: UUID(uuidString: session_id) ?? UUID(),
            eventType: event_type,
            status: TerminalMonitorStatus(rawValue: status) ?? .failed,
            eventAt: Date(timeIntervalSince1970: event_at_epoch),
            message: message,
            metadataJSON: metadata_json
        )
    }
}

private struct DatabaseSessionChunkRow: Decodable {
    var id: Int64
    var session_id: String
    var chunk_index: Int
    var source: String
    var captured_at_epoch: Double
    var byte_count: Int
    var prompt: String?
    var preview_text: String
    var raw_base64: String
    var status: String?
    var status_reason: String?
    var message: String?

    func makeChunk() -> TerminalTranscriptChunk {
        TerminalTranscriptChunk(
            id: id,
            sessionID: UUID(uuidString: session_id) ?? UUID(),
            chunkIndex: chunk_index,
            source: source,
            capturedAt: Date(timeIntervalSince1970: captured_at_epoch),
            byteCount: byte_count,
            previewText: preview_text,
            text: decodedTerminalText(from: raw_base64),
            promptSnapshot: prompt,
            sessionStatus: status.flatMap(TerminalMonitorStatus.init(rawValue:)),
            sessionStatusReason: status_reason,
            sessionMessage: message
        )
    }

    private func decodedTerminalText(from rawBase64: String) -> String {
        guard let data = Data(base64Encoded: rawBase64) else { return "" }
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{0000}", with: "")
    }
}

private struct DatabaseSessionInputChunkRow: Decodable {
    var id: Int64
    var session_id: String
    var input_index: Int
    var source: String
    var captured_at_epoch: Double
    var byte_count: Int
    var prompt: String?
    var preview_text: String
    var raw_base64: String
    var status: String?
    var status_reason: String?
    var message: String?

    func makeChunk() -> TerminalInputChunk {
        TerminalInputChunk(
            id: id,
            sessionID: UUID(uuidString: session_id) ?? UUID(),
            inputIndex: input_index,
            source: source,
            capturedAt: Date(timeIntervalSince1970: captured_at_epoch),
            byteCount: byte_count,
            previewText: preview_text,
            text: decodedTerminalText(from: raw_base64),
            promptSnapshot: prompt,
            sessionStatus: status.flatMap(TerminalMonitorStatus.init(rawValue:)),
            sessionStatusReason: status_reason,
            sessionMessage: message
        )
    }

    private func decodedTerminalText(from rawBase64: String) -> String {
        guard let data = Data(base64Encoded: raw_base64) else { return "" }
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{0000}", with: "")
    }
}

struct DatabaseStorageSummaryRow: Decodable {
    var session_count: Int
    var active_session_count: Int
    var completed_session_count: Int
    var failed_session_count: Int
    var transcript_complete_session_count: Int
    var transcript_streaming_session_count: Int
    var transcript_coverage_unknown_session_count: Int
    var input_complete_session_count: Int
    var input_streaming_session_count: Int
    var input_coverage_unknown_session_count: Int
    var chunk_count: Int
    var input_chunk_count: Int
    var event_count: Int
    var logical_transcript_bytes: Int64
    var logical_input_bytes: Int64
    var session_table_bytes: Int64
    var chunk_table_bytes: Int64
    var input_chunk_table_bytes: Int64
    var event_table_bytes: Int64
    var oldest_session_at_epoch: Double?
    var newest_session_at_epoch: Double?

    func makeSummary() -> MongoStorageSummary {
        MongoStorageSummary(
            sessionCount: session_count,
            activeSessionCount: active_session_count,
            completedSessionCount: completed_session_count,
            failedSessionCount: failed_session_count,
            transcriptCompleteSessionCount: transcript_complete_session_count,
            transcriptStreamingSessionCount: transcript_streaming_session_count,
            transcriptCoverageUnknownSessionCount: transcript_coverage_unknown_session_count,
            inputCompleteSessionCount: input_complete_session_count,
            inputStreamingSessionCount: input_streaming_session_count,
            inputCoverageUnknownSessionCount: input_coverage_unknown_session_count,
            chunkCount: chunk_count,
            inputChunkCount: input_chunk_count,
            eventCount: event_count,
            logicalTranscriptBytes: logical_transcript_bytes,
            logicalInputBytes: logical_input_bytes,
            sessionTableBytes: session_table_bytes,
            chunkTableBytes: chunk_table_bytes,
            inputChunkTableBytes: input_chunk_table_bytes,
            eventTableBytes: event_table_bytes,
            oldestSessionAt: oldest_session_at_epoch.map(Date.init(timeIntervalSince1970:)),
            newestSessionAt: newest_session_at_epoch.map(Date.init(timeIntervalSince1970:))
        )
    }
}

private struct DatabaseSessionChunkSummaryRow: Decodable {
    var chunk_count: Int
    var byte_count: Int64
    var min_chunk_index: Int?
    var max_chunk_index: Int?

    func makeSummary() -> MongoSessionChunkSummary {
        MongoSessionChunkSummary(
            chunkCount: chunk_count,
            byteCount: byte_count,
            minChunkIndex: min_chunk_index,
            maxChunkIndex: max_chunk_index
        )
    }
}

actor MongoMonitoringWriter {
    private static let sessionDocumentEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let mongoRowDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private let commandBuilder = CommandBuilder()
    private var initializedFingerprint: String?

    nonisolated static func schemaInitializationFingerprint(for settings: MongoMonitoringSettings) -> String {
        settings.trimmedConnectionURL + "|" + settings.trimmedSchemaName + "|" + settings.expandedLocalDataDirectory
    }

    nonisolated static func needsSchemaInitialization(currentFingerprint: String?, nextFingerprint: String) -> Bool {
        currentFingerprint != nextFingerprint
    }

    nonisolated static func mongoNullableDateExpression(_ payloadPath: String) -> String {
        "\(payloadPath) != null ? new Date(\(payloadPath)) : null"
    }

    nonisolated static let mongoUpsertOptionsScript = "{ upsert: true }"

    nonisolated static func mongoProviderModelUsageDocument(_ rows: [GeminiSessionStatsModelUsageRow]?) -> Any {
        guard let rows, !rows.isEmpty else { return NSNull() }
        return rows.map { row in
            var result: [String: Any] = ["model": row.model]
            if let label = row.label, !label.isEmpty {
                result["label"] = label
            }
            if let requests = row.requests {
                result["requests"] = requests
            }
            if let inputTokens = row.inputTokens {
                result["inputTokens"] = inputTokens
            }
            if let cacheReads = row.cacheReads {
                result["cacheReads"] = cacheReads
            }
            if let outputTokens = row.outputTokens {
                result["outputTokens"] = outputTokens
            }
            return result
        }
    }

    nonisolated static func mongoProviderModelCapacityDocument(_ rows: [GeminiModelCapacityRow]?) -> Any {
        guard let rows, !rows.isEmpty else { return NSNull() }
        return rows.map { row in
            var result: [String: Any] = ["model": row.model]
            if let usedPercentage = row.usedPercentage {
                result["used_percentage"] = usedPercentage
            }
            if let resetTime = row.resetTime, !resetTime.isEmpty {
                result["reset_time"] = resetTime
            }
            if let rawText = row.rawText, !rawText.isEmpty {
                result["raw_text"] = rawText
            }
            return result
        }
    }

    nonisolated static func mongoObservedInteractionDocuments(_ rows: [ObservedTranscriptInteractionSummary]?) -> Any {
        guard let rows, !rows.isEmpty else { return NSNull() }
        return rows.map { row in
            [
                "text": row.text,
                "kind": row.kind.rawValue,
                "source": row.source,
                "first_observed_at": Int64(row.firstObservedAt.timeIntervalSince1970 * 1_000),
                "last_observed_at": Int64(row.lastObservedAt.timeIntervalSince1970 * 1_000),
                "observation_count": row.observationCount
            ]
        }
    }

    nonisolated static func recordSessionStartScript(configLiteral: String, payloadLiteral: String) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(configLiteral));
            const payload = JSON.parse(\(payloadLiteral));
            const targetDb = db.getSiblingDB(cfg.cfg);
            targetDb.terminal_sessions.updateOne(
                { session_id: payload.session_id },
                {
                    $set: {
                        profile_id: payload.profile_id,
                        profile_name: payload.profile_name,
                        agent_kind: payload.agent_kind,
                        account_identifier: payload.account_identifier,
                        provider_session_id: payload.provider_session_id,
                        provider_auth_method: payload.provider_auth_method,
                        provider_tier: payload.provider_tier,
                        provider_cli_version: payload.provider_cli_version,
                        provider_runner_path: payload.provider_runner_path,
                        provider_runner_build: payload.provider_runner_build,
                        provider_wrapper_resolved_path: payload.provider_wrapper_resolved_path,
                        provider_wrapper_kind: payload.provider_wrapper_kind,
                        provider_launch_mode: payload.provider_launch_mode,
                        provider_shell_fallback_executable: payload.provider_shell_fallback_executable,
                        provider_auto_continue_mode: payload.provider_auto_continue_mode,
                        provider_pty_backend: payload.provider_pty_backend,
                        provider_startup_clear_command: payload.provider_startup_clear_command,
                        provider_startup_clear_command_source: payload.provider_startup_clear_command_source,
                        provider_startup_clear_completed: payload.provider_startup_clear_completed,
                        provider_startup_clear_reason: payload.provider_startup_clear_reason,
                        provider_startup_stats_command: payload.provider_startup_stats_command,
                        provider_startup_stats_command_source: payload.provider_startup_stats_command_source,
                        provider_startup_model_command: payload.provider_startup_model_command,
                        provider_startup_model_command_source: payload.provider_startup_model_command_source,
                        provider_current_model: payload.provider_current_model,
                        provider_model_capacity: payload.provider_model_capacity,
                        provider_model_capacity_raw_lines: payload.provider_model_capacity_raw_lines,
                        mongo_transcript_sync_state: payload.mongo_transcript_sync_state,
                        mongo_transcript_sync_source: payload.mongo_transcript_sync_source,
                        mongo_transcript_chunk_count: payload.mongo_transcript_chunk_count,
                        mongo_transcript_byte_count: payload.mongo_transcript_byte_count,
                        mongo_transcript_synchronized_at: \(Self.mongoNullableDateExpression("payload.mongo_transcript_synchronized_at")),
                        input_capture_path: payload.input_capture_path,
                        input_chunk_count: payload.input_chunk_count,
                        input_byte_count: payload.input_byte_count,
                        mongo_input_sync_state: payload.mongo_input_sync_state,
                        mongo_input_sync_source: payload.mongo_input_sync_source,
                        mongo_input_chunk_count: payload.mongo_input_chunk_count,
                        mongo_input_byte_count: payload.mongo_input_byte_count,
                        mongo_input_synchronized_at: \(Self.mongoNullableDateExpression("payload.mongo_input_synchronized_at")),
                        provider_fresh_session_prepared: payload.provider_fresh_session_prepared,
                        provider_fresh_session_reset_reason: payload.provider_fresh_session_reset_reason,
                        provider_fresh_session_removed_path_count: payload.provider_fresh_session_removed_path_count,
                        provider_model_usage_note: payload.provider_model_usage_note,
                        provider_model_usage: payload.provider_model_usage,
                        observed_slash_commands: payload.observed_slash_commands,
                        observed_prompt_submissions: payload.observed_prompt_submissions,
                        observed_interactions: payload.observed_interactions,
                        prompt: payload.prompt,
                        working_directory: payload.working_directory,
                        transcript_path: payload.transcript_path,
                        launch_command: payload.launch_command,
                        capture_mode: payload.capture_mode,
                        session_payload: payload.session_payload,
                        status: payload.status,
                        started_at: new Date(payload.started_at),
                        activity_at: new Date(payload.activity_at),
                        last_activity_at: \(Self.mongoNullableDateExpression("payload.last_activity_at")),
                        ended_at: \(Self.mongoNullableDateExpression("payload.ended_at")),
                        chunk_count: payload.chunk_count,
                        byte_count: payload.byte_count,
                        last_error: payload.last_error,
                        last_preview: payload.last_preview,
                        last_database_message: payload.last_database_message,
                        status_reason: payload.status_reason,
                        exit_code: payload.exit_code,
                        metadata_json: payload.metadata_json
                    },
                    $setOnInsert: {
                        session_id: payload.session_id
                    }
                },
                \(Self.mongoUpsertOptionsScript)
            );

            targetDb.terminal_session_events.insertOne({
                session_id: payload.session_id,
                event_type: "session_started",
                status: payload.status,
                event_at: new Date(payload.started_at),
                message: "Session registered for monitoring.",
                metadata_json: payload.metadata_json
            });
            print("ok");
        })();
        """
    }

    nonisolated static func recordObservedInteractionSummaryScript(configLiteral: String, payloadLiteral: String) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(configLiteral));
            const payload = JSON.parse(\(payloadLiteral));
            const targetDb = db.getSiblingDB(cfg.cfg);
            targetDb.terminal_sessions.updateOne(
                { session_id: payload.session_id },
                {
                    $set: {
                        observed_slash_commands: payload.observed_slash_commands,
                        observed_prompt_submissions: payload.observed_prompt_submissions,
                        observed_interactions: payload.observed_interactions,
                        session_payload: payload.session_payload
                    }
                }
            );
            print("ok");
        })();
        """
    }

    nonisolated static func fetchSessionChunkSummaryScript(configLiteral: String, payloadLiteral: String) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(configLiteral));
            const params = JSON.parse(\(payloadLiteral));
            const targetDb = db.getSiblingDB(cfg.cfg);
            const summary = targetDb.terminal_chunks.aggregate([
                { $match: { session_id: params.session_id } },
                {
                    $group: {
                        _id: null,
                        chunkCount: { $sum: 1 },
                        totalBytes: { $sum: { $ifNull: ["$byte_count", 0] } },
                        minChunkIndex: { $min: "$chunk_index" },
                        maxChunkIndex: { $max: "$chunk_index" }
                    }
                }
            ]).toArray();
            const row = summary.length > 0 ? summary[0] : null;
            print(EJSON.stringify({
                chunk_count: row && row.chunkCount != null ? Number(row.chunkCount) : 0,
                byte_count: row && row.totalBytes != null ? Number(row.totalBytes) : 0,
                min_chunk_index: row && row.minChunkIndex != null ? Number(row.minChunkIndex) : null,
                max_chunk_index: row && row.maxChunkIndex != null ? Number(row.maxChunkIndex) : null
            }));
        })();
        """
    }

    nonisolated static func recordSessionSnapshotScript(configLiteral: String, payloadLiteral: String) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(configLiteral));
            const payload = JSON.parse(\(payloadLiteral));
            const targetDb = db.getSiblingDB(cfg.cfg);
            targetDb.terminal_sessions.updateOne(
                { session_id: payload.session_id },
                {
                    $set: {
                        profile_id: payload.profile_id,
                        profile_name: payload.profile_name,
                        agent_kind: payload.agent_kind,
                        account_identifier: payload.account_identifier,
                        provider_session_id: payload.provider_session_id,
                        provider_auth_method: payload.provider_auth_method,
                        provider_tier: payload.provider_tier,
                        provider_cli_version: payload.provider_cli_version,
                        provider_runner_path: payload.provider_runner_path,
                        provider_runner_build: payload.provider_runner_build,
                        provider_wrapper_resolved_path: payload.provider_wrapper_resolved_path,
                        provider_wrapper_kind: payload.provider_wrapper_kind,
                        provider_launch_mode: payload.provider_launch_mode,
                        provider_shell_fallback_executable: payload.provider_shell_fallback_executable,
                        provider_auto_continue_mode: payload.provider_auto_continue_mode,
                        provider_pty_backend: payload.provider_pty_backend,
                        provider_startup_clear_command: payload.provider_startup_clear_command,
                        provider_startup_clear_command_source: payload.provider_startup_clear_command_source,
                        provider_startup_clear_completed: payload.provider_startup_clear_completed,
                        provider_startup_clear_reason: payload.provider_startup_clear_reason,
                        provider_startup_stats_command: payload.provider_startup_stats_command,
                        provider_startup_stats_command_source: payload.provider_startup_stats_command_source,
                        provider_startup_model_command: payload.provider_startup_model_command,
                        provider_startup_model_command_source: payload.provider_startup_model_command_source,
                        provider_current_model: payload.provider_current_model,
                        provider_model_capacity: payload.provider_model_capacity,
                        provider_model_capacity_raw_lines: payload.provider_model_capacity_raw_lines,
                        mongo_transcript_sync_state: payload.mongo_transcript_sync_state,
                        mongo_transcript_sync_source: payload.mongo_transcript_sync_source,
                        mongo_transcript_chunk_count: payload.mongo_transcript_chunk_count,
                        mongo_transcript_byte_count: payload.mongo_transcript_byte_count,
                        mongo_transcript_synchronized_at: \(Self.mongoNullableDateExpression("payload.mongo_transcript_synchronized_at")),
                        input_capture_path: payload.input_capture_path,
                        input_chunk_count: payload.input_chunk_count,
                        input_byte_count: payload.input_byte_count,
                        mongo_input_sync_state: payload.mongo_input_sync_state,
                        mongo_input_sync_source: payload.mongo_input_sync_source,
                        mongo_input_chunk_count: payload.mongo_input_chunk_count,
                        mongo_input_byte_count: payload.mongo_input_byte_count,
                        mongo_input_synchronized_at: \(Self.mongoNullableDateExpression("payload.mongo_input_synchronized_at")),
                        provider_fresh_session_prepared: payload.provider_fresh_session_prepared,
                        provider_fresh_session_reset_reason: payload.provider_fresh_session_reset_reason,
                        provider_fresh_session_removed_path_count: payload.provider_fresh_session_removed_path_count,
                        provider_model_usage_note: payload.provider_model_usage_note,
                        provider_model_usage: payload.provider_model_usage,
                        observed_slash_commands: payload.observed_slash_commands,
                        observed_prompt_submissions: payload.observed_prompt_submissions,
                        observed_interactions: payload.observed_interactions,
                        prompt: payload.prompt,
                        working_directory: payload.working_directory,
                        transcript_path: payload.transcript_path,
                        launch_command: payload.launch_command,
                        capture_mode: payload.capture_mode,
                        started_at: new Date(payload.started_at),
                        activity_at: new Date(payload.activity_at),
                        last_activity_at: \(Self.mongoNullableDateExpression("payload.last_activity_at")),
                        ended_at: \(Self.mongoNullableDateExpression("payload.ended_at")),
                        chunk_count: payload.chunk_count,
                        byte_count: payload.byte_count,
                        last_error: payload.last_error,
                        last_preview: payload.last_preview,
                        last_database_message: payload.last_database_message,
                        status_reason: payload.status_reason,
                        exit_code: payload.exit_code,
                        metadata_json: payload.metadata_json,
                        session_payload: payload.session_payload,
                        status: payload.status
                    }
                },
                \(Self.mongoUpsertOptionsScript)
            );
            print("ok");
        })();
        """
    }

    nonisolated static func recordChunkSourceBackfillScript(configLiteral: String, payloadLiteral: String) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(configLiteral));
            const payload = JSON.parse(\(payloadLiteral));
            const targetDb = db.getSiblingDB(cfg.cfg);
            targetDb.terminal_chunks.updateMany(
                { session_id: payload.session_id, source: payload.legacy_source },
                {
                    $set: {
                        source: payload.normalized_source
                    }
                }
            );
            print("ok");
        })();
        """
    }

    nonisolated static func recordChunkScript(configLiteral: String, payloadLiteral: String) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(configLiteral));
            const payload = JSON.parse(\(payloadLiteral));
            const targetDb = db.getSiblingDB(cfg.cfg);

            targetDb.terminal_chunks.updateOne(
                { session_id: payload.session_id, chunk_index: payload.chunk_index },
                {
                    $set: {
                        source: payload.source,
                        prompt: payload.prompt,
                        captured_at: new Date(payload.captured_at),
                        byte_count: payload.byte_count,
                        preview_text: payload.preview_text,
                        raw_base64: payload.raw_base64,
                        status: payload.status,
                        status_reason: payload.status_reason,
                        message: payload.message
                    }
                },
                { upsert: true }
            );

            targetDb.terminal_sessions.updateOne(
                { session_id: payload.session_id },
                {
                    $set: {
                        profile_id: payload.session.profile_id,
                        profile_name: payload.session.profile_name,
                        agent_kind: payload.session.agent_kind,
                        account_identifier: payload.session.account_identifier,
                        provider_session_id: payload.session.provider_session_id,
                        provider_auth_method: payload.session.provider_auth_method,
                        provider_tier: payload.session.provider_tier,
                        provider_cli_version: payload.session.provider_cli_version,
                        provider_runner_path: payload.session.provider_runner_path,
                        provider_runner_build: payload.session.provider_runner_build,
                        provider_wrapper_resolved_path: payload.session.provider_wrapper_resolved_path,
                        provider_wrapper_kind: payload.session.provider_wrapper_kind,
                        provider_launch_mode: payload.session.provider_launch_mode,
                        provider_shell_fallback_executable: payload.session.provider_shell_fallback_executable,
                        provider_auto_continue_mode: payload.session.provider_auto_continue_mode,
                        provider_pty_backend: payload.session.provider_pty_backend,
                        provider_startup_clear_command: payload.session.provider_startup_clear_command,
                        provider_startup_clear_command_source: payload.session.provider_startup_clear_command_source,
                        provider_startup_clear_completed: payload.session.provider_startup_clear_completed,
                        provider_startup_clear_reason: payload.session.provider_startup_clear_reason,
                        provider_startup_stats_command: payload.session.provider_startup_stats_command,
                        provider_startup_stats_command_source: payload.session.provider_startup_stats_command_source,
                        provider_startup_model_command: payload.session.provider_startup_model_command,
                        provider_startup_model_command_source: payload.session.provider_startup_model_command_source,
                        provider_current_model: payload.session.provider_current_model,
                        provider_model_capacity: payload.session.provider_model_capacity,
                        provider_model_capacity_raw_lines: payload.session.provider_model_capacity_raw_lines,
                        mongo_transcript_sync_state: payload.session.mongo_transcript_sync_state,
                        mongo_transcript_sync_source: payload.session.mongo_transcript_sync_source,
                        mongo_transcript_chunk_count: payload.session.mongo_transcript_chunk_count,
                        mongo_transcript_byte_count: payload.session.mongo_transcript_byte_count,
                        mongo_transcript_synchronized_at: \(Self.mongoNullableDateExpression("payload.session.mongo_transcript_synchronized_at")),
                        input_capture_path: payload.session.input_capture_path,
                        input_chunk_count: payload.session.input_chunk_count,
                        input_byte_count: payload.session.input_byte_count,
                        mongo_input_sync_state: payload.session.mongo_input_sync_state,
                        mongo_input_sync_source: payload.session.mongo_input_sync_source,
                        mongo_input_chunk_count: payload.session.mongo_input_chunk_count,
                        mongo_input_byte_count: payload.session.mongo_input_byte_count,
                        mongo_input_synchronized_at: \(Self.mongoNullableDateExpression("payload.session.mongo_input_synchronized_at")),
                        provider_fresh_session_prepared: payload.session.provider_fresh_session_prepared,
                        provider_fresh_session_reset_reason: payload.session.provider_fresh_session_reset_reason,
                        provider_fresh_session_removed_path_count: payload.session.provider_fresh_session_removed_path_count,
                        provider_model_usage_note: payload.session.provider_model_usage_note,
                        provider_model_usage: payload.session.provider_model_usage,
                        observed_slash_commands: payload.session.observed_slash_commands,
                        observed_prompt_submissions: payload.session.observed_prompt_submissions,
                        observed_interactions: payload.session.observed_interactions,
                        prompt: payload.session.prompt,
                        working_directory: payload.session.working_directory,
                        transcript_path: payload.session.transcript_path,
                        launch_command: payload.session.launch_command,
                        capture_mode: payload.session.capture_mode,
                        started_at: \(Self.mongoNullableDateExpression("payload.session.started_at")),
                        session_payload: payload.session.session_payload,
                        activity_at: new Date(payload.captured_at),
                        last_activity_at: new Date(payload.captured_at),
                        chunk_count: payload.total_chunks,
                        byte_count: payload.total_bytes,
                        status: payload.session.status,
                        last_preview: payload.preview_text,
                        last_database_message: payload.message,
                        status_reason: payload.session.status_reason,
                        last_error: payload.session.last_error,
                        metadata_json: payload.session.metadata_json,
                        ended_at: \(Self.mongoNullableDateExpression("payload.session.ended_at")),
                        exit_code: payload.session.exit_code
                    }
                },
                \(Self.mongoUpsertOptionsScript)
            );

            print("ok");
        })();
        """
    }

    nonisolated static func recordInputChunkScript(configLiteral: String, payloadLiteral: String) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(configLiteral));
            const payload = JSON.parse(\(payloadLiteral));
            const targetDb = db.getSiblingDB(cfg.cfg);

            targetDb.terminal_input_chunks.updateOne(
                { session_id: payload.session_id, input_index: payload.input_index },
                {
                    $set: {
                        source: payload.source,
                        prompt: payload.prompt,
                        captured_at: new Date(payload.captured_at),
                        byte_count: payload.byte_count,
                        preview_text: payload.preview_text,
                        raw_base64: payload.raw_base64,
                        status: payload.status,
                        status_reason: payload.status_reason,
                        message: payload.message
                    }
                },
                { upsert: true }
            );

            targetDb.terminal_sessions.updateOne(
                { session_id: payload.session_id },
                {
                    $set: {
                        session_payload: payload.session.session_payload,
                        activity_at: new Date(payload.captured_at),
                        last_activity_at: new Date(payload.captured_at),
                        status: payload.session.status,
                        last_database_message: payload.message,
                        status_reason: payload.session.status_reason,
                        last_error: payload.session.last_error,
                        metadata_json: payload.session.metadata_json,
                        ended_at: \(Self.mongoNullableDateExpression("payload.session.ended_at")),
                        exit_code: payload.session.exit_code
                    }
                },
                \(Self.mongoUpsertOptionsScript)
            );

            print("ok");
        })();
        """
    }

    nonisolated static func orderedSessions(_ sessions: [TerminalMonitorSession], by requestedSessionIDs: [UUID]) -> [TerminalMonitorSession] {
        let order = Dictionary(uniqueKeysWithValues: requestedSessionIDs.enumerated().map { ($0.element, $0.offset) })
        return sessions.sorted { lhs, rhs in
            let lhsIndex = order[lhs.id] ?? Int.max
            let rhsIndex = order[rhs.id] ?? Int.max
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func sessionDocument(from session: TerminalMonitorSession) -> [String: Any] {
        let lastActivityMillis = session.lastActivityAt.map { Int64($0.timeIntervalSince1970 * 1_000) }
        let endedAtMillis = session.endedAt.map { Int64($0.timeIntervalSince1970 * 1_000) }

        let sessionPayload: String
        do {
            let data = try Self.sessionDocumentEncoder.encode(session)
            sessionPayload = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            sessionPayload = "{}"
        }

        let metadata: [String: String] = [
            "capture_mode": session.captureMode.rawValue,
            "working_directory": session.workingDirectory,
            "transcript_path": session.transcriptPath
        ]
        let metadataJSON = (try? JSONSerialization.data(withJSONObject: metadata))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return [
            "session_id": session.id.uuidString,
            "profile_id": session.profileID?.uuidString ?? NSNull(),
            "profile_name": session.profileName,
            "agent_kind": session.agentKind.rawValue,
            "account_identifier": session.accountIdentifier ?? NSNull(),
            "provider_session_id": session.providerSessionID ?? NSNull(),
            "provider_auth_method": session.providerAuthMethod ?? NSNull(),
            "provider_tier": session.providerTier ?? NSNull(),
            "provider_cli_version": session.providerCLIVersion ?? NSNull(),
            "provider_runner_path": session.providerRunnerPath ?? NSNull(),
            "provider_runner_build": session.providerRunnerBuild ?? NSNull(),
            "provider_wrapper_resolved_path": session.providerWrapperResolvedPath ?? NSNull(),
            "provider_wrapper_kind": session.providerWrapperKind ?? NSNull(),
            "provider_launch_mode": session.providerLaunchMode ?? NSNull(),
            "provider_shell_fallback_executable": session.providerShellFallbackExecutable ?? NSNull(),
            "provider_auto_continue_mode": session.providerAutoContinueMode ?? NSNull(),
            "provider_pty_backend": session.providerPTYBackend ?? NSNull(),
            "provider_startup_clear_command": session.providerStartupClearCommand ?? NSNull(),
            "provider_startup_clear_command_source": session.providerStartupClearCommandSource ?? NSNull(),
            "provider_startup_clear_completed": session.providerStartupClearCompleted ?? NSNull(),
            "provider_startup_clear_reason": session.providerStartupClearReason ?? NSNull(),
            "provider_startup_stats_command": session.providerStartupStatsCommand ?? NSNull(),
            "provider_startup_stats_command_source": session.providerStartupStatsCommandSource ?? NSNull(),
            "provider_startup_model_command": session.providerStartupModelCommand ?? NSNull(),
            "provider_startup_model_command_source": session.providerStartupModelCommandSource ?? NSNull(),
            "provider_current_model": session.providerCurrentModel ?? NSNull(),
            "provider_model_capacity": Self.mongoProviderModelCapacityDocument(session.providerModelCapacity),
            "provider_model_capacity_raw_lines": session.providerModelCapacityRawLines ?? NSNull(),
            "mongo_transcript_sync_state": session.mongoTranscriptSyncState?.rawValue ?? NSNull(),
            "mongo_transcript_sync_source": session.mongoTranscriptSyncSource ?? NSNull(),
            "mongo_transcript_chunk_count": session.mongoTranscriptChunkCount ?? NSNull(),
            "mongo_transcript_byte_count": session.mongoTranscriptByteCount ?? NSNull(),
            "mongo_transcript_synchronized_at": session.mongoTranscriptSynchronizedAt.map { Int64($0.timeIntervalSince1970 * 1_000) } ?? NSNull(),
            "input_capture_path": session.inputCapturePath ?? NSNull(),
            "input_chunk_count": session.inputChunkCount,
            "input_byte_count": session.inputByteCount,
            "mongo_input_sync_state": session.mongoInputSyncState?.rawValue ?? NSNull(),
            "mongo_input_sync_source": session.mongoInputSyncSource ?? NSNull(),
            "mongo_input_chunk_count": session.mongoInputChunkCount ?? NSNull(),
            "mongo_input_byte_count": session.mongoInputByteCount ?? NSNull(),
            "mongo_input_synchronized_at": session.mongoInputSynchronizedAt.map { Int64($0.timeIntervalSince1970 * 1_000) } ?? NSNull(),
            "provider_fresh_session_prepared": session.providerFreshSessionPrepared ?? NSNull(),
            "provider_fresh_session_reset_reason": session.providerFreshSessionResetReason ?? NSNull(),
            "provider_fresh_session_removed_path_count": session.providerFreshSessionRemovedPathCount ?? NSNull(),
            "provider_model_usage_note": session.providerModelUsageNote ?? NSNull(),
            "provider_model_usage": Self.mongoProviderModelUsageDocument(session.providerModelUsage),
            "observed_slash_commands": session.observedSlashCommands ?? NSNull(),
            "observed_prompt_submissions": session.observedPromptSubmissions ?? NSNull(),
            "observed_interactions": Self.mongoObservedInteractionDocuments(session.observedInteractions),
            "prompt": session.prompt,
            "working_directory": session.workingDirectory,
            "transcript_path": session.transcriptPath,
            "launch_command": session.launchCommand,
            "capture_mode": session.captureMode.rawValue,
            "status": session.status.rawValue,
            "started_at": Int64(session.startedAt.timeIntervalSince1970 * 1_000),
            "activity_at": Int64(session.activityDate.timeIntervalSince1970 * 1_000),
            "last_activity_at": nullableMongoValue(lastActivityMillis),
            "ended_at": nullableMongoValue(endedAtMillis),
            "chunk_count": session.chunkCount,
            "byte_count": session.byteCount,
            "last_error": session.lastError ?? NSNull(),
            "last_preview": session.lastPreview,
            "last_database_message": session.lastDatabaseMessage,
            "status_reason": session.statusReason ?? NSNull(),
            "exit_code": session.exitCode ?? NSNull(),
            "metadata_json": metadataJSON,
            "session_payload": sessionPayload
        ]
    }

    func testConnection(settings: MongoMonitoringSettings) throws -> String {
        guard settings.enableMongoWrites else {
            return "Mongo writes are disabled."
        }
        let script = """
        (function() {
            const targetDb = db.getSiblingDB(\(mongoStringLiteral(mongoDatabaseName(from: settings))) );
            const ping = targetDb.adminCommand({ ping: 1 });
            print(
                JSON.stringify({
                    ok: !!(ping && ping.ok === 1),
                    db: targetDb.getName(),
                    host: ping && ping.host ? ping.host : "unknown",
                    version: targetDb.version()
                })
            );
        })();
        """

        let output = try runMongo(script, settings: settings)
        guard let line = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return "Connected to MongoDB."
        }
        return line
    }

    func ensureSchema(settings: MongoMonitoringSettings) throws {
        guard settings.enableMongoWrites else { return }
        guard !settings.localDataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let fingerprint = Self.schemaInitializationFingerprint(for: settings)
        guard Self.needsSchemaInitialization(currentFingerprint: initializedFingerprint, nextFingerprint: fingerprint) else {
            return
        }
        _ = try runMongo(Self.ensureSchemaScript(databaseName: mongoDatabaseName(from: settings)), settings: settings)
        initializedFingerprint = fingerprint
    }

    nonisolated static func ensureSchemaScript(databaseName: String) -> String {
        """
        (function() {
            const targetDb = db.getSiblingDB(\(MongoShellLiterals.stringLiteral(databaseName)));
            targetDb.terminal_sessions.updateMany(
                {
                    $or: [
                        { activity_at: null },
                        { activity_at: { $exists: false } }
                    ]
                },
                [
                    {
                        $set: {
                            activity_at: { $ifNull: ["$last_activity_at", { $ifNull: ["$ended_at", "$started_at"] }] }
                        }
                    }
                ]
            );
            targetDb.terminal_sessions.createIndex({ session_id: 1 }, { unique: true });
            targetDb.terminal_sessions.createIndex({ account_identifier: 1 });
            targetDb.terminal_sessions.createIndex({ provider_session_id: 1 });
            targetDb.terminal_sessions.createIndex({ activity_at: -1 });
            targetDb.terminal_sessions.createIndex({ status: 1, activity_at: -1 });
            targetDb.terminal_sessions.createIndex({ mongo_transcript_sync_state: 1, mongo_transcript_synchronized_at: -1 });
            targetDb.terminal_sessions.createIndex({ mongo_transcript_synchronized_at: -1 });
            targetDb.terminal_sessions.createIndex({ mongo_input_sync_state: 1, mongo_input_synchronized_at: -1 });
            targetDb.terminal_sessions.createIndex({ mongo_input_synchronized_at: -1 });
            targetDb.terminal_sessions.createIndex({ prompt: "text" });
            targetDb.terminal_chunks.createIndex({ session_id: 1, chunk_index: 1 }, { unique: true });
            targetDb.terminal_input_chunks.createIndex({ session_id: 1, input_index: 1 }, { unique: true });
            targetDb.terminal_session_events.createIndex({ session_id: 1, event_at: -1, _id: -1 });
            try {
                targetDb.terminal_sessions.dropIndex({ status: 1, ended_at: -1, last_activity_at: -1, started_at: -1 });
            } catch (error) {}
            print("MongoDB monitoring collections ready.");
        })();
        """
    }

    nonisolated static func fetchRecentSessionsScript(configLiteral: String, payloadLiteral: String) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(configLiteral));
            const params = JSON.parse(\(payloadLiteral));
            const targetDb = db.getSiblingDB(cfg.cfg);
            const rows = targetDb.terminal_sessions.find({
                activity_at: { $gte: new Date(params.cutoff_ms) }
            }).sort({ activity_at: -1 }).limit(params.limit).toArray();

            rows.forEach((row) => {
                print(EJSON.stringify({
                    session_id: row.session_id,
                    profile_id: row.profile_id ?? null,
                    profile_name: row.profile_name,
                    agent_kind: row.agent_kind,
                    account_identifier: row.account_identifier ?? null,
                    provider_session_id: row.provider_session_id ?? null,
                    provider_auth_method: row.provider_auth_method ?? null,
                    provider_tier: row.provider_tier ?? null,
                    provider_cli_version: row.provider_cli_version ?? null,
                    provider_runner_path: row.provider_runner_path ?? null,
                    provider_runner_build: row.provider_runner_build ?? null,
                    provider_wrapper_resolved_path: row.provider_wrapper_resolved_path ?? null,
                    provider_wrapper_kind: row.provider_wrapper_kind ?? null,
                    provider_launch_mode: row.provider_launch_mode ?? null,
                    provider_shell_fallback_executable: row.provider_shell_fallback_executable ?? null,
                    provider_auto_continue_mode: row.provider_auto_continue_mode ?? null,
                    provider_pty_backend: row.provider_pty_backend ?? null,
                    provider_startup_clear_command: row.provider_startup_clear_command ?? null,
                    provider_startup_clear_command_source: row.provider_startup_clear_command_source ?? null,
                    provider_startup_clear_completed: row.provider_startup_clear_completed ?? null,
                    provider_startup_clear_reason: row.provider_startup_clear_reason ?? null,
                    provider_startup_stats_command: row.provider_startup_stats_command ?? null,
                    provider_startup_stats_command_source: row.provider_startup_stats_command_source ?? null,
                    provider_startup_model_command: row.provider_startup_model_command ?? null,
                    provider_startup_model_command_source: row.provider_startup_model_command_source ?? null,
                    provider_current_model: row.provider_current_model ?? null,
                    provider_model_capacity: row.provider_model_capacity ?? null,
                    provider_model_capacity_raw_lines: row.provider_model_capacity_raw_lines ?? null,
                    mongo_transcript_sync_state: row.mongo_transcript_sync_state ?? null,
                    mongo_transcript_sync_source: row.mongo_transcript_sync_source ?? null,
                    mongo_transcript_chunk_count: row.mongo_transcript_chunk_count ?? null,
                    mongo_transcript_byte_count: row.mongo_transcript_byte_count ?? null,
                    mongo_transcript_synchronized_at_epoch: row.mongo_transcript_synchronized_at ? row.mongo_transcript_synchronized_at.getTime() / 1000 : null,
                    input_capture_path: row.input_capture_path ?? null,
                    input_chunk_count: row.input_chunk_count ?? null,
                    input_byte_count: row.input_byte_count ?? null,
                    mongo_input_sync_state: row.mongo_input_sync_state ?? null,
                    mongo_input_sync_source: row.mongo_input_sync_source ?? null,
                    mongo_input_chunk_count: row.mongo_input_chunk_count ?? null,
                    mongo_input_byte_count: row.mongo_input_byte_count ?? null,
                    mongo_input_synchronized_at_epoch: row.mongo_input_synchronized_at ? row.mongo_input_synchronized_at.getTime() / 1000 : null,
                    provider_fresh_session_prepared: row.provider_fresh_session_prepared ?? null,
                    provider_fresh_session_reset_reason: row.provider_fresh_session_reset_reason ?? null,
                    provider_fresh_session_removed_path_count: row.provider_fresh_session_removed_path_count ?? null,
                    provider_model_usage_note: row.provider_model_usage_note ?? null,
                    provider_model_usage: row.provider_model_usage ?? null,
                    observed_slash_commands: row.observed_slash_commands ?? null,
                    observed_prompt_submissions: row.observed_prompt_submissions ?? null,
                    observed_interactions: row.observed_interactions
                        ? row.observed_interactions.map((item) => ({
                            text: item.text ?? "",
                            kind: item.kind ?? "",
                            source: item.source ?? "",
                            first_observed_at_epoch: item.first_observed_at != null ? Number(item.first_observed_at) / 1000 : 0,
                            last_observed_at_epoch: item.last_observed_at != null ? Number(item.last_observed_at) / 1000 : 0,
                            observation_count: item.observation_count ?? 0
                        }))
                        : null,
                    prompt: row.prompt ?? null,
                    working_directory: row.working_directory,
                    transcript_path: row.transcript_path,
                    launch_command: row.launch_command,
                    capture_mode: row.capture_mode,
                    status: row.status,
                    started_at_epoch: row.started_at ? row.started_at.getTime() / 1000 : null,
                    activity_at_epoch: row.activity_at ? row.activity_at.getTime() / 1000 : null,
                    last_activity_at_epoch: row.last_activity_at ? row.last_activity_at.getTime() / 1000 : null,
                    ended_at_epoch: row.ended_at ? row.ended_at.getTime() / 1000 : null,
                    chunk_count: row.chunk_count,
                    byte_count: row.byte_count,
                    last_error: row.last_error ?? null,
                    last_preview: row.last_preview ?? "",
                    last_database_message: row.last_database_message ?? "",
                    status_reason: row.status_reason ?? null,
                    exit_code: row.exit_code ?? null,
                    session_payload: row.session_payload ?? null
                }));
            });
        })();
        """
    }

    nonisolated static func pruneCompletedHistoryScript(configLiteral: String, payloadLiteral: String) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(configLiteral));
            const params = JSON.parse(\(payloadLiteral));
            const targetDb = db.getSiblingDB(cfg.cfg);

            const doomed = targetDb.terminal_sessions.find({
                status: { $in: ["completed", "failed", "stopped"] },
                activity_at: { $lt: new Date(params.cutoff_ms) }
            }, { projection: { session_id: 1, byte_count: 1 } }).toArray();

            const doomedIds = doomed.map((entry) => entry.session_id);
            const deletedSessionCount = doomedIds.length;

            let deletedChunkCount = 0;
            let deletedChunkBytes = 0;
            let deletedInputChunkCount = 0;
            let deletedInputChunkBytes = 0;
            let deletedEventCount = 0;

            if (doomedIds.length > 0) {
                const doomedChunks = targetDb.terminal_chunks.find({ session_id: { $in: doomedIds } }).toArray();
                doomedChunks.forEach((chunk) => {
                    deletedChunkCount += 1;
                    const chunkBytes = Number(chunk.byte_count || 0);
                    deletedChunkBytes += Number(chunkBytes);
                });
                const doomedInputChunks = targetDb.terminal_input_chunks.find({ session_id: { $in: doomedIds } }).toArray();
                doomedInputChunks.forEach((chunk) => {
                    deletedInputChunkCount += 1;
                    const chunkBytes = Number(chunk.byte_count || 0);
                    deletedInputChunkBytes += Number(chunkBytes);
                });

                const inputDelete = targetDb.terminal_input_chunks.deleteMany({ session_id: { $in: doomedIds } });
                const eventDelete = targetDb.terminal_session_events.deleteMany({ session_id: { $in: doomedIds } });
                deletedEventCount = Number(eventDelete.deletedCount || 0);

                const chunkDelete = targetDb.terminal_chunks.deleteMany({ session_id: { $in: doomedIds } });
                deletedChunkCount = Number(chunkDelete.deletedCount || deletedChunkCount);
                deletedInputChunkCount = Number(inputDelete.deletedCount || deletedInputChunkCount);

                const sessionDelete = targetDb.terminal_sessions.deleteMany({ session_id: { $in: doomedIds } });
                const actualSessionCount = Number(sessionDelete.deletedCount || deletedSessionCount);

                print(JSON.stringify({
                    deletedSessions: actualSessionCount,
                    deletedChunks: deletedChunkCount,
                    deletedInputChunks: deletedInputChunkCount,
                    deletedEvents: deletedEventCount,
                    deletedChunkBytes: deletedChunkBytes,
                    deletedInputChunkBytes: deletedInputChunkBytes
                }));
            } else {
                print(JSON.stringify({
                    deletedSessions: 0,
                    deletedChunks: 0,
                    deletedInputChunks: 0,
                    deletedEvents: 0,
                    deletedChunkBytes: 0,
                    deletedInputChunkBytes: 0
                }));
            }
        })();
        """
    }

    func recordSessionStart(_ session: TerminalMonitorSession, settings: MongoMonitoringSettings) throws {
        guard settings.enableMongoWrites else { return }
        try ensureSchema(settings: settings)

        let payload = sessionDocument(from: session)
        let script = Self.recordSessionStartScript(
            configLiteral: mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)]),
            payloadLiteral: mongoJSONLiteral(payload)
        )
        _ = try runMongo(script, settings: settings)
    }

    func recordObservedInteractionSummary(_ session: TerminalMonitorSession, settings: MongoMonitoringSettings) throws {
        guard settings.enableMongoWrites else { return }
        guard session.observedInteractions?.isEmpty == false ||
              session.observedSlashCommands?.isEmpty == false ||
              session.observedPromptSubmissions?.isEmpty == false else {
            return
        }
        try ensureSchema(settings: settings)

        let payload = sessionDocument(from: session)
        let script = Self.recordObservedInteractionSummaryScript(
            configLiteral: mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)]),
            payloadLiteral: mongoJSONLiteral(payload)
        )
        _ = try runMongo(script, settings: settings)
    }

    func recordSessionSnapshot(_ session: TerminalMonitorSession, settings: MongoMonitoringSettings) throws {
        guard settings.enableMongoWrites else { return }
        try ensureSchema(settings: settings)

        let payload = sessionDocument(from: session)
        let script = Self.recordSessionSnapshotScript(
            configLiteral: mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)]),
            payloadLiteral: mongoJSONLiteral(payload)
        )
        _ = try runMongo(script, settings: settings)
    }

    func recordChunkSourceBackfill(
        sessionID: UUID,
        legacySource: String = "terminal_transcript",
        normalizedSource: String,
        settings: MongoMonitoringSettings
    ) throws {
        guard settings.enableMongoWrites else { return }
        let cleanedNormalizedSource = normalizedSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedNormalizedSource.isEmpty else { return }
        try ensureSchema(settings: settings)

        let payload: [String: Any] = [
            "session_id": sessionID.uuidString,
            "legacy_source": legacySource,
            "normalized_source": cleanedNormalizedSource
        ]
        let script = Self.recordChunkSourceBackfillScript(
            configLiteral: mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)]),
            payloadLiteral: mongoJSONLiteral(payload)
        )
        _ = try runMongo(script, settings: settings)
    }

    func recordChunk(
        sessionID: UUID,
        chunkIndex: Int,
        data: Data,
        source: String,
        session: TerminalMonitorSession,
        prompt: String,
        preview: String,
        totalChunks: Int,
        totalBytes: Int,
        capturedAt: Date,
        status: TerminalMonitorStatus,
        settings: MongoMonitoringSettings
    ) throws {
        guard settings.enableMongoWrites else { return }
        try ensureSchema(settings: settings)

        let sessionPayload = sessionDocument(from: session)
        let payload: [String: Any] = [
            "session_id": sessionID.uuidString,
            "chunk_index": chunkIndex,
            "source": source,
            "prompt": prompt,
            "captured_at": Int64(capturedAt.timeIntervalSince1970 * 1_000),
            "byte_count": data.count,
            "preview_text": preview,
            "raw_base64": data.base64EncodedString(),
            "status": status.rawValue,
            "status_reason": session.statusReason ?? NSNull(),
            "message": session.lastDatabaseMessage.isEmpty ? "Synced chunk \(totalChunks) to MongoDB." : session.lastDatabaseMessage,
            "total_chunks": totalChunks,
            "total_bytes": totalBytes,
            "session": sessionPayload
        ]

        let script = Self.recordChunkScript(
            configLiteral: mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)]),
            payloadLiteral: mongoJSONLiteral(payload)
        )
        _ = try runMongo(script, settings: settings)
    }

    func recordInputChunk(
        sessionID: UUID,
        inputIndex: Int,
        data: Data,
        source: String,
        session: TerminalMonitorSession,
        prompt: String,
        preview: String,
        capturedAt: Date,
        status: TerminalMonitorStatus,
        settings: MongoMonitoringSettings
    ) throws {
        guard settings.enableMongoWrites else { return }
        try ensureSchema(settings: settings)

        let sessionPayload = sessionDocument(from: session)
        let payload: [String: Any] = [
            "session_id": sessionID.uuidString,
            "input_index": inputIndex,
            "source": source,
            "prompt": prompt,
            "captured_at": Int64(capturedAt.timeIntervalSince1970 * 1_000),
            "byte_count": data.count,
            "preview_text": preview,
            "raw_base64": data.base64EncodedString(),
            "status": status.rawValue,
            "status_reason": session.statusReason ?? NSNull(),
            "message": session.lastDatabaseMessage.isEmpty ? "Synced input chunk \(inputIndex) to MongoDB." : session.lastDatabaseMessage,
            "session": sessionPayload
        ]

        let script = Self.recordInputChunkScript(
            configLiteral: mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)]),
            payloadLiteral: mongoJSONLiteral(payload)
        )
        _ = try runMongo(script, settings: settings)
    }

    func recordStatus(
        session: TerminalMonitorSession,
        status: TerminalMonitorStatus,
        eventType: String,
        message: String?,
        eventAt: Date,
        endedAt: Date? = nil,
        statusReason: String? = nil,
        exitCode: Int? = nil,
        metadata: [String: Any]? = nil,
        settings: MongoMonitoringSettings
    ) throws {
        guard settings.enableMongoWrites else { return }
        try ensureSchema(settings: settings)

        let statusMessage = message ?? defaultMessage(for: status)
        var resolvedSession = session
        resolvedSession.status = status
        resolvedSession.endedAt = endedAt ?? session.endedAt
        resolvedSession.statusReason = statusReason ?? session.statusReason
        resolvedSession.exitCode = exitCode ?? session.exitCode
        if status == .failed, resolvedSession.lastError == nil {
            resolvedSession.lastError = statusMessage
        }
        if status == .completed || status == .failed || status == .stopped {
            resolvedSession.lastActivityAt = eventAt
        }

        let resolvedSessionPayload = sessionDocument(from: resolvedSession)
        let endedAtMillis = resolvedSession.endedAt.map { Int64($0.timeIntervalSince1970 * 1_000) }
        var eventMetadata: [String: Any] = [
            "status_reason": nullableMongoValue(resolvedSession.statusReason),
            "exit_code": nullableMongoValue(resolvedSession.exitCode),
            "ended_at": nullableMongoValue(endedAtMillis),
            "message": statusMessage
        ]
        if let metadata {
            for (key, value) in metadata {
                eventMetadata[key] = value
            }
        }
        let payload: [String: Any] = [
            "session_id": session.id.uuidString,
            "status": resolvedSession.status.rawValue,
            "event_type": eventType,
            "event_at": Int64(eventAt.timeIntervalSince1970 * 1_000),
            "message": statusMessage,
            "status_reason": nullableMongoValue(resolvedSession.statusReason),
            "exit_code": nullableMongoValue(resolvedSession.exitCode),
            "ended_at": nullableMongoValue(endedAtMillis),
            "session": resolvedSessionPayload,
            "metadata": eventMetadata
        ]

        let script = """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const payload = JSON.parse(\(mongoJSONLiteral(payload)));
            const targetDb = db.getSiblingDB(cfg.cfg);

            targetDb.terminal_sessions.updateOne(
                { session_id: payload.session_id },
                {
                    $set: {
                        profile_id: payload.session.profile_id,
                        profile_name: payload.session.profile_name,
                        agent_kind: payload.session.agent_kind,
                        account_identifier: payload.session.account_identifier,
                        provider_session_id: payload.session.provider_session_id,
                        provider_auth_method: payload.session.provider_auth_method,
                        provider_tier: payload.session.provider_tier,
                        provider_cli_version: payload.session.provider_cli_version,
                        provider_runner_path: payload.session.provider_runner_path,
                        provider_runner_build: payload.session.provider_runner_build,
                        provider_wrapper_resolved_path: payload.session.provider_wrapper_resolved_path,
                        provider_wrapper_kind: payload.session.provider_wrapper_kind,
                        provider_launch_mode: payload.session.provider_launch_mode,
                        provider_shell_fallback_executable: payload.session.provider_shell_fallback_executable,
                        provider_auto_continue_mode: payload.session.provider_auto_continue_mode,
                        provider_pty_backend: payload.session.provider_pty_backend,
                        provider_startup_clear_command: payload.session.provider_startup_clear_command,
                        provider_startup_clear_command_source: payload.session.provider_startup_clear_command_source,
                        provider_startup_clear_completed: payload.session.provider_startup_clear_completed,
                        provider_startup_clear_reason: payload.session.provider_startup_clear_reason,
                        provider_startup_stats_command: payload.session.provider_startup_stats_command,
                        provider_startup_stats_command_source: payload.session.provider_startup_stats_command_source,
                        provider_startup_model_command: payload.session.provider_startup_model_command,
                        provider_startup_model_command_source: payload.session.provider_startup_model_command_source,
                        provider_current_model: payload.session.provider_current_model,
                        provider_model_capacity: payload.session.provider_model_capacity,
                        provider_model_capacity_raw_lines: payload.session.provider_model_capacity_raw_lines,
                        mongo_transcript_sync_state: payload.session.mongo_transcript_sync_state,
                        mongo_transcript_sync_source: payload.session.mongo_transcript_sync_source,
                        mongo_transcript_chunk_count: payload.session.mongo_transcript_chunk_count,
                        mongo_transcript_byte_count: payload.session.mongo_transcript_byte_count,
                        mongo_transcript_synchronized_at: \(Self.mongoNullableDateExpression("payload.session.mongo_transcript_synchronized_at")),
                        input_capture_path: payload.session.input_capture_path,
                        input_chunk_count: payload.session.input_chunk_count,
                        input_byte_count: payload.session.input_byte_count,
                        mongo_input_sync_state: payload.session.mongo_input_sync_state,
                        mongo_input_sync_source: payload.session.mongo_input_sync_source,
                        mongo_input_chunk_count: payload.session.mongo_input_chunk_count,
                        mongo_input_byte_count: payload.session.mongo_input_byte_count,
                        mongo_input_synchronized_at: \(Self.mongoNullableDateExpression("payload.session.mongo_input_synchronized_at")),
                        provider_fresh_session_prepared: payload.session.provider_fresh_session_prepared,
                        provider_fresh_session_reset_reason: payload.session.provider_fresh_session_reset_reason,
                        provider_fresh_session_removed_path_count: payload.session.provider_fresh_session_removed_path_count,
                        provider_model_usage_note: payload.session.provider_model_usage_note,
                        provider_model_usage: payload.session.provider_model_usage,
                        observed_slash_commands: payload.session.observed_slash_commands,
                        observed_prompt_submissions: payload.session.observed_prompt_submissions,
                        observed_interactions: payload.session.observed_interactions,
                        prompt: payload.session.prompt,
                        working_directory: payload.session.working_directory,
                        transcript_path: payload.session.transcript_path,
                        launch_command: payload.session.launch_command,
                        capture_mode: payload.session.capture_mode,
                        started_at: new Date(payload.session.started_at),
                        activity_at: new Date(payload.event_at),
                        last_activity_at: new Date(payload.event_at),
                        ended_at: payload.ended_at != null ? new Date(payload.ended_at) : null,
                        chunk_count: payload.session.chunk_count,
                        byte_count: payload.session.byte_count,
                        last_database_message: payload.message,
                        status_reason: payload.status_reason,
                        last_error: payload.session.last_error,
                        exit_code: payload.exit_code,
                        status: payload.status,
                        last_preview: payload.session.last_preview,
                        metadata_json: payload.session.metadata_json,
                        session_payload: payload.session.session_payload
                    }
                },
                \(Self.mongoUpsertOptionsScript)
            );

            targetDb.terminal_session_events.insertOne({
                session_id: payload.session_id,
                event_type: payload.event_type,
                status: payload.status,
                event_at: new Date(payload.event_at),
                message: payload.message,
                metadata_json: payload.metadata ? EJSON.stringify(payload.metadata) : null
            });
            print("ok");
        })();
        """
        _ = try runMongo(script, settings: settings)
    }

    func recordFailure(session: TerminalMonitorSession, message: String, status: TerminalMonitorStatus, settings: MongoMonitoringSettings) throws {
        try recordStatus(
            session: session,
            status: status,
            eventType: "session_failed",
            message: message,
            eventAt: Date(),
            endedAt: Date(),
            statusReason: "monitoring_error",
            exitCode: nil,
            settings: settings
        )
    }

    func recordCompletion(session: TerminalMonitorSession, settings: MongoMonitoringSettings) throws {
        try recordStatus(
            session: session,
            status: session.status,
            eventType: session.status == .completed ? "session_completed" : "session_exited_nonzero",
            message: session.lastDatabaseMessage,
            eventAt: session.endedAt ?? Date(),
            endedAt: session.endedAt ?? Date(),
            statusReason: session.statusReason,
            exitCode: session.exitCode,
            settings: settings
        )
    }

    func fetchRecentSessions(settings: MongoMonitoringSettings, limit: Int, lookbackHours: Int) throws -> [TerminalMonitorSession] {
        guard settings.enableMongoWrites else { return [] }
        try ensureSchema(settings: settings)

        let safeLimit = max(1, min(200, limit))
        let safeLookbackHours = max(1, min(24 * 90, lookbackHours))
        let payload: [String: Any] = [
            "limit": safeLimit,
            "lookback_hours": safeLookbackHours,
            "cutoff_ms": Int64((Date().addingTimeInterval(-TimeInterval(safeLookbackHours) * 3_600).timeIntervalSince1970) * 1_000)
        ]
        let script = Self.fetchRecentSessionsScript(
            configLiteral: mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)]),
            payloadLiteral: mongoJSONLiteral(payload)
        )

        let output = try runMongo(script, settings: settings)
        let rows = try parseMongoRows(output, as: DatabaseSessionRow.self)
        return rows.map { $0.makeSession() }
    }

    func fetchSessions(sessionIDs: [UUID], settings: MongoMonitoringSettings) throws -> [TerminalMonitorSession] {
        guard settings.enableMongoWrites else { return [] }
        let uniqueSessionIDs = Array(NSOrderedSet(array: sessionIDs)) as? [UUID] ?? sessionIDs
        guard !uniqueSessionIDs.isEmpty else { return [] }
        try ensureSchema(settings: settings)

        let payload: [String: Any] = [
            "session_ids": uniqueSessionIDs.map(\.uuidString)
        ]

        let script = """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const params = JSON.parse(\(mongoJSONLiteral(payload)));
            const targetDb = db.getSiblingDB(cfg.cfg);
            const rows = targetDb.terminal_sessions.find({ session_id: { $in: params.session_ids } }).toArray();
            rows.forEach((row) => {
                print(EJSON.stringify({
                    session_id: row.session_id,
                    profile_id: row.profile_id ?? null,
                    profile_name: row.profile_name,
                    agent_kind: row.agent_kind,
                    account_identifier: row.account_identifier ?? null,
                    provider_session_id: row.provider_session_id ?? null,
                    provider_auth_method: row.provider_auth_method ?? null,
                    provider_tier: row.provider_tier ?? null,
                    provider_cli_version: row.provider_cli_version ?? null,
                    provider_runner_path: row.provider_runner_path ?? null,
                    provider_runner_build: row.provider_runner_build ?? null,
                    provider_wrapper_resolved_path: row.provider_wrapper_resolved_path ?? null,
                    provider_wrapper_kind: row.provider_wrapper_kind ?? null,
                    provider_launch_mode: row.provider_launch_mode ?? null,
                    provider_shell_fallback_executable: row.provider_shell_fallback_executable ?? null,
                    provider_auto_continue_mode: row.provider_auto_continue_mode ?? null,
                    provider_pty_backend: row.provider_pty_backend ?? null,
                    provider_startup_clear_command: row.provider_startup_clear_command ?? null,
                    provider_startup_clear_command_source: row.provider_startup_clear_command_source ?? null,
                    provider_startup_clear_completed: row.provider_startup_clear_completed ?? null,
                    provider_startup_clear_reason: row.provider_startup_clear_reason ?? null,
                    provider_startup_stats_command: row.provider_startup_stats_command ?? null,
                    provider_startup_stats_command_source: row.provider_startup_stats_command_source ?? null,
                    provider_startup_model_command: row.provider_startup_model_command ?? null,
                    provider_startup_model_command_source: row.provider_startup_model_command_source ?? null,
                    provider_current_model: row.provider_current_model ?? null,
                    provider_model_capacity: row.provider_model_capacity ?? null,
                    provider_model_capacity_raw_lines: row.provider_model_capacity_raw_lines ?? null,
                    mongo_transcript_sync_state: row.mongo_transcript_sync_state ?? null,
                    mongo_transcript_sync_source: row.mongo_transcript_sync_source ?? null,
                    mongo_transcript_chunk_count: row.mongo_transcript_chunk_count ?? null,
                    mongo_transcript_byte_count: row.mongo_transcript_byte_count ?? null,
                    mongo_transcript_synchronized_at_epoch: row.mongo_transcript_synchronized_at ? row.mongo_transcript_synchronized_at.getTime() / 1000 : null,
                    input_capture_path: row.input_capture_path ?? null,
                    input_chunk_count: row.input_chunk_count ?? null,
                    input_byte_count: row.input_byte_count ?? null,
                    mongo_input_sync_state: row.mongo_input_sync_state ?? null,
                    mongo_input_sync_source: row.mongo_input_sync_source ?? null,
                    mongo_input_chunk_count: row.mongo_input_chunk_count ?? null,
                    mongo_input_byte_count: row.mongo_input_byte_count ?? null,
                    mongo_input_synchronized_at_epoch: row.mongo_input_synchronized_at ? row.mongo_input_synchronized_at.getTime() / 1000 : null,
                    provider_fresh_session_prepared: row.provider_fresh_session_prepared ?? null,
                    provider_fresh_session_reset_reason: row.provider_fresh_session_reset_reason ?? null,
                    provider_fresh_session_removed_path_count: row.provider_fresh_session_removed_path_count ?? null,
                    provider_model_usage_note: row.provider_model_usage_note ?? null,
                    provider_model_usage: row.provider_model_usage ?? null,
                    observed_slash_commands: row.observed_slash_commands ?? null,
                    observed_prompt_submissions: row.observed_prompt_submissions ?? null,
                    observed_interactions: row.observed_interactions
                        ? row.observed_interactions.map((item) => ({
                            text: item.text ?? "",
                            kind: item.kind ?? "",
                            source: item.source ?? "",
                            first_observed_at_epoch: item.first_observed_at != null ? Number(item.first_observed_at) / 1000 : 0,
                            last_observed_at_epoch: item.last_observed_at != null ? Number(item.last_observed_at) / 1000 : 0,
                            observation_count: item.observation_count ?? 0
                        }))
                        : null,
                    prompt: row.prompt ?? null,
                    working_directory: row.working_directory,
                    transcript_path: row.transcript_path,
                    launch_command: row.launch_command,
                    capture_mode: row.capture_mode,
                    status: row.status,
                    started_at_epoch: row.started_at ? row.started_at.getTime() / 1000 : null,
                    activity_at_epoch: row.activity_at ? row.activity_at.getTime() / 1000 : null,
                    last_activity_at_epoch: row.last_activity_at ? row.last_activity_at.getTime() / 1000 : null,
                    ended_at_epoch: row.ended_at ? row.ended_at.getTime() / 1000 : null,
                    chunk_count: row.chunk_count,
                    byte_count: row.byte_count,
                    last_error: row.last_error ?? null,
                    last_preview: row.last_preview ?? "",
                    last_database_message: row.last_database_message ?? "",
                    status_reason: row.status_reason ?? null,
                    exit_code: row.exit_code ?? null,
                    session_payload: row.session_payload ?? null
                }));
            });
        })();
        """

        let output = try runMongo(script, settings: settings)
        let rows = try parseMongoRows(output, as: DatabaseSessionRow.self)
        return Self.orderedSessions(rows.map { $0.makeSession() }, by: uniqueSessionIDs)
    }

    func fetchSession(sessionID: UUID, settings: MongoMonitoringSettings) throws -> TerminalMonitorSession? {
        try fetchSessions(sessionIDs: [sessionID], settings: settings).first
    }

    func fetchSessionEvents(sessionID: UUID, settings: MongoMonitoringSettings, limit: Int) throws -> [TerminalSessionEvent] {
        guard settings.enableMongoWrites else { return [] }
        try ensureSchema(settings: settings)

        let safeLimit = max(1, min(500, limit))
        let payload: [String: Any] = [
            "session_id": sessionID.uuidString,
            "limit": safeLimit
        ]

        let script = """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const params = JSON.parse(\(mongoJSONLiteral(payload)));
            const targetDb = db.getSiblingDB(cfg.cfg);
            const rows = targetDb.terminal_session_events.find({ session_id: params.session_id }).sort({ event_at: -1, _id: -1 }).limit(params.limit).toArray();
            rows.forEach((row, index) => {
                print(EJSON.stringify({
                    id: index + 1,
                    session_id: row.session_id,
                    event_type: row.event_type,
                    status: row.status,
                    event_at_epoch: row.event_at ? row.event_at.getTime() / 1000 : null,
                    message: row.message ?? null,
                    metadata_json: row.metadata_json ?? null
                }));
            });
        })();
        """

        let output = try runMongo(script, settings: settings)
        let rows = try parseMongoRows(output, as: DatabaseSessionEventRow.self)
        return rows.map { $0.makeEvent() }
    }

    func fetchSessionChunkSummary(sessionID: UUID, settings: MongoMonitoringSettings) throws -> MongoSessionChunkSummary {
        guard settings.enableMongoWrites else {
            return MongoSessionChunkSummary(chunkCount: 0, byteCount: 0)
        }
        try ensureSchema(settings: settings)

        let payload: [String: Any] = [
            "session_id": sessionID.uuidString
        ]

        let script = Self.fetchSessionChunkSummaryScript(
            configLiteral: mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)]),
            payloadLiteral: mongoJSONLiteral(payload)
        )

        let output = try runMongo(script, settings: settings)
        let rows = try parseMongoRows(output, as: DatabaseSessionChunkSummaryRow.self)
        return rows.first?.makeSummary() ?? MongoSessionChunkSummary(chunkCount: 0, byteCount: 0)
    }

    func fetchSessionChunks(sessionID: UUID, settings: MongoMonitoringSettings, limit: Int) throws -> [TerminalTranscriptChunk] {
        guard settings.enableMongoWrites else { return [] }
        try ensureSchema(settings: settings)

        let safeLimit = max(1, min(500, limit))
        return try fetchSessionChunks(sessionID: sessionID, settings: settings, safeLimit: safeLimit)
    }

    func fetchSessionChunksForObservedInteractionBackfill(sessionID: UUID, settings: MongoMonitoringSettings, limit: Int) throws -> [TerminalTranscriptChunk] {
        guard settings.enableMongoWrites else { return [] }
        try ensureSchema(settings: settings)

        let safeLimit = max(1, min(10_000, limit))
        return try fetchSessionChunks(sessionID: sessionID, settings: settings, safeLimit: safeLimit)
    }

    private func fetchSessionChunks(sessionID: UUID, settings: MongoMonitoringSettings, safeLimit: Int) throws -> [TerminalTranscriptChunk] {
        let payload: [String: Any] = [
            "session_id": sessionID.uuidString,
            "limit": safeLimit
        ]

        let script = """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const params = JSON.parse(\(mongoJSONLiteral(payload)));
            const targetDb = db.getSiblingDB(cfg.cfg);
            const rows = targetDb.terminal_chunks.find({ session_id: params.session_id }).sort({ chunk_index: -1 }).limit(params.limit).toArray();
            rows.reverse().forEach((row, index) => {
                print(EJSON.stringify({
                    id: index + 1,
                    session_id: row.session_id,
                    chunk_index: row.chunk_index,
                    source: row.source,
                    captured_at_epoch: row.captured_at ? row.captured_at.getTime() / 1000 : null,
                    byte_count: row.byte_count,
                    prompt: row.prompt,
                    preview_text: row.preview_text,
                    raw_base64: row.raw_base64,
                    status: row.status,
                    status_reason: row.status_reason,
                    message: row.message
                }));
            });
        })();
        """

        let output = try runMongo(script, settings: settings)
        let rows = try parseMongoRows(output, as: DatabaseSessionChunkRow.self)
        return rows.map { $0.makeChunk() }
    }

    func fetchSessionInputChunkSummary(sessionID: UUID, settings: MongoMonitoringSettings) throws -> MongoSessionChunkSummary {
        guard settings.enableMongoWrites else {
            return MongoSessionChunkSummary(chunkCount: 0, byteCount: 0)
        }
        try ensureSchema(settings: settings)

        let payload: [String: Any] = [
            "session_id": sessionID.uuidString
        ]

        let script = """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const params = JSON.parse(\(mongoJSONLiteral(payload)));
            const targetDb = db.getSiblingDB(cfg.cfg);
            const summary = targetDb.terminal_input_chunks.aggregate([
                { $match: { session_id: params.session_id } },
                {
                    $group: {
                        _id: null,
                        chunkCount: { $sum: 1 },
                        totalBytes: { $sum: { $ifNull: ["$byte_count", 0] } },
                        minChunkIndex: { $min: "$input_index" },
                        maxChunkIndex: { $max: "$input_index" }
                    }
                }
            ]).toArray();
            const row = summary.length > 0 ? summary[0] : null;
            print(EJSON.stringify({
                chunk_count: row && row.chunkCount != null ? Number(row.chunkCount) : 0,
                byte_count: row && row.totalBytes != null ? Number(row.totalBytes) : 0,
                min_chunk_index: row && row.minChunkIndex != null ? Number(row.minChunkIndex) : null,
                max_chunk_index: row && row.maxChunkIndex != null ? Number(row.maxChunkIndex) : null
            }));
        })();
        """

        let output = try runMongo(script, settings: settings)
        let rows = try parseMongoRows(output, as: DatabaseSessionChunkSummaryRow.self)
        return rows.first?.makeSummary() ?? MongoSessionChunkSummary(chunkCount: 0, byteCount: 0)
    }

    func fetchSessionInputChunks(sessionID: UUID, settings: MongoMonitoringSettings, limit: Int) throws -> [TerminalInputChunk] {
        guard settings.enableMongoWrites else { return [] }
        try ensureSchema(settings: settings)

        let safeLimit = max(1, min(2_000, limit))
        let payload: [String: Any] = [
            "session_id": sessionID.uuidString,
            "limit": safeLimit
        ]

        let script = """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const params = JSON.parse(\(mongoJSONLiteral(payload)));
            const targetDb = db.getSiblingDB(cfg.cfg);
            const rows = targetDb.terminal_input_chunks.find({ session_id: params.session_id }).sort({ input_index: -1 }).limit(params.limit).toArray();
            rows.reverse().forEach((row, index) => {
                print(EJSON.stringify({
                    id: index + 1,
                    session_id: row.session_id,
                    input_index: row.input_index,
                    source: row.source,
                    captured_at_epoch: row.captured_at ? row.captured_at.getTime() / 1000 : null,
                    byte_count: row.byte_count,
                    prompt: row.prompt,
                    preview_text: row.preview_text,
                    raw_base64: row.raw_base64,
                    status: row.status,
                    status_reason: row.status_reason,
                    message: row.message
                }));
            });
        })();
        """

        let output = try runMongo(script, settings: settings)
        let rows = try parseMongoRows(output, as: DatabaseSessionInputChunkRow.self)
        return rows.map { $0.makeChunk() }
    }

    func fetchStorageSummary(settings: MongoMonitoringSettings) throws -> MongoStorageSummary {
        guard settings.enableMongoWrites else { return MongoStorageSummary() }
        try ensureSchema(settings: settings)

        let script = Self.fetchStorageSummaryScript(
            configLiteral: mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])
        )

        let output = try runMongo(script, settings: settings)
        let rows = try parseMongoRows(output, as: DatabaseStorageSummaryRow.self)
        guard let row = rows.first else {
            return MongoStorageSummary()
        }
        return row.makeSummary()
    }

    nonisolated static func fetchStorageSummaryScript(configLiteral: String) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(configLiteral));
            const targetDb = db.getSiblingDB(cfg.cfg);

            const sessionCount = targetDb.terminal_sessions.countDocuments({});
            const activeSessionCount = targetDb.terminal_sessions.countDocuments({ status: { $in: ["prepared", "launching", "monitoring", "idle"] } });
            const completedSessionCount = targetDb.terminal_sessions.countDocuments({ status: "completed" });
            const failedSessionCount = targetDb.terminal_sessions.countDocuments({ status: { $in: ["failed", "stopped"] } });
            const transcriptCompleteSessionCount = targetDb.terminal_sessions.countDocuments({ mongo_transcript_sync_state: "complete" });
            const transcriptStreamingSessionCount = targetDb.terminal_sessions.countDocuments({ mongo_transcript_sync_state: "streaming" });
            const inputCompleteSessionCount = targetDb.terminal_sessions.countDocuments({ mongo_input_sync_state: "complete" });
            const inputStreamingSessionCount = targetDb.terminal_sessions.countDocuments({ mongo_input_sync_state: "streaming" });
            const transcriptCoverageUnknownSessionCount = targetDb.terminal_sessions.countDocuments({
                $or: [
                    { mongo_transcript_sync_state: null },
                    { mongo_transcript_sync_state: { $exists: false } },
                    { mongo_transcript_sync_state: { $nin: ["complete", "streaming"] } }
                ]
            });
            const inputCoverageUnknownSessionCount = targetDb.terminal_sessions.countDocuments({
                $or: [
                    { mongo_input_sync_state: null },
                    { mongo_input_sync_state: { $exists: false } },
                    { mongo_input_sync_state: { $nin: ["complete", "streaming"] } }
                ]
            });
            const chunkCount = targetDb.terminal_chunks.countDocuments({});
            const inputChunkCount = targetDb.terminal_input_chunks.countDocuments({});
            const eventCount = targetDb.terminal_session_events.countDocuments({});

            const logicalBytesDoc = targetDb.terminal_chunks.aggregate([
                { $group: { _id: null, totalBytes: { $sum: { $ifNull: ["$byte_count", 0] } } } }
            ]).toArray();
            const chunkBytes = logicalBytesDoc.length > 0 && logicalBytesDoc[0].totalBytes != null ? logicalBytesDoc[0].totalBytes : 0;
            const logicalInputBytesDoc = targetDb.terminal_input_chunks.aggregate([
                { $group: { _id: null, totalBytes: { $sum: { $ifNull: ["$byte_count", 0] } } } }
            ]).toArray();
            const inputBytes = logicalInputBytesDoc.length > 0 && logicalInputBytesDoc[0].totalBytes != null ? logicalInputBytesDoc[0].totalBytes : 0;
            const collectionStorageBytes = (name) => {
                try {
                    const stats = targetDb.getCollection(name).stats();
                    if (stats && stats.storageSize != null) {
                        return Number(stats.storageSize);
                    }
                    if (stats && stats.size != null) {
                        return Number(stats.size);
                    }
                } catch (error) {
                    void error;
                }
                return 0;
            };
            const sessionTableBytes = collectionStorageBytes("terminal_sessions");
            const chunkTableBytes = collectionStorageBytes("terminal_chunks");
            const inputChunkTableBytes = collectionStorageBytes("terminal_input_chunks");
            const eventTableBytes = collectionStorageBytes("terminal_session_events");

            const oldestSession = targetDb.terminal_sessions.find({}, { projection: { started_at: 1 } }).sort({ started_at: 1 }).limit(1).toArray();
            const newestSession = targetDb.terminal_sessions.find(
                {},
                { projection: { activity_at: 1 } }
            ).sort({ activity_at: -1 }).limit(1).toArray();

            print(EJSON.stringify({
                session_count: Number(sessionCount),
                active_session_count: Number(activeSessionCount),
                completed_session_count: Number(completedSessionCount),
                failed_session_count: Number(failedSessionCount),
                transcript_complete_session_count: Number(transcriptCompleteSessionCount),
                transcript_streaming_session_count: Number(transcriptStreamingSessionCount),
                transcript_coverage_unknown_session_count: Number(transcriptCoverageUnknownSessionCount),
                input_complete_session_count: Number(inputCompleteSessionCount),
                input_streaming_session_count: Number(inputStreamingSessionCount),
                input_coverage_unknown_session_count: Number(inputCoverageUnknownSessionCount),
                chunk_count: Number(chunkCount),
                input_chunk_count: Number(inputChunkCount),
                event_count: Number(eventCount),
                logical_transcript_bytes: Number(chunkBytes),
                logical_input_bytes: Number(inputBytes),
                session_table_bytes: Number(sessionTableBytes),
                chunk_table_bytes: Number(chunkTableBytes),
                input_chunk_table_bytes: Number(inputChunkTableBytes),
                event_table_bytes: Number(eventTableBytes),
                oldest_session_at_epoch: oldestSession.length > 0 && oldestSession[0].started_at ? oldestSession[0].started_at.getTime() / 1000 : null,
                newest_session_at_epoch: newestSession.length > 0 && newestSession[0].activity_at ? newestSession[0].activity_at.getTime() / 1000 : null
            }));
        })();
        """
    }

    func pruneCompletedHistory(settings: MongoMonitoringSettings, retentionDays: Int) throws -> MongoPruneSummary {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(max(1, retentionDays)) * 86_400)
        guard settings.enableMongoWrites else {
            return MongoPruneSummary(cutoffDate: cutoffDate)
        }
        try ensureSchema(settings: settings)

        let safeRetentionDays = max(1, min(3_650, retentionDays))
        let payload: [String: Any] = [
            "cutoff_ms": Int64(cutoffDate.timeIntervalSince1970 * 1_000),
            "retention_days": safeRetentionDays
        ]

        let script = Self.pruneCompletedHistoryScript(
            configLiteral: mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)]),
            payloadLiteral: mongoJSONLiteral(payload)
        )

        let output = try runMongo(script, settings: settings)
        guard let line = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return MongoPruneSummary(cutoffDate: cutoffDate)
        }

        return try Self.mongoRowDecoder.decode(MongoPruneSummary.self, from: Data(line.utf8))
    }

    func clearAllHistory(settings: MongoMonitoringSettings) throws -> MongoClearSummary {
        guard settings.enableMongoWrites else { return MongoClearSummary() }
        try ensureSchema(settings: settings)

        let script = Self.clearAllHistoryScript(
            configLiteral: mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])
        )

        let output = try runMongo(script, settings: settings)
        guard let line = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return MongoClearSummary()
        }

        return try Self.mongoRowDecoder.decode(MongoClearSummary.self, from: Data(line.utf8))
    }

    nonisolated static func clearAllHistoryScript(configLiteral: String) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(configLiteral));
            const targetDb = db.getSiblingDB(cfg.cfg);
            const deletedSessions = targetDb.terminal_sessions.countDocuments({});
            const deletedChunks = targetDb.terminal_chunks.countDocuments({});
            const deletedInputChunks = targetDb.terminal_input_chunks.countDocuments({});
            const deletedEvents = targetDb.terminal_session_events.countDocuments({});

            targetDb.terminal_sessions.deleteMany({});
            targetDb.terminal_chunks.deleteMany({});
            targetDb.terminal_input_chunks.deleteMany({});
            targetDb.terminal_session_events.deleteMany({});

            print(JSON.stringify({
                deletedSessions: Number(deletedSessions),
                deletedChunks: Number(deletedChunks),
                deletedInputChunks: Number(deletedInputChunks),
                deletedEvents: Number(deletedEvents)
            }));
        })();
        """
    }

    private func runMongo(_ script: String, settings: MongoMonitoringSettings) throws -> String {
        let launch = try makeMongoLaunchConfiguration(settings: settings)
        do {
            return try executeMongoLaunch(launch: launch, script: script)
        } catch {
            guard shouldRetryMongoLaunch(for: error, settings: settings) else { throw error }
            try startLocalMongodIfNeeded(settings: settings)
            return try executeMongoLaunch(launch: launch, script: script)
        }
    }

    private func executeMongoLaunch(launch: MongoLaunchConfiguration, script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executablePath)
        process.arguments = launch.arguments + ["--quiet", "--norc", "--eval", script, launch.connectionURL]
        process.environment = launch.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw LauncherError.validation("MongoDB execution failed: \(errorText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }

    private func shouldRetryMongoLaunch(for error: Error, settings: MongoMonitoringSettings) -> Bool {
        guard settings.enableMongoWrites else { return false }
        guard settings.mongoConnection.isLocal else { return false }
        let message = error.localizedDescription.lowercased()
        return message.contains("connection") && (
            message.contains("refused") ||
            message.contains("unreachable") ||
            message.contains("timed out") ||
            message.contains("server selection timeout") ||
            message.contains("failed to connect") ||
            message.contains("couldn't connect") ||
            message.contains("could not connect") ||
            message.contains("no connection")
        )
    }

    private func startLocalMongodIfNeeded(settings: MongoMonitoringSettings) throws {
        let port = mongoPort(from: settings.trimmedConnectionURL)
        guard let mongodPath = commandBuilder.resolvedExecutable(settings.mongodExecutable) else {
            throw LauncherError.validation("Local MongoDB monitoring is configured for \(settings.redactedConnectionDescription), but mongod was not found.")
        }
        guard ensureDirectoryExists(at: settings.expandedLocalDataDirectory) else {
            throw LauncherError.validation("Could not create local MongoDB data directory: \(settings.expandedLocalDataDirectory)")
        }

        let logPath = NSString(string: settings.expandedLocalDataDirectory).appendingPathComponent("mongod.log")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mongodPath)
        process.arguments = [
            "--dbpath", settings.expandedLocalDataDirectory,
            "--bind_ip", "127.0.0.1",
            "--port", "\(port)",
            "--fork",
            "--logpath", logPath
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputText = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let errorText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [outputText, errorText].filter { !$0.isEmpty }.joined(separator: " ")

        guard process.terminationStatus == 0 || combined.contains("already running") || combined.contains("Address already in use") else {
            throw LauncherError.validation("Failed to start local mongod: \(combined)")
        }

        guard isMongoReachable(settings: settings) else {
            throw LauncherError.validation("Local mongod did not become reachable on localhost:\(port). See \(logPath).")
        }
    }

    private func isMongoReachable(settings: MongoMonitoringSettings) -> Bool {
        let pingScript = """
        (function() {
            try {
                const ping = db.adminCommand({ ping: 1 });
                print(JSON.stringify({ ok: ping && ping.ok === 1 }));
            } catch (error) {
                print(error.toString());
                process.exit(1);
            }
        })();
        """

        guard let launch = try? makeMongoLaunchConfiguration(settings: settings) else {
            return false
        }

        for _ in 0..<20 {
            do {
                let output = try executeMongoLaunch(launch: launch, script: pingScript)
                if output.lowercased().contains("\"ok\":true") {
                    return true
                }
            } catch {
                // retry while mongod initializes
            }
            usleep(250_000)
        }
        return false
    }

    private func makeMongoLaunchConfiguration(settings: MongoMonitoringSettings) throws -> MongoLaunchConfiguration {
        let executable = commandBuilder.resolvedExecutable(settings.mongoshExecutable) ?? settings.mongoshExecutable
        guard !settings.trimmedConnectionURL.isEmpty else {
            throw LauncherError.validation("Mongo connection URL is empty.")
        }
        guard let components = URLComponents(string: settings.trimmedConnectionURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "mongodb" || scheme == "mongodb+srv"
        else {
            throw LauncherError.validation("Mongo connection URL must begin with mongodb:// or mongodb+srv://")
        }
        return MongoLaunchConfiguration(
            executablePath: executable,
            arguments: [],
            connectionURL: settings.trimmedConnectionURL,
            environment: ProcessInfo.processInfo.environment
        )
    }

    private func ensureDirectoryExists(at path: String) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            return false
        }
    }

    private func mongoPort(from connectionURL: String) -> Int {
        guard let components = URLComponents(string: connectionURL), let port = components.port else {
            return 27_017
        }
        return port
    }

    private func mongoDatabaseName(from settings: MongoMonitoringSettings) -> String {
        mongoDatabaseName(from: settings.trimmedConnectionURL, fallback: settings.trimmedSchemaName)
    }

    private func mongoDatabaseName(from connectionString: String, fallback: String) -> String {
        guard let components = URLComponents(string: connectionString) else {
            return fallback.isEmpty ? "clilauncher_monitor" : fallback
        }
        let path = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            return fallback.isEmpty ? "clilauncher_monitor" : fallback
        }
        let segments = path.split(separator: "/")
        guard let first = segments.first else {
            return fallback.isEmpty ? "clilauncher_monitor" : fallback
        }
        return String(first)
    }

    private func parseMongoRows<T: Decodable>(_ output: String, as _: T.Type) throws -> [T] {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { line in
                try Self.mongoRowDecoder.decode(T.self, from: Data(line.utf8))
            }
    }

    private func mongoStringLiteral(_ raw: String) -> String {
        MongoShellLiterals.stringLiteral(raw)
    }

    private func mongoJSONLiteral(_ value: Any?) -> String {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return mongoStringLiteral(string)
    }

    private func nullableMongoValue<T>(_ value: T?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    private func defaultMessage(for status: TerminalMonitorStatus) -> String {
        switch status {
        case .prepared: return "Session prepared."
        case .launching: return "Session launching."
        case .monitoring: return "Session monitoring in progress."
        case .idle: return "Session idle; no recent transcript activity."
        case .completed: return "Session completed successfully."
        case .failed: return "Session failed."
        case .stopped: return "Session stopped."
        }
    }
}
