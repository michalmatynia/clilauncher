import AppKit
import Combine
import Foundation

private let sessionPayloadJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
}()

private struct PreparedMonitoringContext: Sendable {
    var session: TerminalMonitorSession
    var wrappedCommand: String
    var completionMarkerPath: String
}

private struct MongoLaunchConfiguration: Sendable {
    var executablePath: String
    var arguments: [String]
    var connectionURL: String
    var environment: [String: String]
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

private struct DatabaseSessionRow: Decodable {
    var session_id: String
    var profile_id: String?
    var profile_name: String
    var agent_kind: String
    var account_identifier: String?
    var prompt: String?
    var working_directory: String
    var transcript_path: String
    var launch_command: String
    var capture_mode: String
    var status: String
    var started_at_epoch: Double
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
        let fallbackSession = TerminalMonitorSession(
            id: UUID(uuidString: session_id) ?? UUID(),
            profileID: profile_id.flatMap(UUID.init(uuidString:)),
            profileName: profile_name,
            agentKind: AgentKind(rawValue: agent_kind) ?? .gemini,
            accountIdentifier: account_identifier,
            prompt: prompt ?? "",
            workingDirectory: working_directory,
            transcriptPath: transcript_path,
            launchCommand: launch_command,
            captureMode: TerminalTranscriptCaptureMode(rawValue: capture_mode) ?? .outputOnly,
            startedAt: Date(timeIntervalSince1970: started_at_epoch),
            lastActivityAt: last_activity_at_epoch.map(Date.init(timeIntervalSince1970:)),
            endedAt: ended_at_epoch.map(Date.init(timeIntervalSince1970:)),
            chunkCount: chunk_count,
            byteCount: byte_count,
            status: TerminalMonitorStatus(rawValue: status) ?? .failed,
            lastPreview: last_preview ?? "",
            lastDatabaseMessage: last_database_message ?? "Loaded from MongoDB.",
            lastError: last_error,
            statusReason: status_reason,
            exitCode: exit_code,
            isHistorical: true
        )

        guard var payloadSession = payloadBackfilledSession() else {
            return fallbackSession
        }

        payloadSession.id = UUID(uuidString: session_id) ?? payloadSession.id
        payloadSession.profileID = profile_id.flatMap(UUID.init(uuidString:))
            ?? payloadSession.profileID
        payloadSession.profileName = profile_name
        payloadSession.agentKind = AgentKind(rawValue: agent_kind) ?? payloadSession.agentKind
        payloadSession.accountIdentifier = account_identifier
        if let prompt {
            payloadSession.prompt = prompt
        }
        payloadSession.workingDirectory = working_directory
        payloadSession.transcriptPath = transcript_path
        payloadSession.launchCommand = launch_command
        payloadSession.captureMode = TerminalTranscriptCaptureMode(rawValue: capture_mode) ?? payloadSession.captureMode
        payloadSession.status = TerminalMonitorStatus(rawValue: status) ?? payloadSession.status
        payloadSession.startedAt = Date(timeIntervalSince1970: started_at_epoch)
        payloadSession.lastActivityAt = last_activity_at_epoch.map(Date.init(timeIntervalSince1970:))
        payloadSession.endedAt = ended_at_epoch.map(Date.init(timeIntervalSince1970:))
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

    private func payloadBackfilledSession() -> TerminalMonitorSession? {
        guard let rawPayload = session_payload?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPayload.isEmpty,
              let payloadData = rawPayload.data(using: .utf8) else {
            return nil
        }
        return try? sessionPayloadJSONDecoder.decode(TerminalMonitorSession.self, from: payloadData)
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
    var preview_text: String
    var raw_base64: String

    func makeChunk() -> TerminalTranscriptChunk {
        TerminalTranscriptChunk(
            id: id,
            sessionID: UUID(uuidString: session_id) ?? UUID(),
            chunkIndex: chunk_index,
            source: source,
            capturedAt: Date(timeIntervalSince1970: captured_at_epoch),
            byteCount: byte_count,
            previewText: preview_text,
            text: decodedTerminalText(from: raw_base64)
        )
    }
}

private struct DatabaseStorageSummaryRow: Decodable {
    var session_count: Int
    var active_session_count: Int
    var completed_session_count: Int
    var failed_session_count: Int
    var chunk_count: Int
    var event_count: Int
    var logical_transcript_bytes: Int64
    var session_table_bytes: Int64
    var chunk_table_bytes: Int64
    var event_table_bytes: Int64
    var oldest_session_at_epoch: Double?
    var newest_session_at_epoch: Double?

