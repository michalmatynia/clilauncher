import SwiftUI

@main
struct CLILauncherNativeApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var logger = LaunchLogger()
    @StateObject private var terminalMonitor = TerminalMonitorStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(logger)
                .environmentObject(terminalMonitor)
        }
        .windowStyle(.automatic)
        .commands {
            CommandMenu("Launcher") {
                Button("Refresh Diagnostics") {
                    NotificationCenter.default.post(name: .refreshDiagnosticsRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Relaunch Last") {
                    NotificationCenter.default.post(name: .relaunchLastRequested, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Toggle Automation") {
                    NotificationCenter.default.post(name: .toggleAutomationRequested, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Enable Automation") {
                    NotificationCenter.default.post(name: .enableAutomationRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Disable Automation") {
                    NotificationCenter.default.post(name: .disableAutomationRequested, object: nil)
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            }
        }
    }
}
