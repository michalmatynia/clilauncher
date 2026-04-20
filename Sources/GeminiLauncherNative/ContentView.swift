import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var logger: LaunchLogger
    @EnvironmentObject private var terminalMonitor: TerminalMonitorStore

    @State private var selectedTab: LauncherTab = .launch
    @State private var profileSearch: String = ""
    @State private var bookmarkSearch: String = ""
    @State private var workbenchSearch: String = ""
    @State private var logSearch: String = ""
    @State private var logLevelFilter: String = "all"
    @State private var logCategoryFilter: String = "all"
    @State private var monitorSearch: String = ""
    @State private var diagnostics: PreflightCheck = PreflightCheck()
    @State private var availableITermProfiles: [String] = []
    @State private var iTermProfileSourceDescription: String = ""
    @State private var bookmarkSelection: UUID?
    @State private var workbenchSelection: UUID?
    @State private var liveRefreshTask: Task<Void, Never>? = nil
    @State private var showingDeleteProfileAlert = false
    @State private var showingDeleteWorkbenchAlert = false

    private let commandBuilder = CommandBuilder()
    private let planner = LaunchPlanner()
    private let preflight = PreflightService()
    private let iTermProfiles = ITerm2ProfileService()
    private let iTermLauncher = TerminalLauncherDispatcher()
    private let launcherExporter = LauncherExportService()
    private let companionLauncher = WorkspaceCompanionLauncher()

    @ViewBuilder
    private func providerSection(for kind: AgentKind, profile: Binding<LaunchProfile>) -> some View {
        let sectionTitle = kind.displayName
        switch kind {
        case .gemini:
            geminiSection(profile: profile, title: sectionTitle)
        case .copilot:
            copilotSection(profile: profile, title: sectionTitle)
        case .codex:
            codexSection(profile: profile, title: sectionTitle)
        case .claudeBypass:
            claudeSection(profile: profile, title: sectionTitle)
        case .kiroCLI:
            kiroSection(profile: profile, title: sectionTitle)
        case .ollamaLaunch:
            ollamaSection(profile: profile, title: sectionTitle)
        }
    }

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

            logsTab
                .tabItem { Label("Log", systemImage: "text.append") }
                .tag(LauncherTab.logs)

            settingsTab
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(LauncherTab.settings)
        }
        .frame(minWidth: 1240, minHeight: 820)
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
        .onChange(of: selectedTab) { selection in
            if selection == .monitoring {
                terminalMonitor.refreshRecentSessions(settings: store.settings, logger: logger)
            } else if selection == .launch {
                scheduleLiveStateRefresh(immediate: true, includeITermDiscovery: true)
            }
        }
        .onChange(of: store.selectedProfileID) { _ in scheduleLiveStateRefresh() }
        .onChange(of: store.settings) { _ in
            logger.apply(settings: store.settings.observability)
            scheduleLiveStateRefresh()
        }
        .onChange(of: store.profiles) { _ in scheduleLiveStateRefresh() }
        .onChange(of: store.bookmarks) { _ in scheduleLiveStateRefresh() }
        .onChange(of: store.workbenches) { _ in scheduleLiveStateRefresh() }
    }

    private var filteredProfiles: [LaunchProfile] {
        let query = profileSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.profiles }
        return store.profiles.filter {
            $0.name.lowercased().contains(query) ||
            $0.tags.joined(separator: " ").lowercased().contains(query) ||
            $0.agentKind.displayName.lowercased().contains(query)
        }
    }

    private var filteredBookmarks: [WorkspaceBookmark] {
        let query = bookmarkSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.bookmarks }
        return store.bookmarks.filter {
            $0.name.lowercased().contains(query) ||
            $0.path.lowercased().contains(query) ||
            $0.tags.joined(separator: " ").lowercased().contains(query)
        }
    }

    private var filteredWorkbenches: [LaunchWorkbench] {
        let query = workbenchSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.workbenches }
        return store.workbenches.filter {
            $0.name.lowercased().contains(query) ||
            $0.notes.lowercased().contains(query) ||
            $0.tags.joined(separator: " ").lowercased().contains(query) ||
            $0.role.displayName.lowercased().contains(query) ||
            String($0.startupDelayMs).contains(query) ||
            $0.postLaunchActionHints.joined(separator: " ").lowercased().contains(query)
        }
    }

    private var filteredLogs: [LogEntry] {
        let query = logSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return logger.entries.filter { entry in
            let matchesLevel = logLevelFilter == "all" || entry.level.rawValue == logLevelFilter
            let matchesCategory = logCategoryFilter == "all" || entry.category.rawValue == logCategoryFilter
            let matchesQuery = query.isEmpty || entry.message.lowercased().contains(query) || entry.level.rawValue.lowercased().contains(query) || entry.category.rawValue.lowercased().contains(query) || (entry.details?.lowercased().contains(query) ?? false)
            return matchesLevel && matchesCategory && matchesQuery
        }
    }

    private var filteredMonitorSessions: [TerminalMonitorSession] {
        let query = monitorSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return terminalMonitor.sessions }
        return terminalMonitor.sessions.filter {
            $0.profileName.lowercased().contains(query) ||
            $0.workingDirectory.lowercased().contains(query) ||
            $0.transcriptPath.lowercased().contains(query) ||
            $0.lastPreview.lowercased().contains(query) ||
            $0.lastDatabaseMessage.lowercased().contains(query) ||
            ($0.statusReason?.lowercased().contains(query) ?? false) ||
            ($0.lastError?.lowercased().contains(query) ?? false) ||
            $0.agentKind.displayName.lowercased().contains(query) ||
            $0.status.displayName.lowercased().contains(query)
        }
    }

    private var liveMonitorSessionCount: Int {
        terminalMonitor.sessions.filter { !$0.isHistorical }.count
    }

    private var historicalMonitorSessionCount: Int {
        terminalMonitor.sessions.filter(\.isHistorical).count
    }

    private var completedMonitorSessionCount: Int {
        terminalMonitor.sessions.filter { $0.status == .completed }.count
    }

    private var failedMonitorSessionCount: Int {
        terminalMonitor.sessions.filter { $0.status == .failed }.count
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
        return store.workbenches.first(where: { $0.id == workbenchSelection })
    }

    private var planPreview: PlannedLaunch? {
        guard let profile = store.selectedProfile else { return nil }
        return try? planner.buildPlan(primary: profile, allProfiles: store.profiles, settings: store.settings)
    }

    private var workbenchPlanPreview: PlannedLaunch? {
        guard let workbench = selectedWorkbench else { return nil }
        return try? planner.buildWorkbenchPlan(workbench: workbench, profiles: store.profiles, bookmarks: store.bookmarks, settings: store.settings)
    }

    private var selectedWorkbenchDiagnostics: PreflightCheck {
        guard let workbench = selectedWorkbench else { return PreflightCheck() }
        return preflight.run(workbench: workbench, profiles: store.profiles, bookmarks: store.bookmarks, settings: store.settings)
    }


    private var selectedEnvironmentPreset: EnvironmentPreset? {
        guard let presetID = store.selectedProfile?.environmentPresetID else { return nil }
        return store.settings.environmentPresets.first(where: { $0.id == presetID })
    }

    private var selectedBootstrapPreset: ShellBootstrapPreset? {
        guard let presetID = store.selectedProfile?.bootstrapPresetID else { return nil }
        return store.settings.shellBootstrapPresets.first(where: { $0.id == presetID })
    }

    private var featuredWorkbenches: [LaunchWorkbench] {
        let favorites = store.workbenches.filter { $0.tags.contains(where: { $0.lowercased() == "favorite" }) }
        if !favorites.isEmpty { return Array(favorites.prefix(4)) }
        return Array(store.workbenches.prefix(4))
    }

    private var launchCenterTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryHeader
                quickLaunchGrid
                featuredWorkbenchesCard
                planCard
                preflightCard
                cautionBoxes
            }
            .padding()
        }
    }

    private var summaryHeader: some View {
        GroupBox("Current Selection") {
            VStack(alignment: .leading, spacing: 8) {
                if let profile = store.selectedProfile {
                    Text(profile.name)
                        .font(.title2.bold())
                    Text(profile.agentKind.summary)
                        .foregroundStyle(.secondary)
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
                        Button("Launch Selected") { launchSelectedProfile() }
                            .buttonStyle(.borderedProminent)
                        Button("Duplicate") { store.duplicateSelectedProfile() }
                        Menu("Apply Preset") {
                            ForEach(LaunchBehaviorPreset.allCases) { preset in
                                Button(preset.displayName) {
                                    store.updateSelected { $0.applyBehaviorPreset(preset) }
                                }
                            }
                        }
                        Button("Bookmark Workspace") { store.addBookmark(from: profile) }
                        Button("Reveal Workspace") { store.reveal(profile.expandedWorkingDirectory) }
                        Button("Open in Finder") { openWorkspaceNow(profile, app: .finder) }
                        Button("Open in VS Code") { openWorkspaceNow(profile, app: .visualStudioCode) }
                            .disabled(!companionLauncher.isAvailable(.visualStudioCode))
                        Button("Export Launcher…") { exportSelectedProfileLauncher() }
                    }
                } else {
                    Text("No profile selected.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quickLaunchGrid: some View {
        GroupBox("Quick Launch") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Start a fresh iTerm2 session from a ready-made launcher template.")
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(LaunchTemplateCatalog.quickLaunchTemplates) { template in
                        quickLaunchButton(title: template.title, systemImage: template.systemImage) {
                            launchQuick(template)
                        }
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
                        Button("Create from Current Profile") { addWorkbenchFromCurrentSelection() }
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
                                   let bookmark = store.bookmarks.first(where: { $0.id == sharedBookmarkID }) {
                                    Label(bookmark.name, systemImage: "folder")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Launch") { launch(workbench: workbench) }
                                .buttonStyle(.borderedProminent)
                            Button("Edit") {
                                workbenchSelection = workbench.id
                                selectedTab = .workbenches
                            }
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var planCard: some View {
        GroupBox("Launch Plan Preview") {
            VStack(alignment: .leading, spacing: 10) {
                if let planPreview {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(planPreview.items.count) tab(s) will open")
                                .font(.headline)
                            HStack(spacing: 10) {
                                Label("\(planPreview.tabLaunchDelayMs) ms between tabs", systemImage: "timer")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !planPreview.postLaunchActions.isEmpty {
                                    Label("\(planPreview.postLaunchActions.count) post-launch action(s)", systemImage: "square.and.arrow.up.on.square")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Button("Copy Combined Commands") {
                            ClipboardService.copy(planPreview.combinedCommandPreview)
                            logger.log(.info, "Copied combined launch plan.")
                        }
                        Button("Copy AppleScript") {
                            ClipboardService.copy(iTermLauncher.buildAppleScript(plan: planPreview))
                            logger.log(.info, "Copied combined AppleScript preview.")
                        }
                        Button("Export Launcher…") {
                            exportLauncher(plan: planPreview, suggestedName: (store.selectedProfile?.name ?? "Launch") + ".command")
                        }
                    }
                    if !planPreview.postLaunchActions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Post-launch actions")
                                .font(.subheadline.weight(.semibold))
                            ForEach(planPreview.postLaunchActions) { action in
                                Label(action.label, systemImage: action.app.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    ForEach(planPreview.items) { item in
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

    private var preflightCard: some View {
        GroupBox("Preflight") {
            VStack(alignment: .leading, spacing: 8) {
                if diagnostics.errors.isEmpty && diagnostics.warnings.isEmpty {
                    Label("Everything needed for the current plan looks ready.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(diagnostics.errors, id: \.self) { message in
                        Label(message, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                    ForEach(diagnostics.warnings, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var cautionBoxes: some View {
        if let profile = store.selectedProfile {
            let cautions = LaunchTemplateCatalog.cautions(for: profile)
            if !cautions.isEmpty {
                ForEach(cautions, id: \.self) { caution in
                    cautionBox(title: "Caution", body: caution)
                }
            }
        }
    }

    private var profilesTab: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search profiles", text: $profileSearch)
                    Menu {
                        ForEach(AgentKind.allCases) { kind in
                            Button("Add \(kind.displayName)") {
                                store.addProfile(kind: kind)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add profile")
                }
                .padding()

                List(selection: $store.selectedProfileID) {
                    ForEach(filteredProfiles) { profile in
                        profileRow(profile)
                            .tag(profile.id)
                            .contextMenu {
                                Button("Duplicate") {
                                    store.selectedProfileID = profile.id
                                    store.duplicateSelectedProfile()
                                }
                                Button("Bookmark Workspace") {
                                    store.addBookmark(from: profile)
                                }
                            }
                    }
                }
            }
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

    private func profileRow(_ profile: LaunchProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(profile.name)
                        .font(.headline)
                    if profile.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
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
    }

    private func profileEditor(profile: Binding<LaunchProfile>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("General") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Profile name", text: profile.name)
                        Toggle("Favorite", isOn: profile.isFavorite)
                        TextField("Tags (comma separated)", text: Binding(
                            get: { profile.wrappedValue.tags.joined(separator: ", ") },
                            set: { profile.wrappedValue.tags = parseTags($0) }
                        ))
                        TextField("Notes", text: profile.notes, axis: .vertical)
                            .lineLimit(3...6)

                        Picker("Tool", selection: profile.agentKind) {
                            ForEach(AgentKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .onChange(of: profile.wrappedValue.agentKind) { newValue in
                            store.updateSelected { updated in
                                updated.agentKind = newValue
                                updated.applyKindDefaults(settings: store.settings)
                            }
                        }

                        HStack {
                            TextField("Working directory", text: profile.workingDirectory)
                            Button("Choose…") {
                                if let path = FilePanelService.chooseDirectory() {
                                    profile.wrappedValue.workingDirectory = path
                                }
                            }
                            Button("Reveal") {
                                store.reveal(profile.wrappedValue.expandedWorkingDirectory)
                            }
                        }

                        Picker("Terminal application", selection: profile.terminalApp) {
                            ForEach(TerminalApp.allCases) { app in
                                Text(app.displayName).tag(app)
                            }
                        }

                        Picker("Open in \(profile.wrappedValue.terminalApp.displayName)", selection: profile.openMode) {
                            ForEach(ITermOpenMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }

                        if profile.wrappedValue.terminalApp == .iterm2 {
                            Picker("iTerm2 profile", selection: profile.iTermProfile) {
                                Text("Default Profile").tag("")
                                ForEach(availableITermProfiles, id: \.self) { item in
                                    Text(item).tag(item)
                                }
                            }
                        }

                        Toggle("Open workspace in Finder after launch", isOn: profile.openWorkspaceInFinderOnLaunch)
                        Toggle("Open workspace in VS Code after launch", isOn: profile.openWorkspaceInVSCodeOnLaunch)
                        Stepper(value: profile.tabLaunchDelayMs, in: 50...3000, step: 50) {
                            Text("Delay between iTerm2 tabs: \(profile.wrappedValue.tabLaunchDelayMs) ms")
                        }

                        Picker("Environment preset", selection: profile.environmentPresetID) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.settings.environmentPresets) { preset in
                                Text(preset.name).tag(Optional(preset.id))
                            }
                        }

                        Picker("Bootstrap preset", selection: profile.bootstrapPresetID) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.settings.shellBootstrapPresets) { preset in
                                Text(preset.name).tag(Optional(preset.id))
                            }
                        }

                        HStack {
                            Text(mergedEnvironmentSummary(for: profile.wrappedValue))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Manage Shared Presets") {
                                selectedTab = .settings
                            }
                        }

                        TextField("Extra CLI args", text: profile.extraCLIArgs)
                        TextField("Shell bootstrap command", text: profile.shellBootstrapCommand, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }

                providerSection(for: profile.wrappedValue.agentKind, profile: profile)

                companionSection(profile: profile)
                environmentSection(profile: profile)
                actionRow(profile: profile)
            }
            .padding()
        }
    }

    private func geminiSection(profile: Binding<LaunchProfile>, title: String) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Flavor", selection: profile.geminiFlavor) {
                    ForEach(GeminiFlavor.allCases) { flavor in
                        Text(flavor.displayName).tag(flavor)
                    }
                }
                .onChange(of: profile.wrappedValue.geminiFlavor) { _ in
                    store.updateSelected { updated in
                        updated.applyGeminiFlavorDefaults()
                    }
                }

                Picker("Launch mode", selection: profile.geminiLaunchMode) {
                    ForEach(GeminiLaunchMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(
                    profile.wrappedValue.geminiLaunchMode == .automationRunner
                    ? "Automation runner mode uses the bundled Gemini runner when this path is blank. Node is required. Install `@lydell/node-pty` or `node-pty` in the workspace for PTY hotkeys and prompt automation."
                    : "Direct wrapper mode launches the configured Gemini wrapper directly and skips the bundled automation runner."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                TextField("Wrapper command", text: profile.geminiWrapperCommand)
                TextField("ISO home", text: profile.geminiISOHome)
                HStack {
                    TextField("Initial model", text: profile.geminiInitialModel)
                    Button("Reset") {
                        profile.wrappedValue.geminiInitialModel = profile.wrappedValue.geminiFlavor.defaultInitialModel
                    }
                    .help("Reset initial model to flavor default")
                }
                HStack(alignment: .top) {
                    TextField("Model chain", text: profile.geminiModelChain, axis: .vertical)
                        .lineLimit(2...4)
                    Button("Reset") {
                        profile.wrappedValue.geminiModelChain = profile.wrappedValue.geminiFlavor.defaultModelChain
                    }
                    .help("Reset model chain to flavor default")
                }
                TextField("Automation runner path", text: profile.geminiAutomationRunnerPath)
                Text("Leave the automation runner path blank to use the app-bundled runner for \(profile.wrappedValue.geminiFlavor.displayName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Node executable", text: profile.nodeExecutable)
                TextField("Hotkey prefix", text: profile.geminiHotkeyPrefix)

                HStack {
                    Stepper(value: profile.geminiKeepTryMax, in: 0...25) {
                        Text("Keep-try max: \(profile.wrappedValue.geminiKeepTryMax)")
                    }
                    Stepper(value: profile.geminiManualOverrideMs, in: 1000...120000, step: 1000) {
                        Text("Manual override: \(profile.wrappedValue.geminiManualOverrideMs) ms")
                    }
                }

                Picker("Auto continue", selection: profile.geminiAutoContinueMode) {
                    ForEach(AutoContinueMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle("Resume latest", isOn: profile.geminiResumeLatest)
                Toggle("Automation enabled", isOn: profile.geminiAutomationEnabled)
                Toggle("Auto allow session permissions", isOn: profile.geminiAutoAllowSessionPermissions)
                Toggle("Never switch model", isOn: profile.geminiNeverSwitch)
                Toggle("Quiet child node warnings", isOn: profile.geminiQuietChildNodeWarnings)
                Toggle("Raw output", isOn: profile.geminiRawOutput)
            }
        }
    }

    private func copilotSection(profile: Binding<LaunchProfile>, title: String) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Executable", text: profile.copilotExecutable)
                Picker("Mode", selection: profile.copilotMode) {
                    ForEach(CopilotMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                TextField("Model", text: profile.copilotModel)
                TextField("COPILOT_HOME", text: profile.copilotHome)
                TextField("Initial prompt", text: profile.copilotInitialPrompt, axis: .vertical)
                    .lineLimit(2...5)
                Stepper(value: profile.copilotMaxAutopilotContinues, in: 1...50) {
                    Text("Max autopilot continues: \(profile.wrappedValue.copilotMaxAutopilotContinues)")
                }
            }
        }
    }

    private func codexSection(profile: Binding<LaunchProfile>, title: String) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Executable", text: profile.codexExecutable)
                Picker("Mode", selection: profile.codexMode) {
                    ForEach(CodexMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                TextField("Model", text: profile.codexModel)
            }
        }
    }

    private func claudeSection(profile: Binding<LaunchProfile>, title: String) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Executable", text: profile.claudeExecutable)
                TextField("Model", text: profile.claudeModel)
            }
        }
    }

    private func kiroSection(profile: Binding<LaunchProfile>, title: String) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Executable", text: profile.kiroExecutable)
                Picker("Mode", selection: profile.kiroMode) {
                    ForEach(KiroMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
        }
    }

    private func ollamaSection(profile: Binding<LaunchProfile>, title: String) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Executable", text: profile.ollamaExecutable)
                Picker("Integration", selection: profile.ollamaIntegration) {
                    ForEach(OllamaIntegration.allCases) { integration in
                        Text(integration.displayName).tag(integration)
                    }
                }
                TextField("Model", text: profile.ollamaModel)
                Toggle("Config only", isOn: profile.ollamaConfigOnly)
            }
        }
    }

    private func companionSection(profile: Binding<LaunchProfile>) -> some View {
        GroupBox("Companion Tabs") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch companion tabs with this profile", isOn: profile.autoLaunchCompanions)
                if profile.wrappedValue.autoLaunchCompanions {
                    ForEach(store.profiles.filter { $0.id != profile.wrappedValue.id }) { companion in
                        Toggle(isOn: Binding(
                            get: { profile.wrappedValue.companionProfileIDs.contains(companion.id) },
                            set: { enabled in
                                if enabled {
                                    if !profile.wrappedValue.companionProfileIDs.contains(companion.id) {
                                        profile.wrappedValue.companionProfileIDs.append(companion.id)
                                    }
                                } else {
                                    profile.wrappedValue.companionProfileIDs.removeAll { $0 == companion.id }
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

    private func environmentSection(profile: Binding<LaunchProfile>) -> some View {
        GroupBox("Environment") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(profile.environmentEntries) { $item in
                    HStack {
                        TextField("KEY", text: $item.key)
                        TextField("VALUE", text: $item.value)
                    }
                }
                HStack {
                    Button("Add Environment Variable") {
                        profile.wrappedValue.environmentEntries.append(EnvironmentEntry())
                    }
                    Button("Remove Last") {
                        if !profile.wrappedValue.environmentEntries.isEmpty {
                            profile.wrappedValue.environmentEntries.removeLast()
                        }
                    }
                }
            }
        }
    }

    private func actionRow(profile: Binding<LaunchProfile>) -> some View {
        HStack {
            Button("Launch") { launchSelectedProfile() }
                .buttonStyle(.borderedProminent)
            Button("Duplicate") { store.duplicateSelectedProfile() }
            Menu("Apply Preset") {
                ForEach(LaunchBehaviorPreset.allCases) { preset in
                    Button(preset.displayName) {
                        profile.wrappedValue.applyBehaviorPreset(preset)
                    }
                }
            }
            Button("Bookmark Workspace") { store.addBookmark(from: profile.wrappedValue) }
            Button("Delete") { showingDeleteProfileAlert = true }
                .tint(.red)
            Spacer()
            if let result = try? commandBuilder.buildLaunchResult(profile: profile.wrappedValue, settings: store.settings) {
                Button("Copy Command") {
                    ClipboardService.copy(result.command)
                    logger.log(.info, "Copied command preview.")
                }
                Button("Copy AppleScript") {
                    ClipboardService.copy(result.appleScript)
                    logger.log(.info, "Copied AppleScript preview.")
                }
                Button("Export Launcher…") {
                    exportLauncherForProfile(profile.wrappedValue)
                }
            }
        }
    }

    private var workbenchesTab: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search workbenches", text: $workbenchSearch)
                    Button {
                        addWorkbenchFromCurrentSelection()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Create workbench from current profile")
                }
                .padding()

                List(selection: $workbenchSelection) {
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
            .frame(minWidth: 280, maxWidth: 340)

            if let workbench = selectedWorkbenchBinding {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("Workbench") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Name", text: workbench.name)
                                TextField("Tags (comma separated)", text: Binding(
                                    get: { workbench.wrappedValue.tags.joined(separator: ", ") },
                                    set: { workbench.wrappedValue.tags = parseTags($0) }
                                ))
                                Picker("Role", selection: Binding(
                                    get: { workbench.wrappedValue.role },
                                    set: { workbench.wrappedValue.role = $0 }
                                )) {
                                    ForEach(WorkbenchRole.allCases) { role in
                                        Text(role.displayName).tag(role)
                                    }
                                }
                                Stepper("Startup delay (ms): \(workbench.wrappedValue.startupDelayMs)", value: Binding(
                                    get: { workbench.wrappedValue.startupDelayMs },
                                    set: { workbench.wrappedValue.startupDelayMs = max(0, $0) }
                                ), in: 0...300_000, step: 50)
                                TextField("Notes", text: workbench.notes, axis: .vertical)
                                    .lineLimit(3...6)
                                TextField("Post-launch action hints (comma separated)", text: Binding(
                                    get: { workbench.wrappedValue.postLaunchActionHints.joined(separator: ", ") },
                                    set: { workbench.wrappedValue.postLaunchActionHints = parseTags($0) }
                                ))

                                Picker("Shared workspace", selection: Binding(
                                    get: { workbench.wrappedValue.sharedBookmarkID },
                                    set: { workbench.wrappedValue.sharedBookmarkID = $0 }
                                )) {
                                    Text("None").tag(UUID?.none)
                                    ForEach(store.bookmarks) { bookmark in
                                        Text(bookmark.name).tag(Optional(bookmark.id))
                                    }
                                }

                                HStack {
                                    Button("Launch Workbench") { launch(workbench: workbench.wrappedValue) }
                                        .buttonStyle(.borderedProminent)
                                    Button("Duplicate") {
                                        if let copy = store.duplicateWorkbench(workbench.wrappedValue.id) {
                                            workbenchSelection = copy.id
                                        }
                                    }
                                    Button("Delete", role: .destructive) {
                                        showingDeleteWorkbenchAlert = true
                                    }
                                }
                            }
                        }

                        GroupBox("Profiles in This Workbench") {
                            VStack(alignment: .leading, spacing: 12) {
                                if workbench.wrappedValue.profileIDs.isEmpty {
                                    Text("Select one or more profiles below to build a workbench.")
                                        .foregroundStyle(.secondary)
                                }

                                ForEach(Array(workbench.wrappedValue.profileIDs.enumerated()), id: \.element) { index, profileID in
                                    if let profile = store.profiles.first(where: { $0.id == profileID }) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(profile.name)
                                                    .font(.headline)
                                                Text(profile.agentKind.displayName)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Button {
                                                moveWorkbenchProfile(workbenchID: workbench.wrappedValue.id, profileID: profileID, direction: -1)
                                            } label: { Image(systemName: "arrow.up") }
                                            .buttonStyle(.borderless)
                                            .disabled(index == 0)
                                            Button {
                                                moveWorkbenchProfile(workbenchID: workbench.wrappedValue.id, profileID: profileID, direction: 1)
                                            } label: { Image(systemName: "arrow.down") }
                                            .buttonStyle(.borderless)
                                            .disabled(index == workbench.wrappedValue.profileIDs.count - 1)
                                            Button(role: .destructive) {
                                                removeProfileFromWorkbench(workbenchID: workbench.wrappedValue.id, profileID: profileID)
                                            } label: { Image(systemName: "trash") }
                                            .buttonStyle(.borderless)
                                        }
                                        .padding(10)
                                        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                }

                                Divider()

                                Text("Available profiles")
                                    .font(.headline)
                                ForEach(store.profiles) { profile in
                                    Toggle(isOn: workbenchMembershipBinding(workbenchID: workbench.wrappedValue.id, profileID: profile.id)) {
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

                        GroupBox("Workbench Preflight") {
                            VStack(alignment: .leading, spacing: 8) {
                                if !workbench.wrappedValue.postLaunchActionHints.isEmpty {
                                    GroupBox("Post-launch Hints") {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(workbench.wrappedValue.postLaunchActionHints, id: \.self) { item in
                                                Label(item, systemImage: "lightbulb")
                                                    .font(.caption)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                ForEach(selectedWorkbenchDiagnostics.errors, id: \.self) { item in
                                    Label(item, systemImage: "xmark.octagon.fill")
                                        .foregroundStyle(.red)
                                }
                                ForEach(selectedWorkbenchDiagnostics.warnings, id: \.self) { item in
                                    Label(item, systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                }
                                if selectedWorkbenchDiagnostics.errors.isEmpty && selectedWorkbenchDiagnostics.warnings.isEmpty {
                                    Label("Workbench plan looks ready.", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Launch Preview") {
                            VStack(alignment: .leading, spacing: 10) {
                                if let workbenchPlanPreview {
                                    HStack {
                                        Spacer()
                                        Button("Copy Combined Commands") {
                                            ClipboardService.copy(workbenchPlanPreview.combinedCommandPreview)
                                            logger.log(.info, "Copied workbench launch plan.")
                                        }
                                        Button("Copy AppleScript") {
                                            ClipboardService.copy(iTermLauncher.buildAppleScript(plan: workbenchPlanPreview))
                                            logger.log(.info, "Copied workbench AppleScript preview.")
                                        }
                                        Button("Export Launcher…") {
                                            exportLauncher(plan: workbenchPlanPreview, suggestedName: workbench.wrappedValue.name + ".command")
                                        }
                                    }
                                    Text(workbenchPlanPreview.combinedCommandPreview)
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
                    .padding()
                }
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
            VStack(spacing: 0) {
                HStack {
                    TextField("Search workspaces", text: $bookmarkSearch)
                    Button {
                        addWorkspaceBookmarkFromChooser()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                .padding()
                List(selection: $bookmarkSelection) {
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
            .frame(minWidth: 280, maxWidth: 340)

            if let bookmark = selectedBookmarkBinding {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("Bookmark") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Name", text: bookmark.name)
                                HStack {
                                    TextField("Path", text: bookmark.path)
                                    Button("Choose…") {
                                        if let path = FilePanelService.chooseDirectory() {
                                            bookmark.wrappedValue.path = path
                                        }
                                    }
                                    Button("Reveal") { store.reveal(bookmark.wrappedValue.expandedPath) }
                                }
                                TextField("Tags (comma separated)", text: Binding(
                                    get: { bookmark.wrappedValue.tags.joined(separator: ", ") },
                                    set: { bookmark.wrappedValue.tags = parseTags($0) }
                                ))
                                TextField("Notes", text: bookmark.notes, axis: .vertical)
                                    .lineLimit(3...6)

                                Picker("Default profile", selection: Binding(
                                    get: { bookmark.wrappedValue.defaultProfileID },
                                    set: { bookmark.wrappedValue.defaultProfileID = $0 }
                                )) {
                                    Text("None").tag(UUID?.none)
                                    ForEach(store.profiles) { profile in
                                        Text(profile.name).tag(Optional(profile.id))
                                    }
                                }
                            }
                        }

                        HStack {
                            Button("Apply to Selected Profile") {
                                guard let profileID = store.selectedProfileID else { return }
                                store.apply(bookmark: bookmark.wrappedValue, to: profileID)
                                logger.log(.success, "Applied bookmark to selected profile.")
                            }
                            Button("New Workbench Here") {
                                createWorkbenchFromSelectedBookmark(bookmark.wrappedValue)
                            }
                            Button("Launch Default Profile Here") {
                                launchBookmark(bookmark.wrappedValue)
                            }
                            Button("Delete Bookmark", role: .destructive) {
                                store.removeBookmark(bookmark.wrappedValue)
                                bookmarkSelection = store.bookmarks.first?.id
                            }
                        }
                    }
                    .padding()
                }
            } else {
                unavailablePlaceholder("No workspace selected", systemImage: "folder", message: "Select a workspace bookmark from the list or add one.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Launch History")
                    .font(.title2.bold())
                Spacer()
                Button("Relaunch Last") { relaunchLast() }
                    .buttonStyle(.borderedProminent)
            }
            List {
                ForEach(store.history) { item in
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

    private var diagnosticsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Resolved Executables") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(diagnostics.statuses) { status in
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
                            Text("\(availableITermProfiles.count)")
                                .font(.headline)
                        }
                        Text(iTermProfileSourceDescription.isEmpty ? "Profile discovery information will appear here after diagnostics refresh." : iTermProfileSourceDescription)
                            .foregroundStyle(.secondary)
                        if !availableITermProfiles.isEmpty {
                            Text(availableITermProfiles.joined(separator: ", "))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Preflight Summary") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(diagnostics.errors, id: \.self) { item in
                            Label(item, systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                        ForEach(diagnostics.warnings, id: \.self) { item in
                            Label(item, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if diagnostics.errors.isEmpty && diagnostics.warnings.isEmpty {
                            Label("No issues detected.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Current Plan") {
                    if let planPreview {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(planPreview.combinedCommandPreview)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !planPreview.postLaunchActions.isEmpty {
                                Divider()
                                Text("Post-launch actions: " + planPreview.postLaunchSummary)
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
            .padding()
        }
    }

    private var logsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search log", text: $logSearch)
                Picker("Level", selection: $logLevelFilter) {
                    Text("All Levels").tag("all")
                    ForEach(LogLevel.allCases) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                }
                .frame(width: 150)
                Picker("Category", selection: $logCategoryFilter) {
                    Text("All Categories").tag("all")
                    ForEach(LogCategory.allCases) { category in
                        Text(category.displayName).tag(category.rawValue)
                    }
                }
                .frame(width: 170)
                Button("Clear") { logger.clear() }
                Button("Reveal Log Folder") { logger.revealLogDirectory() }
                Button("Copy Visible") {
                    let text = filteredLogs.map { formattedLogLine(for: $0) }.joined(separator: "\n")
                    ClipboardService.copy(text)
                }
                Button("Export Visible…") { exportLogs() }
                Button("Export Diagnostics…") { exportDiagnostics() }
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


    private var monitoringTab: some View {
        MonitoringDashboardView()
    }

    private var settingsTab: some View {
        Form {
            Section("Defaults") {
                TextField("Default working directory", text: $store.settings.defaultWorkingDirectory)
                TextField("Default Node executable", text: $store.settings.defaultNodeExecutable)
                TextField("Default automation runner path", text: $store.settings.defaultGeminiRunnerPath)
                Text("Leave the default automation runner path blank to use the bundled Gemini automation runner shipped with the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Default iTerm2 profile", text: $store.settings.defaultITermProfile)
                TextField("Default hotkey prefix", text: $store.settings.defaultHotkeyPrefix)
                TextField("Default shell bootstrap command", text: $store.settings.defaultShellBootstrapCommand, axis: .vertical)
                    .lineLimit(2...4)
                Toggle("Default: open workspace in Finder after launch", isOn: $store.settings.defaultOpenWorkspaceInFinderOnLaunch)
                Toggle("Default: open workspace in VS Code after launch", isOn: $store.settings.defaultOpenWorkspaceInVSCodeOnLaunch)

                Picker("Default iTerm2 open mode", selection: $store.settings.defaultOpenMode) {
                    ForEach(ITermOpenMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Stepper(value: $store.settings.defaultTabLaunchDelayMs, in: 50...3000, step: 50) {
                    Text("Default iTerm2 tab delay: \(store.settings.defaultTabLaunchDelayMs) ms")
                }
                Stepper(value: $store.settings.defaultKeepTryMax, in: 0...25) {
                    Text("Default automation keep-try max: \(store.settings.defaultKeepTryMax)")
                }
                Stepper(value: $store.settings.defaultManualOverrideMs, in: 1000...120000, step: 1000) {
                    Text("Default manual override: \(store.settings.defaultManualOverrideMs) ms")
                }
                Stepper(value: $store.settings.maxHistoryItems, in: 20...500, step: 10) {
                    Text("History size: \(store.settings.maxHistoryItems)")
                }
                Stepper(value: $store.settings.maxBookmarks, in: 5...300, step: 5) {
                    Text("Bookmark limit: \(store.settings.maxBookmarks)")
                }
                Toggle("Confirm before launch", isOn: $store.settings.confirmBeforeLaunch)
                Toggle("Quiet child Node warnings by default", isOn: $store.settings.quietChildNodeWarningsByDefault)
            }

            Section("Observability") {
                Toggle("Verbose runtime logging", isOn: $store.settings.observability.verboseLogging)
                Toggle("Persist logs to disk", isOn: $store.settings.observability.persistLogsToDisk)
                Toggle("Include AppleScript payloads in logs", isOn: $store.settings.observability.includeAppleScriptInLogs)
                Toggle("Deduplicate repeated log entries", isOn: $store.settings.observability.deduplicateRepeatedEntries)
                Stepper(value: $store.settings.observability.maxInMemoryEntries, in: 100...10000, step: 100) {
                    Text("In-memory log limit: \(store.settings.observability.maxInMemoryEntries)")
                }
                HStack {
                    Text("Runtime log file")
                    Spacer()
                    Text(logger.runtimeLogFileURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Shared Environment Presets") {
                if store.settings.environmentPresets.isEmpty {
                    Text("No shared environment presets yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach($store.settings.environmentPresets) { $preset in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Preset name", text: $preset.name)
                            Spacer()
                            Button(role: .destructive) {
                                let presetID = preset.id
                                store.settings.environmentPresets.removeAll { $0.id == presetID }
                                for index in store.profiles.indices where store.profiles[index].environmentPresetID == presetID {
                                    store.profiles[index].environmentPresetID = nil
                                }
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
                        store.settings.environmentPresets.append(EnvironmentPreset())
                    }
                    Button("Capture Selected Profile Environment") {
                        captureEnvironmentPresetFromSelectedProfile()
                    }
                    .disabled(store.selectedProfile == nil)
                }
            }

            Section("Shared Shell Bootstrap Presets") {
                if store.settings.shellBootstrapPresets.isEmpty {
                    Text("No shared bootstrap presets yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach($store.settings.shellBootstrapPresets) { $preset in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Preset name", text: $preset.name)
                            Spacer()
                            Button(role: .destructive) {
                                let presetID = preset.id
                                store.settings.shellBootstrapPresets.removeAll { $0.id == presetID }
                                for index in store.profiles.indices where store.profiles[index].bootstrapPresetID == presetID {
                                    store.profiles[index].bootstrapPresetID = nil
                                }
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
                        store.settings.shellBootstrapPresets.append(ShellBootstrapPreset())
                    }
                    Button("Capture Selected Profile Bootstrap") {
                        captureBootstrapPresetFromSelectedProfile()
                    }
                    .disabled(store.selectedProfile == nil)
                }
            }

            Section("Terminal Monitoring / MongoDB") {
                Toggle("Enable terminal transcript monitoring", isOn: $store.settings.postgresMonitoring.enabled)
                Toggle("Write captured transcript chunks into MongoDB", isOn: $store.settings.postgresMonitoring.enablePostgresWrites)
                    .disabled(!store.settings.postgresMonitoring.enabled)

                Picker("Capture mode", selection: $store.settings.postgresMonitoring.captureMode) {
                    ForEach(TerminalTranscriptCaptureMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(!store.settings.postgresMonitoring.enabled)

                TextField("Mongo connection URL", text: $store.settings.postgresMonitoring.connectionURL)
                    .disabled(!store.settings.postgresMonitoring.enabled || !store.settings.postgresMonitoring.enablePostgresWrites)
                TextField("Schema name", text: $store.settings.postgresMonitoring.schemaName)
                    .disabled(!store.settings.postgresMonitoring.enabled || !store.settings.postgresMonitoring.enablePostgresWrites)
                TextField("Mongo shell executable", text: $store.settings.postgresMonitoring.psqlExecutable)
                    .disabled(!store.settings.postgresMonitoring.enabled)
                TextField("mongod executable", text: $store.settings.postgresMonitoring.mongodExecutable)
                    .disabled(!store.settings.postgresMonitoring.enabled || !store.settings.postgresMonitoring.enablePostgresWrites)
                TextField("Local Mongo data directory", text: $store.settings.postgresMonitoring.localDataDirectory)
                    .disabled(!store.settings.postgresMonitoring.enabled || !store.settings.postgresMonitoring.enablePostgresWrites)
                TextField("script executable", text: $store.settings.postgresMonitoring.scriptExecutable)
                    .disabled(!store.settings.postgresMonitoring.enabled)
                TextField("Transcript directory", text: $store.settings.postgresMonitoring.transcriptDirectory)
                    .disabled(!store.settings.postgresMonitoring.enabled)

                Stepper(value: $store.settings.postgresMonitoring.pollingIntervalMs, in: 250...5000, step: 50) {
                    Text("Polling interval: \(store.settings.postgresMonitoring.pollingIntervalMs) ms")
                }
                .disabled(!store.settings.postgresMonitoring.enabled)

                Stepper(value: $store.settings.postgresMonitoring.previewCharacterLimit, in: 100...8000, step: 100) {
                    Text("Chunk preview limit: \(store.settings.postgresMonitoring.previewCharacterLimit) chars")
                }
                .disabled(!store.settings.postgresMonitoring.enabled)

                Stepper(value: $store.settings.postgresMonitoring.recentHistoryLimit, in: 10...200, step: 10) {
                    Text("Recent MongoDB session load limit: \(store.settings.postgresMonitoring.clampedRecentHistoryLimit)")
                }
                .disabled(!store.settings.postgresMonitoring.enabled || !store.settings.postgresMonitoring.enablePostgresWrites)

                Stepper(value: $store.settings.postgresMonitoring.recentHistoryLookbackDays, in: 1...365, step: 1) {
                    Text("Recent history lookback: \(store.settings.postgresMonitoring.clampedRecentHistoryLookbackDays) day(s)")
                }
                .disabled(!store.settings.postgresMonitoring.enabled || !store.settings.postgresMonitoring.enablePostgresWrites)

                Stepper(value: $store.settings.postgresMonitoring.detailEventLimit, in: 10...500, step: 10) {
                    Text("Detail event fetch limit: \(store.settings.postgresMonitoring.clampedDetailEventLimit)")
                }
                .disabled(!store.settings.postgresMonitoring.enabled || !store.settings.postgresMonitoring.enablePostgresWrites)

                Stepper(value: $store.settings.postgresMonitoring.detailChunkLimit, in: 10...500, step: 10) {
                    Text("Detail chunk fetch limit: \(store.settings.postgresMonitoring.clampedDetailChunkLimit)")
                }
                .disabled(!store.settings.postgresMonitoring.enabled || !store.settings.postgresMonitoring.enablePostgresWrites)

                Stepper(value: $store.settings.postgresMonitoring.transcriptPreviewByteLimit, in: 10_000...2_000_000, step: 10_000) {
                    Text(
                        "Transcript preview window: \(ByteCountFormatter.string(fromByteCount: Int64(store.settings.postgresMonitoring.clampedTranscriptPreviewByteLimit), countStyle: .file))"
                    )
                }
                .disabled(!store.settings.postgresMonitoring.enabled)

                Stepper(value: $store.settings.postgresMonitoring.databaseRetentionDays, in: 1...3650, step: 1) {
                    Text("Database retention window: \(store.settings.postgresMonitoring.clampedDatabaseRetentionDays) day(s)")
                }
                .disabled(!store.settings.postgresMonitoring.enabled || !store.settings.postgresMonitoring.enablePostgresWrites)

                Stepper(value: $store.settings.postgresMonitoring.localTranscriptRetentionDays, in: 1...3650, step: 1) {
                    Text("Local transcript retention window: \(store.settings.postgresMonitoring.clampedLocalTranscriptRetentionDays) day(s)")
                }
                .disabled(!store.settings.postgresMonitoring.enabled)

                Toggle("Keep local transcript files after launch", isOn: $store.settings.postgresMonitoring.keepLocalTranscriptFiles)
                    .disabled(!store.settings.postgresMonitoring.enabled)

                if store.settings.postgresMonitoring.captureMode.usesScriptKeyLogging {
                    Text("Warning: Input + output capture can record passwords, tokens, and any other secrets typed into monitored terminals.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button("Test Connection") {
                        terminalMonitor.testConnection(settings: store.settings, logger: logger)
                    }
                    .disabled(!store.settings.postgresMonitoring.enabled || !store.settings.postgresMonitoring.enablePostgresWrites)

                    Button("Reveal Transcript Folder") {
                        terminalMonitor.revealTranscriptDirectory(settings: store.settings)
                    }
                }
            }

            Section("Data") {
                HStack {
                    Button("Export State…") { exportState() }
                    Button("Import State…") { importState() }
                    Button("Reveal State Folder") { store.reveal(store.stateURL.deletingLastPathComponent().path) }
                }
            }
        }
        .padding()
    }

    private func cautionBox(title: String, body: String) -> some View {
        GroupBox(title) {
            Text(body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quickLaunchButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private func parseTags(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func mergedEnvironmentSummary(for profile: LaunchProfile) -> String {
        let presetCount = store.settings.environmentPresets.first(where: { $0.id == profile.environmentPresetID })?.entries.count ?? 0
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
            guard selectedTab == .launch else { return }
            refreshLiveState(includeITermDiscovery: includeITermDiscovery)
        }
    }

    private func refreshLiveState(includeITermDiscovery: Bool = true) {
        logger.apply(settings: store.settings.observability)
        if includeITermDiscovery {
            do {
                let discovery = try iTermProfiles.fetchProfiles()
                availableITermProfiles = discovery.names
                iTermProfileSourceDescription = discovery.sourceDescription
            } catch {
                logger.log(.warning, "Failed to read iTerm2 profiles: \(error.localizedDescription)", category: .iterm)
                availableITermProfiles = []
                iTermProfileSourceDescription = "Profile discovery failed: \(error.localizedDescription)"
            }
        }
        if let profile = store.selectedProfile {
            diagnostics = preflight.run(profile: profile, settings: store.settings, allProfiles: store.profiles)
        } else {
            diagnostics = PreflightCheck()
        }
        if bookmarkSelection == nil || !store.bookmarks.contains(where: { $0.id == bookmarkSelection }) {
            bookmarkSelection = store.bookmarks.first?.id
        }
        if workbenchSelection == nil || !store.workbenches.contains(where: { $0.id == workbenchSelection }) {
            workbenchSelection = store.workbenches.first?.id
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
            if !diagnostics.isPassing && profile.id == store.selectedProfileID {
                let detail = ([diagnostics.errors.joined(separator: " | "), diagnostics.warnings.joined(separator: " | ")].filter { !$0.isEmpty }).joined(separator: " • ")
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
                store.workbenches.first(where: { $0.id == workbenchID })?.profileIDs.contains(profileID) == true
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
        guard destination >= 0 && destination < store.workbenches[index].profileIDs.count else { return }
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

    private func exportLogs() {
        guard let url = FilePanelService.saveFile(suggestedName: "CLILauncherLog.txt", allowedContentTypes: [UTType.plainText]) else { return }
        let text = filteredLogs.map { formattedLogLine(for: $0) }.joined(separator: "\n")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            logger.log(.success, "Exported visible launch log.", category: .diagnostics)
        } catch {
            logger.log(.error, "Failed to export log: \(error.localizedDescription)", category: .diagnostics)
        }
    }

    private func exportDiagnostics() {
        guard let url = FilePanelService.saveFile(suggestedName: "CLILauncherDiagnostics.json", allowedContentTypes: [UTType.json]) else { return }
        let report = ApplicationDiagnosticReport(
            appSupportDirectory: AppPaths.containerDirectory.path,
            stateFilePath: AppPaths.stateFileURL.path,
            logFilePath: logger.runtimeLogFileURL.path,
            selectedTab: selectedTab.displayName,
            selectedProfileName: store.selectedProfile?.name,
            selectedProfileID: store.selectedProfileID,
            diagnosticsErrors: diagnostics.errors,
            diagnosticsWarnings: diagnostics.warnings,
            diagnosticStatuses: diagnostics.statuses,
            iterm: iTermLauncher.diagnosticSnapshot(discoveredProfiles: availableITermProfiles, discoverySource: iTermProfileSourceDescription),
            monitoring: MonitoringDiagnosticSnapshot(
                sessionCount: terminalMonitor.sessions.count,
                databaseStatus: terminalMonitor.databaseStatus,
                lastConnectionCheck: terminalMonitor.lastConnectionCheck,
                storageSummaryStatus: terminalMonitor.storageSummaryStatus
            ),
            commandPreview: planPreview?.combinedCommandPreview,
            appleScriptPreview: planPreview.map { iTermLauncher.buildAppleScript(plan: $0) },
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

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
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
