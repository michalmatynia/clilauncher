import Foundation

private struct LauncherMongoLaunchConfiguration {
    let executablePath: String
    let arguments: [String]
    let connectionURL: String
    let environment: [String: String]
}

struct LauncherMongoStateConfiguration {
    var connectionURL: String = AppPaths.stateMongoConnectionURL
    var databaseName: String = AppPaths.stateMongoDatabaseName
    var collectionName: String = "launcher_state"
    var mongoshExecutable: String = "mongosh"
    var mongodExecutable: String = "mongod"
    var localDataDirectory: String = AppPaths.mongoDataDirectoryPath

    var expandedLocalDataDirectory: String {
        NSString(string: localDataDirectory).expandingTildeInPath
    }

    var locationDescription: String {
        "\(connectionURL)/\(databaseName)"
    }
}

final class MongoStateStore {
    private let configuration: LauncherMongoStateConfiguration
    private let commandBuilder = CommandBuilder()

    init(configuration: LauncherMongoStateConfiguration = LauncherMongoStateConfiguration()) {
        self.configuration = configuration
    }

    var locationDescription: String {
        configuration.locationDescription
    }

    var dataDirectoryPath: String {
        configuration.expandedLocalDataDirectory
    }

    func loadState() throws -> PersistedState? {
        let script = Self.loadStateScript(
            databaseName: configuration.databaseName,
            collectionName: configuration.collectionName
        )

        let output = try runMongo(script)
        guard let line = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return nil
        }
        return try JSONDecoder.pretty.decode(PersistedState.self, from: Data(line.utf8))
    }

    func saveState(_ state: PersistedState) throws {
        try ensureSchema()

        let encoded = try JSONEncoder.pretty.encode(state)
        let payload = try JSONSerialization.jsonObject(with: encoded)
        let script = """
        (function() {
            const targetDb = db.getSiblingDB(\(mongoStringLiteral(configuration.databaseName)));
            const payload = JSON.parse(\(mongoJSONLiteral(payload)));
            targetDb[\(mongoStringLiteral(configuration.collectionName))].updateOne(
                { _id: "singleton" },
                {
                    $set: {
                        payload: payload,
                        format_version: 1,
                        updated_at: new Date()
                    }
                },
                { upsert: true }
            );
            print(JSON.stringify({ ok: true }));
        })();
        """

        _ = try runMongo(script)
    }

    private func ensureSchema() throws {
        let script = Self.ensureSchemaScript(
            databaseName: configuration.databaseName,
            collectionName: configuration.collectionName
        )

        _ = try runMongo(script)
    }

    private func runMongo(_ script: String) throws -> String {
        let launch = try makeLaunchConfiguration()
        do {
            return try executeMongoLaunch(launch: launch, script: script)
        } catch {
            guard shouldRetryMongoLaunch(for: error) else { throw error }
            try startLocalMongodIfNeeded()
            return try executeMongoLaunch(launch: launch, script: script)
        }
    }

    private func executeMongoLaunch(launch: LauncherMongoLaunchConfiguration, script: String) throws -> String {
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
            throw LauncherError.validation("MongoDB state persistence failed: \(errorText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }

    private func shouldRetryMongoLaunch(for error: Error) -> Bool {
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

    private func startLocalMongodIfNeeded() throws {
        let port = mongoPort(from: configuration.connectionURL)
        guard let mongodPath = commandBuilder.resolvedExecutable(configuration.mongodExecutable) else {
            throw LauncherError.validation("Local MongoDB state persistence requires mongod, but it was not found.")
        }
        guard ensureDirectoryExists(at: configuration.expandedLocalDataDirectory) else {
            throw LauncherError.validation("Could not create local MongoDB state directory: \(configuration.expandedLocalDataDirectory)")
        }

        let logPath = NSString(string: configuration.expandedLocalDataDirectory).appendingPathComponent("mongod.log")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mongodPath)
        process.arguments = [
            "--dbpath", configuration.expandedLocalDataDirectory,
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

        guard isMongoReachable() else {
            throw LauncherError.validation("Local mongod did not become reachable on localhost:\(port). See \(logPath).")
        }
    }

    private func isMongoReachable() -> Bool {
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

        guard let launch = try? makeLaunchConfiguration() else {
            return false
        }

        for _ in 0..<20 {
            do {
                let output = try executeMongoLaunch(launch: launch, script: pingScript)
                if output.lowercased().contains("\"ok\":true") {
                    return true
                }
            } catch {
                // Retry while mongod initializes.
            }
            usleep(250_000)
        }
        return false
    }

    private func makeLaunchConfiguration() throws -> LauncherMongoLaunchConfiguration {
        let executable = commandBuilder.resolvedExecutable(configuration.mongoshExecutable) ?? configuration.mongoshExecutable
        guard let components = URLComponents(string: configuration.connectionURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "mongodb" || scheme == "mongodb+srv"
        else {
            throw LauncherError.validation("Mongo state connection URL must begin with mongodb:// or mongodb+srv://")
        }

        return LauncherMongoLaunchConfiguration(
            executablePath: executable,
            arguments: [],
            connectionURL: configuration.connectionURL,
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

    nonisolated static func loadStateScript(databaseName: String, collectionName: String) -> String {
        """
        (function() {
            const targetDb = db.getSiblingDB(\(MongoShellLiterals.stringLiteral(databaseName)));
            const doc = targetDb[\(MongoShellLiterals.stringLiteral(collectionName))].findOne({ _id: "singleton" });
            if (!doc || !doc.payload) {
                return;
            }
            print(JSON.stringify(doc.payload));
        })();
        """
    }

    nonisolated static func ensureSchemaScript(databaseName: String, collectionName: String) -> String {
        """
        (function() {
            const targetDb = db.getSiblingDB(\(MongoShellLiterals.stringLiteral(databaseName)));
            targetDb[\(MongoShellLiterals.stringLiteral(collectionName))].createIndex({ updated_at: -1 });
            print(JSON.stringify({ ok: true }));
        })();
        """
    }

    private func mongoStringLiteral(_ raw: String) -> String {
        MongoShellLiterals.stringLiteral(raw)
    }

    private func mongoJSONLiteral(_ value: Any?) -> String {
        guard let value else { return "null" }

        if let string = value as? String {
            return mongoStringLiteral(string)
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }

        if let array = value as? [Any] {
            return "[" + array.map(mongoJSONLiteral).joined(separator: ",") + "]"
        }

        if let dictionary = value as? [String: Any] {
            return "{" + dictionary
                .keys
                .sorted()
                .map { key in
                    "\(mongoStringLiteral(key)):\(mongoJSONLiteral(dictionary[key] ?? NSNull()))"
                }
                .joined(separator: ",") + "}"
        }

        if value is NSNull {
            return "null"
        }

        return mongoStringLiteral(String(describing: value))
    }
}
