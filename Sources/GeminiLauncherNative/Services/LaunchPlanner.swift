import Foundation

struct LaunchPlanner {
    let commandBuilder = CommandBuilder()

    func buildPlan(primary: LaunchProfile, allProfiles: [LaunchProfile], settings: AppSettings) throws -> PlannedLaunch {
        let primaryResult = try commandBuilder.buildLaunchResult(profile: primary, settings: settings)
        var items = [
            PlannedLaunchItem(
                profileID: primary.id,
                profileName: primary.name,
                command: primaryResult.command,
                openMode: primary.openMode,
                terminalApp: primary.terminalApp,
                iTermProfile: primary.trimmedITermProfile,
                description: primaryResult.description
            )
        ]
        var actionProfiles: [LaunchProfile] = [primary]

        if primary.autoLaunchCompanions {
            let lookup = Dictionary(uniqueKeysWithValues: allProfiles.map { ($0.id, $0) })
            for companionID in primary.companionProfileIDs {
                guard let companion = lookup[companionID], companion.id != primary.id else { continue }
                let result = try commandBuilder.buildLaunchResult(profile: companion, settings: settings)
                items.append(
                    PlannedLaunchItem(
                        profileID: companion.id,
                        profileName: companion.name,
                        command: result.command,
                        openMode: .newTab,
                        terminalApp: companion.terminalApp,
                        iTermProfile: companion.trimmedITermProfile,
                        description: result.description
                    )
                )
                actionProfiles.append(companion)
            }
        }

        let postLaunchActions = buildPostLaunchActions(for: actionProfiles)
        return PlannedLaunch(items: items, postLaunchActions: postLaunchActions, tabLaunchDelayMs: max(0, primary.tabLaunchDelayMs))
    }

    func buildWorkbenchPlan(workbench: LaunchWorkbench, profiles: [LaunchProfile], bookmarks: [WorkspaceBookmark], settings: AppSettings) throws -> PlannedLaunch {
        let profileLookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let bookmarkLookup = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0) })

        guard !workbench.profileIDs.isEmpty else {
            throw LauncherError.validation("Workbench has no profiles selected.")
        }

        let sharedBookmark = workbench.sharedBookmarkID.flatMap { bookmarkLookup[$0] }
        if workbench.sharedBookmarkID != nil, sharedBookmark == nil {
            throw LauncherError.validation("Workbench shared workspace no longer exists.")
        }

        var items: [PlannedLaunchItem] = []
        var adjustedProfiles: [LaunchProfile] = []
        for (index, profileID) in workbench.profileIDs.enumerated() {
            guard let original = profileLookup[profileID] else { continue }
            let adjusted = applying(sharedBookmark: sharedBookmark, to: original)
            let result = try commandBuilder.buildLaunchResult(profile: adjusted, settings: settings)
            let label = sharedBookmark.map { "\(original.name) @ \($0.name)" } ?? original.name
            items.append(
                PlannedLaunchItem(
                    profileID: original.id,
                    profileName: label,
                    command: result.command,
                    openMode: index == 0 ? original.openMode : .newTab,
                    terminalApp: adjusted.terminalApp,
                    iTermProfile: adjusted.trimmedITermProfile,
                    description: result.description
                )
            )
            adjustedProfiles.append(adjusted)
        }

        guard !items.isEmpty else {
            throw LauncherError.validation("Workbench does not reference any existing profiles.")
        }

        let primaryDelay = max(0, workbench.startupDelayMs)
        return PlannedLaunch(items: items, postLaunchActions: buildPostLaunchActions(for: adjustedProfiles), tabLaunchDelayMs: max(0, primaryDelay))
    }

    private func buildPostLaunchActions(for profiles: [LaunchProfile]) -> [PostLaunchAction] {
        var seen: Set<String> = []
        var actions: [PostLaunchAction] = []

        for profile in profiles {
            let path = profile.expandedWorkingDirectory
            for app in profile.workspaceCompanionApps {
                let key = "\(app.rawValue)|\(path)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                actions.append(
                    PostLaunchAction(
                        app: app,
                        path: path,
                        label: "\(app.displayName) • \(URL(fileURLWithPath: path).lastPathComponent)"
                    )
                )
            }
        }

        return actions
    }

    private func applying(sharedBookmark: WorkspaceBookmark?, to profile: LaunchProfile) -> LaunchProfile {
        guard let sharedBookmark else { return profile }
        var adjusted = profile
        adjusted.workingDirectory = sharedBookmark.path
        adjusted.tags = Array(Set(adjusted.tags + sharedBookmark.tags)).sorted()
        return adjusted
    }
}
