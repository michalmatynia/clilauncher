import Foundation

extension Notification.Name {
    static let refreshDiagnosticsRequested = Notification.Name("refreshDiagnosticsRequested")
    static let relaunchLastRequested = Notification.Name("relaunchLastRequested")
    static let toggleAutomationRequested = Notification.Name("toggleAutomationRequested")
    static let enableAutomationRequested = Notification.Name("enableAutomationRequested")
    static let disableAutomationRequested = Notification.Name("disableAutomationRequested")
}

enum AppPaths {
    static let folderName = "CLILauncherNativeV24"
    static let legacyFolderNames = [
        "GeminiLauncherNativeV24",
        "GeminiLauncherNativeV23",
        "GeminiLauncherNativeV22",
        "GeminiLauncherNativeV21",
        "GeminiLauncherNativeV20",
        "GeminiLauncherNativeV19",
        "GeminiLauncherNativeV18",
        "GeminiLauncherNativeV17",
        "GeminiLauncherNativeV16",
        "GeminiLauncherNativeV15",
        "GeminiLauncherNativeV14",
        "GeminiLauncherNativeV13",
        "GeminiLauncherNativeV12",
        "GeminiLauncherNativeV11",
        "GeminiLauncherNativeV10",
        "GeminiLauncherNativeV9",
        "GeminiLauncherNativeV8"
    ]

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static var containerDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    static var stateFileURL: URL {
        containerDirectory.appendingPathComponent("state.json")
    }

    static var stateMongoConnectionURL: String {
        "mongodb://127.0.0.1:27017"
    }

    static var stateMongoDatabaseName: String {
        "clilauncher_state"
    }

    static var stateMongoLocationDescription: String {
        "\(stateMongoConnectionURL)/\(stateMongoDatabaseName)"
    }

    static var logsDirectoryURL: URL {
        containerDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    static var runtimeLogFileURL: URL {
        logsDirectoryURL.appendingPathComponent("runtime.log")
    }

    static var mongoDataDirectoryPath: String {
        "~/Library/Application Support/\(folderName)/Mongo"
    }

    static var mongoDataDirectoryURL: URL {
        applicationSupportDirectory
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("Mongo", isDirectory: true)
    }

    static var defaultTranscriptDirectoryPath: String {
        "~/Library/Application Support/\(folderName)/Transcripts"
    }
}

struct EnvironmentEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var key: String = ""
    var value: String = ""
}

struct EnvironmentPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "Shared Environment"
    var notes: String = ""
    var entries: [EnvironmentEntry] = []

    var environmentMap: [String: String] {
        entries.reduce(into: [:]) { partial, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            partial[key] = item.value
        }
    }
}

struct ShellBootstrapPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "Shared Bootstrap"
    var notes: String = ""
    var command: String = ""

    var trimmedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ObservabilitySettings: Codable, Equatable {
    var verboseLogging: Bool = true
    var persistLogsToDisk: Bool = true
    var includeAppleScriptInLogs: Bool = true
    var deduplicateRepeatedEntries: Bool = true
    var maxInMemoryEntries: Int = 1_500

    init() {}

    enum CodingKeys: String, CodingKey {
        case verboseLogging, persistLogsToDisk, includeAppleScriptInLogs, deduplicateRepeatedEntries, maxInMemoryEntries
    }

    init(from decoder: Decoder) throws {
        let defaults = Self()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verboseLogging = try container.decodeDefault(Bool.self, forKey: .verboseLogging, default: defaults.verboseLogging)
        persistLogsToDisk = try container.decodeDefault(Bool.self, forKey: .persistLogsToDisk, default: defaults.persistLogsToDisk)
        includeAppleScriptInLogs = try container.decodeDefault(Bool.self, forKey: .includeAppleScriptInLogs, default: defaults.includeAppleScriptInLogs)
        deduplicateRepeatedEntries = try container.decodeDefault(Bool.self, forKey: .deduplicateRepeatedEntries, default: defaults.deduplicateRepeatedEntries)
        maxInMemoryEntries = try container.decodeDefault(Int.self, forKey: .maxInMemoryEntries, default: defaults.maxInMemoryEntries)
    }
}