    func makeSummary() -> MongoStorageSummary {
        MongoStorageSummary(
            sessionCount: session_count,
            activeSessionCount: active_session_count,
            completedSessionCount: completed_session_count,
            failedSessionCount: failed_session_count,
            chunkCount: chunk_count,
            eventCount: event_count,
            logicalTranscriptBytes: logical_transcript_bytes,
            sessionTableBytes: session_table_bytes,
            chunkTableBytes: chunk_table_bytes,
            eventTableBytes: event_table_bytes,
            oldestSessionAt: oldest_session_at_epoch.map(Date.init(timeIntervalSince1970:)),
            newestSessionAt: newest_session_at_epoch.map(Date.init(timeIntervalSince1970:))
        )
    }
}

private struct DatabasePruneSummaryRow: Decodable {
    var deleted_sessions: Int
    var deleted_chunks: Int
    var deleted_events: Int
    var deleted_chunk_bytes: Int64
}

private struct LocalTranscriptInventory: Sendable {
    var fileCount: Int = 0
    var totalBytes: Int64 = 0
    var oldestFileAt: Date?
    var newestFileAt: Date?
}

private struct LocalTranscriptPruneResult: Sendable {
    var deletedFileCount: Int = 0
    var deletedBytes: Int64 = 0
}

private func decodedTerminalText(from rawBase64: String) -> String {
    guard let data = Data(base64Encoded: rawBase64) else { return "" }
    return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{0000}", with: "")
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

struct MonitoringDiagnosticsService {
    private let builder = CommandBuilder()

    func inspect(settings: MongoMonitoringSettings) -> [ToolStatus] {
        guard settings.enabled else { return [] }

        var statuses: [ToolStatus] = []
        let scriptResolved = builder.resolvedExecutable(settings.scriptExecutable)
        statuses.append(
            ToolStatus(
                name: "Terminal capture",
                requested: settings.scriptExecutable,
                resolved: scriptResolved,
                detail: scriptResolved != nil
                    ? (settings.captureMode.usesScriptKeyLogging ? "script(1) will record keyboard input and terminal output." : "script(1) will record terminal output.")
                    : "script executable was not found",
                isError: scriptResolved == nil
            )
        )

        let transcriptPath = settings.expandedTranscriptDirectory
        let transcriptReady = ensureDirectoryExists(at: transcriptPath)
        statuses.append(
            ToolStatus(
                name: "Transcript directory",
                requested: transcriptPath,
                resolved: transcriptReady ? transcriptPath : nil,
                detail: transcriptReady ? "Ready for local terminal transcripts." : "Could not create transcript directory.",
                isError: !transcriptReady
            )
        )

        if settings.enableMongoWrites {
            let mongoResolved = builder.resolvedExecutable(settings.mongoshExecutable)
            statuses.append(
                ToolStatus(
                    name: "MongoDB CLI",
                    requested: settings.mongoshExecutable,
                    resolved: mongoResolved,
                    detail: mongoResolved != nil ? "MongoDB shell resolved." : "MongoDB shell executable was not found",
                    isError: mongoResolved == nil
                )
            )
            let mongodResolved = builder.resolvedExecutable(settings.mongodExecutable)
            let localMongo = settings.mongoConnection.isLocal
            statuses.append(
                ToolStatus(
                    name: "mongod",
                    requested: settings.mongodExecutable,
                    resolved: mongodResolved,
                    detail: localMongo
                        ? (mongodResolved != nil ? "Local Mongo daemon executable resolved." : "Local Mongo connection uses localhost and requires mongod.")
                        : (mongodResolved != nil ? "mongod executable resolved." : "mongod executable was not found."),
                    isError: localMongo && settings.enableMongoWrites && mongodResolved == nil
                )
            )
            let hasConnection = !settings.trimmedConnectionURL.isEmpty
            statuses.append(
                ToolStatus(
                    name: "Mongo connection URL",
                    requested: settings.redactedConnectionDescription,
                    resolved: hasConnection ? settings.redactedConnectionDescription : nil,
                    detail: hasConnection ? "Connection string configured." : "Connection URL is empty.",
                    isError: !hasConnection
                )
            )
            if settings.enableMongoWrites {
                let dataDirReady = ensureDirectoryExists(at: settings.expandedLocalDataDirectory)
                statuses.append(
                    ToolStatus(
                        name: "Local Mongo data directory",
                        requested: settings.expandedLocalDataDirectory,
                        resolved: dataDirReady ? settings.expandedLocalDataDirectory : nil,
                        detail: dataDirReady ? "Ready for a local MongoDB data directory." : "Could not create local MongoDB data directory.",
                        isError: !dataDirReady
                    )
                )
            }
        }

        return statuses
    }

    private func ensureDirectoryExists(at path: String) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            return false
        }
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
            "prompt": session.prompt,
            "working_directory": session.workingDirectory,
            "transcript_path": session.transcriptPath,
            "launch_command": session.launchCommand,
            "capture_mode": session.captureMode.rawValue,
            "status": session.status.rawValue,
            "started_at": Int64(session.startedAt.timeIntervalSince1970 * 1_000),
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
        _ = try runMongo(ensureSchemaScript(settings: settings), settings: settings)
        let fingerprint = settings.trimmedConnectionURL + "|" + settings.trimmedSchemaName + "|" + settings.expandedLocalDataDirectory
        initializedFingerprint = fingerprint
    }

