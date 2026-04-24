import Foundation

struct PreflightCheck: Sendable {
    var warnings: [String] = []
    var errors: [String] = []
    var statuses: [ToolStatus] = []

    var isPassing: Bool { errors.isEmpty }
}

struct PreflightService {
    let planner = LaunchPlanner()
    let discovery = ToolDiscoveryService()
    let companionLauncher = WorkspaceCompanionLauncher()
    private let commandBuilder = CommandBuilder()

    func run(profile: LaunchProfile, settings: AppSettings, allProfiles: [LaunchProfile]) -> PreflightCheck {
        var check = PreflightCheck()
        let effectiveProfile = profile.preparedForLaunch()
        let discoveryResult = discovery.inspect(profile: profile, settings: settings)
        check.statuses = discoveryResult.statuses
        check.warnings.append(contentsOf: discoveryResult.warnings)

        if !check.statuses.filter(\.isError).isEmpty {
            check.errors.append(contentsOf: check.statuses.filter(\.isError).map { $0.name + ": " + $0.detail })
        }

        check.warnings.append(contentsOf: effectiveProfile.agentKind.defaultCautionMessages(for: effectiveProfile))
        if effectiveProfile.autoLaunchCompanions, effectiveProfile.companionProfileIDs.isEmpty {
            check.warnings.append("Companion launch is enabled but no companion profiles are selected.")
        }
        if effectiveProfile.autoLaunchCompanions {
            let existing = Set(allProfiles.map(\.id))
            let missing = effectiveProfile.companionProfileIDs.filter { !existing.contains($0) }
            if !missing.isEmpty {
                check.warnings.append("One or more companion profiles no longer exist.")
            }
        }
        if let presetID = effectiveProfile.environmentPresetID {
            if settings.environmentPresets.first(where: { $0.id == presetID }) == nil {
                check.warnings.append("Selected environment preset no longer exists.")
            }
        }
        if let presetID = effectiveProfile.bootstrapPresetID {
            if settings.shellBootstrapPresets.first(where: { $0.id == presetID }) == nil {
                check.warnings.append("Selected shell bootstrap preset no longer exists.")
            }
        }
        if effectiveProfile.openWorkspaceInVSCodeOnLaunch, !companionLauncher.isAvailable(.visualStudioCode) {
            check.warnings.append("Visual Studio Code will not open after launch because the app is not installed or not visible to Launch Services.")
        }
        if effectiveProfile.tabLaunchDelayMs < 100 {
            check.warnings.append("Tab launch delay below 100 ms can cause iTerm2 tab creation race conditions.")
        }
        if settings.mongoMonitoring.enabled, settings.mongoMonitoring.captureMode.usesScriptKeyLogging {
            check.warnings.append("Terminal transcript monitoring is set to capture keyboard input and terminal output. Passwords or secrets typed in the terminal can be recorded.")
        }
        if settings.mongoMonitoring.enabled, settings.mongoMonitoring.enableMongoWrites, settings.mongoMonitoring.trimmedConnectionURL.isEmpty {
            check.errors.append("MongoDB monitoring is enabled but the connection URL is empty.")
        }
        if settings.mongoMonitoring.enabled, settings.mongoMonitoring.enableMongoWrites, settings.mongoMonitoring.mongoConnection.isLocal {
            if commandBuilder.resolvedExecutable(settings.mongoMonitoring.mongodExecutable) == nil {
                check.errors.append("Local MongoDB URL is configured, but mongod executable was not found. Set it in Monitoring settings.")
            }
            if settings.mongoMonitoring.expandedLocalDataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                check.errors.append("Local MongoDB URL is configured, but local Mongo data directory is empty.")
            } else if !FileManager.default.fileExists(atPath: settings.mongoMonitoring.expandedLocalDataDirectory) {
                check.warnings.append("Local Mongo data directory does not exist yet; it will be created on first monitoring write.")
            }
        }

        do {
            _ = try planner.buildPlan(primary: effectiveProfile, allProfiles: allProfiles, settings: settings)
        } catch {
            check.errors.append(error.localizedDescription)
        }

        return check
    }

    func run(workbench: LaunchWorkbench, profiles: [LaunchProfile], bookmarks: [WorkspaceBookmark], settings: AppSettings) -> PreflightCheck {
        var check = PreflightCheck()
        let profileLookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let bookmarkLookup = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0) })

        if workbench.profileIDs.isEmpty {
            check.errors.append("Workbench has no profiles selected.")
        }

        let missingProfiles = workbench.profileIDs.filter { profileLookup[$0] == nil }
        if !missingProfiles.isEmpty {
            check.warnings.append("One or more workbench profiles no longer exist.")
        }

        if let sharedBookmarkID = workbench.sharedBookmarkID {
            if bookmarkLookup[sharedBookmarkID] == nil {
                check.errors.append("Workbench shared workspace no longer exists.")
            }
        }

        for profileID in workbench.profileIDs {
            guard var profile = profileLookup[profileID] else { continue }
            if let sharedBookmarkID = workbench.sharedBookmarkID, let bookmark = bookmarkLookup[sharedBookmarkID] {
                profile.workingDirectory = bookmark.path
                profile.tags = Array(Set(profile.tags + bookmark.tags)).sorted()
            }
            let effectiveProfile = profile.preparedForLaunch()
            let inspection = discovery.inspect(profile: profile, settings: settings)
            check.warnings.append(contentsOf: effectiveProfile.agentKind.defaultCautionMessages(for: effectiveProfile).map { "\(effectiveProfile.name): \($0)" })
            check.warnings.append(contentsOf: inspection.warnings.map { "\(effectiveProfile.name): \($0)" })
            let statuses = inspection.statuses.map {
                ToolStatus(
                    name: "\(effectiveProfile.name) • \($0.name)",
                    requested: $0.requested,
                    resolved: $0.resolved,
                    detail: $0.detail,
                    isError: $0.isError,
                    resolutionSource: $0.resolutionSource,
                    updateCommand: $0.updateCommand,
                    installDocumentation: $0.installDocumentation,
                    providerRiskLevel: $0.providerRiskLevel
                )
            }
            check.statuses.append(contentsOf: statuses)
        }

        if !check.statuses.filter(\.isError).isEmpty {
            check.errors.append(contentsOf: check.statuses.filter(\.isError).map { $0.name + ": " + $0.detail })
        }
        if settings.mongoMonitoring.enabled, settings.mongoMonitoring.captureMode.usesScriptKeyLogging {
            check.warnings.append("Terminal transcript monitoring is set to capture keyboard input and terminal output for launched workbench tabs.")
        }
        if settings.mongoMonitoring.enabled, settings.mongoMonitoring.enableMongoWrites, settings.mongoMonitoring.trimmedConnectionURL.isEmpty {
            check.errors.append("MongoDB monitoring is enabled but the connection URL is empty.")
        }
        if settings.mongoMonitoring.enabled, settings.mongoMonitoring.enableMongoWrites, settings.mongoMonitoring.mongoConnection.isLocal {
            if commandBuilder.resolvedExecutable(settings.mongoMonitoring.mongodExecutable) == nil {
                check.errors.append("Local MongoDB URL is configured, but mongod executable was not found. Set it in Monitoring settings.")
            }
            if settings.mongoMonitoring.expandedLocalDataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                check.errors.append("Local MongoDB URL is configured, but local Mongo data directory is empty.")
            }
        }

        do {
            _ = try planner.buildWorkbenchPlan(workbench: workbench, profiles: profiles, bookmarks: bookmarks, settings: settings)
        } catch {
            check.errors.append(error.localizedDescription)
        }

        return check
    }
}
