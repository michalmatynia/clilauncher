import Foundation

enum GeminiLaunchMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case automationRunner
    case directWrapper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automationRunner: return "Automation runner"
        case .directWrapper: return "Direct wrapper"
        }
    }
}

enum ITermOpenMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case newWindow
    case newTab

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newWindow: return "New window"
        case .newTab: return "New tab"
        }
    }
}

enum TerminalApp: String, CaseIterable, Codable, Identifiable, Sendable {
    case iterm2
    case terminal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iterm2: return "iTerm2"
        case .terminal: return "Terminal.app"
        }
    }
}

enum AutoContinueMode: String, CaseIterable, Codable, Identifiable {
    case off
    case promptOnly = "prompt_only"
    case capacity
    case yolo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .promptOnly: return "Prompt only"
        case .capacity: return "Capacity"
        case .yolo: return "YOLO (Always)"
        }
    }
}

enum GeminiModelMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto
    case fixed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .fixed: return "Fixed"
        }
    }
}

enum LaunchBehaviorPreset: String, CaseIterable, Codable, Identifiable {
    case safe
    case balanced
    case aggressive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safe: return "Safe"
        case .balanced: return "Balanced"
        case .aggressive: return "Aggressive"
        }
    }

    var summary: String {
        switch self {
        case .safe: return "More manual control, fewer autonomous actions."
        case .balanced: return "Good default for normal daily work."
        case .aggressive: return "Faster automation with broader autonomy."
        }
    }
}

