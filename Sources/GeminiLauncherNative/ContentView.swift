import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LaunchPreviewStore: ObservableObject {
    @Published var diagnostics = PreflightCheck()
    @Published var planPreview: PlannedLaunch?
    @Published var workbenchPlanPreview: PlannedLaunch?
    @Published var commandPreview: LaunchResult?
    @Published var selectedWorkbenchDiagnostics = PreflightCheck()
    @Published var availableITermProfiles: [String] = []
    @Published var iTermProfileSourceDescription: String = ""
    @Published var isVSCodeAvailable: Bool = false
}

struct ContentView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var logger: LaunchLogger
    @EnvironmentObject private var terminalMonitor: TerminalMonitorStore
    @StateObject private var preview = LaunchPreviewStore()

    @State private var selectedTab: LauncherTab = .launch
    @State private var bookmarkSelection: UUID?
    @State private var workbenchSelection: UUID?
    @State private var liveRefreshTask: Task<Void, Never>?
    @State private var showingDeleteProfileAlert = false
    @State private var showingDeleteWorkbenchAlert = false

    private let commandBuilder = CommandBuilder()
    private let planner = LaunchPlanner()
    private let preflight = PreflightService()
    private let iTermProfiles = ITerm2ProfileService()
    private let iTermLauncher = TerminalLauncherDispatcher()
    private let launcherExporter = LauncherExportService()
    private let companionLauncher = WorkspaceCompanionLauncher()

    var body: some View {
        TabView(selection: $selectedTab) {
            launchCenterTab
                .tabItem { Label("Launch", systemImage: "play.circle.fill") }
                .tag(LauncherTab.launch)

            profilesTab
                .tabItem { Label("Profiles", systemImage: "list.bullet.rectangle") }
                .tag(LauncherTab.profiles)

            workbenchesTab
                .tabItem { Label("Workbenches", systemImage: "square.stack.3d.up.fill") }
                .tag(LauncherTab.workbenches)

            workspacesTab
                .tabItem { Label("Workspaces", systemImage: "folder.badge.gearshape") }
                .tag(LauncherTab.workspaces)

            historyTab
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(LauncherTab.history)

            diagnosticsTab
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .tag(LauncherTab.diagnostics)

            monitoringTab
                .tabItem { Label("Monitoring", systemImage: "externaldrive.badge.timemachine") }
                .tag(LauncherTab.monitoring)

            keystrokesTab
                .tabItem { Label("Keystrokes", systemImage: "keyboard") }
                .tag(LauncherTab.keystrokes)

            logsTab
                .tabItem { Label("Log", systemImage: "text.append") }
                .tag(LauncherTab.logs)

            settingsTab
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(LauncherTab.settings)
        }
        .frame(minWidth: 1_240, minHeight: 820)
        .onAppear {
            logger.apply(settings: store.settings.observability)
            refreshLiveState()
            if selectedTab == .monitoring {
                terminalMonitor.refreshRecentSessions(settings: store.settings, logger: logger)
            }
        }
        .onDisappear {
            liveRefreshTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshDiagnosticsRequested)) { _ in
            scheduleLiveStateRefresh(immediate: true, includeITermDiscovery: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .relaunchLastRequested)) { _ in
            relaunchLast()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAutomationRequested)) { _ in
            toggleSelectedProfileAutomation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .enableAutomationRequested)) { _ in
            setSelectedProfileAutomation(enabled: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .disableAutomationRequested)) { _ in
            setSelectedProfileAutomation(enabled: false)
        }
        .onChange(of: selectedTab) { selection in
            if selection == .monitoring {
                terminalMonitor.refreshRecentSessions(settings: store.settings, logger: logger)
            } else if selection == .launch {
                scheduleLiveStateRefresh(immediate: true, includeITermDiscovery: true)
            } else if selection == .workbenches {
                scheduleLiveStateRefresh(immediate: true)
            }
        }
        .onChange(of: store.selectedProfileID) { _ in scheduleLiveStateRefresh(immediate: true) }
        .onChange(of: workbenchSelection) { _ in scheduleLiveStateRefresh(immediate: true) }
        .onChange(of: store.settings.observability) { _ in
            logger.apply(settings: store.settings.observability)
        }
        .onChange(of: liveRefreshSettingsSignature) { _ in scheduleLiveStateRefresh() }
        .onChange(of: selectedProfilePlanRefreshSignature) { _ in scheduleLiveStateRefresh() }
        .onChange(of: selectedWorkbenchPlanRefreshSignature) { _ in scheduleLiveStateRefresh() }
    }

    private var selectedProfileBinding: Binding<LaunchProfile>? {
        guard store.selectedIndex != nil else { return nil }
        return Binding(
            get: {
                guard let index = store.selectedIndex else {
                    return ProfileStore.fallbackStarterProfile(settings: store.settings)
                }
                return store.profiles[index]
            },
            set: { newValue in
                store.updateSelected { updated in
                    updated = newValue
                }
            }
        )
    }

    private var selectedBookmarkBinding: Binding<WorkspaceBookmark>? {
        guard let bookmarkSelection, let index = store.bookmarks.firstIndex(where: { $0.id == bookmarkSelection }) else { return nil }
        return Binding(
            get: { store.bookmarks[index] },
            set: { store.bookmarks[index] = $0 }
        )
    }

    private var selectedWorkbenchBinding: Binding<LaunchWorkbench>? {
        guard let workbenchSelection, let index = store.workbenches.firstIndex(where: { $0.id == workbenchSelection }) else { return nil }
        return Binding(
            get: { store.workbenches[index] },
            set: { store.workbenches[index] = $0 }
        )
    }

    private var selectedWorkbench: LaunchWorkbench? {
        guard let workbenchSelection else { return nil }
        return store.workbenches.first { $0.id == workbenchSelection }
    }

    private var shouldRefreshLiveState: Bool {
        selectedTab == .launch || selectedTab == .workbenches
    }

    private var liveRefreshSettingsSignature: String {
        [
            store.settings.defaultShellBootstrapCommand,
            store.settings.defaultNodeExecutable,
            store.settings.defaultGeminiRunnerPath
        ].joined(separator: "\u{1F}")
    }

    private var selectedProfilePlanRefreshSignature: String {
        guard let profile = store.selectedProfile else { return "none" }

        var components = [profileLaunchSignature(for: profile)]
        if profile.autoLaunchCompanions {
            components.append(contentsOf: profile.companionProfileIDs.map { profileID in
                if let companion = store.profiles.first(where: { $0.id == profileID }) {
                    return profileLaunchSignature(for: companion)
                }
                return "missing-profile:\(profileID.uuidString)"
            })
        }
        return components.joined(separator: "\u{1E}")
    }

    private var selectedWorkbenchPlanRefreshSignature: String {
        guard let workbench = selectedWorkbench else { return "none" }

        var components = [
            workbench.role.rawValue,
            String(workbench.startupDelayMs),
            workbench.postLaunchActionHints.joined(separator: "\u{1F}"),
            workbench.profileIDs.map(\.uuidString).joined(separator: "\u{1F}"),
            workbench.sharedBookmarkID?.uuidString ?? ""
        ]

        components.append(contentsOf: workbench.profileIDs.map { profileID in
            if let profile = store.profiles.first(where: { $0.id == profileID }) {
                return profileLaunchSignature(for: profile)
            }
            return "missing-profile:\(profileID.uuidString)"
        })

        if let bookmarkID = workbench.sharedBookmarkID {
            if let bookmark = store.bookmarks.first(where: { $0.id == bookmarkID }) {
                components.append("bookmark:\(bookmark.expandedPath)")
            } else {
                components.append("missing-bookmark:\(bookmarkID.uuidString)")
            }
        }

        return components.joined(separator: "\u{1E}")
    }

    private var selectedEnvironmentPreset: EnvironmentPreset? {
        guard let presetID = store.selectedProfile?.environmentPresetID else { return nil }
        return store.settings.environmentPresets.first { $0.id == presetID }
    }

    private var selectedBootstrapPreset: ShellBootstrapPreset? {
        guard let presetID = store.selectedProfile?.bootstrapPresetID else { return nil }
        return store.settings.shellBootstrapPresets.first { $0.id == presetID }
    }

    private var featuredWorkbenches: [LaunchWorkbench] {
        let favorites = store.workbenches.filter { $0.tags.contains { $0.lowercased() == "favorite" } }
        if !favorites.isEmpty { return Array(favorites.prefix(4)) }
        return Array(store.workbenches.prefix(4))
    }

    private func profileLaunchSignature(for profile: LaunchProfile) -> String {
        let selectedEnvironmentPresetSignature: String
        if let presetID = profile.environmentPresetID {
            if let preset = store.settings.environmentPresets.first(where: { $0.id == presetID }) {
                selectedEnvironmentPresetSignature = [
                    presetID.uuidString,
                    environmentEntriesSignature(preset.entries)
                ].joined(separator: "\u{1F}")
            } else {
                selectedEnvironmentPresetSignature = "missing-environment-preset:\(presetID.uuidString)"
            }
        } else {
            selectedEnvironmentPresetSignature = ""
        }

        let selectedBootstrapPresetSignature: String
        if let presetID = profile.bootstrapPresetID {
            if let preset = store.settings.shellBootstrapPresets.first(where: { $0.id == presetID }) {
                selectedBootstrapPresetSignature = [
                    presetID.uuidString,
                    preset.trimmedCommand
                ].joined(separator: "\u{1F}")
            } else {
                selectedBootstrapPresetSignature = "missing-bootstrap-preset:\(presetID.uuidString)"
            }
        } else {
            selectedBootstrapPresetSignature = ""
        }

        var components = [
            profile.id.uuidString,
            profile.agentKind.rawValue,
            profile.workingDirectory,
            profile.terminalApp.rawValue,
            profile.iTermProfile,
            profile.openMode.rawValue,
            profile.extraCLIArgs,
            profile.shellBootstrapCommand,
            String(profile.openWorkspaceInFinderOnLaunch),
            String(profile.openWorkspaceInVSCodeOnLaunch),
            String(profile.tabLaunchDelayMs),
            environmentEntriesSignature(profile.environmentEntries),
            selectedEnvironmentPresetSignature,
            selectedBootstrapPresetSignature,
            String(profile.autoLaunchCompanions),
            profile.autoLaunchCompanions ? profile.companionProfileIDs.map(\.uuidString).joined(separator: "\u{1F}") : ""
        ]

        components.append(contentsOf: [
            profile.geminiFlavor.rawValue,
            profile.geminiLaunchMode.rawValue,
            profile.geminiWrapperCommand,
            profile.geminiISOHome,
            profile.geminiInitialModel,
            profile.geminiModelChain,
            String(profile.geminiResumeLatest),
            String(profile.geminiKeepTryMax),
            profile.geminiAutoContinueMode.rawValue,
            String(profile.geminiAutoAllowSessionPermissions),
            String(profile.geminiAutomationEnabled),
            String(profile.geminiNeverSwitch),
            String(profile.geminiQuietChildNodeWarnings),
            String(profile.geminiRawOutput),
            String(profile.geminiManualOverrideMs),
            profile.geminiHotkeyPrefix,
            profile.geminiAutomationRunnerPath,
            profile.nodeExecutable,
            profile.copilotExecutable,
            profile.copilotMode.rawValue,
            profile.copilotModel,
            profile.copilotHome,
            profile.copilotInitialPrompt,
            String(profile.copilotMaxAutopilotContinues),
            profile.codexExecutable,
            profile.codexMode.rawValue,
            profile.codexModel,
            profile.claudeExecutable,
            profile.claudeModel,
            profile.kiroExecutable,
            profile.kiroMode.rawValue,
            profile.ollamaExecutable,
            profile.ollamaIntegration.rawValue,
            profile.ollamaModel,
            String(profile.ollamaConfigOnly)
        ])

        return components.joined(separator: "\u{1E}")
    }

    private func environmentEntriesSignature(_ entries: [EnvironmentEntry]) -> String {
        entries
            .map { "\($0.key)\u{1F}\($0.value)" }
            .sorted()
            .joined(separator: "\u{1E}")
    }

    private var launchCenterTab: some View {
        LaunchCenterPane(
            preview: preview,
            profile: store.selectedProfile,
            selectedEnvironmentPreset: selectedEnvironmentPreset,
            selectedBootstrapPreset: selectedBootstrapPreset,
            featuredWorkbenches: featuredWorkbenches,
            bookmarks: store.bookmarks,
            cautionMessages: store.selectedProfile.map { LaunchTemplateCatalog.cautions(for: $0) } ?? [],
            isVSCodeAvailable: preview.isVSCodeAvailable,
            favoriteProfiles: store.profiles.filter(\.isFavorite),
            launchSelectedProfile: launchSelectedProfile,
            duplicateSelectedProfile: store.duplicateSelectedProfile,
            applyPreset: { preset in
                store.updateSelected { $0.applyBehaviorPreset(preset) }
            },
            bookmarkWorkspace: {
                guard let profile = store.selectedProfile else { return }
                store.addBookmark(from: profile)
            },
            revealWorkspace: {
                guard let profile = store.selectedProfile else { return }
                store.reveal(profile.expandedWorkingDirectory)
            },
            openInFinder: {
                guard let profile = store.selectedProfile else { return }
                openWorkspaceNow(profile, app: .finder)
            },
            openInVSCode: {
                guard let profile = store.selectedProfile else { return }
                openWorkspaceNow(profile, app: .visualStudioCode)
            },
            exportSelectedProfileLauncher: exportSelectedProfileLauncher,
            launchQuick: launchQuick,
            launchFavorite: { profile in
                store.selectedProfileID = profile.id
                launchSelectedProfile()
            },
            createWorkbenchFromCurrentProfile: addWorkbenchFromCurrentSelection,
            launchWorkbench: launch,
            editWorkbench: { workbenchID in
                workbenchSelection = workbenchID
                selectedTab = .workbenches
            },
            copyCombinedCommands: {
                guard let plan = preview.planPreview else { return }
                ClipboardService.copy(plan.combinedCommandPreview)
                logger.log(.info, "Copied combined launch plan.")
            },
            copyAppleScript: {
                guard let plan = preview.planPreview else { return }
                ClipboardService.copy(iTermLauncher.buildAppleScript(plan: plan))
                logger.log(.info, "Copied combined AppleScript preview.")
            },
            exportPlanLauncher: {
                guard let plan = preview.planPreview else { return }
                exportLauncher(plan: plan, suggestedName: (store.selectedProfile?.name ?? "Launch") + ".command")
            },
            toggleAutomation: toggleSelectedProfileAutomation
        )
    }

    private var profilesTab: some View {
        HSplitView {
            ProfilesSidebarPane(
                profiles: store.profiles,
                selectedProfileID: $store.selectedProfileID,
                addProfile: { kind in
                    store.addProfile(kind: kind)
                },
                duplicateProfile: { profile in
                    store.selectedProfileID = profile.id
                    store.duplicateSelectedProfile()
                },
                bookmarkProfile: { profile in
                    store.addBookmark(from: profile)
                }
            )
            .frame(minWidth: 280, maxWidth: 340)

            if let profile = selectedProfileBinding {
                profileEditor(profile: profile)
                    .frame(minWidth: 760)
            } else {
                unavailablePlaceholder("No profile selected", systemImage: "person.crop.rectangle.stack", message: "Choose a profile from the list or create a new one.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Delete profile?", isPresented: $showingDeleteProfileAlert) {
            Button("Delete", role: .destructive) { store.removeSelectedProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected profile will be removed.")
        }
    }

    private func profileEditor(profile: Binding<LaunchProfile>) -> some View {
        ProfileEditorPane(
            profile: profile,
            preview: preview,
            environmentPresets: store.settings.environmentPresets,
            shellBootstrapPresets: store.settings.shellBootstrapPresets,
            defaultWorkingDirectory: store.settings.defaultWorkingDirectory,
            companionProfiles: store.profiles.filter { $0.id != profile.wrappedValue.id },
            mergedEnvironmentSummary: mergedEnvironmentSummary(for: profile.wrappedValue),
            parseTags: parseTags,
            chooseWorkingDirectory: {
                if let path = FilePanelService.chooseDirectory() {
                    profile.wrappedValue.workingDirectory = path
                }
            },
            useDefaultWorkingDirectory: {
                profile.wrappedValue.workingDirectory = store.settings.defaultWorkingDirectory
            },
                                revealWorkingDirectory: {
                                    store.reveal(profile.wrappedValue.expandedWorkingDirectory)
                                },
                                revealISO: {
                                    store.reveal(profile.wrappedValue.expandedGeminiISOHome)
                                },
                                manageSharedPresets: {
                                    selectedTab = .settings
                                }, onAgentKindChanged: { newValue in
                store.updateSelected { updated in
                    updated.agentKind = newValue
                    updated.applyKindDefaults(settings: store.settings)
                }
                                },
            onGeminiFlavorChanged: {
                store.updateSelected { updated in
                    updated.applyGeminiFlavorDefaults()
                }
            },
            launchSelectedProfile: launchSelectedProfile,
            duplicateSelectedProfile: store.duplicateSelectedProfile,
            applyPreset: { preset in
                profile.wrappedValue.applyBehaviorPreset(preset)
            },
            bookmarkWorkspace: {
                store.addBookmark(from: profile.wrappedValue)
            },
            deleteProfile: {
                showingDeleteProfileAlert = true
            },
            copyCommand: {
                guard let commandPreview = preview.commandPreview else { return }
                ClipboardService.copy(commandPreview.command)
                logger.log(.info, "Copied command preview.")
            },
            copyAppleScript: {
                guard let commandPreview = preview.commandPreview else { return }
                ClipboardService.copy(commandPreview.appleScript)
                logger.log(.info, "Copied AppleScript preview.")
            },
            exportLauncher: {
                exportLauncherForProfile(profile.wrappedValue)
            }
        )
    }

    private var workbenchesTab: some View {
        HSplitView {
            WorkbenchSidebarPane(
                workbenches: store.workbenches,
                selection: $workbenchSelection,
                createWorkbench: addWorkbenchFromCurrentSelection
            )
            .frame(minWidth: 280, maxWidth: 340)

            if let workbench = selectedWorkbenchBinding {
                WorkbenchEditorPane(
                    workbench: workbench,
                    preview: preview,
                    profiles: store.profiles,
                    bookmarks: store.bookmarks,
                    parseTags: parseTags,
                    membershipBinding: { profileID in
                        workbenchMembershipBinding(workbenchID: workbench.wrappedValue.id, profileID: profileID)
                    },
                    launchWorkbench: {
                        launch(workbench: workbench.wrappedValue)
                    },
                    duplicateWorkbench: {
                        if let copy = store.duplicateWorkbench(workbench.wrappedValue.id) {
                            workbenchSelection = copy.id
                        }
                    },
                    deleteWorkbench: {
                        showingDeleteWorkbenchAlert = true
                    },
                    moveProfile: { profileID, direction in
                        moveWorkbenchProfile(workbenchID: workbench.wrappedValue.id, profileID: profileID, direction: direction)
                    },
                    removeProfile: { profileID in
                        removeProfileFromWorkbench(workbenchID: workbench.wrappedValue.id, profileID: profileID)
                    },
                    copyCombinedCommands: {
                        guard let plan = preview.workbenchPlanPreview else { return }
                        ClipboardService.copy(plan.combinedCommandPreview)
                        logger.log(.info, "Copied workbench launch plan.")
                    },
                    copyAppleScript: {
                        guard let plan = preview.workbenchPlanPreview else { return }
                        ClipboardService.copy(iTermLauncher.buildAppleScript(plan: plan))
                        logger.log(.info, "Copied workbench AppleScript preview.")
                    },
                    exportLauncher: {
                        guard let plan = preview.workbenchPlanPreview else { return }
                        exportLauncher(plan: plan, suggestedName: workbench.wrappedValue.name + ".command")
                    }
                )
            } else {
                unavailablePlaceholder("No workbench selected", systemImage: "square.stack.3d.up", message: "Select a workbench from the list or create a new one.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Delete workbench?", isPresented: $showingDeleteWorkbenchAlert) {
            Button("Delete", role: .destructive) {
                if let workbenchSelection {
                    store.removeWorkbench(workbenchSelection)
                    self.workbenchSelection = store.workbenches.first?.id
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected workbench will be removed.")
        }
    }

    private var workspacesTab: some View {
        HSplitView {
            WorkspaceBookmarksSidebarPane(
                bookmarks: store.bookmarks,
                selection: $bookmarkSelection,
                addBookmark: addWorkspaceBookmarkFromChooser
            )
            .frame(minWidth: 280, maxWidth: 340)

            if let bookmark = selectedBookmarkBinding {
                WorkspaceBookmarkEditorPane(
                    bookmark: bookmark,
                    profiles: store.profiles,
                    parseTags: parseTags,
                    chooseDirectory: {
                        if let path = FilePanelService.chooseDirectory() {
                            bookmark.wrappedValue.path = path
                        }
                    },
                    revealBookmark: {
                        store.reveal(bookmark.wrappedValue.expandedPath)
                    },
                    applyToSelectedProfile: {
                        guard let profileID = store.selectedProfileID else { return }
                        store.apply(bookmark: bookmark.wrappedValue, to: profileID)
                        logger.log(.success, "Applied bookmark to selected profile.")
                    },
                    createWorkbenchHere: {
                        createWorkbenchFromSelectedBookmark(bookmark.wrappedValue)
                    },
                    launchDefaultProfileHere: {
                        launchBookmark(bookmark.wrappedValue)
                    },
                    deleteBookmark: {
                        store.removeBookmark(bookmark.wrappedValue)
                        bookmarkSelection = store.bookmarks.first?.id
                    }
                )
            } else {
                unavailablePlaceholder("No workspace selected", systemImage: "folder", message: "Select a workspace bookmark from the list or add one.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var historyTab: some View {
        HistoryTabPane(
            history: store.history,
            relaunchLast: relaunchLast
        )
    }

    private var diagnosticsTab: some View {
        DiagnosticsTabPane(
            preview: preview
        )
    }

    private var logsTab: some View {
        LogsTabPane(
            logger: logger,
            exportVisibleLogs: { entries in
                exportLogs(entries)
            },
            exportDiagnostics: exportDiagnostics
        )
    }

    private var monitoringTab: some View {
        MonitoringDashboardView()
    }

    private var keystrokesTab: some View {
        KeystrokesTabPane(
            selectedProfileName: store.selectedProfile?.name,
            activeProfilePrefix: resolvedProfileHotkeyPrefix,
            selectedProfileAutomationMode: store.selectedProfile?.agentKind == .gemini ? store.selectedProfile?.geminiLaunchMode : nil,
            selectedProfileAutomationEnabled: store.selectedProfile?.agentKind == .gemini ? store.selectedProfile?.geminiAutomationEnabled : nil,
            defaultHotkeyPrefix: store.settings.defaultHotkeyPrefix,
            canToggleAutomation: store.selectedProfile?.agentKind == .gemini
        ) { value in
                setSelectedProfileAutomation(enabled: value)
        }
    }

    private var settingsTab: some View {
        SettingsTabPane(
            store: store,
            logger: logger,
            terminalMonitor: terminalMonitor,
            captureEnvironmentPresetFromSelectedProfile: captureEnvironmentPresetFromSelectedProfile,
            captureBootstrapPresetFromSelectedProfile: captureBootstrapPresetFromSelectedProfile,
            exportState: exportState,
            importState: importState
        )
    }

    private var resolvedProfileHotkeyPrefix: String {
        guard let profile = store.selectedProfile, profile.agentKind == .gemini else { return store.settings.defaultHotkeyPrefix }
        let configured = profile.geminiHotkeyPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.isEmpty ? store.settings.defaultHotkeyPrefix : configured
    }

    private func parseTags(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func mergedEnvironmentSummary(for profile: LaunchProfile) -> String {
        let presetCount = store.settings.environmentPresets.first { $0.id == profile.environmentPresetID }?.entries.count ?? 0
        let profileCount = profile.environmentEntries.filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        let total = commandBuilder.buildEnvironment(profile: profile, settings: store.settings).count
        return "Shared: \(presetCount) • Profile: \(profileCount) • Effective: \(total)"
    }

    private func captureEnvironmentPresetFromSelectedProfile() {
        guard let profile = store.selectedProfile else { return }
        let entries = profile.environmentEntries.filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var preset = EnvironmentPreset()
        preset.name = profile.name + " Env"
        preset.notes = profile.notes
        preset.entries = entries
        store.settings.environmentPresets.insert(preset, at: 0)
        store.updateSelected { $0.environmentPresetID = preset.id }
        logger.log(.success, "Captured shared environment preset from \(profile.name).")
    }

    private func captureBootstrapPresetFromSelectedProfile() {
        guard let profile = store.selectedProfile else { return }
        let command = profile.trimmedShellBootstrapCommand
        guard !command.isEmpty else {
            logger.log(.warning, "Selected profile does not have a shell bootstrap command to capture.")
            return
        }
        var preset = ShellBootstrapPreset()
        preset.name = profile.name + " Bootstrap"
        preset.notes = profile.notes
        preset.command = command
        store.settings.shellBootstrapPresets.insert(preset, at: 0)
        store.updateSelected { $0.bootstrapPresetID = preset.id }
        logger.log(.success, "Captured shared shell bootstrap preset from \(profile.name).")
    }

    private func scheduleLiveStateRefresh(immediate: Bool = false, includeITermDiscovery: Bool = false) {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard !Task.isCancelled else { return }
            guard shouldRefreshLiveState else { return }
            refreshLiveState(includeITermDiscovery: includeITermDiscovery)
        }
    }

    private func refreshLiveState(includeITermDiscovery: Bool = true) {
        logger.apply(settings: store.settings.observability)
        synchronizeEditorSelections()
        refreshSelectedProfileLiveState()
        refreshSelectedWorkbenchLiveState()
        refreshITermProfileDiscovery(includeITermDiscovery: includeITermDiscovery)
        preview.isVSCodeAvailable = companionLauncher.isAvailable(.visualStudioCode)
    }

    private func synchronizeEditorSelections() {
        if bookmarkSelection == nil || !store.bookmarks.contains(where: { $0.id == bookmarkSelection }) {
            bookmarkSelection = store.bookmarks.first?.id
        }
        if workbenchSelection == nil || !store.workbenches.contains(where: { $0.id == workbenchSelection }) {
            workbenchSelection = store.workbenches.first?.id
        }
    }

    private func refreshSelectedProfileLiveState() {
        guard let profile = store.selectedProfile else {
            preview.diagnostics = PreflightCheck()
            preview.planPreview = nil
            preview.commandPreview = nil
            return
        }
        preview.diagnostics = preflight.run(profile: profile, settings: store.settings, allProfiles: store.profiles)
        preview.planPreview = try? planner.buildPlan(primary: profile, allProfiles: store.profiles, settings: store.settings)
        preview.commandPreview = try? commandBuilder.buildLaunchResult(profile: profile, settings: store.settings)
    }

    private func refreshSelectedWorkbenchLiveState() {
        guard let workbench = selectedWorkbench else {
            preview.selectedWorkbenchDiagnostics = PreflightCheck()
            preview.workbenchPlanPreview = nil
            return
        }
        preview.selectedWorkbenchDiagnostics = preflight.run(workbench: workbench, profiles: store.profiles, bookmarks: store.bookmarks, settings: store.settings)
        preview.workbenchPlanPreview = try? planner.buildWorkbenchPlan(workbench: workbench, profiles: store.profiles, bookmarks: store.bookmarks, settings: store.settings)
    }

    private func refreshITermProfileDiscovery(includeITermDiscovery: Bool) {
        if includeITermDiscovery {
            do {
                let discovery = try iTermProfiles.fetchProfiles()
                preview.availableITermProfiles = discovery.names
                preview.iTermProfileSourceDescription = discovery.sourceDescription
            } catch {
                logger.log(.warning, "Failed to read iTerm2 profiles: \(error.localizedDescription)", category: .iterm)
                preview.availableITermProfiles = []
                preview.iTermProfileSourceDescription = "Profile discovery failed: \(error.localizedDescription)"
            }
        }
    }

    private func launchQuick(_ template: LaunchTemplate) {
        launch(profile: template.buildProfile(using: store.settings), recordHistory: false)
    }

    private func launchSelectedProfile() {
        guard let profile = store.selectedProfile else { return }
        launch(profile: profile, recordHistory: true)
    }

    private func launch(profile: LaunchProfile, recordHistory: Bool) {
        logger.log(.info, "Launch requested for \(profile.name).", category: .launch, details: "agent=\(profile.agentKind.displayName) • openMode=\(profile.openMode.displayName) • workdir=\(profile.expandedWorkingDirectory)")
        do {
            let basePlan = try planner.buildPlan(primary: profile, allProfiles: store.profiles, settings: store.settings)
            logger.debug("Built launch plan for \(profile.name).", category: .launch, details: basePlan.combinedCommandPreview)
            if store.settings.confirmBeforeLaunch, !confirmLaunch(plan: basePlan, profile: profile) {
                logger.log(.info, "Launch cancelled.", category: .launch)
                return
            }
            if !preview.diagnostics.isPassing, profile.id == store.selectedProfileID {
                let detail = ([preview.diagnostics.errors.joined(separator: " | "), preview.diagnostics.warnings.joined(separator: " | ")].filter { !$0.isEmpty }).joined(separator: " • ")
                logger.log(.warning, "Launching despite preflight issues.", category: .preflight, details: detail.isEmpty ? nil : detail)
            }

            let monitoredPlan = try terminalMonitor.prepare(plan: basePlan, profiles: store.profiles, settings: store.settings, logger: logger)
            do {
                try iTermLauncher.launch(plan: monitoredPlan, logger: logger, observability: store.settings.observability)
                terminalMonitor.activatePreparedSessions(for: monitoredPlan, settings: store.settings, logger: logger)
                let performedActions = performPostLaunchActions(for: monitoredPlan)
                logger.log(.success, "Opened \(monitoredPlan.items.count) iTerm2 tab(s) for \(profile.name)." + (performedActions.isEmpty ? "" : " Also ran \(performedActions.count) post-launch action(s)."), category: .launch)
                if recordHistory {
                    store.recordLaunch(profile: profile, plan: monitoredPlan)
                }
                for bookmark in store.bookmarks where bookmark.expandedPath == profile.expandedWorkingDirectory {
                    store.touchBookmark(bookmark.id)
                }
            } catch {
                terminalMonitor.cancelPreparedSessions(for: monitoredPlan, reason: error.localizedDescription, settings: store.settings, logger: logger)
                logger.log(.error, "Launch failed after preparation.", category: .launch, details: error.localizedDescription)
                throw error
            }
        } catch {
            logger.log(.error, "Launch failed before iTerm2 could open.", category: .launch, details: error.localizedDescription)
        }
    }

    private func confirmLaunch(plan: PlannedLaunch, profile: LaunchProfile) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Launch \(profile.name)?"
        alert.informativeText = "This will open \(plan.items.count) iTerm2 tab(s) starting in \(profile.expandedWorkingDirectory)." + (plan.postLaunchActions.isEmpty ? "" : " It will also run \(plan.postLaunchActions.count) post-launch workspace action(s).")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Launch")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func addWorkspaceBookmarkFromChooser() {
        guard let path = FilePanelService.chooseDirectory() else { return }
        let name = URL(fileURLWithPath: path).lastPathComponent
        store.addBookmark(name: name, path: path, defaultProfileID: store.selectedProfileID)
        bookmarkSelection = store.bookmarks.first?.id
    }

    private func launchBookmark(_ bookmark: WorkspaceBookmark) {
        let baseProfile: LaunchProfile
        if let defaultID = bookmark.defaultProfileID, let existing = store.profiles.first(where: { $0.id == defaultID }) {
            baseProfile = existing
        } else if let current = store.selectedProfile {
            baseProfile = current
        } else {
            baseProfile = ProfileStore.fallbackStarterProfile(settings: store.settings)
        }
        var profile = baseProfile
        profile.workingDirectory = bookmark.path
        profile.name = baseProfile.name + " @ " + bookmark.name
        launch(profile: profile, recordHistory: false)
        store.touchBookmark(bookmark.id)
    }

    private func relaunchLast() {
        guard let latest = store.history.first else {
            logger.log(.info, "No launch history available yet.")
            return
        }
        if let profileID = latest.profileID, let profile = store.profiles.first(where: { $0.id == profileID }) {
            launch(profile: profile, recordHistory: true)
        } else {
            logger.log(.warning, "Last launch profile is no longer available.")
        }
    }

    private func toggleSelectedProfileAutomation() {
        guard let profile = store.selectedProfile else { return }
        if profile.agentKind == .gemini {
            store.updateSelected { $0.geminiAutomationEnabled.toggle() }
            let newState = store.selectedProfile?.geminiAutomationEnabled ?? false
            logger.log(.info, "Automation \(newState ? "enabled" : "disabled") for '\(profile.name)'.", category: .app)
            scheduleLiveStateRefresh(immediate: true)
        } else {
            logger.log(.warning, "Automation toggling is only supported for Gemini profiles.", category: .app)
        }
    }

    private func setSelectedProfileAutomation(enabled: Bool) {
        guard let profile = store.selectedProfile else {
            logger.log(.warning, "No selected profile to change automation state.")
            return
        }
        guard profile.agentKind == .gemini else {
            logger.log(.warning, "Automation state changes are only supported for Gemini profiles.")
            return
        }
        guard profile.geminiAutomationEnabled != enabled else {
            logger.log(.info, "Automation is already \(enabled ? "enabled" : "disabled") for '\(profile.name)'.", category: .app)
            return
        }

        store.updateSelected { $0.geminiAutomationEnabled = enabled }
        logger.log(.info, "Automation \(enabled ? "enabled" : "disabled") for '\(profile.name)'.", category: .app)
        scheduleLiveStateRefresh(immediate: true)
    }

    private func addWorkbenchFromCurrentSelection() {
        let workbench = store.addWorkbench(seedProfileID: store.selectedProfileID, sharedBookmarkID: bookmarkSelection)
        workbenchSelection = workbench.id
        selectedTab = .workbenches
        logger.log(.success, "Created a new workbench.")
    }

    private func createWorkbenchFromSelectedBookmark(_ bookmark: WorkspaceBookmark) {
        let workbench = store.addWorkbench(seedProfileID: bookmark.defaultProfileID ?? store.selectedProfileID, sharedBookmarkID: bookmark.id)
        if workbench.profileIDs.isEmpty, let firstProfile = store.profiles.first?.id {
            if let index = store.workbenches.firstIndex(where: { $0.id == workbench.id }) {
                store.workbenches[index].profileIDs = [firstProfile]
            }
        }
        workbenchSelection = workbench.id
        selectedTab = .workbenches
        logger.log(.success, "Created a workbench for \(bookmark.name).")
    }

    private func launch(workbench: LaunchWorkbench) {
        logger.log(
            .info,
            "Workbench launch requested for \(workbench.name).",
            category: .launch,
            details: "profiles=\(workbench.profileIDs.count), role=\(workbench.role.rawValue), startupDelayMs=\(workbench.startupDelayMs)"
        )
        do {
            let basePlan = try planner.buildWorkbenchPlan(workbench: workbench, profiles: store.profiles, bookmarks: store.bookmarks, settings: store.settings)
            logger.debug("Built workbench launch plan for \(workbench.name).", category: .launch, details: basePlan.combinedCommandPreview)
            if store.settings.confirmBeforeLaunch, !confirmLaunch(workbench: workbench, plan: basePlan) {
                logger.log(.info, "Launch cancelled.", category: .launch)
                return
            }
            let workbenchDiagnostics = preflight.run(workbench: workbench, profiles: store.profiles, bookmarks: store.bookmarks, settings: store.settings)
            if !workbenchDiagnostics.isPassing {
                let detail = ([workbenchDiagnostics.errors.joined(separator: " | "), workbenchDiagnostics.warnings.joined(separator: " | ")].filter { !$0.isEmpty }).joined(separator: " • ")
                logger.log(.warning, "Launching workbench despite preflight issues.", category: .preflight, details: detail.isEmpty ? nil : detail)
            }

            let monitoredPlan = try terminalMonitor.prepare(plan: basePlan, profiles: store.profiles, settings: store.settings, logger: logger)
            do {
                try iTermLauncher.launch(plan: monitoredPlan, logger: logger, observability: store.settings.observability)
                terminalMonitor.activatePreparedSessions(for: monitoredPlan, settings: store.settings, logger: logger)
                let performedActions = performPostLaunchActions(for: monitoredPlan)
                logger.log(.success, "Opened \(monitoredPlan.items.count) iTerm2 tab(s) for workbench \(workbench.name)." + (performedActions.isEmpty ? "" : " Also ran \(performedActions.count) post-launch action(s)."), category: .launch)
                store.recordLaunch(workbench: workbench, plan: monitoredPlan)
                store.touchWorkbench(workbench.id)
                if let sharedBookmarkID = workbench.sharedBookmarkID {
                    store.touchBookmark(sharedBookmarkID)
                }
            } catch {
                terminalMonitor.cancelPreparedSessions(for: monitoredPlan, reason: error.localizedDescription, settings: store.settings, logger: logger)
                logger.log(.error, "Workbench launch failed after preparation.", category: .launch, details: error.localizedDescription)
                throw error
            }
        } catch {
            logger.log(.error, "Workbench launch failed before iTerm2 could open.", category: .launch, details: error.localizedDescription)
        }
    }

    private func confirmLaunch(workbench: LaunchWorkbench, plan: PlannedLaunch) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Launch \(workbench.name)?"
        alert.informativeText = "This workbench will open \(plan.items.count) iTerm2 tab(s) in role \(workbench.role.displayName) with a startup delay of \(workbench.startupDelayMs)ms." + (plan.postLaunchActions.isEmpty ? "" : " It will also run \(plan.postLaunchActions.count) post-launch workspace action(s).")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Launch")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func workbenchMembershipBinding(workbenchID: UUID, profileID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                store.workbenches.first { $0.id == workbenchID }?.profileIDs.contains(profileID) == true
            },
            set: { enabled in
                guard let index = store.workbenches.firstIndex(where: { $0.id == workbenchID }) else { return }
                if enabled {
                    if !store.workbenches[index].profileIDs.contains(profileID) {
                        store.workbenches[index].profileIDs.append(profileID)
                    }
                } else {
                    store.workbenches[index].profileIDs.removeAll { $0 == profileID }
                }
            }
        )
    }

    private func moveWorkbenchProfile(workbenchID: UUID, profileID: UUID, direction: Int) {
        guard let index = store.workbenches.firstIndex(where: { $0.id == workbenchID }),
              let current = store.workbenches[index].profileIDs.firstIndex(of: profileID) else { return }
        let destination = current + direction
        guard destination >= 0, destination < store.workbenches[index].profileIDs.count else { return }
        let moved = store.workbenches[index].profileIDs.remove(at: current)
        store.workbenches[index].profileIDs.insert(moved, at: destination)
    }

    private func removeProfileFromWorkbench(workbenchID: UUID, profileID: UUID) {
        guard let index = store.workbenches.firstIndex(where: { $0.id == workbenchID }) else { return }
        store.workbenches[index].profileIDs.removeAll { $0 == profileID }
    }

    @discardableResult
    private func performPostLaunchActions(for plan: PlannedLaunch) -> [String] {
        let performed = companionLauncher.perform(actions: plan.postLaunchActions)
        for label in performed {
            logger.log(.info, "Post-launch action completed: \(label)")
        }
        let skipped = plan.postLaunchActions.map(\.label).filter { !performed.contains($0) }
        for label in skipped {
            logger.log(.warning, "Post-launch action skipped: \(label)")
        }
        return performed
    }

    private func openWorkspaceNow(_ profile: LaunchProfile, app: WorkspaceCompanionApp) {
        let action = PostLaunchAction(
            app: app,
            path: profile.expandedWorkingDirectory,
            label: "\(app.displayName) • \(URL(fileURLWithPath: profile.expandedWorkingDirectory).lastPathComponent)"
        )
        if companionLauncher.perform(action: action) {
            logger.log(.success, "Opened workspace in \(app.displayName).")
        } else {
            logger.log(.warning, "Could not open workspace in \(app.displayName).")
        }
    }

    private func exportSelectedProfileLauncher() {
        guard let profile = store.selectedProfile else { return }
        exportLauncherForProfile(profile)
    }

    private func exportLauncherForProfile(_ profile: LaunchProfile) {
        do {
            let plan = try planner.buildPlan(primary: profile, allProfiles: store.profiles, settings: store.settings)
            exportLauncher(plan: plan, suggestedName: profile.name + ".command")
        } catch {
            logger.log(.error, error.localizedDescription)
        }
    }

    private func exportLauncher(plan: PlannedLaunch, suggestedName: String) {
        do {
            let url = try launcherExporter.exportLauncherScript(plan: plan, suggestedName: suggestedName)
            logger.log(.success, "Exported launcher script to \(url.path).")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            if error.localizedDescription != "Export cancelled." {
                logger.log(.error, "Failed to export launcher: \(error.localizedDescription)")
            }
        }
    }

    private func formattedLogLine(for entry: LogEntry) -> String {
        var line = "[\(entry.timestamp.formatted(date: .numeric, time: .standard))] [\(entry.level.rawValue.uppercased())] [\(entry.category.rawValue.uppercased())] \(entry.message)"
        if entry.repeatCount > 1 {
            line += " (x\(entry.repeatCount))"
        }
        if let details = entry.details, !details.isEmpty {
            line += "\n    \(details)"
        }
        return line
    }

    private func exportLogs(_ entries: [LogEntry]) {
        guard let url = FilePanelService.saveFile(suggestedName: "CLILauncherLog.txt", allowedContentTypes: [UTType.plainText]) else { return }
        let text = entries.map { formattedLogLine(for: $0) }.joined(separator: "\n")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            logger.log(.success, "Exported visible launch log.", category: .diagnostics)
        } catch {
            logger.log(.error, "Failed to export log: \(error.localizedDescription)", category: .diagnostics)
        }
    }

    private func exportDiagnostics() {
        guard let url = FilePanelService.saveFile(suggestedName: "CLILauncherDiagnostics.json", allowedContentTypes: [UTType.json]) else { return }
        let diagnosticPlanPreview: PlannedLaunch?
        if let profile = store.selectedProfile {
            diagnosticPlanPreview = try? planner.buildPlan(primary: profile, allProfiles: store.profiles, settings: store.settings)
        } else {
            diagnosticPlanPreview = nil
        }
        let report = ApplicationDiagnosticReport(
            appSupportDirectory: AppPaths.containerDirectory.path,
            stateFilePath: AppPaths.stateFileURL.path,
            logFilePath: logger.runtimeLogFileURL.path,
            selectedTab: selectedTab.displayName,
            selectedProfileName: store.selectedProfile?.name,
            selectedProfileID: store.selectedProfileID,
            diagnosticsErrors: preview.diagnostics.errors,
            diagnosticsWarnings: preview.diagnostics.warnings,
            diagnosticStatuses: preview.diagnostics.statuses,
            iterm: iTermLauncher.diagnosticSnapshot(discoveredProfiles: preview.availableITermProfiles, discoverySource: preview.iTermProfileSourceDescription),
            monitoring: MonitoringDiagnosticSnapshot(
                sessionCount: terminalMonitor.sessions.count,
                databaseStatus: terminalMonitor.databaseStatus,
                lastConnectionCheck: terminalMonitor.lastConnectionCheck,
                storageSummaryStatus: terminalMonitor.storageSummaryStatus
            ),
            commandPreview: diagnosticPlanPreview?.combinedCommandPreview,
            appleScriptPreview: diagnosticPlanPreview.map { iTermLauncher.buildAppleScript(plan: $0) },
            recentLogs: Array(logger.entries.prefix(400))
        )

        do {
            let data = try JSONEncoder.pretty.encode(report)
            try data.write(to: url, options: [.atomic])
            logger.log(.success, "Exported diagnostic report.", category: .diagnostics, details: url.path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            logger.log(.error, "Failed to export diagnostics: \(error.localizedDescription)", category: .diagnostics)
        }
    }

    private func exportState() {
        guard let url = FilePanelService.saveFile(suggestedName: "CLILauncherState.json", allowedContentTypes: [UTType.json]) else { return }
        do {
            try store.exportState(to: url)
            logger.log(.success, "Exported launcher state.")
        } catch {
            logger.log(.error, "Failed to export state: \(error.localizedDescription)")
        }
    }

    private func importState() {
        guard let path = FilePanelService.chooseFile(allowedContentTypes: [UTType.json]) else { return }
        do {
            try store.importState(from: URL(fileURLWithPath: path))
            logger.log(.success, "Imported launcher state.")
            refreshLiveState()
        } catch {
            logger.log(.error, "Failed to import state: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private func unavailablePlaceholder(_ title: String, systemImage: String, message: String? = nil) -> some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let message, !message.isEmpty {
                    Text(message)
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3.weight(.semibold))
                if let message, !message.isEmpty {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

@MainActor
private struct LaunchPlanPreviewCard: View, Equatable {
    let plan: PlannedLaunch?
    let suggestedName: String
    let copyCombinedCommands: () -> Void
    let copyAppleScript: () -> Void
    let exportLauncher: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.suggestedName == rhs.suggestedName && lhs.planSignature == rhs.planSignature
    }

    nonisolated private var planSignature: String {
        guard let plan else { return "none" }
        let itemSignature = plan.items.map { "\($0.profileName)|\($0.openMode.displayName)|\($0.description)|\($0.command)" }.joined(separator: "||")
        let actionSignature = plan.postLaunchActions.map(\.label).joined(separator: "||")
        return "\(plan.tabLaunchDelayMs)|\(itemSignature)|\(actionSignature)"
    }

    var body: some View {
        GroupBox("Launch Plan Preview") {
            VStack(alignment: .leading, spacing: 10) {
                if let plan {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(plan.items.count) tab(s) will open")
                                .font(.headline)
                            HStack(spacing: 10) {
                                Label("\(plan.tabLaunchDelayMs) ms between tabs", systemImage: "timer")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !plan.postLaunchActions.isEmpty {
                                    Label("\(plan.postLaunchActions.count) post-launch action(s)", systemImage: "square.and.arrow.up.on.square")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Button("Copy Combined Commands", action: copyCombinedCommands)
                        Button("Copy AppleScript", action: copyAppleScript)
                        Button("Export Launcher…", action: exportLauncher)
                    }
                    if !plan.postLaunchActions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Post-launch actions")
                                .font(.subheadline.weight(.semibold))
                            ForEach(plan.postLaunchActions) { action in
                                Label(action.label, systemImage: action.app.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    ForEach(plan.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.profileName)
                                    .font(.headline)
                                Spacer()
                                Text(item.openMode.displayName)
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.description)
                                .foregroundStyle(.secondary)
                            Text(item.command)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    Text("Select a valid profile to generate a launch plan.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
private struct WorkbenchPreflightCard: View, Equatable {
    let postLaunchHints: [String]
    let diagnostics: PreflightCheck

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.postLaunchHints == rhs.postLaunchHints &&
        lhs.diagnostics.errors == rhs.diagnostics.errors &&
        lhs.diagnostics.warnings == rhs.diagnostics.warnings
    }

    var body: some View {
        GroupBox("Workbench Preflight") {
            VStack(alignment: .leading, spacing: 8) {
                if !postLaunchHints.isEmpty {
                    GroupBox("Post-launch Hints") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(postLaunchHints, id: \.self) { item in
                                Label(item, systemImage: "lightbulb")
                                    .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(diagnostics.errors, id: \.self) { item in
                    Label(item, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                ForEach(diagnostics.warnings, id: \.self) { item in
                    Label(item, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if diagnostics.errors.isEmpty, diagnostics.warnings.isEmpty {
                    Label("Workbench plan looks ready.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
private struct WorkbenchLaunchPreviewCard: View, Equatable {
    let plan: PlannedLaunch?
    let suggestedName: String
    let copyCombinedCommands: () -> Void
    let copyAppleScript: () -> Void
    let exportLauncher: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.suggestedName == rhs.suggestedName && lhs.planSignature == rhs.planSignature
    }

    nonisolated private var planSignature: String {
        guard let plan else { return "none" }
        let actionSignature = plan.postLaunchActions.map(\.label).joined(separator: "||")
        return "\(plan.tabLaunchDelayMs)|\(plan.combinedCommandPreview)|\(actionSignature)"
    }

    var body: some View {
        GroupBox("Launch Preview") {
            VStack(alignment: .leading, spacing: 10) {
                if let plan {
                    HStack {
                        Spacer()
                        Button("Copy Combined Commands", action: copyCombinedCommands)
                        Button("Copy AppleScript", action: copyAppleScript)
                        Button("Export Launcher…", action: exportLauncher)
                    }
                    Text(plan.combinedCommandPreview)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Select profiles in the workbench to preview the combined launch plan.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

@MainActor
private struct CurrentPlanDiagnosticsCard: View, Equatable {
    let plan: PlannedLaunch?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.planSignature == rhs.planSignature
    }

    nonisolated private var planSignature: String {
        guard let plan else { return "none" }
        return "\(plan.combinedCommandPreview)|\(plan.postLaunchSummary)"
    }

    var body: some View {
        GroupBox("Current Plan") {
            if let plan {
                VStack(alignment: .leading, spacing: 8) {
                    Text(plan.combinedCommandPreview)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !plan.postLaunchActions.isEmpty {
                        Divider()
                        Text("Post-launch actions: " + plan.postLaunchSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Select a valid profile to preview the plan.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private struct ProfileActionRow: View, Equatable {
    let commandPreview: LaunchResult?
    let launchSelectedProfile: () -> Void
    let duplicateSelectedProfile: () -> Void
    let applyPreset: (LaunchBehaviorPreset) -> Void
    let bookmarkWorkspace: () -> Void
    let deleteProfile: () -> Void
    let copyCommand: () -> Void
    let copyAppleScript: () -> Void
    let exportLauncher: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.commandPreviewSignature == rhs.commandPreviewSignature
    }

    nonisolated private var commandPreviewSignature: String {
        guard let commandPreview else { return "none" }
        return "\(commandPreview.command)|\(commandPreview.appleScript)"
    }

    var body: some View {
        HStack {
            Button("Launch", action: launchSelectedProfile)
                .buttonStyle(.borderedProminent)
            Button("Duplicate", action: duplicateSelectedProfile)
            Menu("Apply Preset") {
                ForEach(LaunchBehaviorPreset.allCases) { preset in
                    Button(preset.displayName) {
                        applyPreset(preset)
                    }
                }
            }
            Button("Bookmark Workspace", action: bookmarkWorkspace)
            Button("Delete", action: deleteProfile)
                .tint(.red)
            Spacer()
            if commandPreview != nil {
                Button("Copy Command", action: copyCommand)
                Button("Copy AppleScript", action: copyAppleScript)
                Button("Export Launcher…", action: exportLauncher)
            }
        }
    }
}

private struct ProfileEditorPane: View {
    @Binding var profile: LaunchProfile
    @ObservedObject var preview: LaunchPreviewStore

    let environmentPresets: [EnvironmentPreset]
    let shellBootstrapPresets: [ShellBootstrapPreset]
    let defaultWorkingDirectory: String
    let companionProfiles: [LaunchProfile]
    let mergedEnvironmentSummary: String
    let parseTags: (String) -> [String]
    let chooseWorkingDirectory: () -> Void
    let useDefaultWorkingDirectory: () -> Void
    let revealWorkingDirectory: () -> Void
    let revealISO: () -> Void
    let manageSharedPresets: () -> Void
    let onAgentKindChanged: (AgentKind) -> Void
    let onGeminiFlavorChanged: () -> Void
    let launchSelectedProfile: () -> Void
    let duplicateSelectedProfile: () -> Void
    let applyPreset: (LaunchBehaviorPreset) -> Void
    let bookmarkWorkspace: () -> Void
    let deleteProfile: () -> Void
    let copyCommand: () -> Void
    let copyAppleScript: () -> Void
    let exportLauncher: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProfileGeneralSection(
                    profile: $profile,
                    availableITermProfiles: preview.availableITermProfiles,
                    environmentPresets: environmentPresets,
                    shellBootstrapPresets: shellBootstrapPresets,
                    defaultWorkingDirectory: defaultWorkingDirectory,
                    mergedEnvironmentSummary: mergedEnvironmentSummary,
                    parseTags: parseTags,
                    chooseWorkingDirectory: chooseWorkingDirectory,
                    useDefaultWorkingDirectory: useDefaultWorkingDirectory,
                    revealWorkingDirectory: revealWorkingDirectory,
                    manageSharedPresets: manageSharedPresets,
                    onAgentKindChanged: onAgentKindChanged
                )
                ProfileProviderSection(
                    profile: $profile,
                    onGeminiFlavorChanged: onGeminiFlavorChanged,
                    revealISO: revealISO
                )
                ProfileCompanionSection(
                    profile: $profile,
                    companionProfiles: companionProfiles
                )
                ProfileEnvironmentSection(profile: $profile)
                ProfileActionRow(
                    commandPreview: preview.commandPreview,
                    launchSelectedProfile: launchSelectedProfile,
                    duplicateSelectedProfile: duplicateSelectedProfile,
                    applyPreset: applyPreset,
                    bookmarkWorkspace: bookmarkWorkspace,
                    deleteProfile: deleteProfile,
                    copyCommand: copyCommand,
                    copyAppleScript: copyAppleScript,
                    exportLauncher: exportLauncher
                )
                .equatable()
            }
            .padding()
        }
    }
}

private struct WorkbenchEditorPane: View {
    @Binding var workbench: LaunchWorkbench
    @ObservedObject var preview: LaunchPreviewStore

    let profiles: [LaunchProfile]
    let bookmarks: [WorkspaceBookmark]
    let parseTags: (String) -> [String]
    let membershipBinding: (UUID) -> Binding<Bool>
    let launchWorkbench: () -> Void
    let duplicateWorkbench: () -> Void
    let deleteWorkbench: () -> Void
    let moveProfile: (UUID, Int) -> Void
    let removeProfile: (UUID) -> Void
    let copyCombinedCommands: () -> Void
    let copyAppleScript: () -> Void
    let exportLauncher: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WorkbenchGeneralSection(
                    workbench: $workbench,
                    bookmarks: bookmarks,
                    parseTags: parseTags,
                    launchWorkbench: launchWorkbench,
                    duplicateWorkbench: duplicateWorkbench,
                    deleteWorkbench: deleteWorkbench
                )
                WorkbenchProfilesSection(
                    workbench: $workbench,
                    profiles: profiles,
                    membershipBinding: membershipBinding,
                    moveProfile: moveProfile,
                    removeProfile: removeProfile
                )

                WorkbenchPreflightCard(
                    postLaunchHints: workbench.postLaunchActionHints,
                    diagnostics: preview.selectedWorkbenchDiagnostics
                )
                .equatable()

                WorkbenchLaunchPreviewCard(
                    plan: preview.workbenchPlanPreview,
                    suggestedName: workbench.name + ".command",
                    copyCombinedCommands: copyCombinedCommands,
                    copyAppleScript: copyAppleScript,
                    exportLauncher: exportLauncher
                )
                .equatable()
            }
            .padding()
        }
    }
}

private struct ProfileGeneralSection: View {
    @Binding var profile: LaunchProfile

    let availableITermProfiles: [String]
    let environmentPresets: [EnvironmentPreset]
    let shellBootstrapPresets: [ShellBootstrapPreset]
    let defaultWorkingDirectory: String
    let mergedEnvironmentSummary: String
    let parseTags: (String) -> [String]
    let chooseWorkingDirectory: () -> Void
    let useDefaultWorkingDirectory: () -> Void
    let revealWorkingDirectory: () -> Void
    let manageSharedPresets: () -> Void
    let onAgentKindChanged: (AgentKind) -> Void

    var body: some View {
        GroupBox("General") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Profile name", text: $profile.name)
                Toggle("Favorite", isOn: $profile.isFavorite)
                TextField("Tags (comma separated)", text: Binding(
                    get: { profile.tags.joined(separator: ", ") },
                    set: { profile.tags = parseTags($0) }
                ))
                TextField("Notes", text: $profile.notes, axis: .vertical)
                    .lineLimit(3...6)

                Picker("Tool", selection: $profile.agentKind) {
                    ForEach(AgentKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .onChange(of: profile.agentKind, perform: onAgentKindChanged)

                HStack {
                    TextField("Application / working directory", text: $profile.workingDirectory)
                    Button("Choose…", action: chooseWorkingDirectory)
                    Button("Use Default", action: useDefaultWorkingDirectory)
                    Button("Reveal", action: revealWorkingDirectory)
                }
                Text("Gemini launches from this folder. Point it at your app path, for example `/Users/michalmatynia/Desktop/NPM/2026/Gemini new Pull/geminitestapp`. New profiles start from the Settings default: \(defaultWorkingDirectory)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Terminal application", selection: $profile.terminalApp) {
                    ForEach(TerminalApp.allCases) { app in
                        Text(app.displayName).tag(app)
                    }
                }

                Picker("Open in \(profile.terminalApp.displayName)", selection: $profile.openMode) {
                    ForEach(ITermOpenMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if profile.terminalApp == .iterm2 {
                    Picker("iTerm2 profile", selection: $profile.iTermProfile) {
                        Text("Default Profile").tag("")
                        ForEach(availableITermProfiles, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                }

                Toggle("Open workspace in Finder after launch", isOn: $profile.openWorkspaceInFinderOnLaunch)
                Toggle("Open workspace in VS Code after launch", isOn: $profile.openWorkspaceInVSCodeOnLaunch)
                Stepper(value: $profile.tabLaunchDelayMs, in: 50...3_000, step: 50) {
                    Text("Delay between iTerm2 tabs: \(profile.tabLaunchDelayMs) ms")
                }

                Picker("Environment preset", selection: $profile.environmentPresetID) {
                    Text("None").tag(UUID?.none)
                    ForEach(environmentPresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }

                Picker("Bootstrap preset", selection: $profile.bootstrapPresetID) {
                    Text("None").tag(UUID?.none)
                    ForEach(shellBootstrapPresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }

                HStack {
                    Text(mergedEnvironmentSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Manage Shared Presets", action: manageSharedPresets)
                }

                TextField("Extra CLI args", text: $profile.extraCLIArgs)
                TextField("Shell bootstrap command", text: $profile.shellBootstrapCommand, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }
}

private struct ProfileProviderSection: View {
    @Binding var profile: LaunchProfile
    let onGeminiFlavorChanged: () -> Void
    let revealISO: () -> Void

    @ViewBuilder
    var body: some View {
        switch profile.agentKind {
        case .gemini:
            ProfileGeminiProviderSection(
                profile: $profile,
                onGeminiFlavorChanged: onGeminiFlavorChanged,
                revealISO: revealISO
            )

        case .copilot:
            ProfileCopilotProviderSection(profile: $profile)

        case .codex:
            ProfileCodexProviderSection(profile: $profile)

        case .claudeBypass:
            ProfileClaudeProviderSection(profile: $profile)

        case .kiroCLI:
            ProfileKiroProviderSection(profile: $profile)

        case .ollamaLaunch:
            ProfileOllamaProviderSection(profile: $profile)

        case .aider:
            ProfileAiderProviderSection(profile: $profile)
        }
    }
}

private struct ProfileGeminiProviderSection: View {
    @Binding var profile: LaunchProfile
    let onGeminiFlavorChanged: () -> Void
    let revealISO: () -> Void

    var body: some View {
        GroupBox(profile.agentKind.displayName) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Flavor", selection: $profile.geminiFlavor) {
                    ForEach(GeminiFlavor.allCases) { flavor in
                        Text(flavor.displayName).tag(flavor)
                    }
                }
                .onChange(of: profile.geminiFlavor) { _ in
                    onGeminiFlavorChanged()
                }

                Picker("Launch mode", selection: $profile.geminiLaunchMode) {
                    ForEach(GeminiLaunchMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(
                    profile.geminiLaunchMode == .automationRunner
                    ? "Automation runner mode uses the bundled Gemini runner when this path is blank. Node is required. Install `@lydell/node-pty` or `node-pty` in the workspace for PTY hotkeys and prompt automation."
                    : "Direct wrapper mode launches the configured Gemini wrapper directly and skips the bundled automation runner."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                TextField("Wrapper command", text: $profile.geminiWrapperCommand)
                HStack {
                    TextField("ISO home", text: $profile.geminiISOHome)
                    Button("Reveal", action: revealISO)
                }
                HStack {
                    TextField("Initial model", text: $profile.geminiInitialModel)
                    Button("Reset") {
                        profile.geminiInitialModel = profile.geminiFlavor.defaultInitialModel
                    }
                    .help("Reset initial model to flavor default")
                }
                HStack(alignment: .top) {
                    TextField("Model chain", text: $profile.geminiModelChain, axis: .vertical)
                        .lineLimit(2...4)
                    Button("Reset") {
                        profile.geminiModelChain = profile.geminiFlavor.defaultModelChain
                    }
                    .help("Reset model chain to flavor default")
                }
                HStack(alignment: .top) {
                    TextField("Initial prompt", text: $profile.geminiInitialPrompt, axis: .vertical)
                        .lineLimit(2...5)
                    Button("Clear") {
                        profile.geminiInitialPrompt = ""
                    }
                    .help("Clear initial prompt")
                }
                TextField("Automation runner path", text: $profile.geminiAutomationRunnerPath)
                Text("Leave the automation runner path blank to use the app-bundled runner for \(profile.geminiFlavor.displayName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Node executable", text: $profile.nodeExecutable)
                TextField("Hotkey prefix", text: $profile.geminiHotkeyPrefix)

                HStack {
                    Stepper(value: $profile.geminiKeepTryMax, in: 0...1_000) {
                        Text("Keep-try max: \(profile.geminiKeepTryMax)")
                    }
                    Stepper(value: $profile.geminiManualOverrideMs, in: 1_000...120_000, step: 1_000) {
                        Text("Manual override: \(profile.geminiManualOverrideMs) ms")
                    }
                }
                HStack {
                    Stepper(value: $profile.geminiCapacityRetryMs, in: 250...30_000, step: 250) {
                        Text("Capacity retry: \(profile.geminiCapacityRetryMs) ms")
                    }
                }

                Picker("Auto continue", selection: $profile.geminiAutoContinueMode) {
                    ForEach(AutoContinueMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle("Resume latest", isOn: $profile.geminiResumeLatest)
                Toggle("Automation enabled", isOn: $profile.geminiAutomationEnabled)
                Toggle("YOLO Mode (Always Auto-Continue)", isOn: $profile.geminiYolo)
                    .onChange(of: profile.geminiYolo) { newValue in
                        if newValue {
                            profile.geminiAutoContinueMode = .yolo
                            profile.geminiKeepTryMax = 10
                            profile.geminiCapacityRetryMs = 500
                            profile.geminiAutoAllowSessionPermissions = true
                        } else {
                            profile.geminiAutoContinueMode = .promptOnly
                            profile.geminiKeepTryMax = 25
                            profile.geminiCapacityRetryMs = 5_000
                        }
                    }
                Toggle("Auto allow session permissions", isOn: $profile.geminiAutoAllowSessionPermissions)
                Toggle("Never switch model", isOn: $profile.geminiNeverSwitch)
                Toggle("Set HOME to ISO folder", isOn: $profile.geminiSetHomeToIso)
                Toggle("Quiet child node warnings", isOn: $profile.geminiQuietChildNodeWarnings)
                Toggle("Raw output", isOn: $profile.geminiRawOutput)
            }
        }
    }
}

private struct ProfileCopilotProviderSection: View {
    @Binding var profile: LaunchProfile

    var body: some View {
        GroupBox(profile.agentKind.displayName) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Executable", text: $profile.copilotExecutable)
                Picker("Mode", selection: $profile.copilotMode) {
                    ForEach(CopilotMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                TextField("Model", text: $profile.copilotModel)
                TextField("COPILOT_HOME", text: $profile.copilotHome)
                TextField("Initial prompt", text: $profile.copilotInitialPrompt, axis: .vertical)
                    .lineLimit(2...5)
                Stepper(value: $profile.copilotMaxAutopilotContinues, in: 1...50) {
                    Text("Max autopilot continues: \(profile.copilotMaxAutopilotContinues)")
                }
            }
        }
    }
}

private struct ProfileCodexProviderSection: View {
    @Binding var profile: LaunchProfile

    var body: some View {
        GroupBox(profile.agentKind.displayName) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Executable", text: $profile.codexExecutable)
                Picker("Mode", selection: $profile.codexMode) {
                    ForEach(CodexMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                TextField("Model", text: $profile.codexModel)
            }
        }
    }
}

private struct ProfileClaudeProviderSection: View {
    @Binding var profile: LaunchProfile

    var body: some View {
        GroupBox(profile.agentKind.displayName) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Executable", text: $profile.claudeExecutable)
                TextField("Model", text: $profile.claudeModel)
            }
        }
    }
}

private struct ProfileKiroProviderSection: View {
    @Binding var profile: LaunchProfile

    var body: some View {
        GroupBox(profile.agentKind.displayName) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Executable", text: $profile.kiroExecutable)
                Picker("Mode", selection: $profile.kiroMode) {
                    ForEach(KiroMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
        }
    }
}

private struct ProfileOllamaProviderSection: View {
    @Binding var profile: LaunchProfile

    var body: some View {
        GroupBox(profile.agentKind.displayName) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Executable", text: $profile.ollamaExecutable)
                Picker("Integration", selection: $profile.ollamaIntegration) {
                    ForEach(OllamaIntegration.allCases) { integration in
                        Text(integration.displayName).tag(integration)
                    }
                }
                TextField("Model", text: $profile.ollamaModel)
                Toggle("Config only", isOn: $profile.ollamaConfigOnly)
            }
        }
    }
}

private struct ProfileAiderProviderSection: View {
    @Binding var profile: LaunchProfile

    var body: some View {
        GroupBox(profile.agentKind.displayName) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Executable", text: $profile.aiderExecutable)
                Picker("Mode", selection: $profile.aiderMode) {
                    ForEach(AiderMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                TextField("Model", text: $profile.aiderModel)
                Toggle("Auto commit", isOn: $profile.aiderAutoCommit)
                Toggle("Notify on completion", isOn: $profile.aiderNotify)
                Toggle("Dark theme", isOn: $profile.aiderDarkTheme)
            }
        }
    }
}

private struct ProfileCompanionSection: View {
    @Binding var profile: LaunchProfile
    let companionProfiles: [LaunchProfile]

    var body: some View {
        GroupBox("Companion Tabs") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch companion tabs with this profile", isOn: $profile.autoLaunchCompanions)
                if profile.autoLaunchCompanions {
                    ForEach(companionProfiles) { companion in
                        Toggle(isOn: Binding(
                            get: { profile.companionProfileIDs.contains(companion.id) },
                            set: { enabled in
                                if enabled {
                                    if !profile.companionProfileIDs.contains(companion.id) {
                                        profile.companionProfileIDs.append(companion.id)
                                    }
                                } else {
                                    profile.companionProfileIDs.removeAll { $0 == companion.id }
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(companion.name)
                                Text(companion.agentKind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ProfileEnvironmentSection: View {
    @Binding var profile: LaunchProfile

    var body: some View {
        GroupBox("Environment") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach($profile.environmentEntries) { $item in
                    HStack {
                        TextField("KEY", text: $item.key)
                        TextField("VALUE", text: $item.value)
                    }
                }
                HStack {
                    Button("Add Environment Variable") {
                        profile.environmentEntries.append(EnvironmentEntry())
                    }
                    Button("Remove Last") {
                        if !profile.environmentEntries.isEmpty {
                            profile.environmentEntries.removeLast()
                        }
                    }
                }
            }
        }
    }
}

private struct WorkbenchGeneralSection: View {
    @Binding var workbench: LaunchWorkbench

    let bookmarks: [WorkspaceBookmark]
    let parseTags: (String) -> [String]
    let launchWorkbench: () -> Void
    let duplicateWorkbench: () -> Void
    let deleteWorkbench: () -> Void

    var body: some View {
        GroupBox("Workbench") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $workbench.name)
                TextField("Tags (comma separated)", text: Binding(
                    get: { workbench.tags.joined(separator: ", ") },
                    set: { workbench.tags = parseTags($0) }
                ))
                Picker("Role", selection: $workbench.role) {
                    ForEach(WorkbenchRole.allCases) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                Stepper("Startup delay (ms): \(workbench.startupDelayMs)", value: Binding(
                    get: { workbench.startupDelayMs },
                    set: { workbench.startupDelayMs = max(0, $0) }
                ), in: 0...300_000, step: 50)
                TextField("Notes", text: $workbench.notes, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Post-launch action hints (comma separated)", text: Binding(
                    get: { workbench.postLaunchActionHints.joined(separator: ", ") },
                    set: { workbench.postLaunchActionHints = parseTags($0) }
                ))

                Picker("Shared workspace", selection: $workbench.sharedBookmarkID) {
                    Text("None").tag(UUID?.none)
                    ForEach(bookmarks) { bookmark in
                        Text(bookmark.name).tag(Optional(bookmark.id))
                    }
                }

                HStack {
                    Button("Launch Workbench", action: launchWorkbench)
                        .buttonStyle(.borderedProminent)
                    Button("Duplicate", action: duplicateWorkbench)
                    Button("Delete", role: .destructive, action: deleteWorkbench)
                }
            }
        }
    }
}

private struct WorkbenchProfilesSection: View {
    @Binding var workbench: LaunchWorkbench

    let profiles: [LaunchProfile]
    let membershipBinding: (UUID) -> Binding<Bool>
    let moveProfile: (UUID, Int) -> Void
    let removeProfile: (UUID) -> Void

    var body: some View {
        GroupBox("Profiles in This Workbench") {
            VStack(alignment: .leading, spacing: 12) {
                if workbench.profileIDs.isEmpty {
                    Text("Select one or more profiles below to build a workbench.")
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(workbench.profileIDs.enumerated()), id: \.element) { index, profileID in
                    if let profile = profiles.first(where: { $0.id == profileID }) {
                        WorkbenchSelectedProfileRow(
                            profile: profile,
                            index: index,
                            totalCount: workbench.profileIDs.count,
                            moveUp: { moveProfile(profileID, -1) },
                            moveDown: { moveProfile(profileID, 1) },
                            remove: { removeProfile(profileID) }
                        )
                    }
                }

                Divider()

                Text("Available profiles")
                    .font(.headline)
                ForEach(profiles) { profile in
                    Toggle(isOn: membershipBinding(profile.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                            Text(profile.agentKind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct WorkbenchSelectedProfileRow: View {
    let profile: LaunchProfile
    let index: Int
    let totalCount: Int
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.headline)
                Text(profile.agentKind.displayName)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: moveUp) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            Button(action: moveDown) {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == totalCount - 1)
            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct WorkspaceBookmarkEditorPane: View {
    @Binding var bookmark: WorkspaceBookmark

    let profiles: [LaunchProfile]
    let parseTags: (String) -> [String]
    let chooseDirectory: () -> Void
    let revealBookmark: () -> Void
    let applyToSelectedProfile: () -> Void
    let createWorkbenchHere: () -> Void
    let launchDefaultProfileHere: () -> Void
    let deleteBookmark: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Bookmark") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name", text: $bookmark.name)
                        HStack {
                            TextField("Path", text: $bookmark.path)
                            Button("Choose…", action: chooseDirectory)
                            Button("Reveal", action: revealBookmark)
                        }
                        TextField("Tags (comma separated)", text: Binding(
                            get: { bookmark.tags.joined(separator: ", ") },
                            set: { bookmark.tags = parseTags($0) }
                        ))
                        TextField("Notes", text: $bookmark.notes, axis: .vertical)
                            .lineLimit(3...6)

                        Picker("Default profile", selection: $bookmark.defaultProfileID) {
                            Text("None").tag(UUID?.none)
                            ForEach(profiles) { profile in
                                Text(profile.name).tag(Optional(profile.id))
                            }
                        }
                    }
                }

                HStack {
                    Button("Apply to Selected Profile", action: applyToSelectedProfile)
                    Button("New Workbench Here", action: createWorkbenchHere)
                    Button("Launch Default Profile Here", action: launchDefaultProfileHere)
                    Button("Delete Bookmark", role: .destructive, action: deleteBookmark)
                }
            }
            .padding()
        }
    }
}

private struct ProfilesSidebarPane: View {
    let profiles: [LaunchProfile]
    @Binding var selectedProfileID: UUID?
    let addProfile: (AgentKind) -> Void
    let duplicateProfile: (LaunchProfile) -> Void
    let bookmarkProfile: (LaunchProfile) -> Void

    @State private var search: String = ""

    private var filteredProfiles: [LaunchProfile] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return profiles }
        return profiles.filter {
            $0.name.lowercased().contains(query) ||
            $0.tags.joined(separator: " ").lowercased().contains(query) ||
            $0.agentKind.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search profiles", text: $search)
                Menu {
                    ForEach(AgentKind.allCases) { kind in
                        Button("Add \(kind.displayName)") {
                            addProfile(kind)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add profile")
            }
            .padding()

            List(selection: $selectedProfileID) {
                ForEach(filteredProfiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(profile.name)
                                    .font(.headline)
                                if profile.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                                if profile.agentKind == .gemini, profile.geminiAutomationEnabled {
                                    Image(systemName: "bolt.fill")
                                        .foregroundStyle(.green)
                                        .imageScale(.small)
                                }
                            }
                            Text(profile.agentKind.displayName)
                                .foregroundStyle(.secondary)
                            if !profile.tags.isEmpty {
                                Text(profile.tags.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .tag(profile.id)
                    .contextMenu {
                        Button("Duplicate") {
                            duplicateProfile(profile)
                        }
                        Button("Bookmark Workspace") {
                            bookmarkProfile(profile)
                        }
                    }
                }
            }
        }
    }
}

private struct WorkbenchSidebarPane: View {
    let workbenches: [LaunchWorkbench]
    @Binding var selection: UUID?
    let createWorkbench: () -> Void

    @State private var search: String = ""

    private var filteredWorkbenches: [LaunchWorkbench] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return workbenches }
        return workbenches.filter {
            $0.name.lowercased().contains(query) ||
            $0.notes.lowercased().contains(query) ||
            $0.tags.joined(separator: " ").lowercased().contains(query) ||
            $0.role.displayName.lowercased().contains(query) ||
            String($0.startupDelayMs).contains(query) ||
            $0.postLaunchActionHints.joined(separator: " ").lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search workbenches", text: $search)
                Button(action: createWorkbench) {
                    Image(systemName: "plus")
                }
                .help("Create workbench from current profile")
            }
            .padding()

            List(selection: $selection) {
                ForEach(filteredWorkbenches) { workbench in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(workbench.name)
                                .font(.headline)
                            Text(workbench.role.displayName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.quaternary.opacity(0.2), in: Capsule())
                            Spacer()
                            Text(workbench.profileIDs.count == 1 ? "1 tab" : "\(workbench.profileIDs.count) tabs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !workbench.tags.isEmpty {
                            Text(workbench.tags.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let last = workbench.lastLaunchedAt {
                            Text("Last launched \(last.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(workbench.id)
                }
            }
        }
    }
}

private struct WorkspaceBookmarksSidebarPane: View {
    let bookmarks: [WorkspaceBookmark]
    @Binding var selection: UUID?
    let addBookmark: () -> Void

    @State private var search: String = ""

    private var filteredBookmarks: [WorkspaceBookmark] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.name.lowercased().contains(query) ||
            $0.path.lowercased().contains(query) ||
            $0.tags.joined(separator: " ").lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search workspaces", text: $search)
                Button(action: addBookmark) {
                    Image(systemName: "plus")
                }
            }
            .padding()

            List(selection: $selection) {
                ForEach(filteredBookmarks) { bookmark in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bookmark.name)
                            .font(.headline)
                        Text(bookmark.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .tag(bookmark.id)
                }
            }
        }
    }
}

private struct HistoryTabPane: View {
    let history: [LaunchHistoryItem]
    let relaunchLast: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Launch History")
                    .font(.title2.bold())
                Spacer()
                Button("Relaunch Last", action: relaunchLast)
                    .buttonStyle(.borderedProminent)
            }
            List {
                ForEach(history) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.profileName)
                                .font(.headline)
                            if item.profileID == nil {
                                Text("Workbench")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.blue.opacity(0.12), in: Capsule())
                            }
                            Spacer()
                            Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        Text(item.description)
                            .foregroundStyle(.secondary)
                        Text(item.command)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                        if item.companionCount > 0 {
                            Text("Opened \(item.companionCount) companion tab(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
    }
}

private struct SettingsTabPane: View {
    @ObservedObject var store: ProfileStore

    let logger: LaunchLogger
    let terminalMonitor: TerminalMonitorStore
    let captureEnvironmentPresetFromSelectedProfile: () -> Void
    let captureBootstrapPresetFromSelectedProfile: () -> Void
    let exportState: () -> Void
    let importState: () -> Void

    private var settingsBinding: Binding<AppSettings> {
        Binding(
            get: { store.settings },
            set: { store.settings = $0 }
        )
    }

    var body: some View {
        Form {
            SettingsDefaultsSection(settings: settingsBinding)
            SettingsObservabilitySection(
                settings: settingsBinding,
                runtimeLogFilePath: logger.runtimeLogFileURL.path
            )
            SettingsEnvironmentPresetsSection(
                settings: settingsBinding,
                hasSelectedProfile: store.selectedProfile != nil,
                removePreset: removeEnvironmentPreset,
                captureFromSelectedProfile: captureEnvironmentPresetFromSelectedProfile
            )
            SettingsShellBootstrapPresetsSection(
                settings: settingsBinding,
                hasSelectedProfile: store.selectedProfile != nil,
                removePreset: removeShellBootstrapPreset,
                captureFromSelectedProfile: captureBootstrapPresetFromSelectedProfile
            )
            SettingsMonitoringSection(
                settings: settingsBinding,
                testConnection: {
                    terminalMonitor.testConnection(settings: store.settings, logger: logger)
                },
                revealTranscriptFolder: {
                    terminalMonitor.revealTranscriptDirectory(settings: store.settings)
                }
            )
            SettingsDataSection(
                revealStateFolder: {
                    store.reveal(store.stateURL.deletingLastPathComponent().path)
                },
                exportState: exportState,
                importState: importState
            )
        }
        .padding()
    }

    private func removeEnvironmentPreset(_ presetID: UUID) {
        store.settings.environmentPresets.removeAll { $0.id == presetID }
        for index in store.profiles.indices where store.profiles[index].environmentPresetID == presetID {
            store.profiles[index].environmentPresetID = nil
        }
    }

    private func removeShellBootstrapPreset(_ presetID: UUID) {
        store.settings.shellBootstrapPresets.removeAll { $0.id == presetID }
        for index in store.profiles.indices where store.profiles[index].bootstrapPresetID == presetID {
            store.profiles[index].bootstrapPresetID = nil
        }
    }
}

private struct SettingsDefaultsSection: View {
    @Binding var settings: AppSettings

    var body: some View {
        Section("Defaults") {
            TextField("Default application / working directory", text: $settings.defaultWorkingDirectory)
            Text("New profiles start here. Launch commands always `cd` into the selected profile's application / working directory before Gemini starts.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Default Node executable", text: $settings.defaultNodeExecutable)
            TextField("Default automation runner path", text: $settings.defaultGeminiRunnerPath)
            Text("Leave the default automation runner path blank to use the bundled Gemini automation runner shipped with the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Default iTerm2 profile", text: $settings.defaultITermProfile)
            TextField("Default hotkey prefix", text: $settings.defaultHotkeyPrefix)
            TextField("Default shell bootstrap command", text: $settings.defaultShellBootstrapCommand, axis: .vertical)
                .lineLimit(2...4)
            Toggle("Default: open workspace in Finder after launch", isOn: $settings.defaultOpenWorkspaceInFinderOnLaunch)
            Toggle("Default: open workspace in VS Code after launch", isOn: $settings.defaultOpenWorkspaceInVSCodeOnLaunch)

            Picker("Default iTerm2 open mode", selection: $settings.defaultOpenMode) {
                ForEach(ITermOpenMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Stepper(value: $settings.defaultTabLaunchDelayMs, in: 50...3_000, step: 50) {
                Text("Default iTerm2 tab delay: \(settings.defaultTabLaunchDelayMs) ms")
            }
            Stepper(value: $settings.defaultKeepTryMax, in: 0...25) {
                Text("Default automation keep-try max: \(settings.defaultKeepTryMax)")
            }
            Stepper(value: $settings.defaultManualOverrideMs, in: 1_000...120_000, step: 1_000) {
                Text("Default manual override: \(settings.defaultManualOverrideMs) ms")
            }
            Stepper(value: $settings.maxHistoryItems, in: 20...500, step: 10) {
                Text("History size: \(settings.maxHistoryItems)")
            }
            Stepper(value: $settings.maxBookmarks, in: 5...300, step: 5) {
                Text("Bookmark limit: \(settings.maxBookmarks)")
            }
            Toggle("Confirm before launch", isOn: $settings.confirmBeforeLaunch)
            Toggle("Quiet child Node warnings by default", isOn: $settings.quietChildNodeWarningsByDefault)
        }
    }
}

private struct SettingsObservabilitySection: View {
    @Binding var settings: AppSettings
    let runtimeLogFilePath: String

    var body: some View {
        Section("Observability") {
            Toggle("Verbose runtime logging", isOn: $settings.observability.verboseLogging)
            Toggle("Persist logs to disk", isOn: $settings.observability.persistLogsToDisk)
            Toggle("Include AppleScript payloads in logs", isOn: $settings.observability.includeAppleScriptInLogs)
            Toggle("Deduplicate repeated log entries", isOn: $settings.observability.deduplicateRepeatedEntries)
            Stepper(value: $settings.observability.maxInMemoryEntries, in: 100...10_000, step: 100) {
                Text("In-memory log limit: \(settings.observability.maxInMemoryEntries)")
            }
            HStack {
                Text("Runtime log file")
                Spacer()
                Text(runtimeLogFilePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct SettingsEnvironmentPresetsSection: View {
    @Binding var settings: AppSettings

    let hasSelectedProfile: Bool
    let removePreset: (UUID) -> Void
    let captureFromSelectedProfile: () -> Void

    var body: some View {
        Section("Shared Environment Presets") {
            if settings.environmentPresets.isEmpty {
                Text("No shared environment presets yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach($settings.environmentPresets) { $preset in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Preset name", text: $preset.name)
                        Spacer()
                        Button(role: .destructive) {
                            removePreset(preset.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    TextField("Notes", text: $preset.notes, axis: .vertical)
                        .lineLimit(2...4)
                    ForEach($preset.entries) { $entry in
                        HStack {
                            TextField("Key", text: $entry.key)
                            TextField("Value", text: $entry.value)
                            Button(role: .destructive) {
                                let entryID = entry.id
                                preset.entries.removeAll { $0.id == entryID }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                        }
                    }
                    Button("Add Variable") {
                        preset.entries.append(EnvironmentEntry())
                    }
                }
                .padding(.vertical, 6)
            }
            HStack {
                Button("Add Environment Preset") {
                    settings.environmentPresets.append(EnvironmentPreset())
                }
                Button("Capture Selected Profile Environment", action: captureFromSelectedProfile)
                    .disabled(!hasSelectedProfile)
            }
        }
    }
}

private struct SettingsShellBootstrapPresetsSection: View {
    @Binding var settings: AppSettings

    let hasSelectedProfile: Bool
    let removePreset: (UUID) -> Void
    let captureFromSelectedProfile: () -> Void

    var body: some View {
        Section("Shared Shell Bootstrap Presets") {
            if settings.shellBootstrapPresets.isEmpty {
                Text("No shared bootstrap presets yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach($settings.shellBootstrapPresets) { $preset in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Preset name", text: $preset.name)
                        Spacer()
                        Button(role: .destructive) {
                            removePreset(preset.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    TextField("Notes", text: $preset.notes, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Command", text: $preset.command, axis: .vertical)
                        .lineLimit(2...6)
                }
                .padding(.vertical, 6)
            }
            HStack {
                Button("Add Bootstrap Preset") {
                    settings.shellBootstrapPresets.append(ShellBootstrapPreset())
                }
                Button("Capture Selected Profile Bootstrap", action: captureFromSelectedProfile)
                    .disabled(!hasSelectedProfile)
            }
        }
    }
}

private struct SettingsMonitoringSection: View {
    @Binding var settings: AppSettings

    let testConnection: () -> Void
    let revealTranscriptFolder: () -> Void

    var body: some View {
        Section("Terminal Monitoring / MongoDB") {
            Toggle("Enable terminal transcript monitoring", isOn: $settings.mongoMonitoring.enabled)
            Toggle("Write captured transcript chunks into MongoDB", isOn: $settings.mongoMonitoring.enableMongoWrites)
                .disabled(!settings.mongoMonitoring.enabled)

            Picker("Capture mode", selection: $settings.mongoMonitoring.captureMode) {
                ForEach(TerminalTranscriptCaptureMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(!settings.mongoMonitoring.enabled)

            TextField("Mongo connection URL", text: $settings.mongoMonitoring.connectionURL)
                .disabled(!settings.mongoMonitoring.enabled || !settings.mongoMonitoring.enableMongoWrites)
            TextField("Schema name", text: $settings.mongoMonitoring.schemaName)
                .disabled(!settings.mongoMonitoring.enabled || !settings.mongoMonitoring.enableMongoWrites)
            TextField("Mongo shell executable", text: $settings.mongoMonitoring.mongoshExecutable)
                .disabled(!settings.mongoMonitoring.enabled)
            TextField("mongod executable", text: $settings.mongoMonitoring.mongodExecutable)
                .disabled(!settings.mongoMonitoring.enabled || !settings.mongoMonitoring.enableMongoWrites)
            TextField("Local Mongo data directory", text: $settings.mongoMonitoring.localDataDirectory)
                .disabled(!settings.mongoMonitoring.enabled || !settings.mongoMonitoring.enableMongoWrites)
            TextField("script executable", text: $settings.mongoMonitoring.scriptExecutable)
                .disabled(!settings.mongoMonitoring.enabled)
            TextField("Transcript directory", text: $settings.mongoMonitoring.transcriptDirectory)
                .disabled(!settings.mongoMonitoring.enabled)

            Stepper(value: $settings.mongoMonitoring.pollingIntervalMs, in: 250...5_000, step: 50) {
                Text("Polling interval: \(settings.mongoMonitoring.pollingIntervalMs) ms")
            }
            .disabled(!settings.mongoMonitoring.enabled)

            Stepper(value: $settings.mongoMonitoring.previewCharacterLimit, in: 100...8_000, step: 100) {
                Text("Chunk preview limit: \(settings.mongoMonitoring.previewCharacterLimit) chars")
            }
            .disabled(!settings.mongoMonitoring.enabled)

            Stepper(value: $settings.mongoMonitoring.recentHistoryLimit, in: 10...200, step: 10) {
                Text("Recent MongoDB session load limit: \(settings.mongoMonitoring.clampedRecentHistoryLimit)")
            }
            .disabled(!settings.mongoMonitoring.enabled || !settings.mongoMonitoring.enableMongoWrites)

            Stepper(value: $settings.mongoMonitoring.recentHistoryLookbackDays, in: 1...365, step: 1) {
                Text("Recent history lookback: \(settings.mongoMonitoring.clampedRecentHistoryLookbackDays) day(s)")
            }
            .disabled(!settings.mongoMonitoring.enabled || !settings.mongoMonitoring.enableMongoWrites)

            Stepper(value: $settings.mongoMonitoring.detailEventLimit, in: 10...500, step: 10) {
                Text("Detail event fetch limit: \(settings.mongoMonitoring.clampedDetailEventLimit)")
            }
            .disabled(!settings.mongoMonitoring.enabled || !settings.mongoMonitoring.enableMongoWrites)

            Stepper(value: $settings.mongoMonitoring.detailChunkLimit, in: 10...500, step: 10) {
                Text("Detail chunk fetch limit: \(settings.mongoMonitoring.clampedDetailChunkLimit)")
            }
            .disabled(!settings.mongoMonitoring.enabled || !settings.mongoMonitoring.enableMongoWrites)

            Stepper(value: $settings.mongoMonitoring.transcriptPreviewByteLimit, in: 10_000...2_000_000, step: 10_000) {
                Text(
                    "Transcript preview window: \(ByteCountFormatter.string(fromByteCount: Int64(settings.mongoMonitoring.clampedTranscriptPreviewByteLimit), countStyle: .file))"
                )
            }
            .disabled(!settings.mongoMonitoring.enabled)

            Stepper(value: $settings.mongoMonitoring.databaseRetentionDays, in: 1...3_650, step: 1) {
                Text("Database retention window: \(settings.mongoMonitoring.clampedDatabaseRetentionDays) day(s)")
            }
            .disabled(!settings.mongoMonitoring.enabled || !settings.mongoMonitoring.enableMongoWrites)

            Stepper(value: $settings.mongoMonitoring.localTranscriptRetentionDays, in: 1...3_650, step: 1) {
                Text("Local transcript retention window: \(settings.mongoMonitoring.clampedLocalTranscriptRetentionDays) day(s)")
            }
            .disabled(!settings.mongoMonitoring.enabled)

            Toggle("Keep local transcript files after launch", isOn: $settings.mongoMonitoring.keepLocalTranscriptFiles)
                .disabled(!settings.mongoMonitoring.enabled)

            if settings.mongoMonitoring.captureMode.usesScriptKeyLogging {
                Text("Warning: Input + output capture can record passwords, tokens, and any other secrets typed into monitored terminals.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Test Connection", action: testConnection)
                    .disabled(!settings.mongoMonitoring.enabled || !settings.mongoMonitoring.enableMongoWrites)
                Button("Reveal Transcript Folder", action: revealTranscriptFolder)
            }
        }
    }
}

private struct SettingsDataSection: View {
    let revealStateFolder: () -> Void
    let exportState: () -> Void
    let importState: () -> Void

    var body: some View {
        Section("Data") {
            HStack {
                Button("Export State…", action: exportState)
                Button("Import State…", action: importState)
                Button("Reveal State Folder", action: revealStateFolder)
            }
        }
    }
}

private struct LogsTabPane: View {
    @ObservedObject var logger: LaunchLogger
    let exportVisibleLogs: ([LogEntry]) -> Void
    let exportDiagnostics: () -> Void

    @State private var search: String = ""
    @State private var levelFilter: String = "all"
    @State private var categoryFilter: String = "all"

    private var filteredLogs: [LogEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return logger.entries.filter { entry in
            let matchesLevel = levelFilter == "all" || entry.level.rawValue == levelFilter
            let matchesCategory = categoryFilter == "all" || entry.category.rawValue == categoryFilter
            let matchesQuery = query.isEmpty ||
                entry.message.lowercased().contains(query) ||
                entry.level.rawValue.lowercased().contains(query) ||
                entry.category.rawValue.lowercased().contains(query) ||
                (entry.details?.lowercased().contains(query) ?? false)
            return matchesLevel && matchesCategory && matchesQuery
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search log", text: $search)
                Picker("Level", selection: $levelFilter) {
                    Text("All Levels").tag("all")
                    ForEach(LogLevel.allCases) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                }
                .frame(width: 150)
                Picker("Category", selection: $categoryFilter) {
                    Text("All Categories").tag("all")
                    ForEach(LogCategory.allCases) { category in
                        Text(category.displayName).tag(category.rawValue)
                    }
                }
                .frame(width: 170)
                Button("Clear") { logger.clear() }
                Button("Reveal Log Folder") { logger.revealLogDirectory() }
                Button("Copy Visible") {
                    let text = filteredLogs.map(formattedLogLine).joined(separator: "\n")
                    ClipboardService.copy(text)
                }
                Button("Export Visible…") { exportVisibleLogs(filteredLogs) }
                Button("Export Diagnostics…", action: exportDiagnostics)
            }
            List(filteredLogs) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.level.displayName)
                            .font(.headline)
                            .foregroundStyle(color(for: entry.level))
                        Text(entry.category.displayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                        if entry.repeatCount > 1 {
                            Text("×\(entry.repeatCount)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.message)
                    if let details = entry.details, !details.isEmpty {
                        Text(details)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func formattedLogLine(_ entry: LogEntry) -> String {
        var line = "[\(entry.timestamp.formatted(date: .numeric, time: .standard))] [\(entry.level.rawValue.uppercased())] [\(entry.category.rawValue.uppercased())] \(entry.message)"
        if entry.repeatCount > 1 {
            line += " (x\(entry.repeatCount))"
        }
        if let details = entry.details, !details.isEmpty {
            line += "\n    \(details)"
        }
        return line
    }
}

private struct KeystrokesTabPane: View {
    let selectedProfileName: String?
    let activeProfilePrefix: String
    let selectedProfileAutomationMode: GeminiLaunchMode?
    let selectedProfileAutomationEnabled: Bool?
    let defaultHotkeyPrefix: String
    let canToggleAutomation: Bool
    let setSelectedProfileAutomation: (_ enabled: Bool) -> Void

    private var supportsRunnerHotkeys: Bool {
        selectedProfileAutomationMode == .automationRunner
    }

    private var automationPrefixLabel: String {
        activeProfilePrefix.isEmpty ? defaultHotkeyPrefix : activeProfilePrefix
    }

    private var automationModeDescription: String {
        guard let selectedProfileAutomationMode else {
            return "No Gemini profile selected (defaults shown)."
        }

        switch selectedProfileAutomationMode {
        case .automationRunner:
            return "Active for selected profile: automation runner mode."

        case .directWrapper:
            return "Selected profile is in direct wrapper mode; PTY hotkeys are not available."
        }
    }

    private var selectedProfileStateLine: String {
        guard let selectedProfileAutomationEnabled else {
            return "No selected Gemini profile."
        }
        return "Automation for selected Gemini profile is currently: \(selectedProfileAutomationEnabled ? "ON" : "OFF")."
    }

    private var globalShortcuts: [(String, String)] {
        [
            ("⌘ ⇧ R", "Refresh diagnostics"),
            ("⌘ ⇧ L", "Relaunch last launch"),
            ("⌘ ⇧ A", "Toggle automation for selected profile"),
            ("⌘ ⇧ O", "Enable automation for selected profile"),
            ("⌘ ⇧ X", "Disable automation for selected profile")
        ]
    }

    private var runnerShortcuts: [(String, String)] {
        [
            ("\(automationPrefixLabel) h / \(automationPrefixLabel) ?", "Show in-terminal automation help"),
            ("\(automationPrefixLabel) a", "Toggle automation"),
            ("\(automationPrefixLabel) o", "Enable automation"),
            ("\(automationPrefixLabel) x", "Disable automation"),
            ("\(automationPrefixLabel) p", "Pause automation temporarily"),
            ("\(automationPrefixLabel) e", "Re-check last visible prompt"),
            ("\(automationPrefixLabel) i", "Print automation status"),
            ("\(automationPrefixLabel) s", "Request model switch"),
            ("\(automationPrefixLabel) r", "Restart Gemini session"),
            ("\(automationPrefixLabel) c", "Send Ctrl-C + pause"),
            ("\(automationPrefixLabel) q", "Quit Gemini session")
        ]
    }

    private var menuOptions: [(String, String)] {
        [
            ("1 / 2 / 3...", "Use prompt numbers for in-session Gemini menus"),
            ("Keep trying", "Default action for usage-limit prompts when automation is enabled"),
            ("Switch to …", "Switch models when demand keeps repeating"),
            ("Stop", "Stop automation attempt for current prompt")
        ]
    }

    private var exportedKeystrokeText: String {
        var lines: [String] = []
        lines.append("Global application shortcuts")
        for item in globalShortcuts {
            lines.append("  \(item.0): \(item.1)")
        }

        lines.append("")
        lines.append("Gemini automation hotkeys")
        lines.append("  \(automationModeDescription)")
        if supportsRunnerHotkeys {
            lines.append("  Runner hotkeys use the profile or default prefix: \(automationPrefixLabel)")
            for item in runnerShortcuts {
                lines.append("  \(item.0): \(item.1)")
            }
        } else {
            lines.append("  Select a Gemini profile using Automation Runner mode to enable PTY-local hotkeys.")
            lines.append("  Supported prefixes: ctrl-g, ctrl-], ctrl-t, ctrl-\\.")
        }
        lines.append("  \(selectedProfileStateLine)")

        lines.append("")
        lines.append("In-session menu controls")
        for item in menuOptions {
            lines.append("  \(item.0): \(item.1)")
        }

        return lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Keystroke Reference")
                        .font(.title3.bold())
                    Spacer()
                    Button("Copy Keystrokes") {
                        ClipboardService.copy(exportedKeystrokeText)
                    }
                }

                GroupBox("Global application shortcuts") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(globalShortcuts.enumerated()), id: \.offset) { _, entry in
                            let combo = entry.0
                            let action = entry.1
                            KeystrokeRow(keys: combo, action: action)
                        }
                    }
                }

                GroupBox("Automation quick actions") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Apply automation changes for the selected Gemini profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button("Enable Automation") {
                                setSelectedProfileAutomation(true)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canToggleAutomation || selectedProfileAutomationEnabled == true)
                            Button("Disable Automation") {
                                setSelectedProfileAutomation(false)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canToggleAutomation || selectedProfileAutomationEnabled == false)
                            Button("Toggle Automation") {
                                setSelectedProfileAutomation(!(selectedProfileAutomationEnabled ?? false))
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canToggleAutomation)
                        }
                    }
                }

                GroupBox("Gemini automation hotkeys") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(automationModeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if supportsRunnerHotkeys {
                            Text("Runner hotkeys use the profile or default prefix: \(automationPrefixLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(Array(runnerShortcuts.enumerated()), id: \.offset) { _, entry in
                                let combo = entry.0
                                let action = entry.1
                                KeystrokeRow(keys: combo, action: action)
                            }
                        } else {
                            Text("Select a Gemini profile using Automation Runner mode to enable PTY-local hotkeys.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Supported prefixes: ctrl-g, ctrl-], ctrl-t, ctrl-\\.")
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        Text(selectedProfileStateLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("In-session menu controls") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("For prompts that expose numeric options (for example capacity/usage menus), you can use the on-screen number keys; automation also handles known prompts automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(Array(menuOptions.enumerated()), id: \.offset) { _, entry in
                            let combo = entry.0
                            let action = entry.1
                            KeystrokeRow(keys: combo, action: action)
                        }
                    }
                }

                GroupBox("Context") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Selected profile")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(selectedProfileName ?? "None")
                                .font(.system(.caption, design: .monospaced))
                        }
                        if !defaultHotkeyPrefix.isEmpty {
                            HStack {
                                Text("Default hotkey prefix")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(defaultHotkeyPrefix)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                        HStack {
                            Text("Automation state")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(selectedProfileStateLine)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .font(.caption)
                }
            }
            .padding()
        }
    }
}

private struct KeystrokeRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                .frame(minWidth: 150, alignment: .leading)
            Text(action)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct LaunchCenterPane: View {
    @ObservedObject var preview: LaunchPreviewStore
    let profile: LaunchProfile?
    let selectedEnvironmentPreset: EnvironmentPreset?
    let selectedBootstrapPreset: ShellBootstrapPreset?
    let featuredWorkbenches: [LaunchWorkbench]
    let bookmarks: [WorkspaceBookmark]
    let cautionMessages: [String]
    let isVSCodeAvailable: Bool
    let favoriteProfiles: [LaunchProfile]

    let launchSelectedProfile: () -> Void
    let duplicateSelectedProfile: () -> Void
    let applyPreset: (LaunchBehaviorPreset) -> Void
    let bookmarkWorkspace: () -> Void
    let revealWorkspace: () -> Void
    let openInFinder: () -> Void
    let openInVSCode: () -> Void
    let exportSelectedProfileLauncher: () -> Void
    let launchQuick: (LaunchTemplate) -> Void
    let launchFavorite: (LaunchProfile) -> Void
    let createWorkbenchFromCurrentProfile: () -> Void
    let launchWorkbench: (LaunchWorkbench) -> Void
    let editWorkbench: (UUID) -> Void
    let copyCombinedCommands: () -> Void
    let copyAppleScript: () -> Void
    let exportPlanLauncher: () -> Void
    let toggleAutomation: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                currentSelectionCard
                quickLaunchCard
                quickFavoriteProfilesCard
                featuredWorkbenchesCard
                LaunchPlanPreviewCard(
                    plan: preview.planPreview,
                    suggestedName: (profile?.name ?? "Launch") + ".command",
                    copyCombinedCommands: copyCombinedCommands,
                    copyAppleScript: copyAppleScript,
                    exportLauncher: exportPlanLauncher
                )
                .equatable()
                launchPreflightCard
                if !cautionMessages.isEmpty {
                    ForEach(cautionMessages, id: \.self) { caution in
                        GroupBox("Caution") {
                            Text(caution)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var currentSelectionCard: some View {
        GroupBox("Current Selection") {
            VStack(alignment: .leading, spacing: 8) {
                if let profile {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.title2.bold())
                            Text(profile.agentKind.summary)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profile.agentKind == .gemini {
                            Button(action: toggleAutomation) {
                                Label(profile.geminiAutomationEnabled ? "Automation ON" : "Automation OFF",
                                      systemImage: profile.geminiAutomationEnabled ? "bolt.fill" : "bolt.slash.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(profile.geminiAutomationEnabled ? .green : .gray)
                            .help("Toggle automation for this profile (Cmd+Shift+A)")
                        }
                    }
                    HStack(spacing: 12) {
                        Label(profile.openMode.displayName, systemImage: "terminal")
                        Label(profile.expandedWorkingDirectory, systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack(spacing: 10) {
                        if let selectedEnvironmentPreset {
                            Label(selectedEnvironmentPreset.name, systemImage: "switch.2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let selectedBootstrapPreset {
                            Label(selectedBootstrapPreset.name, systemImage: "terminal.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if profile.openWorkspaceInFinderOnLaunch {
                            Label("Finder after launch", systemImage: WorkspaceCompanionApp.finder.systemImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if profile.openWorkspaceInVSCodeOnLaunch {
                            Label("VS Code after launch", systemImage: WorkspaceCompanionApp.visualStudioCode.systemImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Label("\(profile.tabLaunchDelayMs) ms tab delay", systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Launch Selected", action: launchSelectedProfile)
                            .buttonStyle(.borderedProminent)
                        Button("Duplicate", action: duplicateSelectedProfile)
                        Menu("Apply Preset") {
                            ForEach(LaunchBehaviorPreset.allCases) { preset in
                                Button(preset.displayName) {
                                    applyPreset(preset)
                                }
                            }
                        }
                        Button("Bookmark Workspace", action: bookmarkWorkspace)
                        Button("Reveal Workspace", action: revealWorkspace)
                        Button("Open in Finder", action: openInFinder)
                        Button("Open in VS Code", action: openInVSCode)
                            .disabled(!isVSCodeAvailable)
                        Button("Export Launcher…", action: exportSelectedProfileLauncher)
                    }
                } else {
                    Text("No profile selected.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quickFavoriteProfilesCard: some View {
        if favoriteProfiles.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            GroupBox("Quick Favorites") {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(favoriteProfiles) { profile in
                            Button {
                                launchFavorite(profile)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(profile.name, systemImage: "star.fill")
                                        .font(.headline)
                                    Text(profile.agentKind.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        )
    }

    private var quickLaunchCard: some View {
        GroupBox("Quick Launch") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Start a fresh iTerm2 session from a ready-made launcher template.")
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(LaunchTemplateCatalog.quickLaunchTemplates) { template in
                        Button {
                            launchQuick(template)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(template.title, systemImage: template.systemImage)
                                    .font(.headline)
                                Text(template.agentKind.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var featuredWorkbenchesCard: some View {
        GroupBox("Workbenches") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Launch a whole solo-dev stack in one step. Workbenches can share a workspace bookmark across every tab.")
                    .foregroundStyle(.secondary)
                if featuredWorkbenches.isEmpty {
                    HStack {
                        Text("No workbenches yet.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Create from Current Profile", action: createWorkbenchFromCurrentProfile)
                    }
                } else {
                    ForEach(featuredWorkbenches) { workbench in
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workbench.name)
                                    .font(.headline)
                                Text(workbench.role.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(workbench.profileIDs.count == 1 ? "1 tab" : "\(workbench.profileIDs.count) tabs")
                                    .foregroundStyle(.secondary)
                                Text("Startup delay: \(workbench.startupDelayMs)ms")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let sharedBookmarkID = workbench.sharedBookmarkID,
                                   let bookmark = bookmarks.first(where: { $0.id == sharedBookmarkID }) {
                                    Label(bookmark.name, systemImage: "folder")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Launch") { launchWorkbench(workbench) }
                                .buttonStyle(.borderedProminent)
                            Button("Edit") { editWorkbench(workbench.id) }
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var launchPreflightCard: some View {
        GroupBox("Preflight") {
            VStack(alignment: .leading, spacing: 8) {
                if preview.diagnostics.errors.isEmpty, preview.diagnostics.warnings.isEmpty {
                    Label("Everything needed for the current plan looks ready.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(preview.diagnostics.errors, id: \.self) { message in
                        Label(message, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                    ForEach(preview.diagnostics.warnings, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DiagnosticsTabPane: View {
    @ObservedObject var preview: LaunchPreviewStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Resolved Executables") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(preview.diagnostics.statuses) { status in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(status.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(status.isError ? "Missing" : "Ready")
                                        .foregroundStyle(status.isError ? .red : .green)
                                }
                                Text("Requested: \(status.requested)")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                if let resolved = status.resolved {
                                    Text("Resolved: \(resolved)")
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                if let resolutionSource = status.resolutionSource, !resolutionSource.isEmpty {
                                    Text("Source: \(resolutionSource)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(status.detail)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                GroupBox("iTerm2 Runtime") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Discovered iTerm2 profiles", systemImage: "terminal")
                            Spacer()
                            Text("\(preview.availableITermProfiles.count)")
                                .font(.headline)
                        }
                        Text(preview.iTermProfileSourceDescription.isEmpty ? "Profile discovery information will appear here after diagnostics refresh." : preview.iTermProfileSourceDescription)
                            .foregroundStyle(.secondary)
                        if !preview.availableITermProfiles.isEmpty {
                            Text(preview.availableITermProfiles.joined(separator: ", "))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Preflight Summary") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(preview.diagnostics.errors, id: \.self) { item in
                            Label(item, systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                        ForEach(preview.diagnostics.warnings, id: \.self) { item in
                            Label(item, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if preview.diagnostics.errors.isEmpty, preview.diagnostics.warnings.isEmpty {
                            Label("No issues detected.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                CurrentPlanDiagnosticsCard(plan: preview.planPreview)
                    .equatable()
            }
            .padding()
        }
    }
}