    func recordSessionStart(_ session: TerminalMonitorSession, settings: MongoMonitoringSettings) throws {
        guard settings.enableMongoWrites else { return }
        try ensureSchema(settings: settings)

        let payload = sessionDocument(from: session)

        let script = """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const payload = JSON.parse(\(mongoJSONLiteral(payload)));
            const targetDb = db.getSiblingDB(cfg.cfg);
            targetDb.terminal_sessions.updateOne(
                { session_id: payload.session_id },
                {
                    $set: {
                        profile_id: payload.profile_id,
                        profile_name: payload.profile_name,
                        agent_kind: payload.agent_kind,
                        account_identifier: payload.account_identifier,
                        prompt: payload.prompt,
                        working_directory: payload.working_directory,
                        transcript_path: payload.transcript_path,
                        launch_command: payload.launch_command,
                        capture_mode: payload.capture_mode,
                        session_payload: payload.session_payload,
                        status: payload.status,
                        started_at: new Date(payload.started_at),
                        last_activity_at: payload.last_activity_at,
                        ended_at: payload.ended_at,
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
                        session_id: payload.session_id,
                        profile_id: payload.profile_id,
                        started_at: new Date(payload.started_at)
                    }
                },
                { upsert: true }
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
        _ = try runMongo(script, settings: settings)
    }

    func recordChunk(
        sessionID: UUID,
        chunkIndex: Int,
        data: Data,
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
            "source": "terminal_transcript",
            "prompt": prompt,
            "captured_at": Int64(capturedAt.timeIntervalSince1970 * 1_000),
            "byte_count": data.count,
            "preview_text": preview,
            "raw_base64": data.base64EncodedString(),
            "status": status.rawValue,
            "message": "Synced chunk \(totalChunks) to MongoDB.",
            "total_chunks": totalChunks,
            "total_bytes": totalBytes,
            "session": sessionPayload
        ]

        let script = """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const payload = JSON.parse(\(mongoJSONLiteral(payload)));
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
                        raw_base64: payload.raw_base64
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
                        prompt: payload.session.prompt,
                        working_directory: payload.session.working_directory,
                        transcript_path: payload.session.transcript_path,
                        launch_command: payload.session.launch_command,
                        capture_mode: payload.session.capture_mode,
                        session_payload: payload.session.session_payload,
                        last_activity_at: new Date(payload.captured_at),
                        chunk_count: payload.total_chunks,
                        byte_count: payload.total_bytes,
                        status: payload.session.status,
                        last_preview: payload.preview_text,
                        last_database_message: payload.message,
                        status_reason: payload.session.status_reason,
                        last_error: payload.session.last_error,
                        exit_code: payload.session.exit_code,
                        ended_at: payload.session.ended_at,
                        metadata_json: payload.session.metadata_json
                    }
                }
            );
            print("ok");
        })();
        """
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
            "metadata": [
                "status_reason": nullableMongoValue(resolvedSession.statusReason),
                "exit_code": nullableMongoValue(resolvedSession.exitCode),
                "ended_at": nullableMongoValue(endedAtMillis),
                "message": statusMessage
            ]
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
                        prompt: payload.session.prompt,
                        working_directory: payload.session.working_directory,
                        transcript_path: payload.session.transcript_path,
                        launch_command: payload.session.launch_command,
                        capture_mode: payload.session.capture_mode,
                        started_at: new Date(payload.session.started_at),
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
                }
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

        let script = """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const params = JSON.parse(\(mongoJSONLiteral(payload)));
            const targetDb = db.getSiblingDB(cfg.cfg);
            const rows = targetDb.terminal_sessions.aggregate([
                { $match: { started_at: { $gte: new Date(params.cutoff_ms) } } },
                { $addFields: { _sort_at: { $ifNull: ["$last_activity_at", { $ifNull: ["$ended_at", "$started_at"] }] } } },
                { $sort: { _sort_at: -1 } },
                { $limit: params.limit }
            ]).toArray();

            rows.forEach((row) => {
                print(EJSON.stringify({
                    session_id: row.session_id,
                    profile_id: row.profile_id ?? null,
                    profile_name: row.profile_name,
                    agent_kind: row.agent_kind,
                    account_identifier: row.account_identifier ?? null,
                    prompt: row.prompt ?? null,
                    working_directory: row.working_directory,
                    transcript_path: row.transcript_path,
                    launch_command: row.launch_command,
                    capture_mode: row.capture_mode,
                    status: row.status,
                    started_at_epoch: row.started_at ? row.started_at.getTime() / 1000 : null,
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
        return rows.map { $0.makeSession() }
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

    func fetchSessionChunks(sessionID: UUID, settings: MongoMonitoringSettings, limit: Int) throws -> [TerminalTranscriptChunk] {
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
            const rows = targetDb.terminal_chunks.find({ session_id: params.session_id }).sort({ chunk_index: -1 }).limit(params.limit).toArray();
            rows.reverse().forEach((row, index) => {
                print(EJSON.stringify({
                    id: index + 1,
                    session_id: row.session_id,
                    chunk_index: row.chunk_index,
                    source: row.source,
                    captured_at_epoch: row.captured_at ? row.captured_at.getTime() / 1000 : null,
                    byte_count: row.byte_count,
                    preview_text: row.preview_text,
                    raw_base64: row.raw_base64
                }));
            });
        })();
        """

        let output = try runMongo(script, settings: settings)
        let rows = try parseMongoRows(output, as: DatabaseSessionChunkRow.self)
        return rows.map { $0.makeChunk() }
    }

    func fetchStorageSummary(settings: MongoMonitoringSettings) throws -> MongoStorageSummary {
        guard settings.enableMongoWrites else { return MongoStorageSummary() }
        try ensureSchema(settings: settings)

        let script = """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const targetDb = db.getSiblingDB(cfg.cfg);

            const sessionCount = targetDb.terminal_sessions.countDocuments({});
            const activeSessionCount = targetDb.terminal_sessions.countDocuments({ status: { $in: ["prepared", "launching", "monitoring", "idle"] } });
            const completedSessionCount = targetDb.terminal_sessions.countDocuments({ status: "completed" });
            const failedSessionCount = targetDb.terminal_sessions.countDocuments({ status: { $in: ["failed", "stopped"] } });
            const chunkCount = targetDb.terminal_chunks.countDocuments({});
            const eventCount = targetDb.terminal_session_events.countDocuments({});

            const logicalBytesDoc = targetDb.terminal_chunks.aggregate([
                { $group: { _id: null, totalBytes: { $sum: { $ifNull: ["$byte_count", 0] } } } }
            ]).toArray();
            const chunkBytes = logicalBytesDoc.length > 0 && logicalBytesDoc[0].totalBytes != null ? logicalBytesDoc[0].totalBytes : 0;

            const oldestSession = targetDb.terminal_sessions.find({}, { projection: { started_at: 1 } }).sort({ started_at: 1 }).limit(1).toArray();
            const newestSession = targetDb.terminal_sessions.aggregate([
                { $project: { sort_at: { $ifNull: ["$last_activity_at", { $ifNull: ["$ended_at", "$started_at"] }] } } },
                { $sort: { sort_at: -1 } },
                { $limit: 1 },
                { $project: { _id: 0, sort_at: 1 } }
            ]).toArray();

            print(EJSON.stringify({
                session_count: Number(sessionCount),
                active_session_count: Number(activeSessionCount),
                completed_session_count: Number(completedSessionCount),
                failed_session_count: Number(failedSessionCount),
                chunk_count: Number(chunkCount),
                event_count: Number(eventCount),
                logical_transcript_bytes: Number(chunkBytes),
                session_table_bytes: 0,
                chunk_table_bytes: 0,
                event_table_bytes: 0,
                oldest_session_at_epoch: oldestSession.length > 0 && oldestSession[0].started_at ? oldestSession[0].started_at.getTime() / 1000 : null,
                newest_session_at_epoch: newestSession.length > 0 && newestSession[0].sort_at ? newestSession[0].sort_at.getTime() / 1000 : null
            }));
        })();
        """

        let output = try runMongo(script, settings: settings)
        let rows = try parseMongoRows(output, as: DatabaseStorageSummaryRow.self)
        guard let row = rows.first else {
            return MongoStorageSummary()
        }
        return row.makeSummary()
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

        let script = """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const params = JSON.parse(\(mongoJSONLiteral(payload)));
            const targetDb = db.getSiblingDB(cfg.cfg);

            const doomed = targetDb.terminal_sessions.find({
                status: { $in: ["completed", "failed", "stopped"] },
                $expr: { $lt: [ { $ifNull: ["$ended_at", { $ifNull: ["$last_activity_at", "$started_at"] }] }, new Date(params.cutoff_ms) ] }
            }, { projection: { session_id: 1, byte_count: 1 } }).toArray();

            const doomedIds = doomed.map((entry) => entry.session_id);
            const deletedSessionCount = doomedIds.length;

            let deletedChunkCount = 0;
            let deletedChunkBytes = 0;
            let deletedEventCount = 0;

            if (doomedIds.length > 0) {
                const doomedChunks = targetDb.terminal_chunks.find({ session_id: { $in: doomedIds } }).toArray();
                doomedChunks.forEach((chunk) => {
                    deletedChunkCount += 1;
                    const chunkBytes = Number(chunk.byte_count || 0);
                    deletedChunkBytes += Number(chunkBytes);
                });

                const eventDelete = targetDb.terminal_session_events.deleteMany({ session_id: { $in: doomedIds } });
                deletedEventCount = Number(eventDelete.deletedCount || 0);

                const chunkDelete = targetDb.terminal_chunks.deleteMany({ session_id: { $in: doomedIds } });
                deletedChunkCount = Number(chunkDelete.deletedCount || deletedChunkCount);

                const sessionDelete = targetDb.terminal_sessions.deleteMany({ session_id: { $in: doomedIds } });
                const actualSessionCount = Number(sessionDelete.deletedCount || deletedSessionCount);

                print(JSON.stringify({
                    deletedSessions: actualSessionCount,
                    deletedChunks: deletedChunkCount,
                    deletedEvents: deletedEventCount
                }));
            } else {
                print(JSON.stringify({ deletedSessions: 0, deletedChunks: 0, deletedEvents: 0 }));
            }
        })();
        """

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

    func clearAllHistory(settings: MongoMonitoringSettings) throws {
        guard settings.enableMongoWrites else { return }
        try ensureSchema(settings: settings)

        let script = """
        (function() {
            const dbName = \(mongoStringLiteral(mongoDatabaseName(from: settings)));
            const targetDb = db.getSiblingDB(dbName);
            targetDb.terminal_sessions.drop();
            targetDb.terminal_chunks.drop();
            targetDb.terminal_session_events.drop();
            print("OK");
        })();
        """
        _ = try runMongo(script, settings: settings)
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

    private func ensureSchemaScript(settings: MongoMonitoringSettings) -> String {
        """
        (function() {
            const cfg = JSON.parse(\(mongoJSONLiteral(["cfg": mongoDatabaseName(from: settings)])));
            const targetDb = db.getSiblingDB(cfg.cfg);
            const collections = targetDb.listCollections().toArray().map((entry) => entry.name);
            if (!collections.includes("terminal_sessions")) {
                targetDb.createCollection("terminal_sessions");
            }
            if (!collections.includes("terminal_chunks")) {
                targetDb.createCollection("terminal_chunks");
            }
            if (!collections.includes("terminal_session_events")) {
                targetDb.createCollection("terminal_session_events");
            }

            targetDb.terminal_sessions.createIndex({ session_id: 1 }, { unique: true });
            targetDb.terminal_sessions.createIndex({ account_identifier: 1 });
            targetDb.terminal_sessions.createIndex({ prompt: "text" });
            targetDb.terminal_chunks.createIndex({ session_id: 1, chunk_index: 1 }, { unique: true });
            targetDb.terminal_session_events.createIndex({ session_id: 1, event_at: -1, _id: -1 });
            targetDb.terminal_sessions.createIndex({ status: 1, ended_at: -1, last_activity_at: -1, started_at: -1 });
            print("MongoDB monitoring collections ready.");
        })();
        """
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
        _ = components
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
        if let data = try? JSONSerialization.data(withJSONObject: raw, options: []),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\""
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
        case .prepared:
            return "Session prepared."

        case .launching:
            return "Session launching."

        case .monitoring:
            return "Session monitoring in progress."

        case .idle:
            return "Session idle; no recent transcript activity."

        case .completed:
            return "Session completed successfully."

        case .failed:
            return "Session failed."

        case .stopped:
            return "Session stopped."
        }
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
    private let minimumRecentSessionsRefreshInterval: TimeInterval = 1.2
    private let minimumStorageSummaryRefreshInterval: TimeInterval = 1.8
    private static let maxVisibleSessions = 200

    private var preparedContexts: [UUID: PreparedMonitoringContext] = [:]
    private var pollTasks: [UUID: Task<Void, Never>] = [:]
    private var nextDetailRefreshAt: [UUID: Date] = [:]
    private var lastRecentSessionsRefreshAt: Date?
    private var lastStorageSummaryRefreshAt: Date?
    private var sessionIndexByID: [UUID: Int] = [:]
    private let writer = MongoMonitoringWriter()
    private let backupService = DatabaseBackupService()
    private let diagnostics = MonitoringDiagnosticsService()

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
        }

        databaseStatus = settings.mongoMonitoring.enableMongoWrites ? "Prepared \(updatedPlan.items.count) monitored launch(es)." : "Local transcript monitoring prepared."
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

            if settings.mongoMonitoring.enableMongoWrites {
                Task {
                    do {
                        try await writer.ensureSchema(settings: settings.mongoMonitoring)
                        try await writer.recordSessionStart(session, settings: settings.mongoMonitoring)
                        await MainActor.run {
                            self.databaseStatus = "MongoDB session logging active."
                            self.lastConnectionCheck = Date().formatted(date: .abbreviated, time: .standard)
                        }
                    } catch {
                        await MainActor.run {
                            if let index = self.sessionIndex(for: session.id) {
                                self.sessions[index].lastDatabaseMessage = "MongoDB unavailable: \(error.localizedDescription)"
                            }
                            self.databaseStatus = "MongoDB write error"
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
        for id in removedIDs {
            sessionDetailsByID.removeValue(forKey: id)
            detailLoadingSessionIDs.remove(id)
            nextDetailRefreshAt.removeValue(forKey: id)
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
            databaseStatus = "Monitoring disabled"
            logger.log(.warning, "Enable terminal monitoring before testing MongoDB connectivity.", category: .monitoring)
            return
        }
        guard settings.mongoMonitoring.enableMongoWrites else {
            databaseStatus = "Local transcript monitoring only"
            logger.log(.info, "MongoDB writes are disabled; local transcript monitoring is still available.", category: .monitoring)
            return
        }

        databaseStatus = "Testing connection..."
        Task {
            do {
                let result = try await writer.testConnection(settings: settings.mongoMonitoring)
                await MainActor.run {
                    self.lastConnectionCheck = Date().formatted(date: .abbreviated, time: .standard)
                    self.databaseStatus = "Connected • \(result)"
                    logger.log(.success, "MongoDB monitoring connection OK: \(result)", category: .monitoring)
                }
            } catch {
                await MainActor.run {
                    self.databaseStatus = "Connection failed: \(error.localizedDescription)"
                    logger.log(.error, "MongoDB monitoring connection failed: \(error.localizedDescription)", category: .monitoring)
                }
            }
        }
    }

    func refreshRecentSessions(settings: AppSettings, logger: LaunchLogger, force: Bool = false) {
        guard settings.mongoMonitoring.enabled else {
            databaseStatus = "Monitoring disabled"
            storageSummary = nil
            storageSummaryStatus = ""
            isLoadingRecentSessions = false
            return
        }
        guard settings.mongoMonitoring.enableMongoWrites else {
            databaseStatus = "Local transcript monitoring only"
            isLoadingRecentSessions = false
            return
        }
        let now = Date()
        if !force {
            if isLoadingRecentSessions {
                return
            }
            if let lastRefresh = lastRecentSessionsRefreshAt,
               now.timeIntervalSince(lastRefresh) < minimumRecentSessionsRefreshInterval {
                return
            }
        }

        isLoadingRecentSessions = true
        Task {
            do {
                let databaseSessions = try await writer.fetchRecentSessions(
                    settings: settings.mongoMonitoring,
                    limit: settings.mongoMonitoring.clampedRecentHistoryLimit,
                    lookbackHours: settings.mongoMonitoring.clampedRecentHistoryLookbackDays * 24
                )
                await MainActor.run {
                    self.synchronizeHistoricalSessions(databaseSessions)
                    self.lastConnectionCheck = Date().formatted(date: .abbreviated, time: .standard)
                    self.databaseStatus = "Loaded \(databaseSessions.count) recent session(s) from MongoDB."
                    logger.log(.success, "Loaded \(databaseSessions.count) recent monitored session(s) from MongoDB.", category: .monitoring)
                    self.lastRecentSessionsRefreshAt = now
                    self.isLoadingRecentSessions = false
                }
            } catch {
                await MainActor.run {
                    self.databaseStatus = "Recent session refresh failed"
                    logger.log(.error, "Failed to load recent MongoDB-backed sessions: \(error.localizedDescription)", category: .monitoring)
                    self.lastRecentSessionsRefreshAt = now
                    self.isLoadingRecentSessions = false
                }
            }
        }
    }

    func refreshStorageSummary(settings: AppSettings, logger: LaunchLogger, force: Bool = false) {
        guard settings.mongoMonitoring.enabled else {
            storageSummary = nil
            storageSummaryStatus = ""
            isLoadingStorageSummary = false
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

        isLoadingStorageSummary = true
        let monitoringSettings = settings.mongoMonitoring

        Task { [weak self] in
            guard let self else { return }

            var summary = Self.scanTranscriptDirectory(at: monitoringSettings.expandedTranscriptDirectory)
            var notes: [String] = []

            if monitoringSettings.enableMongoWrites {
                do {
                    let databaseSummary = try await writer.fetchStorageSummary(settings: monitoringSettings)
                    summary.sessionCount = databaseSummary.sessionCount
                    summary.activeSessionCount = databaseSummary.activeSessionCount
                    summary.completedSessionCount = databaseSummary.completedSessionCount
                    summary.failedSessionCount = databaseSummary.failedSessionCount
                    summary.chunkCount = databaseSummary.chunkCount
                    summary.eventCount = databaseSummary.eventCount
                    summary.logicalTranscriptBytes = databaseSummary.logicalTranscriptBytes
                    summary.sessionTableBytes = databaseSummary.sessionTableBytes
                    summary.chunkTableBytes = databaseSummary.chunkTableBytes
                    summary.eventTableBytes = databaseSummary.eventTableBytes
                    summary.oldestSessionAt = databaseSummary.oldestSessionAt
                    summary.newestSessionAt = databaseSummary.newestSessionAt
                    notes.append("Loaded MongoDB storage totals.")
                } catch {
                    notes.append("MongoDB storage summary failed: \(error.localizedDescription)")
                    logger.log(.warning, "Failed to load MongoDB storage summary: \(error.localizedDescription)", category: .monitoring)
                }
            } else {
                notes.append("MongoDB writes are disabled; showing local transcript storage only.")
            }

            if summary.transcriptFileCount > 0 {
                notes.append("Scanned \(summary.transcriptFileCount) local transcript file(s).")
            } else {
                notes.append("No local transcript files were found.")
            }

            await MainActor.run {
                self.storageSummary = summary
                self.storageSummaryStatus = notes.joined(separator: " ")
                self.isLoadingStorageSummary = false
                self.lastStorageSummaryRefreshAt = now
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
            if monitoringSettings.enableMongoWrites {
                do {
                    try await writer.clearAllHistory(settings: monitoringSettings)
                    notes.append("Cleared all MongoDB session history.")
                } catch {
                    notes.append("MongoDB clear failed: \(error.localizedDescription)")
                    logger.log(.error, "Failed to clear MongoDB history: \(error.localizedDescription)", category: .monitoring)
                }
            }

            let localPrune = Self.pruneTranscriptDirectory(
                at: monitoringSettings.expandedTranscriptDirectory,
                olderThanDays: 0,
                protectedPaths: []
            )
            notes.append("Cleared all local transcript files: \(localPrune.deletedFileCount) files.")

            await MainActor.run {
                self.isPruningStoredHistory = false
                self.refreshRecentSessions(settings: settings, logger: logger, force: true)
                self.refreshStorageSummary(settings: settings, logger: logger, force: true)
                logger.log(.success, notes.joined(separator: " "), category: .monitoring)
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

            if monitoringSettings.enableMongoWrites {
                do {
                    pruneSummary = try await writer.pruneCompletedHistory(
                        settings: monitoringSettings,
                        retentionDays: databaseRetentionDays
                    )
                    notes.append("Deleted \(pruneSummary.deletedSessions) MongoDB session row(s).")
                } catch {
                    notes.append("MongoDB prune failed: \(error.localizedDescription)")
                    logger.log(.error, "Failed to prune MongoDB monitor history: \(error.localizedDescription)", category: .monitoring)
                }
            } else {
                pruneSummary.cutoffDate = Date().addingTimeInterval(-TimeInterval(localRetentionDays) * 86_400)
                notes.append("MongoDB writes are disabled; pruning local transcript files only.")
            }

            let localPrune = Self.pruneTranscriptDirectory(
                at: monitoringSettings.expandedTranscriptDirectory,
                olderThanDays: localRetentionDays,
                protectedPaths: protectedTranscriptPaths()
            )
            pruneSummary.deletedTranscriptFiles = localPrune.deletedFileCount
            pruneSummary.deletedTranscriptBytes = localPrune.deletedBytes
            notes.append(
                localPrune.deletedFileCount > 0
                    ? "Deleted \(localPrune.deletedFileCount) local transcript file(s)."
                    : "No local transcript files matched the retention cutoff."
            )

            let logLevel: LogLevel = notes.contains { $0.localizedCaseInsensitiveContains("failed") } ? .warning : .success

            await MainActor.run {
                self.lastPruneResult = pruneSummary
                self.lastPruneSummary = Self.describe(pruneSummary: pruneSummary)
                self.databaseStatus = monitoringSettings.enableMongoWrites
                    ? "Stored monitoring history pruned."
                    : "Local transcript history pruned."
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

    func loadDetails(for session: TerminalMonitorSession, settings: AppSettings, logger: LaunchLogger, forceRefresh: Bool = false) {
        let now = Date()
        if detailLoadingSessionIDs.contains(session.id) {
            return
        }

        if !forceRefresh, let nextRefresh = nextDetailRefreshAt[session.id], nextRefresh > now {
            return
        }

        if !forceRefresh, let cached = sessionDetailsByID[session.id], cached.matches(session) {
            nextDetailRefreshAt[session.id] = now.addingTimeInterval(minimumDetailRefreshInterval)
            return
        }

        if !forceRefresh {
            nextDetailRefreshAt[session.id] = now.addingTimeInterval(minimumDetailRefreshInterval)
        }

        detailLoadingSessionIDs.insert(session.id)

        Task { [weak self] in
            guard let self else { return }

            var transcriptText = ""
            var transcriptSource = ""
            var transcriptTruncated = false
            var events: [TerminalSessionEvent] = []
            var chunks: [TerminalTranscriptChunk] = []
            var loadNotes: [String] = []

            if session.hasLocalTranscriptFile {
                do {
                    let snapshot = try Self.readTranscriptPreview(
                        at: session.transcriptPath,
                        maxBytes: settings.mongoMonitoring.clampedTranscriptPreviewByteLimit
                    )
                    transcriptText = snapshot.text
                    transcriptSource = snapshot.sourceDescription
                    transcriptTruncated = snapshot.isTruncated
                    loadNotes.append(snapshot.sourceDescription)
                } catch {
                    loadNotes.append("Local transcript read failed: \(error.localizedDescription)")
                }
            } else {
                loadNotes.append("No local transcript file was found.")
            }

            if settings.mongoMonitoring.enabled, settings.mongoMonitoring.enableMongoWrites {
                do {
                    async let fetchedEvents = writer.fetchSessionEvents(
                        sessionID: session.id,
                        settings: settings.mongoMonitoring,
                        limit: settings.mongoMonitoring.clampedDetailEventLimit
                    )
                    async let fetchedChunks = writer.fetchSessionChunks(
                        sessionID: session.id,
                        settings: settings.mongoMonitoring,
                        limit: settings.mongoMonitoring.clampedDetailChunkLimit
                    )
                    events = try await fetchedEvents
                    chunks = try await fetchedChunks
                    loadNotes.append("Loaded \(events.count) event(s) and \(chunks.count) chunk(s) from MongoDB.")

                    if transcriptText.isEmpty, !chunks.isEmpty {
                        transcriptText = chunks.map(\.text).joined()
                        transcriptTruncated = session.chunkCount > chunks.count
                        transcriptSource = transcriptTruncated
                            ? "Reconstructed from the latest \(chunks.count) MongoDB transcript chunks."
                            : "Reconstructed from MongoDB transcript chunks."
                    }
                } catch {
                    loadNotes.append("MongoDB detail fetch failed: \(error.localizedDescription)")
                    logger.log(.warning, "Failed to load detailed monitor data for \(session.profileName): \(error.localizedDescription)", category: .monitoring)
                }
            } else if session.isHistorical || !session.hasLocalTranscriptFile {
                loadNotes.append("MongoDB detail loading is unavailable in the current settings.")
            }

            if transcriptSource.isEmpty {
                transcriptSource = transcriptText.isEmpty
                    ? "No transcript content is currently available for this session."
                    : "Transcript loaded."
            }

            let details = TerminalMonitorSessionDetails(
                sessionID: session.id,
                loadedAt: Date(),
                sessionStatus: session.status,
                sessionChunkCount: session.chunkCount,
                sessionByteCount: session.byteCount,
                sessionEndedAt: session.endedAt,
                transcriptText: transcriptText,
                transcriptSourceDescription: transcriptSource,
                transcriptTruncated: transcriptTruncated,
                events: events,
                chunks: chunks,
                eventsTruncated: events.count >= settings.mongoMonitoring.clampedDetailEventLimit,
                chunksTruncated: session.chunkCount > chunks.count,
                loadSummary: loadNotes.isEmpty ? "Session details loaded." : loadNotes.joined(separator: " ")
            )

            await MainActor.run {
                self.sessionDetailsByID[session.id] = details
                self.detailLoadingSessionIDs.remove(session.id)
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
        let completionMarkerPath = transcriptPath + ".exit"
        let wrappedCommand = wrapCommand(item.command, transcriptPath: transcriptPath, completionMarkerPath: completionMarkerPath, settings: settings)

        let session = TerminalMonitorSession(
            id: sessionID,
            profileID: item.profileID,
            profileName: item.profileName,
            agentKind: profile.agentKind,
            accountIdentifier: Self.currentAccountIdentifier(for: profile),
            prompt: Self.initialPromptHint(for: profile, command: item.command),
            workingDirectory: profile.expandedWorkingDirectory,
            transcriptPath: transcriptPath,
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
            isYolo: profile.agentKind == .gemini && profile.geminiYolo
        )
        return PreparedMonitoringContext(session: session, wrappedCommand: wrappedCommand, completionMarkerPath: completionMarkerPath)
    }

    private func wrapCommand(_ originalCommand: String, transcriptPath: String, completionMarkerPath: String, settings: MongoMonitoringSettings) -> String {
        let builder = CommandBuilder()
        let scriptExecutable = builder.resolvedExecutable(settings.scriptExecutable) ?? settings.scriptExecutable
        let transcriptDirectory = URL(fileURLWithPath: transcriptPath).deletingLastPathComponent().path
        let keyFlag = settings.captureMode.usesScriptKeyLogging ? "-k " : ""
        return "mkdir -p \(shellQuote(transcriptDirectory)) && \(shellQuote(scriptExecutable)) -q \(keyFlag)-t 0 \(shellQuote(transcriptPath)) /bin/sh -lc \(shellQuote(originalCommand)); __launcher_exit_code=$?; /usr/bin/printf 'exit_code=%s\\nended_at=%s\\nreason=%s\\n' \"$__launcher_exit_code\" \"$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)\" \"command_finished\" > \(shellQuote(completionMarkerPath)); exit $__launcher_exit_code"
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
            var offset: UInt64 = 0
            var chunkIndex = 0
            var lastObservedWrite = Date()
            var pollingDelay = basePollingDelay
            var transcriptHandle: FileHandle?
            defer { try? transcriptHandle?.close() }

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

                    if let completion = Self.readCompletionMarker(at: context.completionMarkerPath) {
                        await markCompleted(
                            sessionID: sessionID,
                            completion: completion,
                            completionMarkerPath: context.completionMarkerPath,
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

                    if Self.isMissingFileError(error), Date() < transcriptGraceDeadline {
                        // The wrapped script process may not have created the transcript file yet.
                        pollingDelay = min(maxPollingDelay, pollingDelay * 2)
                    } else {
                        await markMonitoringFailure(
                            sessionID: sessionID,
                            message: error.localizedDescription,
                            completionMarkerPath: context.completionMarkerPath,
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
        session.prompt = Self.appendPrompt(session.prompt, from: String(decoding: data, as: UTF8.self))
        session.lastDatabaseMessage = settings.enableMongoWrites ? "Chunk \(session.chunkCount) queued for MongoDB." : "Chunk \(session.chunkCount) captured locally."
        session.lastError = nil
        session.statusReason = nil
        upsert(session)

        guard settings.enableMongoWrites else { return }

        do {
                try await writer.recordChunk(
                    sessionID: sessionID,
                    chunkIndex: chunkIndex,
                    data: data,
                    session: session,
                    prompt: session.prompt,
                    preview: preview,
                    totalChunks: session.chunkCount,
                    totalBytes: session.byteCount,
                    capturedAt: timestamp,
                status: .monitoring,
                settings: settings
            )
            if let index = sessionIndex(for: sessionID) {
                sessions[index].lastDatabaseMessage = "Synced chunk \(sessions[index].chunkCount) to MongoDB."
            }
        } catch {
            if let index = sessionIndex(for: sessionID) {
                sessions[index].lastDatabaseMessage = "MongoDB sync failed: \(error.localizedDescription)"
            }
            databaseStatus = "MongoDB write failed"
        }
    }

    private func markIdleIfNeeded(sessionID: UUID, at timestamp: Date, settings: MongoMonitoringSettings) async {
        guard let index = sessionIndex(for: sessionID) else { return }
        guard sessions[index].status != .idle else { return }

        sessions[index].status = .idle
        sessions[index].lastActivityAt = timestamp
        sessions[index].lastDatabaseMessage = settings.enableMongoWrites ? "Waiting for additional terminal output." : "No new terminal output detected yet."
        let idleSession = sessions[index]
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
            if let refreshedIndex = sessionIndex(for: sessionID) {
                sessions[refreshedIndex].lastDatabaseMessage = "MongoDB idle-state sync failed: \(error.localizedDescription)"
            }
            databaseStatus = "MongoDB write failed"
        }
    }

    private func markCompleted(
        sessionID: UUID,
        completion: SessionCompletionMarker,
        completionMarkerPath: String,
        settings: MongoMonitoringSettings
    ) async {
        guard let index = sessionIndex(for: sessionID) else {
            stopPolling(sessionID: sessionID)
            try? FileManager.default.removeItem(atPath: completionMarkerPath)
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

        let finalSession = sessions[index]
        upsert(finalSession)
        stopPolling(sessionID: sessionID)
        try? FileManager.default.removeItem(atPath: completionMarkerPath)

        if settings.enableMongoWrites {
            do {
                try await writer.recordCompletion(session: finalSession, settings: settings)
            } catch {
                if let refreshedIndex = sessionIndex(for: sessionID) {
                    sessions[refreshedIndex].lastDatabaseMessage = "MongoDB completion sync failed: \(error.localizedDescription)"
                }
                databaseStatus = "MongoDB write failed"
            }
        }

        if completedSuccessfully, !settings.keepLocalTranscriptFiles {
            try? FileManager.default.removeItem(atPath: finalSession.transcriptPath)
        }
    }

    private func markMonitoringFailure(
        sessionID: UUID,
        message: String,
        completionMarkerPath: String,
        settings: MongoMonitoringSettings
    ) async {
        guard let index = sessionIndex(for: sessionID) else {
            stopPolling(sessionID: sessionID)
            try? FileManager.default.removeItem(atPath: completionMarkerPath)
            return
        }

        sessions[index].status = .failed
        sessions[index].endedAt = Date()
        sessions[index].lastError = message
        sessions[index].statusReason = "monitoring_error"
        sessions[index].lastDatabaseMessage = settings.enableMongoWrites ? "Monitoring failed before session data could be fully synchronized." : "Monitoring failed locally."
        let failedSession = sessions[index]
        upsert(failedSession)
        stopPolling(sessionID: sessionID)
        try? FileManager.default.removeItem(atPath: completionMarkerPath)

        guard settings.enableMongoWrites else { return }
        do {
            try await writer.recordFailure(session: failedSession, message: message, status: .failed, settings: settings)
        } catch {
            if let refreshedIndex = sessionIndex(for: sessionID) {
                sessions[refreshedIndex].lastDatabaseMessage = "MongoDB failure sync failed: \(error.localizedDescription)"
            }
            databaseStatus = "MongoDB write failed"
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

        for id in staleHistoricalIDs {
            sessionDetailsByID.removeValue(forKey: id)
            detailLoadingSessionIDs.remove(id)
            nextDetailRefreshAt.removeValue(forKey: id)
        }

        sessions = liveSessions
        if sessions.count > Self.maxVisibleSessions {
            let discardedSessions = sessions.dropFirst(Self.maxVisibleSessions)
            for staleSession in discardedSessions {
                sessionDetailsByID.removeValue(forKey: staleSession.id)
                detailLoadingSessionIDs.remove(staleSession.id)
                nextDetailRefreshAt.removeValue(forKey: staleSession.id)
            }
            sessions = Array(sessions.prefix(Self.maxVisibleSessions))
        }
        rebuildSessionIndex()
    }

    private func upsert(_ session: TerminalMonitorSession) {
        if let index = sessionIndex(for: session.id) {
            sessions[index] = session
            let currentDate = Self.sessionActivityDate(session)
            var adjustedIndex = index

            while adjustedIndex > 0, currentDate > Self.sessionActivityDate(sessions[adjustedIndex - 1]) {
                swapSessions(at: adjustedIndex, and: adjustedIndex - 1)
                adjustedIndex -= 1
            }

            while adjustedIndex + 1 < sessions.count, currentDate < Self.sessionActivityDate(sessions[adjustedIndex + 1]) {
                swapSessions(at: adjustedIndex, and: adjustedIndex + 1)
                adjustedIndex += 1
            }
        } else {
            sessions.insert(session, at: 0)
            for index in sessions.indices {
                sessionIndexByID[sessions[index].id] = index
            }
            if sessions.count > Self.maxVisibleSessions {
                let removed = sessions.removeLast()
                sessionIndexByID.removeValue(forKey: removed.id)
                sessionDetailsByID.removeValue(forKey: removed.id)
                detailLoadingSessionIDs.remove(removed.id)
                nextDetailRefreshAt.removeValue(forKey: removed.id)
            }
            return
        }
        if sessions.count > Self.maxVisibleSessions {
            let removed = sessions.removeLast()
            sessionIndexByID.removeValue(forKey: removed.id)
            sessionDetailsByID.removeValue(forKey: removed.id)
            detailLoadingSessionIDs.remove(removed.id)
            nextDetailRefreshAt.removeValue(forKey: removed.id)
        }
    }

    private func swapSessions(at firstIndex: Int, and secondIndex: Int) {
        sessions.swapAt(firstIndex, secondIndex)
        sessionIndexByID[sessions[firstIndex].id] = firstIndex
        sessionIndexByID[sessions[secondIndex].id] = secondIndex
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

    private func protectedTranscriptPaths() -> Set<String> {
        let activeStatuses: Set<TerminalMonitorStatus> = [.prepared, .launching, .monitoring, .idle]
        let activeTranscriptPaths = sessions
            .filter { activeStatuses.contains($0.status) && !$0.isHistorical }
            .map { NSString(string: $0.transcriptPath).expandingTildeInPath }

        var protectedPaths = Set(activeTranscriptPaths)
        for path in activeTranscriptPaths {
            protectedPaths.insert(path + ".exit")
        }
        return protectedPaths
    }

    nonisolated private static func scanTranscriptDirectory(at path: String) -> MongoStorageSummary {
        let inventory = transcriptInventory(at: path)
        return MongoStorageSummary(
            transcriptFileCount: inventory.fileCount,
            transcriptFileBytes: inventory.totalBytes,
            oldestTranscriptFileAt: inventory.oldestFileAt,
            newestTranscriptFileAt: inventory.newestFileAt
        )
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
            guard isManagedTranscriptFile(fileURL),
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]),
                  values.isRegularFile == true
            else {
                continue
            }

            let modifiedAt = values.contentModificationDate ?? values.creationDate ?? Date.distantPast
            let size = Int64(values.fileSize ?? 0)
            inventory.fileCount += 1
            inventory.totalBytes += size

            if let oldest = inventory.oldestFileAt {
                inventory.oldestFileAt = min(oldest, modifiedAt)
            } else {
                inventory.oldestFileAt = modifiedAt
            }

            if let newest = inventory.newestFileAt {
                inventory.newestFileAt = max(newest, modifiedAt)
            } else {
                inventory.newestFileAt = modifiedAt
            }
        }

        return inventory
    }

    nonisolated private static func pruneTranscriptDirectory(at path: String, olderThanDays: Int, protectedPaths: Set<String>) -> LocalTranscriptPruneResult {
        let fm = FileManager.default
        let expanded = NSString(string: path).expandingTildeInPath
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(max(1, olderThanDays)) * 86_400)
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
            guard !protectedPaths.contains(filePath),
                  isManagedTranscriptFile(fileURL) || isManagedCompletionMarkerFile(fileURL),
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]),
                  values.isRegularFile == true
            else {
                continue
            }

            let modifiedAt = values.contentModificationDate ?? values.creationDate ?? Date.distantPast
            guard modifiedAt < cutoffDate else { continue }

            do {
                try fm.removeItem(at: fileURL)
                result.deletedFileCount += 1
                result.deletedBytes += Int64(values.fileSize ?? 0)
            } catch {
                continue
            }
        }

        return result
    }

    nonisolated private static func isManagedTranscriptFile(_ fileURL: URL) -> Bool {
        fileURL.lastPathComponent.hasSuffix(".typescript")
    }

    nonisolated private static func isManagedCompletionMarkerFile(_ fileURL: URL) -> Bool {
        fileURL.lastPathComponent.hasSuffix(".typescript.exit")
    }

    nonisolated private static func describe(pruneSummary: MongoPruneSummary) -> String {
        let localBytes = ByteCountFormatter.string(fromByteCount: pruneSummary.deletedTranscriptBytes, countStyle: .file)
        let chunkBytes = ByteCountFormatter.string(fromByteCount: pruneSummary.deletedChunkBytes, countStyle: .file)
        return [
            "Pruned data older than \(pruneSummary.cutoffDate.formatted(date: .abbreviated, time: .omitted)).",
            "Deleted \(pruneSummary.deletedSessions) session(s), \(pruneSummary.deletedChunks) chunk(s), and \(pruneSummary.deletedEvents) event row(s) from MongoDB (\(chunkBytes) of logical transcript data).",
            "Deleted \(pruneSummary.deletedTranscriptFiles) local transcript file(s) (\(localBytes))."
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

    nonisolated private static let maxPromptCharsStored = 12_000
    nonisolated private static let maxPromptChunkChars = 1_600

    nonisolated private static func appendPrompt(_ existing: String, from rawChunk: String) -> String {
        let chunk = normalizePromptChunk(rawChunk)
        guard !chunk.isEmpty else { return existing }
        if existing.isEmpty {
            return chunk
        }
        let merged = existing + "\n" + chunk
        if merged.count <= maxPromptCharsStored {
            return merged
        }
        let startIndex = merged.index(merged.endIndex, offsetBy: merged.count - maxPromptCharsStored)
        return String(merged[startIndex...])
    }

    nonisolated private static func normalizePromptChunk(_ rawChunk: String) -> String {
        if rawChunk.isEmpty {
            return ""
        }

        let ansiPattern = #"\x1B\[[0-9;]*[A-Za-z]"#
        var sanitized = rawChunk.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
        sanitized = sanitized.replacingOccurrences(of: "\u{0000}", with: "")
        sanitized = sanitized.replacingOccurrences(of: "\r", with: "\n")
        sanitized = sanitized.unicodeScalars
            .filter { $0.value == 0x09 || $0.value == 0x0A || $0.value >= 0x20 }
            .reduce(into: String()) { result, scalar in result.unicodeScalars.append(scalar) }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.count <= maxPromptChunkChars {
            return sanitized
        }
        let endIndex = sanitized.index(sanitized.startIndex, offsetBy: Self.maxPromptChunkChars)
        return String(sanitized[..<endIndex]) + "…"
    }

    nonisolated private static func initialPromptHint(for profile: LaunchProfile, command: String) -> String {
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

    private static func sessionActivityDate(_ session: TerminalMonitorSession) -> Date {
        session.lastActivityAt ?? session.endedAt ?? session.startedAt
    }
}