struct AppSettings: Codable, Equatable {
    var defaultWorkingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    var defaultNodeExecutable: String = "node"
    var defaultGeminiRunnerPath: String = BundledGeminiAutomationRunner.defaultPath
    var defaultTerminalApp: TerminalApp = .iterm2
    var defaultITermProfile: String = ""
    var defaultOpenMode: ITermOpenMode = .newWindow
    var defaultHotkeyPrefix: String = "ctrl-g"
    var defaultShellBootstrapCommand: String = ""
    var defaultOpenWorkspaceInFinderOnLaunch: Bool = false
    var defaultOpenWorkspaceInVSCodeOnLaunch: Bool = false
    var defaultTabLaunchDelayMs: Int = 300
    var defaultKeepTryMax: Int = 25
    var defaultManualOverrideMs: Int = 20_000
    var quietChildNodeWarningsByDefault: Bool = true
    var confirmBeforeLaunch: Bool = true
    var maxHistoryItems: Int = 100
    var maxBookmarks: Int = 60
    var didBootstrapSessionRecording: Bool = false
    var mongoMonitoring = MongoMonitoringSettings()
    var observability = ObservabilitySettings()
    var environmentPresets: [EnvironmentPreset] = []
    var shellBootstrapPresets: [ShellBootstrapPreset] = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case defaultWorkingDirectory, defaultNodeExecutable, defaultGeminiRunnerPath, defaultTerminalApp, defaultITermProfile
        case defaultOpenMode, defaultHotkeyPrefix, defaultShellBootstrapCommand
        case defaultOpenWorkspaceInFinderOnLaunch, defaultOpenWorkspaceInVSCodeOnLaunch, defaultTabLaunchDelayMs
        case defaultKeepTryMax, defaultManualOverrideMs
        case quietChildNodeWarningsByDefault, confirmBeforeLaunch
        case maxHistoryItems, maxBookmarks
        case didBootstrapSessionRecording
        case mongoMonitoring = "postgresMonitoring", observability
        case environmentPresets, shellBootstrapPresets
    }

    init(from decoder: Decoder) throws {
        let defaults = Self()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        defaultWorkingDirectory = try container.decodeDefault(String.self, forKey: .defaultWorkingDirectory, default: defaults.defaultWorkingDirectory)
        defaultNodeExecutable = try container.decodeDefault(String.self, forKey: .defaultNodeExecutable, default: defaults.defaultNodeExecutable)
        defaultGeminiRunnerPath = BundledGeminiAutomationRunner.normalizedConfiguredPath(
            try container.decodeDefault(String.self, forKey: .defaultGeminiRunnerPath, default: defaults.defaultGeminiRunnerPath),
            fillBlankWithDefault: false
        )
        defaultTerminalApp = try container.decodeDefault(TerminalApp.self, forKey: .defaultTerminalApp, default: defaults.defaultTerminalApp)
        defaultITermProfile = try container.decodeDefault(String.self, forKey: .defaultITermProfile, default: defaults.defaultITermProfile)
        defaultOpenMode = try container.decodeDefault(ITermOpenMode.self, forKey: .defaultOpenMode, default: defaults.defaultOpenMode)
        defaultHotkeyPrefix = try container.decodeDefault(String.self, forKey: .defaultHotkeyPrefix, default: defaults.defaultHotkeyPrefix)
        defaultShellBootstrapCommand = try container.decodeDefault(String.self, forKey: .defaultShellBootstrapCommand, default: defaults.defaultShellBootstrapCommand)
        defaultOpenWorkspaceInFinderOnLaunch = try container.decodeDefault(Bool.self, forKey: .defaultOpenWorkspaceInFinderOnLaunch, default: defaults.defaultOpenWorkspaceInFinderOnLaunch)
        defaultOpenWorkspaceInVSCodeOnLaunch = try container.decodeDefault(Bool.self, forKey: .defaultOpenWorkspaceInVSCodeOnLaunch, default: defaults.defaultOpenWorkspaceInVSCodeOnLaunch)
        defaultTabLaunchDelayMs = try container.decodeDefault(Int.self, forKey: .defaultTabLaunchDelayMs, default: defaults.defaultTabLaunchDelayMs)
        defaultKeepTryMax = try container.decodeDefault(Int.self, forKey: .defaultKeepTryMax, default: defaults.defaultKeepTryMax)
        defaultManualOverrideMs = try container.decodeDefault(Int.self, forKey: .defaultManualOverrideMs, default: defaults.defaultManualOverrideMs)
        quietChildNodeWarningsByDefault = try container.decodeDefault(Bool.self, forKey: .quietChildNodeWarningsByDefault, default: defaults.quietChildNodeWarningsByDefault)
        confirmBeforeLaunch = try container.decodeDefault(Bool.self, forKey: .confirmBeforeLaunch, default: defaults.confirmBeforeLaunch)
        maxHistoryItems = try container.decodeDefault(Int.self, forKey: .maxHistoryItems, default: defaults.maxHistoryItems)
        maxBookmarks = try container.decodeDefault(Int.self, forKey: .maxBookmarks, default: defaults.maxBookmarks)
        didBootstrapSessionRecording = try container.decodeDefault(Bool.self, forKey: .didBootstrapSessionRecording, default: defaults.didBootstrapSessionRecording)
        mongoMonitoring = try container.decodeDefault(MongoMonitoringSettings.self, forKey: .mongoMonitoring, default: defaults.mongoMonitoring)
        observability = try container.decodeDefault(ObservabilitySettings.self, forKey: .observability, default: defaults.observability)
        environmentPresets = try container.decodeDefault([EnvironmentPreset].self, forKey: .environmentPresets, default: defaults.environmentPresets)
        shellBootstrapPresets = try container.decodeDefault([ShellBootstrapPreset].self, forKey: .shellBootstrapPresets, default: defaults.shellBootstrapPresets)
    }

    @discardableResult
    mutating func bootstrapSessionRecordingIfNeeded() -> Bool {
        guard !didBootstrapSessionRecording else { return false }

        let defaults = MongoMonitoringSettings()
        mongoMonitoring.enabled = true
        mongoMonitoring.enableMongoWrites = true

        if mongoMonitoring.connectionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mongoMonitoring.connectionURL = defaults.connectionURL
        }
        if mongoMonitoring.schemaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mongoMonitoring.schemaName = defaults.schemaName
        }
        if mongoMonitoring.transcriptDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mongoMonitoring.transcriptDirectory = defaults.transcriptDirectory
        }
        if mongoMonitoring.mongoshExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mongoMonitoring.mongoshExecutable = defaults.mongoshExecutable
        }
        if mongoMonitoring.mongodExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mongoMonitoring.mongodExecutable = defaults.mongodExecutable
        }
        if mongoMonitoring.scriptExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mongoMonitoring.scriptExecutable = defaults.scriptExecutable
        }
        if mongoMonitoring.localDataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mongoMonitoring.localDataDirectory = defaults.localDataDirectory
        }

        didBootstrapSessionRecording = true
        return true
    }
}
