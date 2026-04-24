import AppKit
import Foundation

struct WorkspaceCompanionLauncher {
    private let fileManager = FileManager.default

    func isAvailable(_ app: WorkspaceCompanionApp) -> Bool {
        switch app {
        case .finder:
            return true

        case .visualStudioCode:
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil
        }
    }

    func availableApps(for profile: LaunchProfile) -> [WorkspaceCompanionApp] {
        profile.workspaceCompanionApps.filter { isAvailable($0) }
    }

    func unavailableApps(for profile: LaunchProfile) -> [WorkspaceCompanionApp] {
        profile.workspaceCompanionApps.filter { !isAvailable($0) }
    }

    func perform(actions: [PostLaunchAction]) -> [String] {
        var performed: [String] = []
        for action in actions {
            if perform(action: action) {
                performed.append(action.label)
            }
        }
        return performed
    }

    @discardableResult
    func perform(action: PostLaunchAction) -> Bool {
        let expandedPath = NSString(string: action.path).expandingTildeInPath
        guard fileManager.fileExists(atPath: expandedPath) else { return false }
        let url = URL(fileURLWithPath: expandedPath)

        switch action.app {
        case .finder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true

        case .visualStudioCode:
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") else {
                return false
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, _ in }
            return true
        }
    }
}
