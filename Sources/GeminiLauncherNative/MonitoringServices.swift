import AppKit
import Combine
import Foundation

private struct PreparedMonitoringContext: Sendable {
    var session: TerminalMonitorSession
    var wrappedCommand: String
    var completionMarkerPath: String
}

private struct PSQLLaunchConfiguration: Sendable {
    var executablePath: String
    var arguments: [String]
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

    func makeSession() -> TerminalMonitorSession {
        TerminalMonitorSession(
            id: UUID(uuidString: session_id) ?? UUID(),
            profileID: profile_id.flatMap(UUID.init(uuidString:)),
            profileName: profile_name,
            agentKind: AgentKind(rawValue: agent_kind) ?? .gemini,
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
            lastDatabaseMessage: last_database_message ?? "Loaded from PostgreSQL.",
            lastError: last_error,
            statusReason: status_reason,
            exitCode: exit_code,
            isHistorical: true
        )
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

    func makeSummary() -> PostgresStorageSummary {
        PostgresStorageSummary(
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
    var oldestFileAt: Date? = nil
    var newestFileAt: Date? = nil
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
    static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        fractionalFormatter.string(from: date)
    }

    static func parse(_ value: String?) -> Date? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return fractionalFormatter.date(from: trimmed) ?? plainFormatter.date(from: trimmed)
    }
}

struct MonitoringDiagnosticsService {
    private let builder = CommandBuilder()

