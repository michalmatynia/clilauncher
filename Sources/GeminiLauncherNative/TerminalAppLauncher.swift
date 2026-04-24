import Foundation

struct TerminalAppLauncher {
    private let executor = AppleScriptExecutionService()

    @MainActor
    func launch(plan: PlannedLaunch, logger: LaunchLogger? = nil, observability _: ObservabilitySettings = ObservabilitySettings()) throws {
        let delaySeconds = max(0.05, Double(plan.tabLaunchDelayMs) / 1_000.0)
        LaunchLoggerBridge.log(logger, .info, "Launching \(plan.items.count) Terminal.app session(s).", category: .iterm, details: "tabDelayMs=\(plan.tabLaunchDelayMs)")
        for (index, item) in plan.items.enumerated() {
            let scriptPath = LaunchScriptMaterializer.materialize(command: item.command)
            let source = buildAppleScript(scriptPath: scriptPath)
            do {
                _ = try executor.execute(source: source)
                LaunchLoggerBridge.debug(logger, "Terminal.app AppleScript executed.", category: .iterm, details: "profile=\(item.profileName) • script=\(scriptPath)")
            } catch {
                LaunchLoggerBridge.log(logger, .error, "Terminal.app AppleScript failed.", category: .iterm, details: error.localizedDescription)
                throw error
            }
            if index < plan.items.count - 1 {
                Thread.sleep(forTimeInterval: delaySeconds)
            }
        }
    }

    private func buildAppleScript(scriptPath: String) -> String {
        let escaped = scriptPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Terminal"
          activate
          do script "\(escaped)"
        end tell
        """
    }
}

struct TerminalLauncherDispatcher {
    private let iterm = ITerm2Launcher()
    private let terminal = TerminalAppLauncher()

    @MainActor
    func launch(plan: PlannedLaunch, logger: LaunchLogger? = nil, observability: ObservabilitySettings = ObservabilitySettings()) throws {
        guard !plan.items.isEmpty else { return }
        let groups = groupContiguous(items: plan.items)
        for group in groups {
            let subPlan = PlannedLaunch(items: group.items, postLaunchActions: [], tabLaunchDelayMs: plan.tabLaunchDelayMs)
            switch group.app {
            case .iterm2:
                try iterm.launch(plan: subPlan, logger: logger, observability: observability)

            case .terminal:
                try terminal.launch(plan: subPlan, logger: logger, observability: observability)
            }
        }
    }

    func buildAppleScript(plan: PlannedLaunch) -> String {
        iterm.buildAppleScript(plan: plan)
    }

    func diagnosticSnapshot(discoveredProfiles: [String], discoverySource: String) -> DiagnosticITermSnapshot {
        iterm.diagnosticSnapshot(discoveredProfiles: discoveredProfiles, discoverySource: discoverySource)
    }

    private struct Group { var app: TerminalApp; var items: [PlannedLaunchItem] }

    private func groupContiguous(items: [PlannedLaunchItem]) -> [Group] {
        var groups: [Group] = []
        for item in items {
            if !groups.isEmpty, groups[groups.count - 1].app == item.terminalApp {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(Group(app: item.terminalApp, items: [item]))
            }
        }
        return groups
    }
}