enum WorkspaceCompanionApp: String, CaseIterable, Codable, Identifiable, Sendable {
    case finder
    case visualStudioCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .finder: return "Finder"
        case .visualStudioCode: return "Visual Studio Code"
        }
    }

    var systemImage: String {
        switch self {
        case .finder: return "folder.fill"
        case .visualStudioCode: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct LaunchProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "New Profile"
    var isFavorite: Bool = false
    var tags: [String] = []
    var notes: String = ""

    var agentKind: AgentKind = .gemini
    var workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    var terminalApp: TerminalApp = .iterm2
    var iTermProfile: String = ""
    var openMode: ITermOpenMode = .newWindow
    var extraCLIArgs: String = ""
    var shellBootstrapCommand: String = ""
    var openWorkspaceInFinderOnLaunch: Bool = false
    var openWorkspaceInVSCodeOnLaunch: Bool = false
    var tabLaunchDelayMs: Int = 300
    var environmentEntries: [EnvironmentEntry] = []
    var environmentPresetID: UUID?
    var bootstrapPresetID: UUID?

    var autoLaunchCompanions: Bool = false
    var companionProfileIDs: [UUID] = []

    // Gemini
    var geminiFlavor: GeminiFlavor = .preview
    var geminiLaunchMode: GeminiLaunchMode = .automationRunner
    var geminiWrapperCommand: String = GeminiFlavor.preview.wrapperName
    var geminiISOHome: String = GeminiFlavor.preview.defaultISOHome
    var geminiInitialModel: String = GeminiFlavor.preview.defaultInitialModel
    var geminiModelChain: String = GeminiFlavor.preview.defaultModelChain
    var geminiFlavorDefaultsVersion: Int = GeminiFlavor.preview.defaultsVersion
    var geminiInitialPrompt: String = ""
    var geminiResumeLatest: Bool = true
    var geminiKeepTryMax: Int = 25
    var geminiAutoContinueMode: AutoContinueMode = .promptOnly
    var geminiAutoAllowSessionPermissions: Bool = true
    var geminiAutomationEnabled: Bool = true
    var geminiNeverSwitch: Bool = false
    var geminiYolo: Bool = false
    var geminiSetHomeToIso: Bool = false
    var geminiQuietChildNodeWarnings: Bool = true
    var geminiRawOutput: Bool = false
    var geminiManualOverrideMs: Int = 20_000
    var geminiCapacityRetryMs: Int = 5_000
    var geminiHotkeyPrefix: String = "ctrl-g"
    var geminiAutomationRunnerPath: String = BundledGeminiAutomationRunner.defaultPath
    var nodeExecutable: String = "node"

    // Copilot
    var copilotExecutable: String = "copilot"
    var copilotMode: CopilotMode = .interactive
    var copilotModel: String = ""
    var copilotHome: String = "~/.copilot"
    var copilotInitialPrompt: String = ""
    var copilotMaxAutopilotContinues: Int = 10

    // Codex
    var codexExecutable: String = "codex"
    var codexMode: CodexMode = .fullAuto
    var codexModel: String = ""

    // Claude
    var claudeExecutable: String = "claude"
    var claudeModel: String = ""

    // Kiro
    var kiroExecutable: String = "kiro-cli"
    var kiroMode: KiroMode = .interactive

    // Ollama
    var ollamaExecutable: String = "ollama"
    var ollamaIntegration: OllamaIntegration = .claude
    var ollamaModel: String = "glm-5.1:cloud"
    var ollamaConfigOnly: Bool = false

    // Aider
    var aiderExecutable: String = "aider"
    var aiderMode: AiderMode = .code
    var aiderModel: String = ""
    var aiderAutoCommit: Bool = true
    var aiderNotify: Bool = false
    var aiderDarkTheme: Bool = true

    var expandedWorkingDirectory: String {
        NSString(string: workingDirectory).expandingTildeInPath
    }

    var expandedGeminiISOHome: String {
        NSString(string: geminiISOHome).expandingTildeInPath
    }

    var expandedGeminiRunnerPath: String {
        NSString(string: geminiAutomationRunnerPath).expandingTildeInPath
    }

    var expandedCopilotHome: String {
        NSString(string: copilotHome).expandingTildeInPath
    }

    var geminiModelMode: GeminiModelMode {
        get { geminiNeverSwitch ? .fixed : .auto }
        set { geminiNeverSwitch = newValue == .fixed }
    }

    var effectiveGeminiYolo: Bool {
        geminiYolo && geminiFlavor.supportsYoloFlag
    }

    var trimmedExtraCLIArgs: String {
        extraCLIArgs.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedShellBootstrapCommand: String {
        shellBootstrapCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedITermProfile: String {
        iTermProfile.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var launchStateSignatureToken: String {
        func environmentEntriesSignature(_ entries: [EnvironmentEntry]) -> String {
            entries
                .map { "\($0.key)\u{1F}\($0.value)" }
                .sorted()
                .joined(separator: "\u{1E}")
        }

        let components: [String] = [
            id.uuidString,
            agentKind.rawValue,
            workingDirectory,
            terminalApp.rawValue,
            iTermProfile,
            openMode.rawValue,
            extraCLIArgs,
            shellBootstrapCommand,
            String(openWorkspaceInFinderOnLaunch),
            String(openWorkspaceInVSCodeOnLaunch),
            String(tabLaunchDelayMs),
            environmentEntriesSignature(environmentEntries),
            String(autoLaunchCompanions),
            autoLaunchCompanions ? companionProfileIDs.map(\.uuidString).joined(separator: "\u{1F}") : "",
            geminiFlavor.rawValue,
            geminiLaunchMode.rawValue,
            geminiWrapperCommand,
            geminiISOHome,
            geminiInitialModel,
            geminiModelChain,
            String(geminiFlavorDefaultsVersion),
            geminiInitialPrompt,
            String(geminiResumeLatest),
            String(geminiKeepTryMax),
            geminiAutoContinueMode.rawValue,
            String(geminiAutoAllowSessionPermissions),
            String(geminiAutomationEnabled),
            String(geminiNeverSwitch),
            String(effectiveGeminiYolo),
            String(geminiSetHomeToIso),
            String(geminiQuietChildNodeWarnings),
            String(geminiRawOutput),
            String(geminiManualOverrideMs),
            String(geminiCapacityRetryMs),
            geminiHotkeyPrefix,
            geminiAutomationRunnerPath,
            nodeExecutable,
            copilotExecutable,
            copilotMode.rawValue,
            copilotModel,
            copilotHome,
            copilotInitialPrompt,
            String(copilotMaxAutopilotContinues),
            codexExecutable,
            codexMode.rawValue,
            codexModel,
            claudeExecutable,
            claudeModel,
            kiroExecutable,
            kiroMode.rawValue,
            ollamaExecutable,
            ollamaIntegration.rawValue,
            ollamaModel,
            String(ollamaConfigOnly),
            aiderExecutable,
            aiderMode.rawValue,
            aiderModel,
            String(aiderAutoCommit),
            String(aiderNotify),
            String(aiderDarkTheme)
        ]

        return components.joined(separator: "\u{1E}")
    }

    var environmentMap: [String: String] {
        environmentEntries.reduce(into: [:]) { partial, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            partial[key] = item.value
        }
    }

    var tagSummary: String {
        tags.joined(separator: ", ")
    }

    var workspaceCompanionApps: [WorkspaceCompanionApp] {
        var apps: [WorkspaceCompanionApp] = []
        if openWorkspaceInFinderOnLaunch { apps.append(.finder) }
        if openWorkspaceInVSCodeOnLaunch { apps.append(.visualStudioCode) }
        return apps
    }

    var hasWorkspaceCompanionApps: Bool {
        !workspaceCompanionApps.isEmpty
    }

    var providerExecutableCandidates: [String] {
        let definition = agentKind.providerDefinition

        let configuredExecutable: String
        switch agentKind {
        case .copilot:
            configuredExecutable = copilotExecutable

        case .codex:
            configuredExecutable = codexExecutable

        case .claudeBypass:
            configuredExecutable = claudeExecutable

        case .kiroCLI:
            configuredExecutable = kiroExecutable

        case .ollamaLaunch:
            configuredExecutable = ollamaExecutable

        case .aider:
            configuredExecutable = aiderExecutable

        case .gemini:
            configuredExecutable = geminiWrapperCommand
        }

        let aliases = definition.executableAliases(self)
        var candidates: [String] = []

        let trimmedConfigured = configuredExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedConfigured.isEmpty {
            candidates.append(trimmedConfigured)
        }

        for alias in aliases {
            let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAlias.isEmpty, !candidates.contains(trimmedAlias) {
                candidates.append(trimmedAlias)
            }
        }

        return candidates
    }

    var providerExecutableLabel: String {
        "\(agentKind.displayName) executable"
    }

    var resolvedUpdateCommand: String? {
        switch agentKind {
        case .gemini:
            return geminiFlavor.cliUpdateCommand
        default:
            return agentKind.providerDefinition.updateCommand
        }
    }

    mutating func applyGeminiFlavorDefaults() {
        geminiLaunchMode = .automationRunner
        geminiWrapperCommand = geminiFlavor.wrapperName
        geminiISOHome = geminiFlavor.defaultISOHome
        geminiInitialModel = geminiFlavor.defaultInitialModel
        geminiModelChain = geminiFlavor.defaultModelChain
        geminiFlavorDefaultsVersion = geminiFlavor.defaultsVersion
        if !geminiFlavor.supportsYoloFlag {
            geminiYolo = false
        }
        if geminiAutomationRunnerPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            geminiAutomationRunnerPath = BundledGeminiAutomationRunner.defaultPath
        }
        if agentKind == .gemini {
            name = geminiFlavor.displayName
        }
    }

    mutating func migrateGeminiFlavorDefaultsIfNeeded() {
        guard agentKind == .gemini else { return }

        let targetVersion = geminiFlavor.defaultsVersion
        guard geminiFlavorDefaultsVersion < targetVersion else { return }

        let trimmedInitialModel = geminiInitialModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelChain = geminiModelChain
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")

        if let legacyInitialModel = geminiFlavor.legacyDefaultInitialModelForMigration,
           let legacyModelChain = geminiFlavor.legacyDefaultModelChainForMigration,
           trimmedInitialModel == legacyInitialModel,
           trimmedModelChain == legacyModelChain {
            geminiInitialModel = geminiFlavor.defaultInitialModel
            geminiModelChain = geminiFlavor.defaultModelChain
        }

        geminiFlavorDefaultsVersion = targetVersion
    }

    mutating func stabilizeGeminiAutoModelModeLaunch() {
        guard agentKind == .gemini else { return }
        guard geminiModelMode == .auto else { return }
        guard geminiLaunchMode == .directWrapper else { return }
        geminiLaunchMode = .automationRunner
    }

    mutating func stabilizeGeminiPromptInjectionLaunch() {
        guard agentKind == .gemini else { return }
        guard !geminiInitialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        geminiResumeLatest = false
        guard geminiLaunchMode == .directWrapper else { return }
        geminiLaunchMode = .automationRunner
    }

    mutating func prepareForLaunch() {
        guard agentKind == .gemini else { return }
        migrateGeminiFlavorDefaultsIfNeeded()
        if !geminiFlavor.supportsYoloFlag {
            geminiYolo = false
        }
        stabilizeGeminiAutoModelModeLaunch()
        stabilizeGeminiPromptInjectionLaunch()
    }

    func preparedForLaunch() -> LaunchProfile {
        var profile = self
        profile.prepareForLaunch()
        return profile
    }

    mutating func applyKindDefaults(settings: AppSettings) {
        workingDirectory = settings.defaultWorkingDirectory
        terminalApp = settings.defaultTerminalApp
        iTermProfile = settings.defaultITermProfile
        openMode = settings.defaultOpenMode
        shellBootstrapCommand = settings.defaultShellBootstrapCommand
        openWorkspaceInFinderOnLaunch = settings.defaultOpenWorkspaceInFinderOnLaunch
        openWorkspaceInVSCodeOnLaunch = settings.defaultOpenWorkspaceInVSCodeOnLaunch
        tabLaunchDelayMs = settings.defaultTabLaunchDelayMs
        nodeExecutable = settings.defaultNodeExecutable
        let configuredRunnerPath = settings.defaultGeminiRunnerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        geminiAutomationRunnerPath = configuredRunnerPath.isEmpty
            ? BundledGeminiAutomationRunner.defaultPath
            : settings.defaultGeminiRunnerPath
        geminiHotkeyPrefix = settings.defaultHotkeyPrefix
        geminiKeepTryMax = settings.defaultKeepTryMax
        geminiManualOverrideMs = settings.defaultManualOverrideMs
        geminiQuietChildNodeWarnings = settings.quietChildNodeWarningsByDefault

        agentKind.providerDefinition.defaultProfileMutation?(&self)
    }

    mutating func applyBehaviorPreset(_ preset: LaunchBehaviorPreset) {
        switch agentKind {
        case .gemini:
            switch preset {
            case .safe:
                geminiAutomationEnabled = true
                geminiAutoAllowSessionPermissions = false
                geminiAutoContinueMode = .off
                geminiKeepTryMax = 1
                geminiNeverSwitch = true

            case .balanced:
                geminiAutomationEnabled = true
                geminiAutoAllowSessionPermissions = true
                geminiAutoContinueMode = .promptOnly
                geminiKeepTryMax = 25
                geminiNeverSwitch = false

            case .aggressive:
                geminiAutomationEnabled = true
                geminiAutoAllowSessionPermissions = true
                geminiAutoContinueMode = .yolo
                geminiKeepTryMax = 1_000
                geminiNeverSwitch = false
                geminiYolo = true
            }

        case .copilot:
            switch preset {
            case .safe: copilotMode = .plan
            case .balanced: copilotMode = .interactive
            case .aggressive: copilotMode = .autopilotYolo
            }

        case .codex:
            switch preset {
            case .safe: codexMode = .suggest
            case .balanced: codexMode = .autoEdit
            case .aggressive: codexMode = .fullAuto
            }

        case .claudeBypass:
            break

        case .kiroCLI:
            switch preset {
            case .safe, .balanced: kiroMode = .interactive
            case .aggressive: kiroMode = .chatResume
            }

        case .ollamaLaunch:
            switch preset {
            case .safe, .balanced:
                ollamaConfigOnly = false

            case .aggressive:
                ollamaConfigOnly = true
            }

        case .aider:
            switch preset {
            case .safe: aiderMode = .ask
            case .balanced: aiderMode = .code
            case .aggressive: aiderMode = .architect
            }
        }
    }

    mutating func configureGeminiFireAndForget(prompt: String) {
        guard agentKind == .gemini else { return }

        geminiLaunchMode = .automationRunner
        configureGeminiPromptInjection(prompt: prompt)
        geminiResumeLatest = false
        geminiAutomationEnabled = true
        geminiAutoAllowSessionPermissions = true
        geminiAutoContinueMode = .yolo
        geminiYolo = geminiFlavor.supportsYoloFlag
        geminiKeepTryMax = max(geminiKeepTryMax, 10)
        geminiCapacityRetryMs = max(250, min(geminiCapacityRetryMs, 500))
    }

    mutating func configureGeminiPromptInjection(prompt: String) {
        guard agentKind == .gemini else { return }
        geminiInitialPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !geminiInitialPrompt.isEmpty {
            geminiResumeLatest = false
        }
    }

    static func starter(kind: AgentKind, settings: AppSettings) -> Self {
        var profile = Self()
        profile.agentKind = kind
        profile.applyKindDefaults(settings: settings)
        return profile
    }

    enum CodingKeys: String, CodingKey {
        case id, name, isFavorite, tags, notes
        case agentKind, workingDirectory, terminalApp, iTermProfile, openMode, extraCLIArgs, shellBootstrapCommand, openWorkspaceInFinderOnLaunch, openWorkspaceInVSCodeOnLaunch, tabLaunchDelayMs, environmentEntries, environmentPresetID, bootstrapPresetID
        case autoLaunchCompanions, companionProfileIDs
        case geminiFlavor, geminiLaunchMode, geminiWrapperCommand, geminiISOHome, geminiInitialModel, geminiModelChain, geminiFlavorDefaultsVersion, geminiInitialPrompt, geminiResumeLatest, geminiKeepTryMax, geminiAutoContinueMode, geminiAutoAllowSessionPermissions, geminiAutomationEnabled, geminiNeverSwitch, geminiYolo, geminiSetHomeToIso, geminiQuietChildNodeWarnings, geminiRawOutput, geminiManualOverrideMs, geminiCapacityRetryMs, geminiHotkeyPrefix, geminiAutomationRunnerPath, nodeExecutable
        case copilotExecutable, copilotMode, copilotModel, copilotHome, copilotInitialPrompt, copilotMaxAutopilotContinues
        case codexExecutable, codexMode, codexModel
        case claudeExecutable, claudeModel
        case kiroExecutable, kiroMode
        case ollamaExecutable, ollamaIntegration, ollamaModel, ollamaConfigOnly
    }

    init() {}

    init(from decoder: Decoder) throws {
        let defaults = Self()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeDefault(UUID.self, forKey: .id, default: defaults.id)
        name = try container.decodeDefault(String.self, forKey: .name, default: defaults.name)
        isFavorite = try container.decodeDefault(Bool.self, forKey: .isFavorite, default: defaults.isFavorite)
        tags = try container.decodeDefault([String].self, forKey: .tags, default: defaults.tags)
        notes = try container.decodeDefault(String.self, forKey: .notes, default: defaults.notes)

        agentKind = try container.decodeDefault(AgentKind.self, forKey: .agentKind, default: defaults.agentKind)
        workingDirectory = try container.decodeDefault(String.self, forKey: .workingDirectory, default: defaults.workingDirectory)
        terminalApp = try container.decodeDefault(TerminalApp.self, forKey: .terminalApp, default: defaults.terminalApp)
        iTermProfile = try container.decodeDefault(String.self, forKey: .iTermProfile, default: defaults.iTermProfile)
        openMode = try container.decodeDefault(ITermOpenMode.self, forKey: .openMode, default: defaults.openMode)
        extraCLIArgs = try container.decodeDefault(String.self, forKey: .extraCLIArgs, default: defaults.extraCLIArgs)
        shellBootstrapCommand = try container.decodeDefault(String.self, forKey: .shellBootstrapCommand, default: defaults.shellBootstrapCommand)
        openWorkspaceInFinderOnLaunch = try container.decodeDefault(Bool.self, forKey: .openWorkspaceInFinderOnLaunch, default: defaults.openWorkspaceInFinderOnLaunch)
        openWorkspaceInVSCodeOnLaunch = try container.decodeDefault(Bool.self, forKey: .openWorkspaceInVSCodeOnLaunch, default: defaults.openWorkspaceInVSCodeOnLaunch)
        tabLaunchDelayMs = try container.decodeDefault(Int.self, forKey: .tabLaunchDelayMs, default: defaults.tabLaunchDelayMs)
        environmentEntries = try container.decodeDefault([EnvironmentEntry].self, forKey: .environmentEntries, default: defaults.environmentEntries)
        environmentPresetID = try container.decodeIfPresent(UUID.self, forKey: .environmentPresetID)
        bootstrapPresetID = try container.decodeIfPresent(UUID.self, forKey: .bootstrapPresetID)
        autoLaunchCompanions = try container.decodeDefault(Bool.self, forKey: .autoLaunchCompanions, default: defaults.autoLaunchCompanions)
        companionProfileIDs = try container.decodeDefault([UUID].self, forKey: .companionProfileIDs, default: defaults.companionProfileIDs)

        geminiFlavor = try container.decodeDefault(GeminiFlavor.self, forKey: .geminiFlavor, default: defaults.geminiFlavor)
        geminiLaunchMode = try container.decodeDefault(GeminiLaunchMode.self, forKey: .geminiLaunchMode, default: defaults.geminiLaunchMode)
        geminiWrapperCommand = try container.decodeDefault(String.self, forKey: .geminiWrapperCommand, default: defaults.geminiWrapperCommand)
        geminiISOHome = try container.decodeDefault(String.self, forKey: .geminiISOHome, default: defaults.geminiISOHome)
        geminiInitialModel = try container.decodeDefault(String.self, forKey: .geminiInitialModel, default: defaults.geminiInitialModel)
        geminiModelChain = try container.decodeDefault(String.self, forKey: .geminiModelChain, default: defaults.geminiModelChain)
        geminiFlavorDefaultsVersion = try container.decodeDefault(Int.self, forKey: .geminiFlavorDefaultsVersion, default: defaults.geminiFlavorDefaultsVersion)
        geminiInitialPrompt = try container.decodeDefault(String.self, forKey: .geminiInitialPrompt, default: defaults.geminiInitialPrompt)
        geminiResumeLatest = try container.decodeDefault(Bool.self, forKey: .geminiResumeLatest, default: defaults.geminiResumeLatest)
        geminiKeepTryMax = try container.decodeDefault(Int.self, forKey: .geminiKeepTryMax, default: defaults.geminiKeepTryMax)
        geminiAutoContinueMode = try container.decodeDefault(AutoContinueMode.self, forKey: .geminiAutoContinueMode, default: defaults.geminiAutoContinueMode)
        geminiAutoAllowSessionPermissions = try container.decodeDefault(Bool.self, forKey: .geminiAutoAllowSessionPermissions, default: defaults.geminiAutoAllowSessionPermissions)
        geminiAutomationEnabled = try container.decodeDefault(Bool.self, forKey: .geminiAutomationEnabled, default: defaults.geminiAutomationEnabled)
        geminiNeverSwitch = try container.decodeDefault(Bool.self, forKey: .geminiNeverSwitch, default: defaults.geminiNeverSwitch)
        geminiYolo = try container.decodeDefault(Bool.self, forKey: .geminiYolo, default: defaults.geminiYolo)
        geminiSetHomeToIso = try container.decodeDefault(Bool.self, forKey: .geminiSetHomeToIso, default: defaults.geminiSetHomeToIso)
        geminiQuietChildNodeWarnings = try container.decodeDefault(Bool.self, forKey: .geminiQuietChildNodeWarnings, default: defaults.geminiQuietChildNodeWarnings)
        geminiRawOutput = try container.decodeDefault(Bool.self, forKey: .geminiRawOutput, default: defaults.geminiRawOutput)
        geminiManualOverrideMs = try container.decodeDefault(Int.self, forKey: .geminiManualOverrideMs, default: defaults.geminiManualOverrideMs)
        geminiCapacityRetryMs = try container.decodeDefault(Int.self, forKey: .geminiCapacityRetryMs, default: defaults.geminiCapacityRetryMs)
        geminiHotkeyPrefix = try container.decodeDefault(String.self, forKey: .geminiHotkeyPrefix, default: defaults.geminiHotkeyPrefix)
        geminiAutomationRunnerPath = try container.decodeDefault(String.self, forKey: .geminiAutomationRunnerPath, default: defaults.geminiAutomationRunnerPath)
        nodeExecutable = try container.decodeDefault(String.self, forKey: .nodeExecutable, default: defaults.nodeExecutable)

        copilotExecutable = try container.decodeDefault(String.self, forKey: .copilotExecutable, default: defaults.copilotExecutable)
        copilotMode = try container.decodeDefault(CopilotMode.self, forKey: .copilotMode, default: defaults.copilotMode)
        copilotModel = try container.decodeDefault(String.self, forKey: .copilotModel, default: defaults.copilotModel)
        copilotHome = try container.decodeDefault(String.self, forKey: .copilotHome, default: defaults.copilotHome)
        copilotInitialPrompt = try container.decodeDefault(String.self, forKey: .copilotInitialPrompt, default: defaults.copilotInitialPrompt)
        copilotMaxAutopilotContinues = try container.decodeDefault(Int.self, forKey: .copilotMaxAutopilotContinues, default: defaults.copilotMaxAutopilotContinues)

        codexExecutable = try container.decodeDefault(String.self, forKey: .codexExecutable, default: defaults.codexExecutable)
        codexMode = try container.decodeDefault(CodexMode.self, forKey: .codexMode, default: defaults.codexMode)
        codexModel = try container.decodeDefault(String.self, forKey: .codexModel, default: defaults.codexModel)

        claudeExecutable = try container.decodeDefault(String.self, forKey: .claudeExecutable, default: defaults.claudeExecutable)
        claudeModel = try container.decodeDefault(String.self, forKey: .claudeModel, default: defaults.claudeModel)

        kiroExecutable = try container.decodeDefault(String.self, forKey: .kiroExecutable, default: defaults.kiroExecutable)
        kiroMode = try container.decodeDefault(KiroMode.self, forKey: .kiroMode, default: defaults.kiroMode)

        ollamaExecutable = try container.decodeDefault(String.self, forKey: .ollamaExecutable, default: defaults.ollamaExecutable)
        ollamaIntegration = try container.decodeDefault(OllamaIntegration.self, forKey: .ollamaIntegration, default: defaults.ollamaIntegration)
        ollamaModel = try container.decodeDefault(String.self, forKey: .ollamaModel, default: defaults.ollamaModel)
        ollamaConfigOnly = try container.decodeDefault(Bool.self, forKey: .ollamaConfigOnly, default: defaults.ollamaConfigOnly)
    }
}