    func inspect(settings: PostgresMonitoringSettings) -> [ToolStatus] {
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

        if settings.enablePostgresWrites {
            let psqlResolved = builder.resolvedExecutable(settings.psqlExecutable)
            statuses.append(
                ToolStatus(
                    name: "psql",
                    requested: settings.psqlExecutable,
                    resolved: psqlResolved,
                    detail: psqlResolved != nil ? "PostgreSQL CLI client resolved." : "psql executable was not found",
                    isError: psqlResolved == nil
                )
            )
            let hasConnection = !settings.trimmedConnectionURL.isEmpty
            statuses.append(
                ToolStatus(
                    name: "Postgres URL",
                    requested: settings.redactedConnectionDescription,
                    resolved: hasConnection ? settings.redactedConnectionDescription : nil,
                    detail: hasConnection ? "Connection string configured." : "Connection URL is empty.",
                    isError: !hasConnection
                )
            )
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

actor PostgresMonitoringWriter {
    private let commandBuilder = CommandBuilder()
    private var initializedFingerprint: String?

    func testConnection(settings: PostgresMonitoringSettings) throws -> String {
        guard settings.enablePostgresWrites else {
            return "Postgres writes are disabled."
        }
        let output = try runPSQL("SELECT current_database() || ' as ' || current_user;", settings: settings)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func ensureSchema(settings: PostgresMonitoringSettings) throws {
        guard settings.enablePostgresWrites else { return }
        let fingerprint = settings.trimmedConnectionURL + "|" + settings.trimmedSchemaName
        guard initializedFingerprint != fingerprint else { return }

        let schema = try sqlIdentifier(settings.trimmedSchemaName)
        let sql = """
        CREATE SCHEMA IF NOT EXISTS \(schema);
        CREATE TABLE IF NOT EXISTS \(schema).terminal_sessions (
            session_id uuid PRIMARY KEY,
            profile_id uuid NULL,
            profile_name text NOT NULL,
            agent_kind text NOT NULL,
            working_directory text NOT NULL,
            transcript_path text NOT NULL,
            launch_command text NOT NULL,
            capture_mode text NOT NULL,
            status text NOT NULL,
            started_at timestamptz NOT NULL,
            last_activity_at timestamptz NULL,
            ended_at timestamptz NULL,
            chunk_count integer NOT NULL DEFAULT 0,
            byte_count bigint NOT NULL DEFAULT 0,
            last_error text NULL,
            last_preview text NOT NULL DEFAULT '',
            last_database_message text NOT NULL DEFAULT '',
            status_reason text NULL,
            exit_code integer NULL
        );
        ALTER TABLE \(schema).terminal_sessions ADD COLUMN IF NOT EXISTS last_preview text NOT NULL DEFAULT '';
        ALTER TABLE \(schema).terminal_sessions ADD COLUMN IF NOT EXISTS last_database_message text NOT NULL DEFAULT '';
        ALTER TABLE \(schema).terminal_sessions ADD COLUMN IF NOT EXISTS status_reason text NULL;
        ALTER TABLE \(schema).terminal_sessions ADD COLUMN IF NOT EXISTS exit_code integer NULL;

        CREATE TABLE IF NOT EXISTS \(schema).terminal_chunks (
            id bigserial PRIMARY KEY,
            session_id uuid NOT NULL REFERENCES \(schema).terminal_sessions(session_id) ON DELETE CASCADE,
            chunk_index integer NOT NULL,
            source text NOT NULL,
            captured_at timestamptz NOT NULL,
            byte_count integer NOT NULL,
            preview_text text NOT NULL,
            raw_base64 text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS \(schema).terminal_session_events (
            id bigserial PRIMARY KEY,
            session_id uuid NOT NULL REFERENCES \(schema).terminal_sessions(session_id) ON DELETE CASCADE,
            event_type text NOT NULL,
            status text NOT NULL,
            event_at timestamptz NOT NULL DEFAULT now(),
            message text NULL,
            metadata_json text NULL
        );

        CREATE UNIQUE INDEX IF NOT EXISTS \(settings.trimmedSchemaName)_terminal_chunks_session_chunk_idx
            ON \(schema).terminal_chunks(session_id, chunk_index);
        CREATE INDEX IF NOT EXISTS \(settings.trimmedSchemaName)_terminal_sessions_activity_idx
            ON \(schema).terminal_sessions((COALESCE(last_activity_at, ended_at, started_at)) DESC);
        CREATE INDEX IF NOT EXISTS \(settings.trimmedSchemaName)_terminal_session_events_session_idx
            ON \(schema).terminal_session_events(session_id, event_at DESC);
        """
        _ = try runPSQL(sql, settings: settings)
        initializedFingerprint = fingerprint
    }

    func recordSessionStart(_ session: TerminalMonitorSession, settings: PostgresMonitoringSettings) throws {
        guard settings.enablePostgresWrites else { return }
        try ensureSchema(settings: settings)

        let schema = try sqlIdentifier(settings.trimmedSchemaName)
        let metadataJSON = nullableJSONObjectLiteral([
            "capture_mode": session.captureMode.rawValue,
            "working_directory": session.workingDirectory,
            "transcript_path": session.transcriptPath
        ])
        let sql = """
        INSERT INTO \(schema).terminal_sessions (
            session_id, profile_id, profile_name, agent_kind, working_directory,
            transcript_path, launch_command, capture_mode, status, started_at,
            last_activity_at, ended_at, chunk_count, byte_count, last_error,
            last_preview, last_database_message, status_reason, exit_code
        ) VALUES (
            \(uuidLiteral(session.id)),
            \(nullableUUIDLiteral(session.profileID)),
            \(sqlLiteral(session.profileName)),
            \(sqlLiteral(session.agentKind.rawValue)),
            \(sqlLiteral(session.workingDirectory)),
            \(sqlLiteral(session.transcriptPath)),
            \(sqlLiteral(session.launchCommand)),
            \(sqlLiteral(session.captureMode.rawValue)),
            \(sqlLiteral(session.status.rawValue)),
            \(timestampLiteral(session.startedAt)),
            NULL,
            NULL,
            0,
            0,
            NULL,
            \(sqlLiteral(session.lastPreview)),
            \(sqlLiteral(session.lastDatabaseMessage)),
            \(nullableSQLLiteral(session.statusReason)),
            \(nullableIntLiteral(session.exitCode))
        )
        ON CONFLICT (session_id) DO UPDATE SET
            profile_id = EXCLUDED.profile_id,
            profile_name = EXCLUDED.profile_name,
            agent_kind = EXCLUDED.agent_kind,
            working_directory = EXCLUDED.working_directory,
            transcript_path = EXCLUDED.transcript_path,
            launch_command = EXCLUDED.launch_command,
            capture_mode = EXCLUDED.capture_mode,
            status = EXCLUDED.status,
            started_at = EXCLUDED.started_at,
            last_error = EXCLUDED.last_error,
            last_preview = EXCLUDED.last_preview,
            last_database_message = EXCLUDED.last_database_message,
            status_reason = EXCLUDED.status_reason,
            exit_code = EXCLUDED.exit_code;

        INSERT INTO \(schema).terminal_session_events (
            session_id, event_type, status, event_at, message, metadata_json
        ) VALUES (
            \(uuidLiteral(session.id)),
            'session_started',
            \(sqlLiteral(session.status.rawValue)),
            \(timestampLiteral(session.startedAt)),
            \(sqlLiteral("Session registered for monitoring.")),
            \(metadataJSON)
        );
        """
        _ = try runPSQL(sql, settings: settings)
    }

    func recordChunk(
        sessionID: UUID,
        chunkIndex: Int,
        data: Data,
        preview: String,
        totalChunks: Int,
        totalBytes: Int,
        capturedAt: Date,
        status: TerminalMonitorStatus,
        settings: PostgresMonitoringSettings
    ) throws {
        guard settings.enablePostgresWrites else { return }
        try ensureSchema(settings: settings)

        let schema = try sqlIdentifier(settings.trimmedSchemaName)
        let rawBase64 = data.base64EncodedString()
        let databaseMessage = "Synced chunk \(totalChunks) to PostgreSQL."
        let sql = """
        INSERT INTO \(schema).terminal_chunks (
            session_id, chunk_index, source, captured_at, byte_count, preview_text, raw_base64
        ) VALUES (
            \(uuidLiteral(sessionID)),
            \(chunkIndex),
            'terminal_transcript',
            \(timestampLiteral(capturedAt)),
            \(data.count),
            \(sqlLiteral(preview)),
            \(sqlLiteral(rawBase64))
        )
        ON CONFLICT (session_id, chunk_index) DO NOTHING;

        UPDATE \(schema).terminal_sessions
        SET last_activity_at = \(timestampLiteral(capturedAt)),
            chunk_count = \(totalChunks),
            byte_count = \(totalBytes),
            status = \(sqlLiteral(status.rawValue)),
            last_preview = \(sqlLiteral(preview)),
            last_database_message = \(sqlLiteral(databaseMessage)),
            status_reason = NULL,
            last_error = NULL
        WHERE session_id = \(uuidLiteral(sessionID));
        """
        _ = try runPSQL(sql, settings: settings)
    }

    func recordStatus(
        sessionID: UUID,
        status: TerminalMonitorStatus,
        eventType: String,
        message: String?,
        eventAt: Date,
        endedAt: Date? = nil,
        statusReason: String? = nil,
        exitCode: Int? = nil,
        settings: PostgresMonitoringSettings
    ) throws {
        guard settings.enablePostgresWrites else { return }
        try ensureSchema(settings: settings)

        let schema = try sqlIdentifier(settings.trimmedSchemaName)
        let statusMessage = message ?? defaultMessage(for: status)
        let endedAtSQL = endedAt.map(timestampLiteral) ?? "ended_at"
        let metadataJSON = nullableJSONObjectLiteral([
            "status_reason": statusReason,
            "exit_code": exitCode,
            "ended_at": endedAt.map(MonitorTimestamp.string),
            "message": statusMessage
        ])
        let sql = """
        UPDATE \(schema).terminal_sessions
        SET status = \(sqlLiteral(status.rawValue)),
            last_activity_at = \(timestampLiteral(eventAt)),
            ended_at = \(endedAtSQL),
            last_database_message = \(sqlLiteral(statusMessage)),
            status_reason = \(nullableSQLLiteral(statusReason)),
            last_error = \(status == .failed ? nullableSQLLiteral(statusMessage) : "NULL"),
            exit_code = \(nullableIntLiteral(exitCode))
        WHERE session_id = \(uuidLiteral(sessionID));

        INSERT INTO \(schema).terminal_session_events (
            session_id, event_type, status, event_at, message, metadata_json
        ) VALUES (
            \(uuidLiteral(sessionID)),
            \(sqlLiteral(eventType)),
            \(sqlLiteral(status.rawValue)),
            \(timestampLiteral(eventAt)),
            \(nullableSQLLiteral(statusMessage)),
            \(metadataJSON)
        );
        """
        _ = try runPSQL(sql, settings: settings)
    }

    func recordFailure(sessionID: UUID, message: String, status: TerminalMonitorStatus, settings: PostgresMonitoringSettings) throws {
        try recordStatus(
            sessionID: sessionID,
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

    func recordCompletion(session: TerminalMonitorSession, settings: PostgresMonitoringSettings) throws {
        try recordStatus(
            sessionID: session.id,
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

    func fetchRecentSessions(settings: PostgresMonitoringSettings, limit: Int, lookbackHours: Int) throws -> [TerminalMonitorSession] {
        guard settings.enablePostgresWrites else { return [] }
        try ensureSchema(settings: settings)

        let schema = try sqlIdentifier(settings.trimmedSchemaName)
        let safeLimit = max(1, min(200, limit))
        let safeLookbackHours = max(1, min(24 * 90, lookbackHours))
        let sql = """
        SELECT json_build_object(
            'session_id', session_id::text,
            'profile_id', CASE WHEN profile_id IS NULL THEN NULL ELSE profile_id::text END,
            'profile_name', profile_name,
            'agent_kind', agent_kind,
            'working_directory', working_directory,
            'transcript_path', transcript_path,
            'launch_command', launch_command,
            'capture_mode', capture_mode,
            'status', status,
            'started_at_epoch', EXTRACT(EPOCH FROM started_at),
            'last_activity_at_epoch', CASE WHEN last_activity_at IS NULL THEN NULL ELSE EXTRACT(EPOCH FROM last_activity_at) END,
            'ended_at_epoch', CASE WHEN ended_at IS NULL THEN NULL ELSE EXTRACT(EPOCH FROM ended_at) END,
            'chunk_count', chunk_count,
            'byte_count', byte_count,
            'last_error', last_error,
            'last_preview', last_preview,
            'last_database_message', last_database_message,
            'status_reason', status_reason,
            'exit_code', exit_code
        )::text
        FROM \(schema).terminal_sessions
        WHERE started_at >= now() - interval '\(safeLookbackHours) hours'
        ORDER BY COALESCE(last_activity_at, ended_at, started_at) DESC
        LIMIT \(safeLimit);
        """

        let output = try runPSQL(sql, settings: settings)
        let decoder = JSONDecoder()
        return try output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { line in
                let row = try decoder.decode(DatabaseSessionRow.self, from: Data(line.utf8))
                return row.makeSession()
            }
    }

    func fetchSessionEvents(sessionID: UUID, settings: PostgresMonitoringSettings, limit: Int) throws -> [TerminalSessionEvent] {
        guard settings.enablePostgresWrites else { return [] }
        try ensureSchema(settings: settings)

        let schema = try sqlIdentifier(settings.trimmedSchemaName)
        let safeLimit = max(1, min(500, limit))
        let sql = """
        SELECT json_build_object(
            'id', id,
            'session_id', session_id::text,
            'event_type', event_type,
            'status', status,
            'event_at_epoch', EXTRACT(EPOCH FROM event_at),
            'message', message,
            'metadata_json', metadata_json
        )::text
        FROM \(schema).terminal_session_events
        WHERE session_id = \(uuidLiteral(sessionID))
        ORDER BY event_at DESC, id DESC
        LIMIT \(safeLimit);
        """

        let output = try runPSQL(sql, settings: settings)
        let decoder = JSONDecoder()
        return try output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { line in
                let row = try decoder.decode(DatabaseSessionEventRow.self, from: Data(line.utf8))
                return row.makeEvent()
            }
    }

    func fetchSessionChunks(sessionID: UUID, settings: PostgresMonitoringSettings, limit: Int) throws -> [TerminalTranscriptChunk] {
        guard settings.enablePostgresWrites else { return [] }
        try ensureSchema(settings: settings)

        let schema = try sqlIdentifier(settings.trimmedSchemaName)
        let safeLimit = max(1, min(500, limit))
        let sql = """
        SELECT json_build_object(
            'id', id,
            'session_id', session_id::text,
            'chunk_index', chunk_index,
            'source', source,
            'captured_at_epoch', EXTRACT(EPOCH FROM captured_at),
            'byte_count', byte_count,
            'preview_text', preview_text,
            'raw_base64', raw_base64
        )::text
        FROM (
            SELECT *
            FROM \(schema).terminal_chunks
            WHERE session_id = \(uuidLiteral(sessionID))
            ORDER BY chunk_index DESC
            LIMIT \(safeLimit)
        ) recent_chunks
        ORDER BY chunk_index ASC;
        """

        let output = try runPSQL(sql, settings: settings)
        let decoder = JSONDecoder()
        return try output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { line in
                let row = try decoder.decode(DatabaseSessionChunkRow.self, from: Data(line.utf8))
                return row.makeChunk()
            }
    }

    func fetchStorageSummary(settings: PostgresMonitoringSettings) throws -> PostgresStorageSummary {
        guard settings.enablePostgresWrites else { return PostgresStorageSummary() }
        try ensureSchema(settings: settings)

        let schema = try sqlIdentifier(settings.trimmedSchemaName)
        let sessionRelation = sqlLiteral("\(settings.trimmedSchemaName).terminal_sessions") + "::regclass"
        let chunkRelation = sqlLiteral("\(settings.trimmedSchemaName).terminal_chunks") + "::regclass"
        let eventRelation = sqlLiteral("\(settings.trimmedSchemaName).terminal_session_events") + "::regclass"
        let sql = """
        SELECT json_build_object(
            'session_count', (SELECT COUNT(*)::integer FROM \(schema).terminal_sessions),
            'active_session_count', (
                SELECT COUNT(*)::integer
                FROM \(schema).terminal_sessions
                WHERE status IN ('prepared', 'launching', 'monitoring', 'idle')
            ),
            'completed_session_count', (
                SELECT COUNT(*)::integer
                FROM \(schema).terminal_sessions
                WHERE status = 'completed'
            ),
            'failed_session_count', (
                SELECT COUNT(*)::integer
                FROM \(schema).terminal_sessions
                WHERE status IN ('failed', 'stopped')
            ),
            'chunk_count', (SELECT COUNT(*)::integer FROM \(schema).terminal_chunks),
            'event_count', (SELECT COUNT(*)::integer FROM \(schema).terminal_session_events),
            'logical_transcript_bytes', (
                SELECT COALESCE(SUM(byte_count), 0)::bigint
                FROM \(schema).terminal_chunks
            ),
            'session_table_bytes', pg_total_relation_size(\(sessionRelation)),
            'chunk_table_bytes', pg_total_relation_size(\(chunkRelation)),
            'event_table_bytes', pg_total_relation_size(\(eventRelation)),
            'oldest_session_at_epoch', (
                SELECT CASE
                    WHEN MIN(started_at) IS NULL THEN NULL
                    ELSE EXTRACT(EPOCH FROM MIN(started_at))
                END
                FROM \(schema).terminal_sessions
            ),
            'newest_session_at_epoch', (
                SELECT CASE
                    WHEN MAX(COALESCE(last_activity_at, ended_at, started_at)) IS NULL THEN NULL
                    ELSE EXTRACT(EPOCH FROM MAX(COALESCE(last_activity_at, ended_at, started_at)))
                END
                FROM \(schema).terminal_sessions
            )
        )::text;
        """

        let output = try runPSQL(sql, settings: settings)
        let decoder = JSONDecoder()
        guard let line = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return PostgresStorageSummary()
        }
        let row = try decoder.decode(DatabaseStorageSummaryRow.self, from: Data(line.utf8))
        return row.makeSummary()
    }

    func pruneCompletedHistory(settings: PostgresMonitoringSettings, retentionDays: Int) throws -> PostgresPruneSummary {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(max(1, retentionDays)) * 86_400)
        guard settings.enablePostgresWrites else {
            return PostgresPruneSummary(cutoffDate: cutoffDate)
        }
        try ensureSchema(settings: settings)

        let schema = try sqlIdentifier(settings.trimmedSchemaName)
        let safeRetentionDays = max(1, min(3650, retentionDays))
        let sql = """
        WITH doomed AS (
            SELECT session_id
            FROM \(schema).terminal_sessions
            WHERE status IN ('completed', 'failed', 'stopped')
              AND COALESCE(ended_at, last_activity_at, started_at) < now() - interval '\(safeRetentionDays) days'
        ),
        doomed_chunks AS (
            SELECT COUNT(*)::integer AS deleted_chunks,
                   COALESCE(SUM(byte_count), 0)::bigint AS deleted_chunk_bytes
            FROM \(schema).terminal_chunks
            WHERE session_id IN (SELECT session_id FROM doomed)
        ),
        doomed_events AS (
            SELECT COUNT(*)::integer AS deleted_events
            FROM \(schema).terminal_session_events
            WHERE session_id IN (SELECT session_id FROM doomed)
        ),
        deleted_sessions AS (
            DELETE FROM \(schema).terminal_sessions
            WHERE session_id IN (SELECT session_id FROM doomed)
            RETURNING session_id
        )
        SELECT json_build_object(
            'deleted_sessions', (SELECT COUNT(*)::integer FROM deleted_sessions),
            'deleted_chunks', (SELECT deleted_chunks FROM doomed_chunks),
            'deleted_events', (SELECT deleted_events FROM doomed_events),
            'deleted_chunk_bytes', (SELECT deleted_chunk_bytes FROM doomed_chunks)
        )::text;
        """

        let output = try runPSQL(sql, settings: settings)
        let decoder = JSONDecoder()
        guard let line = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return PostgresPruneSummary(cutoffDate: cutoffDate)
        }

        let row = try decoder.decode(DatabasePruneSummaryRow.self, from: Data(line.utf8))
        return PostgresPruneSummary(
            cutoffDate: cutoffDate,
            deletedSessions: row.deleted_sessions,
            deletedChunks: row.deleted_chunks,
            deletedEvents: row.deleted_events,
            deletedChunkBytes: row.deleted_chunk_bytes
        )
    }

    private func runPSQL(_ sql: String, settings: PostgresMonitoringSettings) throws -> String {
        let launch = try makePSQLLaunchConfiguration(settings: settings)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executablePath)
        process.arguments = launch.arguments + ["-X", "-v", "ON_ERROR_STOP=1", "-q", "-A", "-t", "-c", sql]
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
            throw LauncherError.validation("psql exited with status \(process.terminationStatus): \(errorText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }

    private func makePSQLLaunchConfiguration(settings: PostgresMonitoringSettings) throws -> PSQLLaunchConfiguration {
        let executable = commandBuilder.resolvedExecutable(settings.psqlExecutable) ?? settings.psqlExecutable
        guard !settings.trimmedConnectionURL.isEmpty else {
            throw LauncherError.validation("Postgres monitoring connection URL is empty.")
        }
        guard let components = URLComponents(string: settings.trimmedConnectionURL),
              let scheme = components.scheme?.lowercased(),
              scheme.hasPrefix("postgres")
        else {
            throw LauncherError.validation("Postgres monitoring URL must begin with postgres:// or postgresql://")
        }

        var arguments: [String] = []
        var environment = ProcessInfo.processInfo.environment

        if let host = components.host, !host.isEmpty {
            arguments += ["-h", host]
        }
        if let port = components.port {
            arguments += ["-p", String(port)]
        }
        if let user = components.user?.removingPercentEncoding, !user.isEmpty {
            arguments += ["-U", user]
        } else if let user = components.user, !user.isEmpty {
            arguments += ["-U", user]
        }

        let dbName = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !dbName.isEmpty {
            arguments += ["-d", dbName.removingPercentEncoding ?? dbName]
        }

        if let password = components.password?.removingPercentEncoding ?? components.password {
            environment["PGPASSWORD"] = password
        }

        let queryEnvMap = [
            "application_name": "PGAPPNAME",
            "connect_timeout": "PGCONNECT_TIMEOUT",
            "passfile": "PGPASSFILE",
            "service": "PGSERVICE",
            "sslcert": "PGSSLCERT",
            "sslkey": "PGSSLKEY",
            "sslmode": "PGSSLMODE",
            "sslrootcert": "PGSSLROOTCERT",
            "target_session_attrs": "PGTARGETSESSIONATTRS"
        ]
        for item in components.queryItems ?? [] {
            guard let envKey = queryEnvMap[item.name.lowercased()] else { continue }
            let value = item.value?.removingPercentEncoding ?? item.value
            guard let value, !value.isEmpty else { continue }
            environment[envKey] = value
        }
        environment["PGAPPNAME"] = environment["PGAPPNAME"] ?? AppPaths.folderName

        return PSQLLaunchConfiguration(executablePath: executable, arguments: arguments, environment: environment)
    }

    private func sqlIdentifier(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            throw LauncherError.validation("Schema name may only contain letters, numbers, and underscores.")
        }
        return "\"\(trimmed)\""
    }

    private func sqlLiteral(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\u{0000}", with: "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "''")
        return "'\(cleaned)'"
    }

    private func nullableSQLLiteral(_ raw: String?) -> String {
        guard let raw else { return "NULL" }
        return sqlLiteral(raw)
    }

    private func nullableJSONObjectLiteral(_ values: [String: Any?]) -> String {
        let cleaned = values.reduce(into: [String: Any]()) { partialResult, entry in
            guard let value = entry.value else { return }
            partialResult[entry.key] = value
        }
        guard !cleaned.isEmpty,
              JSONSerialization.isValidJSONObject(cleaned),
              let data = try? JSONSerialization.data(withJSONObject: cleaned, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "NULL"
        }
        return sqlLiteral(string)
    }

    private func uuidLiteral(_ uuid: UUID) -> String {
        "'\(uuid.uuidString)'::uuid"
    }

    private func nullableUUIDLiteral(_ uuid: UUID?) -> String {
        guard let uuid else { return "NULL" }
        return uuidLiteral(uuid)
    }

    private func nullableIntLiteral(_ value: Int?) -> String {
        guard let value else { return "NULL" }
        return String(value)
    }

    private func timestampLiteral(_ date: Date) -> String {
        sqlLiteral(MonitorTimestamp.string(from: date)) + "::timestamptz"
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
    @Published private(set) var storageSummary: PostgresStorageSummary? = nil
    @Published private(set) var lastPruneResult: PostgresPruneSummary? = nil
    @Published private(set) var isLoadingStorageSummary: Bool = false
    @Published private(set) var isPruningStoredHistory: Bool = false

    private var preparedContexts: [UUID: PreparedMonitoringContext] = [:]
    private var pollTasks: [UUID: Task<Void, Never>] = [:]
    private let writer = PostgresMonitoringWriter()
    private let diagnostics = MonitoringDiagnosticsService()

    func prepare(plan: PlannedLaunch, profiles: [LaunchProfile], settings: AppSettings, logger: LaunchLogger) throws -> PlannedLaunch {
        guard settings.postgresMonitoring.enabled else {
            return plan
        }

        let transcriptDirectory = settings.postgresMonitoring.expandedTranscriptDirectory
        try FileManager.default.createDirectory(atPath: transcriptDirectory, withIntermediateDirectories: true, attributes: nil)

        var updatedPlan = plan
        let profileLookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        for index in updatedPlan.items.indices {
            let item = updatedPlan.items[index]
            guard let profile = profileLookup[item.profileID] else { continue }

            let context = try buildPreparedContext(item: item, profile: profile, settings: settings.postgresMonitoring)
            preparedContexts[context.session.id] = context
            updatedPlan.items[index].command = context.wrappedCommand
            updatedPlan.items[index].monitorSessionID = context.session.id
        }

        databaseStatus = settings.postgresMonitoring.enablePostgresWrites ? "Prepared \(updatedPlan.items.count) monitored launch(es)." : "Local transcript monitoring prepared."
        logger.log(.info, "Prepared \(updatedPlan.items.count) monitored iTerm2 launch(es).", category: .monitoring)
        return updatedPlan
    }

    func activatePreparedSessions(for plan: PlannedLaunch, settings: AppSettings, logger: LaunchLogger) {
        guard settings.postgresMonitoring.enabled else { return }

        for item in plan.items {
            guard let sessionID = item.monitorSessionID,
                  let context = preparedContexts.removeValue(forKey: sessionID)
            else { continue }

            var session = context.session
            session.status = .launching
            session.lastDatabaseMessage = settings.postgresMonitoring.enablePostgresWrites ? "Awaiting first PostgreSQL sync." : "Local transcript capture started."
            upsert(session)

            if settings.postgresMonitoring.enablePostgresWrites {
                Task {
                    do {
                        try await writer.ensureSchema(settings: settings.postgresMonitoring)
                        try await writer.recordSessionStart(session, settings: settings.postgresMonitoring)
                        await MainActor.run {
                            self.databaseStatus = "Postgres session logging active."
                            self.lastConnectionCheck = Date().formatted(date: .abbreviated, time: .standard)
                        }
                    } catch {
                        await MainActor.run {
                            if let index = self.sessions.firstIndex(where: { $0.id == session.id }) {
                                self.sessions[index].lastDatabaseMessage = "Postgres unavailable: \(error.localizedDescription)"
                            }
                            self.databaseStatus = "Postgres error"
                            logger.log(.warning, "Postgres monitor setup failed; local transcript capture is still running: \(error.localizedDescription)", category: .monitoring)
                        }
                    }
                }
            }

            startPolling(context: context, settings: settings.postgresMonitoring)
        }
    }

    func cancelPreparedSessions(for plan: PlannedLaunch, reason: String, settings: AppSettings, logger: LaunchLogger) {
        for item in plan.items {
            guard let sessionID = item.monitorSessionID else { continue }
            let context = preparedContexts.removeValue(forKey: sessionID)
            stopPolling(sessionID: sessionID)

            var cancelled = sessions.first(where: { $0.id == sessionID }) ?? TerminalMonitorSession(
                id: sessionID,
                profileID: item.profileID,
                profileName: item.profileName,
                agentKind: .gemini,
                workingDirectory: "",
                transcriptPath: context?.session.transcriptPath ?? "",
                launchCommand: item.command,
                captureMode: settings.postgresMonitoring.captureMode
            )
            cancelled.status = .failed
            cancelled.endedAt = Date()
            cancelled.lastError = reason
            cancelled.statusReason = "launch_cancelled"
            cancelled.lastDatabaseMessage = settings.postgresMonitoring.enablePostgresWrites ? "Launch failed before monitoring could start." : "Launch failed before monitoring could start."
            upsert(cancelled)

            if settings.postgresMonitoring.enablePostgresWrites {
                Task {
                    try? await writer.recordStatus(
                        sessionID: sessionID,
                        status: .failed,
                        eventType: "session_launch_cancelled",
                        message: reason,
                        eventAt: Date(),
                        endedAt: Date(),
                        statusReason: "launch_cancelled",
                        exitCode: nil,
                        settings: settings.postgresMonitoring
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
        }
    }

    func revealTranscriptDirectory(settings: AppSettings) {
        let path = settings.postgresMonitoring.expandedTranscriptDirectory
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func testConnection(settings: AppSettings, logger: LaunchLogger) {
        guard settings.postgresMonitoring.enabled else {
            databaseStatus = "Monitoring disabled"
            logger.log(.warning, "Enable terminal monitoring before testing PostgreSQL connectivity.", category: .monitoring)
            return
        }
        guard settings.postgresMonitoring.enablePostgresWrites else {
            databaseStatus = "Local transcript monitoring only"
            logger.log(.info, "Postgres writes are disabled; local transcript monitoring is still available.", category: .monitoring)
            return
        }

        Task {
            do {
                let result = try await writer.testConnection(settings: settings.postgresMonitoring)
                await MainActor.run {
                    self.lastConnectionCheck = Date().formatted(date: .abbreviated, time: .standard)
                    self.databaseStatus = "Connected • \(result)"
                    logger.log(.success, "Postgres monitoring connection OK: \(result)", category: .monitoring)
                }
            } catch {
                await MainActor.run {
                    self.databaseStatus = "Connection failed"
                    logger.log(.error, "Postgres monitoring connection failed: \(error.localizedDescription)", category: .monitoring)
                }
            }
        }
    }

    func refreshRecentSessions(settings: AppSettings, logger: LaunchLogger) {
        guard settings.postgresMonitoring.enabled else {
            databaseStatus = "Monitoring disabled"
            storageSummary = nil
            storageSummaryStatus = ""
            return
        }
        guard settings.postgresMonitoring.enablePostgresWrites else {
            databaseStatus = "Local transcript monitoring only"
            return
        }

        Task {
            do {
                let databaseSessions = try await writer.fetchRecentSessions(
                    settings: settings.postgresMonitoring,
                    limit: settings.postgresMonitoring.clampedRecentHistoryLimit,
                    lookbackHours: settings.postgresMonitoring.clampedRecentHistoryLookbackDays * 24
                )
                await MainActor.run {
                    self.synchronizeHistoricalSessions(databaseSessions)
                    self.lastConnectionCheck = Date().formatted(date: .abbreviated, time: .standard)
                    self.databaseStatus = "Loaded \(databaseSessions.count) recent session(s) from PostgreSQL."
                    logger.log(.success, "Loaded \(databaseSessions.count) recent monitored session(s) from PostgreSQL.", category: .monitoring)
                }
            } catch {
                await MainActor.run {
                    self.databaseStatus = "Recent session refresh failed"
                    logger.log(.error, "Failed to load recent PostgreSQL-backed sessions: \(error.localizedDescription)", category: .monitoring)
                }
            }
        }
    }

    func refreshStorageSummary(settings: AppSettings, logger: LaunchLogger) {
        guard settings.postgresMonitoring.enabled else {
            storageSummary = nil
            storageSummaryStatus = ""
            return
        }

        isLoadingStorageSummary = true
        let monitoringSettings = settings.postgresMonitoring

        Task { [weak self] in
            guard let self else { return }

            var summary = Self.scanTranscriptDirectory(at: monitoringSettings.expandedTranscriptDirectory)
            var notes: [String] = []

            if monitoringSettings.enablePostgresWrites {
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
                    notes.append("Loaded PostgreSQL storage totals.")
                } catch {
                    notes.append("PostgreSQL storage summary failed: \(error.localizedDescription)")
                    logger.log(.warning, "Failed to load PostgreSQL storage summary: \(error.localizedDescription)", category: .monitoring)
                }
            } else {
                notes.append("Postgres writes are disabled; showing local transcript storage only.")
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
            }
        }
    }

    func pruneStoredHistory(settings: AppSettings, logger: LaunchLogger) {
        guard settings.postgresMonitoring.enabled else {
            lastPruneSummary = "Monitoring is disabled."
            return
        }
        guard !isPruningStoredHistory else { return }

        isPruningStoredHistory = true
        let monitoringSettings = settings.postgresMonitoring
        let databaseRetentionDays = monitoringSettings.clampedDatabaseRetentionDays
        let localRetentionDays = monitoringSettings.clampedLocalTranscriptRetentionDays

        Task { [weak self] in
            guard let self else { return }

            var pruneSummary = PostgresPruneSummary(
                cutoffDate: Date().addingTimeInterval(-TimeInterval(databaseRetentionDays) * 86_400)
            )
            var notes: [String] = []

            if monitoringSettings.enablePostgresWrites {
                do {
                    pruneSummary = try await writer.pruneCompletedHistory(
                        settings: monitoringSettings,
                        retentionDays: databaseRetentionDays
                    )
                    notes.append("Deleted \(pruneSummary.deletedSessions) PostgreSQL session row(s).")
                } catch {
                    notes.append("PostgreSQL prune failed: \(error.localizedDescription)")
                    logger.log(.error, "Failed to prune PostgreSQL monitor history: \(error.localizedDescription)", category: .monitoring)
                }
            } else {
                pruneSummary.cutoffDate = Date().addingTimeInterval(-TimeInterval(localRetentionDays) * 86_400)
                notes.append("Postgres writes are disabled; pruning local transcript files only.")
            }

            let localPrune = Self.pruneTranscriptDirectory(
                at: monitoringSettings.expandedTranscriptDirectory,
                olderThanDays: localRetentionDays,
                protectedPaths: self.protectedTranscriptPaths()
            )
            pruneSummary.deletedTranscriptFiles = localPrune.deletedFileCount
            pruneSummary.deletedTranscriptBytes = localPrune.deletedBytes
            notes.append(
                localPrune.deletedFileCount > 0
                    ? "Deleted \(localPrune.deletedFileCount) local transcript file(s)."
                    : "No local transcript files matched the retention cutoff."
            )

            let logLevel: LogLevel = notes.contains(where: { $0.localizedCaseInsensitiveContains("failed") }) ? .warning : .success

            await MainActor.run {
                self.lastPruneResult = pruneSummary
                self.lastPruneSummary = Self.describe(pruneSummary: pruneSummary)
                self.databaseStatus = monitoringSettings.enablePostgresWrites
                    ? "Stored monitoring history pruned."
                    : "Local transcript history pruned."
                self.isPruningStoredHistory = false
                if monitoringSettings.enablePostgresWrites {
                    self.refreshRecentSessions(settings: settings, logger: logger)
                }
                self.refreshStorageSummary(settings: settings, logger: logger)
                logger.log(logLevel, notes.joined(separator: " "), category: .monitoring)
            }
        }
    }

    func statuses(for settings: AppSettings) -> [ToolStatus] {
        diagnostics.inspect(settings: settings.postgresMonitoring)
    }

    func details(for sessionID: UUID) -> TerminalMonitorSessionDetails? {
        sessionDetailsByID[sessionID]
    }

    func isLoadingDetails(for sessionID: UUID) -> Bool {
        detailLoadingSessionIDs.contains(sessionID)
    }

    func loadDetails(for session: TerminalMonitorSession, settings: AppSettings, logger: LaunchLogger, forceRefresh: Bool = false) {
        if detailLoadingSessionIDs.contains(session.id) {
            return
        }
        if !forceRefresh, let cached = sessionDetailsByID[session.id], cached.matches(session) {
            return
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
                        maxBytes: settings.postgresMonitoring.clampedTranscriptPreviewByteLimit
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

            if settings.postgresMonitoring.enabled && settings.postgresMonitoring.enablePostgresWrites {
                do {
                    async let fetchedEvents = writer.fetchSessionEvents(
                        sessionID: session.id,
                        settings: settings.postgresMonitoring,
                        limit: settings.postgresMonitoring.clampedDetailEventLimit
                    )
                    async let fetchedChunks = writer.fetchSessionChunks(
                        sessionID: session.id,
                        settings: settings.postgresMonitoring,
                        limit: settings.postgresMonitoring.clampedDetailChunkLimit
                    )
                    events = try await fetchedEvents
                    chunks = try await fetchedChunks
                    loadNotes.append("Loaded \(events.count) event(s) and \(chunks.count) chunk(s) from PostgreSQL.")

                    if transcriptText.isEmpty && !chunks.isEmpty {
                        transcriptText = chunks.map(\.text).joined()
                        transcriptTruncated = session.chunkCount > chunks.count
                        transcriptSource = transcriptTruncated
                            ? "Reconstructed from the latest \(chunks.count) PostgreSQL transcript chunks."
                            : "Reconstructed from PostgreSQL transcript chunks."
                    }
                } catch {
                    loadNotes.append("PostgreSQL detail fetch failed: \(error.localizedDescription)")
                    logger.log(.warning, "Failed to load detailed monitor data for \(session.profileName): \(error.localizedDescription)", category: .monitoring)
                }
            } else if session.isHistorical || !session.hasLocalTranscriptFile {
                loadNotes.append("PostgreSQL detail loading is unavailable in the current settings.")
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
                eventsTruncated: events.count >= settings.postgresMonitoring.clampedDetailEventLimit,
                chunksTruncated: session.chunkCount > chunks.count,
                loadSummary: loadNotes.isEmpty ? "Session details loaded." : loadNotes.joined(separator: " ")
            )

            await MainActor.run {
                self.sessionDetailsByID[session.id] = details
                self.detailLoadingSessionIDs.remove(session.id)
            }
        }
    }

    private func buildPreparedContext(item: PlannedLaunchItem, profile: LaunchProfile, settings: PostgresMonitoringSettings) throws -> PreparedMonitoringContext {
        let transcriptDirectory = settings.expandedTranscriptDirectory
        try FileManager.default.createDirectory(atPath: transcriptDirectory, withIntermediateDirectories: true, attributes: nil)

        let sessionID = UUID()
        let timestamp = Self.fileTimestampFormatter.string(from: Date())
        let transcriptFilename = "\(timestamp)-\(profile.agentKind.rawValue)-\(sessionID.uuidString).typescript"
        let transcriptPath = (transcriptDirectory as NSString).appendingPathComponent(transcriptFilename)
        let completionMarkerPath = transcriptPath + ".exit"
        let wrappedCommand = try wrapCommand(item.command, transcriptPath: transcriptPath, completionMarkerPath: completionMarkerPath, settings: settings)

        let session = TerminalMonitorSession(
            id: sessionID,
            profileID: item.profileID,
            profileName: item.profileName,
            agentKind: profile.agentKind,
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
            lastDatabaseMessage: settings.enablePostgresWrites ? "Session prepared for PostgreSQL tracking." : "Local transcript capture only.",
            lastError: nil,
            statusReason: nil,
            exitCode: nil,
            isHistorical: false
        )
        return PreparedMonitoringContext(session: session, wrappedCommand: wrappedCommand, completionMarkerPath: completionMarkerPath)
    }

    private func wrapCommand(_ originalCommand: String, transcriptPath: String, completionMarkerPath: String, settings: PostgresMonitoringSettings) throws -> String {
        let builder = CommandBuilder()
        let scriptExecutable = builder.resolvedExecutable(settings.scriptExecutable) ?? settings.scriptExecutable
        let transcriptDirectory = URL(fileURLWithPath: transcriptPath).deletingLastPathComponent().path
        let keyFlag = settings.captureMode.usesScriptKeyLogging ? "-k " : ""
        return "mkdir -p \(shellQuote(transcriptDirectory)) && \(shellQuote(scriptExecutable)) -q \(keyFlag)-t 0 \(shellQuote(transcriptPath)) /bin/sh -lc \(shellQuote(originalCommand)); __launcher_exit_code=$?; /usr/bin/printf 'exit_code=%s\\nended_at=%s\\nreason=%s\\n' \"$__launcher_exit_code\" \"$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)\" \"command_finished\" > \(shellQuote(completionMarkerPath)); exit $__launcher_exit_code"
    }

    private func startPolling(context: PreparedMonitoringContext, settings: PostgresMonitoringSettings) {
        let sessionID = context.session.id
        stopPolling(sessionID: sessionID)

        pollTasks[sessionID] = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let pollingDelay = UInt64(max(250, settings.pollingIntervalMs)) * 1_000_000
            let chunkByteLimit = 12_000
            let idleThreshold: TimeInterval = 120
            let transcriptGraceDeadline = Date().addingTimeInterval(20)
            var offset: UInt64 = 0
            var chunkIndex = 0
            var lastObservedWrite = Date()

            while !Task.isCancelled {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: context.session.transcriptPath)
                    let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

                    if size > offset {
                        let data = try Self.readAppendedData(at: context.session.transcriptPath, offset: offset)
                        offset = size
                        let slices = stride(from: 0, to: data.count, by: chunkByteLimit).map {
                            data.subdata(in: $0..<min($0 + chunkByteLimit, data.count))
                        }
                        for slice in slices where !slice.isEmpty {
                            chunkIndex += 1
                            lastObservedWrite = Date()
                            let preview = Self.cleanedPreview(from: slice, limit: settings.previewCharacterLimit)
                            await self.consumeChunk(
                                sessionID: sessionID,
                                data: slice,
                                preview: preview,
                                chunkIndex: chunkIndex,
                                timestamp: lastObservedWrite,
                                settings: settings
                            )
                        }
                    }

                    if let completion = Self.readCompletionMarker(at: context.completionMarkerPath) {
                        await self.markCompleted(
                            sessionID: sessionID,
                            completion: completion,
                            completionMarkerPath: context.completionMarkerPath,
                            settings: settings
                        )
                        return
                    }

                    if size > 0, Date().timeIntervalSince(lastObservedWrite) > idleThreshold {
                        await self.markIdleIfNeeded(sessionID: sessionID, at: lastObservedWrite, settings: settings)
                    }
                } catch {
                    if Self.isMissingFileError(error), Date() < transcriptGraceDeadline {
                        // The wrapped script process may not have created the transcript file yet.
                    } else {
                        await self.markMonitoringFailure(
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
        settings: PostgresMonitoringSettings
    ) async {
        guard var session = sessions.first(where: { $0.id == sessionID }) else { return }

        session.status = .monitoring
        session.lastActivityAt = timestamp
        session.chunkCount += 1
        session.byteCount += data.count
        session.lastPreview = preview
        session.lastDatabaseMessage = settings.enablePostgresWrites ? "Chunk \(session.chunkCount) queued for PostgreSQL." : "Chunk \(session.chunkCount) captured locally."
        session.lastError = nil
        session.statusReason = nil
        upsert(session)

        guard settings.enablePostgresWrites else { return }

        do {
            try await writer.recordChunk(
                sessionID: sessionID,
                chunkIndex: chunkIndex,
                data: data,
                preview: preview,
                totalChunks: session.chunkCount,
                totalBytes: session.byteCount,
                capturedAt: timestamp,
                status: .monitoring,
                settings: settings
            )
            if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[index].lastDatabaseMessage = "Synced chunk \(sessions[index].chunkCount) to PostgreSQL."
            }
        } catch {
            if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[index].lastDatabaseMessage = "Postgres sync failed: \(error.localizedDescription)"
            }
            databaseStatus = "Postgres write failed"
        }
    }

    private func markIdleIfNeeded(sessionID: UUID, at timestamp: Date, settings: PostgresMonitoringSettings) async {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[index].status != .idle else { return }

        sessions[index].status = .idle
        sessions[index].lastActivityAt = timestamp
        sessions[index].lastDatabaseMessage = settings.enablePostgresWrites ? "Waiting for additional terminal output." : "No new terminal output detected yet."
        let idleSession = sessions[index]
        upsert(idleSession)

        guard settings.enablePostgresWrites else { return }
        do {
            try await writer.recordStatus(
                sessionID: sessionID,
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
            if let refreshedIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[refreshedIndex].lastDatabaseMessage = "Postgres idle-state sync failed: \(error.localizedDescription)"
            }
            databaseStatus = "Postgres write failed"
        }
    }

    private func markCompleted(
        sessionID: UUID,
        completion: SessionCompletionMarker,
        completionMarkerPath: String,
        settings: PostgresMonitoringSettings
    ) async {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
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
        sessions[index].lastDatabaseMessage = settings.enablePostgresWrites
            ? (completedSuccessfully ? "Session completed and synced to PostgreSQL." : "Session exited non-zero and was recorded in PostgreSQL.")
            : (completedSuccessfully ? "Session completed locally." : "Session exited non-zero.")

        let finalSession = sessions[index]
        upsert(finalSession)
        stopPolling(sessionID: sessionID)
        try? FileManager.default.removeItem(atPath: completionMarkerPath)

        if settings.enablePostgresWrites {
            do {
                try await writer.recordCompletion(session: finalSession, settings: settings)
            } catch {
                if let refreshedIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
                    sessions[refreshedIndex].lastDatabaseMessage = "Postgres completion sync failed: \(error.localizedDescription)"
                }
                databaseStatus = "Postgres write failed"
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
        settings: PostgresMonitoringSettings
    ) async {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            stopPolling(sessionID: sessionID)
            try? FileManager.default.removeItem(atPath: completionMarkerPath)
            return
        }

        sessions[index].status = .failed
        sessions[index].endedAt = Date()
        sessions[index].lastError = message
        sessions[index].statusReason = "monitoring_error"
        sessions[index].lastDatabaseMessage = settings.enablePostgresWrites ? "Monitoring failed before session data could be fully synchronized." : "Monitoring failed locally."
        let failedSession = sessions[index]
        upsert(failedSession)
        stopPolling(sessionID: sessionID)
        try? FileManager.default.removeItem(atPath: completionMarkerPath)

        guard settings.enablePostgresWrites else { return }
        do {
            try await writer.recordFailure(sessionID: sessionID, message: message, status: .failed, settings: settings)
        } catch {
            if let refreshedIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[refreshedIndex].lastDatabaseMessage = "Postgres failure sync failed: \(error.localizedDescription)"
            }
            databaseStatus = "Postgres write failed"
        }
    }

    private func synchronizeHistoricalSessions(_ databaseSessions: [TerminalMonitorSession]) {
        let staleHistoricalIDs = Set(sessions.filter(\.isHistorical).map(\.id)).subtracting(databaseSessions.map(\.id))
        var liveSessions = sessions.filter { !$0.isHistorical }

        for session in databaseSessions {
            if let index = liveSessions.firstIndex(where: { $0.id == session.id }) {
                liveSessions[index].endedAt = session.endedAt ?? liveSessions[index].endedAt
                liveSessions[index].statusReason = session.statusReason ?? liveSessions[index].statusReason
                liveSessions[index].exitCode = session.exitCode ?? liveSessions[index].exitCode
                if liveSessions[index].lastPreview.isEmpty {
                    liveSessions[index].lastPreview = session.lastPreview
                }
                if liveSessions[index].lastDatabaseMessage.isEmpty || liveSessions[index].lastDatabaseMessage.contains("failed") {
                    liveSessions[index].lastDatabaseMessage = session.lastDatabaseMessage
                }
            } else {
                liveSessions.append(session)
            }
        }

        for id in staleHistoricalIDs {
            sessionDetailsByID.removeValue(forKey: id)
            detailLoadingSessionIDs.remove(id)
        }

        sessions = liveSessions
        sessions.sort { ($0.lastActivityAt ?? $0.endedAt ?? $0.startedAt) > ($1.lastActivityAt ?? $1.endedAt ?? $1.startedAt) }
        if sessions.count > 200 {
            sessions = Array(sessions.prefix(200))
        }
    }

    private func upsert(_ session: TerminalMonitorSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { ($0.lastActivityAt ?? $0.endedAt ?? $0.startedAt) > ($1.lastActivityAt ?? $1.endedAt ?? $1.startedAt) }
        if sessions.count > 200 {
            sessions = Array(sessions.prefix(200))
        }
    }

    nonisolated private static func readAppendedData(at path: String, offset: UInt64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        return try handle.readToEnd() ?? Data()
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

    nonisolated private static func scanTranscriptDirectory(at path: String) -> PostgresStorageSummary {
        let inventory = transcriptInventory(at: path)
        return PostgresStorageSummary(
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
                  (isManagedTranscriptFile(fileURL) || isManagedCompletionMarkerFile(fileURL)),
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

    nonisolated private static func describe(pruneSummary: PostgresPruneSummary) -> String {
        let localBytes = ByteCountFormatter.string(fromByteCount: pruneSummary.deletedTranscriptBytes, countStyle: .file)
        let chunkBytes = ByteCountFormatter.string(fromByteCount: pruneSummary.deletedChunkBytes, countStyle: .file)
        return [
            "Pruned data older than \(pruneSummary.cutoffDate.formatted(date: .abbreviated, time: .omitted)).",
            "Deleted \(pruneSummary.deletedSessions) session(s), \(pruneSummary.deletedChunks) chunk(s), and \(pruneSummary.deletedEvents) event row(s) from PostgreSQL (\(chunkBytes) of logical transcript data).",
            "Deleted \(pruneSummary.deletedTranscriptFiles) local transcript file(s) (\(localBytes))."
        ].joined(separator: " ")
    }

    nonisolated private static func cleanedPreview(from data: Data, limit: Int) -> String {
        let raw = String(decoding: data, as: UTF8.self)
        var cleaned = raw.replacingOccurrences(of: "\u{0000}", with: "")
        cleaned = cleaned.unicodeScalars.map { scalar in
            if CharacterSet.controlCharacters.contains(scalar), scalar != "\n" && scalar != "\t" {
                return " "
            }
            return String(scalar)
        }.joined()
        if cleaned.count > limit {
            let end = cleaned.index(cleaned.startIndex, offsetBy: min(limit, cleaned.count))
            return String(cleaned[..<end]) + "…"
        }
        return cleaned
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
        if nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.fileReadNoSuchFile.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == 2 {
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
}
