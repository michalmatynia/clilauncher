import AppKit
import SwiftUI

@MainActor
final class CLILauncherAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        scheduleActivationAttempts()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        scheduleActivationAttempts()
        return true
    }

    private func scheduleActivationAttempts() {
        for delay in [0.0, 0.15, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.activatePrimaryWindow()
            }
        }
    }

    private func activatePrimaryWindow() {
        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: \.isVisible) ?? NSApp.windows.first {
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct CLILauncherNativeApp: App {
    @NSApplicationDelegateAdaptor(CLILauncherAppDelegate.self) private var appDelegate
    @StateObject private var store = ProfileStore()
    @StateObject private var logger = LaunchLogger()
    @StateObject private var terminalMonitor = TerminalMonitorStore()

    var body: some Scene {
        WindowGroup {
            ContentView(
                logger: logger,
                terminalMonitor: terminalMonitor
            )
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
                .disabled(store.relaunchLastTarget() == nil)

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
