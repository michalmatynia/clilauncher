import Foundation

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
                name: "Capture directory",
                requested: transcriptPath,
                resolved: transcriptReady ? transcriptPath : nil,
                detail: transcriptReady ? "Ready for local transcripts and raw input captures." : "Could not create capture directory.",
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
