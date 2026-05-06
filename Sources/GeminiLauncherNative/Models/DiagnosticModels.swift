import Foundation

struct LogEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp = Date()
    var level: LogLevel
    var category: LogCategory = .app
    var message: String
    var details: String?
    var repeatCount: Int = 1
}

struct ToolStatus: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var name: String
    var requested: String
    var resolved: String?
    var detail: String
    var isError: Bool
    var resolutionSource: String?
    var updateCommand: String?
    var installDocumentation: String?
    var providerRiskLevel: ProviderRiskLevel?
}

struct DiagnosticITermSnapshot: Codable {
    var applicationURL: String?
    var bundleIdentifier: String
    var isInstalled: Bool
    var isRunning: Bool
    var profileDiscoverySource: String
    var profileNames: [String]
}

struct MonitoringDiagnosticSnapshot: Codable {
    var sessionCount: Int
    var databaseStatus: String
    var lastConnectionCheck: String
    var storageSummaryStatus: String
}

struct ApplicationDiagnosticReport: Codable {
    var createdAt = Date()
    var appSupportDirectory: String
    var persistenceStorePath: String
    var logFilePath: String
    var selectedTab: String
    var selectedProfileName: String?
    var selectedProfileID: UUID?
    var diagnosticsErrors: [String]
    var diagnosticsWarnings: [String]
    var diagnosticStatuses: [ToolStatus]
    var iterm: DiagnosticITermSnapshot
    var monitoring: MonitoringDiagnosticSnapshot
    var commandPreview: String?
    var appleScriptPreview: String?
    var recentLogs: [LogEntry]

    enum CodingKeys: String, CodingKey {
        case createdAt
        case appSupportDirectory
        case persistenceStorePath
        case stateFilePath
        case logFilePath
        case selectedTab
        case selectedProfileName
        case selectedProfileID
        case diagnosticsErrors
        case diagnosticsWarnings
        case diagnosticStatuses
        case iterm
        case monitoring
        case commandPreview
        case appleScriptPreview
        case recentLogs
    }

    init(
        createdAt: Date = Date(),
        appSupportDirectory: String,
        persistenceStorePath: String,
        logFilePath: String,
        selectedTab: String,
        selectedProfileName: String?,
        selectedProfileID: UUID?,
        diagnosticsErrors: [String],
        diagnosticsWarnings: [String],
        diagnosticStatuses: [ToolStatus],
        iterm: DiagnosticITermSnapshot,
        monitoring: MonitoringDiagnosticSnapshot,
        commandPreview: String?,
        appleScriptPreview: String?,
        recentLogs: [LogEntry]
    ) {
        self.createdAt = createdAt
        self.appSupportDirectory = appSupportDirectory
        self.persistenceStorePath = persistenceStorePath
        self.logFilePath = logFilePath
        self.selectedTab = selectedTab
        self.selectedProfileName = selectedProfileName
        self.selectedProfileID = selectedProfileID
        self.diagnosticsErrors = diagnosticsErrors
        self.diagnosticsWarnings = diagnosticsWarnings
        self.diagnosticStatuses = diagnosticStatuses
        self.iterm = iterm
        self.monitoring = monitoring
        self.commandPreview = commandPreview
        self.appleScriptPreview = appleScriptPreview
        self.recentLogs = recentLogs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try container.decodeDefault(Date.self, forKey: .createdAt, default: Date())
        appSupportDirectory = try container.decode(String.self, forKey: .appSupportDirectory)
        persistenceStorePath =
            try container.decodeIfPresent(String.self, forKey: .persistenceStorePath)
            ?? container.decode(String.self, forKey: .stateFilePath)
        logFilePath = try container.decode(String.self, forKey: .logFilePath)
        selectedTab = try container.decode(String.self, forKey: .selectedTab)
        selectedProfileName = try container.decodeIfPresent(String.self, forKey: .selectedProfileName)
        selectedProfileID = try container.decodeIfPresent(UUID.self, forKey: .selectedProfileID)
        diagnosticsErrors = try container.decode([String].self, forKey: .diagnosticsErrors)
        diagnosticsWarnings = try container.decode([String].self, forKey: .diagnosticsWarnings)
        diagnosticStatuses = try container.decode([ToolStatus].self, forKey: .diagnosticStatuses)
        iterm = try container.decode(DiagnosticITermSnapshot.self, forKey: .iterm)
        monitoring = try container.decode(MonitoringDiagnosticSnapshot.self, forKey: .monitoring)
        commandPreview = try container.decodeIfPresent(String.self, forKey: .commandPreview)
        appleScriptPreview = try container.decodeIfPresent(String.self, forKey: .appleScriptPreview)
        recentLogs = try container.decode([LogEntry].self, forKey: .recentLogs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(appSupportDirectory, forKey: .appSupportDirectory)
        try container.encode(persistenceStorePath, forKey: .persistenceStorePath)
        try container.encode(logFilePath, forKey: .logFilePath)
        try container.encode(selectedTab, forKey: .selectedTab)
        try container.encodeIfPresent(selectedProfileName, forKey: .selectedProfileName)
        try container.encodeIfPresent(selectedProfileID, forKey: .selectedProfileID)
        try container.encode(diagnosticsErrors, forKey: .diagnosticsErrors)
        try container.encode(diagnosticsWarnings, forKey: .diagnosticsWarnings)
        try container.encode(diagnosticStatuses, forKey: .diagnosticStatuses)
        try container.encode(iterm, forKey: .iterm)
        try container.encode(monitoring, forKey: .monitoring)
        try container.encodeIfPresent(commandPreview, forKey: .commandPreview)
        try container.encodeIfPresent(appleScriptPreview, forKey: .appleScriptPreview)
        try container.encode(recentLogs, forKey: .recentLogs)
    }
}

extension KeyedDecodingContainer {
    func decodeDefault<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) throws -> T {
        try decodeIfPresent(type, forKey: key) ?? defaultValue
    }
}

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let pretty: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
