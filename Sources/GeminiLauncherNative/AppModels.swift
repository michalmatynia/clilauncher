import Foundation

struct LaunchWorkbench: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "New Workbench"
    var notes: String = ""
    var tags: [String] = []
    var role: WorkbenchRole = .coding
    var startupDelayMs: Int = 300
    var postLaunchActionHints: [String] = []
    var profileIDs: [UUID] = []
    var sharedBookmarkID: UUID?
    var createdAt = Date()
    var lastLaunchedAt: Date?

    var tagSummary: String {
        tags.joined(separator: ", ")
    }
}

enum WorkbenchRole: String, Codable, CaseIterable, Identifiable {
    case research
    case coding
    case review

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .research: return "Research"
        case .coding: return "Coding"
        case .review: return "Review"
        }
    }
}

struct LaunchResult: Equatable, Sendable {
    var command: String
    var appleScript: String
    var description: String
}

struct PlannedLaunchItem: Identifiable, Equatable, Sendable {
    var id = UUID()
    var profileID: UUID
    var profileName: String
    var command: String
    var openMode: ITermOpenMode
    var terminalApp: TerminalApp = .iterm2
    var iTermProfile: String
    var description: String
    var monitorSessionID: UUID?
}

struct PostLaunchAction: Identifiable, Equatable, Sendable {
    var app: WorkspaceCompanionApp
    var path: String
    var label: String

    var id: String { "\(app.rawValue)|\(path)" }
}

struct PlannedLaunch: Equatable, Sendable {
    var items: [PlannedLaunchItem]
    var postLaunchActions: [PostLaunchAction] = []
    var tabLaunchDelayMs: Int = 300

    var combinedCommandPreview: String {
        items.enumerated().map { index, item in
            "[\(index + 1)] \(item.profileName)\n\(item.command)"
        }.joined(separator: "\n\n")
    }

    var postLaunchSummary: String {
        postLaunchActions.map(\.label).joined(separator: " • ")
    }
}

struct LaunchHistoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var timestamp = Date()
    var profileID: UUID?
    var workbenchID: UUID?
    var profileName: String
    var description: String
    var command: String
    var companionCount: Int = 0
    var monitorSessionIDs: [UUID] = []

    var isWorkbenchLaunch: Bool {
        workbenchID != nil || profileID == nil
    }

    var hasRelaunchTarget: Bool {
        profileID != nil || workbenchID != nil
    }

    var hasMonitoringLink: Bool {
        !monitorSessionIDs.isEmpty
    }

    func matchesSearchQuery(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let searchableFields = [
            profileName,
            description,
            command,
            profileID?.uuidString ?? "",
            workbenchID?.uuidString ?? "",
            monitorSessionIDs.map(\.uuidString).joined(separator: " "),
            isWorkbenchLaunch ? "workbench" : "profile"
        ]

        return searchableFields.contains { $0.lowercased().contains(query) }
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, profileID, workbenchID, profileName, description, command, companionCount, monitorSessionIDs
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        profileID: UUID?,
        workbenchID: UUID? = nil,
        profileName: String,
        description: String,
        command: String,
        companionCount: Int = 0,
        monitorSessionIDs: [UUID] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.profileID = profileID
        self.workbenchID = workbenchID
        self.profileName = profileName
        self.description = description
        self.command = command
        self.companionCount = companionCount
        self.monitorSessionIDs = monitorSessionIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
        workbenchID = try container.decodeIfPresent(UUID.self, forKey: .workbenchID)
        profileName = try container.decode(String.self, forKey: .profileName)
        description = try container.decode(String.self, forKey: .description)
        command = try container.decode(String.self, forKey: .command)
        companionCount = try container.decodeIfPresent(Int.self, forKey: .companionCount) ?? 0
        monitorSessionIDs = try container.decodeIfPresent([UUID].self, forKey: .monitorSessionIDs) ?? []
    }
}

enum LaunchHistoryTarget: Equatable {
    case profile(LaunchProfile)
    case workbench(LaunchWorkbench)
}

struct PersistedState: Codable {
    var profiles: [LaunchProfile]
    var selectedProfileID: UUID?
    var settings: AppSettings
    var history: [LaunchHistoryItem]
    var bookmarks: [WorkspaceBookmark]
    var workbenches: [LaunchWorkbench]

    init(
        profiles: [LaunchProfile],
        selectedProfileID: UUID?,
        settings: AppSettings,
        history: [LaunchHistoryItem],
        bookmarks: [WorkspaceBookmark],
        workbenches: [LaunchWorkbench]
    ) {
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID
        self.settings = settings
        self.history = history
        self.bookmarks = bookmarks
        self.workbenches = workbenches
    }

    enum CodingKeys: String, CodingKey {
        case profiles, selectedProfileID, settings, history, bookmarks, workbenches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decode([LaunchProfile].self, forKey: .profiles)
        selectedProfileID = try container.decodeIfPresent(UUID.self, forKey: .selectedProfileID)
        settings = try container.decode(AppSettings.self, forKey: .settings)
        history = try container.decodeIfPresent([LaunchHistoryItem].self, forKey: .history) ?? []
        bookmarks = try container.decodeIfPresent([WorkspaceBookmark].self, forKey: .bookmarks) ?? []
        workbenches = try container.decodeIfPresent([LaunchWorkbench].self, forKey: .workbenches) ?? []
    }
}

struct WorkspaceBookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "New Bookmark"
    var path: String = FileManager.default.homeDirectoryForCurrentUser.path
    var tags: [String] = []
    var notes: String = ""
    var defaultProfileID: UUID?
    var createdAt = Date()
    var lastUsedAt: Date?

    var expandedPath: String {
        NSString(string: path).expandingTildeInPath
    }
}

enum LauncherTab: String, CaseIterable, Identifiable {
    case launch
    case profiles
    case workbenches
    case workspaces
    case history
    case diagnostics
    case monitoring
    case keystrokes
    case logs
    case settings

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .launch: return "Launch Center"
        case .profiles: return "Profiles"
        case .workbenches: return "Workbenches"
        case .workspaces: return "Workspaces"
        case .history: return "History"
        case .diagnostics: return "Diagnostics"
        case .monitoring: return "Monitoring"
        case .keystrokes: return "Keystrokes"
        case .logs: return "Launch Log"
        case .settings: return "Settings"
        }
    }
}

enum LogCategory: String, Codable, CaseIterable, Identifiable {
    case app
    case launch
    case preflight
    case iterm
    case monitoring
    case diagnostics
    case state

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .app: return "App"
        case .launch: return "Launch"
        case .preflight: return "Preflight"
        case .iterm: return "iTerm2"
        case .monitoring: return "Monitoring"
        case .diagnostics: return "Diagnostics"
        case .state: return "State"
        }
    }
}

enum LogLevel: String, Codable, CaseIterable, Identifiable {
    case debug
    case info
    case success
    case warning
    case error

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}
