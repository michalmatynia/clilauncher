import Foundation

extension Notification.Name {
    static let refreshDiagnosticsRequested = Notification.Name("refreshDiagnosticsRequested")
    static let relaunchLastRequested = Notification.Name("relaunchLastRequested")
    static let toggleAutomationRequested = Notification.Name("toggleAutomationRequested")
    static let enableAutomationRequested = Notification.Name("enableAutomationRequested")
    static let disableAutomationRequested = Notification.Name("disableAutomationRequested")
}

enum AppPaths {
    static let folderName = "CLILauncherNativeV24"
    static let legacyFolderNames = [
        "GeminiLauncherNativeV24",
        "GeminiLauncherNativeV23",
        "GeminiLauncherNativeV22",
        "GeminiLauncherNativeV21",
        "GeminiLauncherNativeV20",
        "GeminiLauncherNativeV19",
        "GeminiLauncherNativeV18",
        "GeminiLauncherNativeV17",
        "GeminiLauncherNativeV16",
        "GeminiLauncherNativeV15",
        "GeminiLauncherNativeV14",
        "GeminiLauncherNativeV13",
        "GeminiLauncherNativeV12",
        "GeminiLauncherNativeV11",
        "GeminiLauncherNativeV10",
        "GeminiLauncherNativeV9",
        "GeminiLauncherNativeV8"
    ]

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static var containerDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    static var stateFileURL: URL {
        containerDirectory.appendingPathComponent("state.json")
    }

    static var logsDirectoryURL: URL {
        containerDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    static var runtimeLogFileURL: URL {
        logsDirectoryURL.appendingPathComponent("runtime.log")
    }

    static var mongoDataDirectoryPath: String {
        "~/Library/Application Support/\(folderName)/Mongo"
    }

    static var mongoDataDirectoryURL: URL {
        applicationSupportDirectory
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("Mongo", isDirectory: true)
    }

    static var defaultTranscriptDirectoryPath: String {
        "~/Library/Application Support/\(folderName)/Transcripts"
    }
}

enum AgentKind: String, CaseIterable, Codable, Identifiable {
    case gemini
    case copilot
    case codex
    case claudeBypass
    case kiroCLI
    case ollamaLaunch
    case aider

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .copilot: return "GitHub Copilot"
        case .codex: return "OpenAI Codex"
        case .claudeBypass: return "Claude Code"
        case .kiroCLI: return "Kiro CLI"
        case .ollamaLaunch: return "Ollama Launch"
        case .aider: return "Aider"
        }
    }

    var summary: String {
        switch self {
        case .gemini: return "Stable, preview, or nightly Gemini CLI with automation-runner support."
        case .copilot: return "GitHub Copilot CLI in interactive, plan, or autopilot modes."
        case .codex: return "OpenAI Codex CLI in suggest, auto edit, or full auto mode."
        case .claudeBypass: return "Claude Code in bypass mode for trusted workspaces."
        case .kiroCLI: return "Kiro CLI interactive or chat-resume workflows."
        case .ollamaLaunch: return "Ollama launch integrations for Claude Code or Codex."
        case .aider: return "AI pair programming in your terminal."
        }
    }
}

enum AiderMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case code
    case architect
    case ask

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .code: return "Code"
        case .architect: return "Architect"
        case .ask: return "Ask"
        }
    }
}

enum ProviderRiskLevel: Int, Codable {
    case low = 1
    case medium = 2
    case high = 3
}

struct ProviderDefinition {
    let kind: AgentKind
    let quickLaunchTitle: String
    let defaultTemplateTitle: String
    let systemImage: String
    let executableAliases: (LaunchProfile) -> [String]
    let defaultProfileMutation: ((inout LaunchProfile) -> Void)?
    let normalizeMissingFields: ((inout LaunchProfile) -> Void)?
    let supportedModes: [String]
    let description: (LaunchProfile) -> String
    let defaultModel: (LaunchProfile) -> String
    let modelFlags: [String]
    let configPaths: [String]
    let envKeys: [String]
    let installDocumentation: String
    let updateCommand: String?
    let riskLevel: ProviderRiskLevel
}

extension AgentKind {
    var providerDefinition: ProviderDefinition {
        switch self {
        case .gemini:
            return ProviderDefinition(
                kind: .gemini,
                quickLaunchTitle: "Gemini Preview",
                defaultTemplateTitle: "Gemini Preview",
                systemImage: "sparkles",
                executableAliases: { profile in
                    var aliases = profile.geminiFlavor.wrapperAliasNames
                    if aliases.isEmpty {
                        aliases = ["gemini-preview-iso"]
                    }
                    return aliases
                },
                defaultProfileMutation: { profile in
                    profile.applyGeminiFlavorDefaults()
                },
                normalizeMissingFields: { profile in
                    if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.name = profile.geminiFlavor.displayName
                    }
                    if profile.geminiWrapperCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.geminiWrapperCommand = profile.geminiFlavor.wrapperName
                    }
                    if profile.geminiISOHome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.geminiISOHome = profile.geminiFlavor.defaultISOHome
                    }
                    if profile.geminiInitialModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.geminiInitialModel = profile.geminiFlavor.defaultInitialModel
                    }
                    if profile.geminiModelChain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.geminiModelChain = profile.geminiFlavor.defaultModelChain
                    }
                },
                supportedModes: [GeminiLaunchMode.automationRunner.rawValue, GeminiLaunchMode.directWrapper.rawValue],
                description: { profile in
                    "\(profile.geminiFlavor.displayName) • \(profile.geminiLaunchMode.displayName)"
                },
                defaultModel: { _ in "" },
                modelFlags: [],
                configPaths: ["~/.config/gemini", "~/.gemini", "~/.cache/gemini", "~/Library/Application Support/Gemini"],
                envKeys: ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_CREDENTIALS", "GOOGLE_APPLICATION_CREDENTIALS"],
                installDocumentation: "https://github.com/google-gemini/gemini-cli",
                updateCommand: "gemini extensions update", riskLevel: .low
            )

        case .copilot:
            return ProviderDefinition(
                kind: .copilot,
                quickLaunchTitle: "Copilot",
                defaultTemplateTitle: "Copilot",
                systemImage: "person.crop.circle.badge.checkmark",
                executableAliases: { _ in ["copilot"] },
                defaultProfileMutation: { profile in
                    profile.name = "Copilot Interactive"
                    profile.copilotMode = .interactive
                    profile.copilotExecutable = "copilot"
                    profile.copilotHome = "~/.copilot"
                    profile.copilotInitialPrompt = ""
                    profile.copilotMaxAutopilotContinues = 10
                    profile.copilotModel = ""
                },
                normalizeMissingFields: { profile in
                    if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.name = "Copilot Interactive"
                    }
                    if profile.copilotExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.copilotExecutable = "copilot"
                    }
                    if profile.copilotHome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.copilotHome = "~/.copilot"
                    }
                    if profile.copilotMaxAutopilotContinues <= 0 {
                        profile.copilotMaxAutopilotContinues = 10
                    }
                },
                supportedModes: [CopilotMode.interactive.rawValue, CopilotMode.plan.rawValue, CopilotMode.autopilot.rawValue, CopilotMode.autopilotYolo.rawValue],
                description: { profile in
                    "Copilot • \(profile.copilotMode.displayName)"
                },
                defaultModel: { $0.copilotModel },
                modelFlags: ["--model"],
                configPaths: ["~/.config/github-copilot", "~/.local/share/github-copilot", "~/.copilot"],
                envKeys: ["GITHUB_TOKEN", "GH_TOKEN", "COPILOT_TOKEN"],
                installDocumentation: "https://github.com/features/copilot",
                updateCommand: nil, riskLevel: .medium
            )

        case .codex:
            return ProviderDefinition(
                kind: .codex,
                quickLaunchTitle: "Codex",
                defaultTemplateTitle: "Codex",
                systemImage: "cpu",
                executableAliases: { _ in ["codex"] },
                defaultProfileMutation: { profile in
                    profile.name = "Codex Full Auto"
                    profile.codexMode = .fullAuto
                    profile.codexExecutable = "codex"
                    profile.codexModel = ""
                },
                normalizeMissingFields: { profile in
                    if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.name = "Codex Full Auto"
                    }
                    if profile.codexExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.codexExecutable = "codex"
                    }
                },
                supportedModes: [CodexMode.suggest.rawValue, CodexMode.autoEdit.rawValue, CodexMode.fullAuto.rawValue],
                description: { profile in
                    "Codex • \(profile.codexMode.displayName)"
                },
                defaultModel: { $0.codexModel },
                modelFlags: ["-m", "--model"],
                configPaths: ["~/.config/codex", "~/.codex"],
                envKeys: ["OPENAI_API_KEY", "OPENAI_BASE_URL", "OPENAI_ORGANIZATION"],
                installDocumentation: "https://openai.com/codex",
                updateCommand: nil, riskLevel: .medium
            )

        case .claudeBypass:
            return ProviderDefinition(
                kind: .claudeBypass,
                quickLaunchTitle: "Claude Bypass",
                defaultTemplateTitle: "Claude Bypass",
                systemImage: "hand.raised.fill",
                executableAliases: { _ in ["claude"] },
                defaultProfileMutation: { profile in
                    profile.name = "Claude Bypass"
                    profile.claudeExecutable = "claude"
                    profile.claudeModel = ""
                },
                normalizeMissingFields: { profile in
                    if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.name = "Claude Bypass"
                    }
                    if profile.claudeExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.claudeExecutable = "claude"
                    }
                },
                supportedModes: [KiroMode.interactive.rawValue],
                description: { _ in
                    "Claude Bypass"
                },
                defaultModel: { $0.claudeModel },
                modelFlags: ["--model"],
                configPaths: ["~/.config/claude", "~/.claude"],
                envKeys: ["ANTHROPIC_API_KEY", "ANTHROPIC_API_BASE", "CLAUDE_API_KEY"],
                installDocumentation: "https://docs.anthropic.com/en/docs/claude-code",
                updateCommand: nil, riskLevel: .medium
            )

        case .kiroCLI:
            return ProviderDefinition(
                kind: .kiroCLI,
                quickLaunchTitle: "Kiro CLI",
                defaultTemplateTitle: "Kiro CLI",
                systemImage: "chevron.left.forwardslash.chevron.right",
                executableAliases: { _ in ["kiro", "kiro-cli"] },
                defaultProfileMutation: { profile in
                    profile.name = "Kiro CLI"
                    profile.kiroExecutable = "kiro-cli"
                    profile.kiroMode = .interactive
                },
                normalizeMissingFields: { profile in
                    if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.name = "Kiro CLI"
                    }
                    if profile.kiroExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.kiroExecutable = "kiro-cli"
                    }
                },
                supportedModes: [KiroMode.interactive.rawValue, KiroMode.chatResume.rawValue],
                description: { profile in
                    "Kiro CLI • \(profile.kiroMode.displayName)"
                },
                defaultModel: { _ in "" },
                modelFlags: [],
                configPaths: ["~/.config/kiro", "~/.kiro"],
                envKeys: ["KIRO_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY"],
                installDocumentation: "https://github.com/iambenf/kiro-cli",
                updateCommand: "gemini extensions update", riskLevel: .low
            )

        case .ollamaLaunch:
            return ProviderDefinition(
                kind: .ollamaLaunch,
                quickLaunchTitle: "Ollama Claude",
                defaultTemplateTitle: "Ollama Claude GLM-5.1 Cloud",
                systemImage: "cloud.fill",
                executableAliases: { _ in ["ollama"] },
                defaultProfileMutation: { profile in
                    profile.ollamaIntegration = .claude
                    profile.ollamaModel = "glm-5.1:cloud"
                    profile.name = "Ollama Claude GLM-5.1 Cloud"
                    profile.ollamaExecutable = "ollama"
                },
                normalizeMissingFields: { profile in
                    if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.name = "Ollama Claude GLM-5.1 Cloud"
                    }
                    if profile.ollamaExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.ollamaExecutable = "ollama"
                    }
                    if profile.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.ollamaModel = "glm-5.1:cloud"
                    }
                },
                supportedModes: [OllamaIntegration.claude.rawValue, OllamaIntegration.codex.rawValue],
                description: { profile in
                    "Ollama \(profile.ollamaIntegration.displayName) • \(profile.ollamaModel)"
                },
                defaultModel: { $0.ollamaModel },
                modelFlags: ["--model", "-m"],
                configPaths: ["~/.ollama", "~/.config/ollama"],
                envKeys: ["OLLAMA_HOST", "OLLAMA_ORIGINS"],
                installDocumentation: "https://ollama.com",
                updateCommand: "gemini extensions update", riskLevel: .low
            )

        case .aider:
            return ProviderDefinition(
                kind: .aider,
                quickLaunchTitle: "Aider",
                defaultTemplateTitle: "Aider",
                systemImage: "magicmouse.fill",
                executableAliases: { _ in ["aider"] },
                defaultProfileMutation: { profile in
                    profile.name = "Aider Code"
                    profile.aiderMode = .code
                    profile.aiderExecutable = "aider"
                    profile.aiderModel = ""
                    profile.aiderAutoCommit = true
                    profile.aiderNotify = false
                    profile.aiderDarkTheme = true
                },
                normalizeMissingFields: { profile in
                    if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.name = "Aider Code"
                    }
                    if profile.aiderExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.aiderExecutable = "aider"
                    }
                },
                supportedModes: [AiderMode.code.rawValue, AiderMode.architect.rawValue, AiderMode.ask.rawValue],
                description: { profile in
                    "Aider • \(profile.aiderMode.displayName)"
                },
                defaultModel: { $0.aiderModel },
                modelFlags: ["--model"],
                configPaths: ["~/.aider.conf.yml", "~/.aider.model.settings.yml"],
                envKeys: ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GOOGLE_API_KEY"],
                installDocumentation: "https://aider.chat",
                updateCommand: nil, riskLevel: .medium
            )
        }
    }

    func defaultCautionMessages(for profile: LaunchProfile) -> [String] {
        switch self {
        case .gemini:
            switch profile.geminiLaunchMode {
            case .automationRunner:
                return ["Gemini automation mode uses the configured automation runner and Node. The launcher will fall back to direct wrapper mode when the runner is unavailable."]

            case .directWrapper:
                return []
            }

        case .copilot:
            switch profile.copilotMode {
            case .autopilotYolo:
                return ["Copilot Autopilot + YOLO may run across multiple premium requests. Use in trusted workspaces only."]

            case .autopilot:
                return ["Copilot Autopilot may continue through multiple tool calls. Keep tasks narrow."]

            default:
                return []
            }

        case .codex:
            return profile.codexMode == .fullAuto ? ["Codex Full Auto can perform broad file edits. Review final changes before continuing."] : []

        case .claudeBypass:
            return ["Claude Bypass skips permission prompts. Use only in trusted workspaces."]

        case .ollamaLaunch:
            return ["Ollama Launch requires an installed Ollama binary and a valid integration."]

        case .aider:
            return profile.aiderAutoCommit ? [] : ["Aider is configured without auto-commit. You will need to commit changes manually."]

        default:
            return []
        }
    }
}

enum GeminiFlavor: String, CaseIterable, Codable, Identifiable {
    case stable
    case preview
    case nightly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stable: return "Gemini"
        case .preview: return "Gemini Preview"
        case .nightly: return "Gemini Nightly"
        }
    }

    var wrapperName: String {
        switch self {
        case .stable: return "gemini-iso"
        case .preview: return "gemini-preview-iso"
        case .nightly: return "gemini-nightly-iso"
        }
    }

    var systemIconName: String {
        switch self {
        case .stable:
            return "bolt.fill"

        case .preview:
            return "sparkles"

        case .nightly:
            return "moon.stars.fill"
        }
    }

    var wrapperAliasNames: [String] {
        let aliases: [String] = [wrapperName, "gemini", "gemini-cli"]
        var unique: [String] = []
        for alias in aliases {
            guard !alias.isEmpty, !unique.contains(alias) else { continue }
            unique.append(alias)
        }
        return unique
    }

    var cliFlavorValue: String {
        switch self {
        case .stable: return "stable"
        case .preview: return "preview"
        case .nightly: return "nightly"
        }
    }

    var defaultISOHome: String {
        switch self {
        case .stable: return "~/.gemini-home"
        case .preview: return "~/.gemini-preview-home"
        case .nightly: return "~/.gemini-nightly-home"
        }
    }

    var defaultInitialModel: String {
        switch self {
        case .stable: return "gemini-2.5-flash"
        case .preview, .nightly: return "gemini-3-pro-preview"
        }
    }

    var defaultModelChain: String {
        switch self {
        case .stable:
            return ["gemini-2.5-flash", "gemini-2.5-flash-lite"].joined(separator: ",")

        case .preview, .nightly:
            return ["gemini-3-pro-preview", "gemini-3-flash-preview", "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite"].joined(separator: ",")
        }
    }
}

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

enum CopilotMode: String, CaseIterable, Codable, Identifiable {
    case interactive
    case plan
    case autopilot
    case autopilotYolo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .interactive: return "Interactive"
        case .plan: return "Plan"
        case .autopilot: return "Autopilot"
        case .autopilotYolo: return "Autopilot + YOLO"
        }
    }

    var isAutonomous: Bool {
        self == .autopilot || self == .autopilotYolo
    }
}

enum CodexMode: String, CaseIterable, Codable, Identifiable {
    case suggest
    case autoEdit
    case fullAuto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .suggest: return "Suggest"
        case .autoEdit: return "Auto Edit"
        case .fullAuto: return "Full Auto"
        }
    }

    var cliFlag: String? {
        switch self {
        case .suggest: return "--suggest"
        case .autoEdit: return "--auto-edit"
        case .fullAuto: return "--full-auto"
        }
    }
}

enum KiroMode: String, CaseIterable, Codable, Identifiable {
    case interactive
    case chat
    case chatResume

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .interactive: return "Interactive"
        case .chat: return "Chat"
        case .chatResume: return "Chat Resume"
        }
    }
}

enum OllamaIntegration: String, CaseIterable, Codable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var subcommand: String { rawValue }
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

struct EnvironmentEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var key: String = ""
    var value: String = ""
}

struct EnvironmentPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "Shared Environment"
    var notes: String = ""
    var entries: [EnvironmentEntry] = []

    var environmentMap: [String: String] {
        entries.reduce(into: [:]) { partial, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            partial[key] = item.value
        }
    }
}

struct ShellBootstrapPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "Shared Bootstrap"
    var notes: String = ""
    var command: String = ""

    var trimmedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TerminalTranscriptCaptureMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case outputOnly = "output_only"
    case inputAndOutput = "input_and_output"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .outputOnly: return "Output only"
        case .inputAndOutput: return "Input + output"
        }
    }

    var usesScriptKeyLogging: Bool {
        self == .inputAndOutput
    }
}

struct MongoMonitoringSettings: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var enableMongoWrites: Bool = false
    var connectionURL: String = "mongodb://127.0.0.1:27017"
    var schemaName: String = "clilauncher_monitor"
    var transcriptDirectory: String = AppPaths.defaultTranscriptDirectoryPath
    var captureMode: TerminalTranscriptCaptureMode = .inputAndOutput
    var mongoshExecutable: String = "mongosh"
    var mongodExecutable: String = "mongod"
    var scriptExecutable: String = "/usr/bin/script"
    var pollingIntervalMs: Int = 700
    var previewCharacterLimit: Int = 1_200
    var keepLocalTranscriptFiles: Bool = true
    var recentHistoryLimit: Int = 50
    var recentHistoryLookbackDays: Int = 7
    var detailEventLimit: Int = 80
    var detailChunkLimit: Int = 120
    var transcriptPreviewByteLimit: Int = 180_000
    var databaseRetentionDays: Int = 30
    var localTranscriptRetentionDays: Int = 30
    var localDataDirectory: String = AppPaths.mongoDataDirectoryPath

    init() {}

    enum CodingKeys: String, CodingKey {
        case enabled, enableMongoWrites = "enablePostgresWrites", connectionURL, schemaName, transcriptDirectory
        case captureMode, mongoshExecutable = "psqlExecutable", mongodExecutable, scriptExecutable, pollingIntervalMs
        case previewCharacterLimit, keepLocalTranscriptFiles
        case recentHistoryLimit, recentHistoryLookbackDays
        case detailEventLimit, detailChunkLimit
        case transcriptPreviewByteLimit
        case databaseRetentionDays, localTranscriptRetentionDays
        case localDataDirectory
    }

    init(from decoder: Decoder) throws {
        let defaults = Self()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        enabled = try container.decodeDefault(Bool.self, forKey: .enabled, default: defaults.enabled)
        enableMongoWrites = try container.decodeDefault(Bool.self, forKey: .enableMongoWrites, default: defaults.enableMongoWrites)
        connectionURL = try container.decodeDefault(String.self, forKey: .connectionURL, default: defaults.connectionURL)
        schemaName = try container.decodeDefault(String.self, forKey: .schemaName, default: defaults.schemaName)
        transcriptDirectory = try container.decodeDefault(String.self, forKey: .transcriptDirectory, default: defaults.transcriptDirectory)
        captureMode = try container.decodeDefault(TerminalTranscriptCaptureMode.self, forKey: .captureMode, default: defaults.captureMode)
        mongoshExecutable = try container.decodeDefault(String.self, forKey: .mongoshExecutable, default: defaults.mongoshExecutable)
        mongodExecutable = try container.decodeDefault(String.self, forKey: .mongodExecutable, default: defaults.mongodExecutable)
        scriptExecutable = try container.decodeDefault(String.self, forKey: .scriptExecutable, default: defaults.scriptExecutable)
        pollingIntervalMs = try container.decodeDefault(Int.self, forKey: .pollingIntervalMs, default: defaults.pollingIntervalMs)
        previewCharacterLimit = try container.decodeDefault(Int.self, forKey: .previewCharacterLimit, default: defaults.previewCharacterLimit)
        keepLocalTranscriptFiles = try container.decodeDefault(Bool.self, forKey: .keepLocalTranscriptFiles, default: defaults.keepLocalTranscriptFiles)
        recentHistoryLimit = try container.decodeDefault(Int.self, forKey: .recentHistoryLimit, default: defaults.recentHistoryLimit)
        recentHistoryLookbackDays = try container.decodeDefault(Int.self, forKey: .recentHistoryLookbackDays, default: defaults.recentHistoryLookbackDays)
        detailEventLimit = try container.decodeDefault(Int.self, forKey: .detailEventLimit, default: defaults.detailEventLimit)
        detailChunkLimit = try container.decodeDefault(Int.self, forKey: .detailChunkLimit, default: defaults.detailChunkLimit)
        transcriptPreviewByteLimit = try container.decodeDefault(Int.self, forKey: .transcriptPreviewByteLimit, default: defaults.transcriptPreviewByteLimit)
        databaseRetentionDays = try container.decodeDefault(Int.self, forKey: .databaseRetentionDays, default: defaults.databaseRetentionDays)
        localTranscriptRetentionDays = try container.decodeDefault(Int.self, forKey: .localTranscriptRetentionDays, default: defaults.localTranscriptRetentionDays)
        localDataDirectory = try container.decodeDefault(String.self, forKey: .localDataDirectory, default: defaults.localDataDirectory)
    }

    var expandedLocalDataDirectory: String {
        NSString(string: localDataDirectory).expandingTildeInPath
    }

    var trimmedConnectionURL: String {
        connectionURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var mongoConnection: MongoConnectionDescriptor {
        MongoConnectionDescriptor(rawValue: trimmedConnectionURL)
    }

    var trimmedDatabaseName: String {
        let trimmed = schemaName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "clilauncher_monitor" : trimmed
    }

    var trimmedSchemaName: String {
        let value = schemaName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "launcher_monitor" : value
    }

    var expandedTranscriptDirectory: String {
        NSString(string: transcriptDirectory).expandingTildeInPath
    }

    var redactedConnectionDescription: String {
        mongoConnection.redactedString
    }

    var clampedRecentHistoryLimit: Int {
        max(10, min(200, recentHistoryLimit))
    }

    var clampedRecentHistoryLookbackDays: Int {
        max(1, min(365, recentHistoryLookbackDays))
    }

    var clampedDetailEventLimit: Int {
        max(10, min(500, detailEventLimit))
    }

    var clampedDetailChunkLimit: Int {
        max(10, min(500, detailChunkLimit))
    }

    var clampedTranscriptPreviewByteLimit: Int {
        max(10_000, min(2_000_000, transcriptPreviewByteLimit))
    }

    var clampedDatabaseRetentionDays: Int {
        max(1, min(3_650, databaseRetentionDays))
    }

    var clampedLocalTranscriptRetentionDays: Int {
        max(1, min(3_650, localTranscriptRetentionDays))
    }
}

enum TerminalMonitorStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case prepared
    case launching
    case monitoring
    case idle
    case completed
    case failed
    case stopped

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prepared: return "Prepared"
        case .launching: return "Launching"
        case .monitoring: return "Monitoring"
        case .idle: return "Idle"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        }
    }

    var systemImage: String {
        switch self {
        case .prepared: return "clock"
        case .launching: return "paperplane"
        case .monitoring: return "waveform.path.ecg"
        case .idle: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .stopped: return "stop.circle"
        }
    }
}

struct TerminalMonitorSession: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var profileID: UUID?
    var profileName: String
    var agentKind: AgentKind
    var accountIdentifier: String?
    var prompt: String = ""
    var workingDirectory: String
    var transcriptPath: String
    var launchCommand: String
    var captureMode: TerminalTranscriptCaptureMode
    var startedAt = Date()
    var lastActivityAt: Date?
    var endedAt: Date?
    var chunkCount: Int = 0
    var byteCount: Int = 0
    var status: TerminalMonitorStatus = .prepared
    var lastPreview: String = ""
    var lastDatabaseMessage: String = ""
    var lastError: String?
    var statusReason: String?
    var exitCode: Int?
    var isHistorical: Bool = false
    var isYolo: Bool = false

    var hasLocalTranscriptFile: Bool {
        let expanded = NSString(string: transcriptPath).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }

    var activityDate: Date {
        lastActivityAt ?? endedAt ?? startedAt
    }

    var duration: TimeInterval? {
        guard let endDate = endedAt ?? lastActivityAt else { return nil }
        return max(0, endDate.timeIntervalSince(startedAt))
    }
}

struct TerminalSessionEvent: Codable, Identifiable, Equatable, Sendable {
    var id: Int64
    var sessionID: UUID
    var eventType: String
    var status: TerminalMonitorStatus
    var eventAt: Date
    var message: String?
    var metadataJSON: String?
}

struct TerminalTranscriptChunk: Codable, Identifiable, Equatable, Sendable {
    var id: Int64
    var sessionID: UUID
    var chunkIndex: Int
    var source: String
    var capturedAt: Date
    var byteCount: Int
    var previewText: String
    var text: String
}

struct TerminalMonitorSessionDetails: Codable, Equatable, Sendable {
    var sessionID: UUID
    var loadedAt = Date()
    var sessionStatus: TerminalMonitorStatus
    var sessionChunkCount: Int
    var sessionByteCount: Int
    var sessionEndedAt: Date?
    var transcriptText: String = ""
    var transcriptSourceDescription: String = ""
    var transcriptTruncated: Bool = false
    var events: [TerminalSessionEvent] = []
    var chunks: [TerminalTranscriptChunk] = []
    var eventsTruncated: Bool = false
    var chunksTruncated: Bool = false
    var loadSummary: String = ""

    func matches(_ session: TerminalMonitorSession) -> Bool {
        sessionID == session.id &&
        sessionStatus == session.status &&
        sessionChunkCount == session.chunkCount &&
        sessionByteCount == session.byteCount &&
        sessionEndedAt == session.endedAt
    }
}

struct MongoStorageSummary: Codable, Equatable, Sendable {
    var sessionCount: Int = 0
    var activeSessionCount: Int = 0
    var completedSessionCount: Int = 0
    var failedSessionCount: Int = 0
    var chunkCount: Int = 0
    var eventCount: Int = 0
    var logicalTranscriptBytes: Int64 = 0
    var sessionTableBytes: Int64 = 0
    var chunkTableBytes: Int64 = 0
    var eventTableBytes: Int64 = 0
    var oldestSessionAt: Date?
    var newestSessionAt: Date?
    var transcriptFileCount: Int = 0
    var transcriptFileBytes: Int64 = 0
    var oldestTranscriptFileAt: Date?
    var newestTranscriptFileAt: Date?

    var totalDatabaseBytes: Int64 {
        sessionTableBytes + chunkTableBytes + eventTableBytes
    }

    var totalKnownBytes: Int64 {
        totalDatabaseBytes + transcriptFileBytes
    }

    var hasAnyData: Bool {
        sessionCount > 0 || chunkCount > 0 || eventCount > 0 || transcriptFileCount > 0
    }
}

struct MongoPruneSummary: Codable, Equatable, Sendable {
    var executedAt = Date()
    var cutoffDate: Date
    var deletedSessions: Int = 0
    var deletedChunks: Int = 0
    var deletedEvents: Int = 0
    var deletedChunkBytes: Int64 = 0
    var deletedTranscriptFiles: Int = 0
    var deletedTranscriptBytes: Int64 = 0

    var didDeleteAnything: Bool {
        deletedSessions > 0 || deletedChunks > 0 || deletedEvents > 0 || deletedTranscriptFiles > 0
    }
}

// Backward-compatible aliases preserved temporarily for builds that still reference legacy type names.
@available(*, deprecated, renamed: "MongoMonitoringSettings")
typealias PostgresMonitoringSettings = MongoMonitoringSettings
@available(*, deprecated, renamed: "MongoStorageSummary")
typealias PostgresStorageSummary = MongoStorageSummary
@available(*, deprecated, renamed: "MongoPruneSummary")
typealias PostgresPruneSummary = MongoPruneSummary

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

struct ObservabilitySettings: Codable, Equatable {
    var verboseLogging: Bool = true
    var persistLogsToDisk: Bool = true
    var includeAppleScriptInLogs: Bool = true
    var deduplicateRepeatedEntries: Bool = true
    var maxInMemoryEntries: Int = 1_500

    init() {}

    enum CodingKeys: String, CodingKey {
        case verboseLogging, persistLogsToDisk, includeAppleScriptInLogs, deduplicateRepeatedEntries, maxInMemoryEntries
    }

    init(from decoder: Decoder) throws {
        let defaults = Self()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verboseLogging = try container.decodeDefault(Bool.self, forKey: .verboseLogging, default: defaults.verboseLogging)
        persistLogsToDisk = try container.decodeDefault(Bool.self, forKey: .persistLogsToDisk, default: defaults.persistLogsToDisk)
        includeAppleScriptInLogs = try container.decodeDefault(Bool.self, forKey: .includeAppleScriptInLogs, default: defaults.includeAppleScriptInLogs)
        deduplicateRepeatedEntries = try container.decodeDefault(Bool.self, forKey: .deduplicateRepeatedEntries, default: defaults.deduplicateRepeatedEntries)
        maxInMemoryEntries = try container.decodeDefault(Int.self, forKey: .maxInMemoryEntries, default: defaults.maxInMemoryEntries)
    }
}

struct AppSettings: Codable, Equatable {
    var defaultWorkingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    var defaultNodeExecutable: String = "node"
    var defaultGeminiRunnerPath: String = BundledGeminiAutomationRunner.defaultPath
    var defaultITermProfile: String = ""
    var defaultOpenMode: ITermOpenMode = .newWindow
    var defaultHotkeyPrefix: String = "ctrl-g"
    var defaultShellBootstrapCommand: String = ""
    var defaultOpenWorkspaceInFinderOnLaunch: Bool = false
    var defaultOpenWorkspaceInVSCodeOnLaunch: Bool = false
    var defaultTabLaunchDelayMs: Int = 300
    var defaultKeepTryMax: Int = 25
    var defaultManualOverrideMs: Int = 20_000
    var quietChildNodeWarningsByDefault: Bool = true
    var confirmBeforeLaunch: Bool = true
    var maxHistoryItems: Int = 100
    var maxBookmarks: Int = 60
    var mongoMonitoring = MongoMonitoringSettings()
    var observability = ObservabilitySettings()
    var environmentPresets: [EnvironmentPreset] = []
    var shellBootstrapPresets: [ShellBootstrapPreset] = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case defaultWorkingDirectory, defaultNodeExecutable, defaultGeminiRunnerPath, defaultITermProfile
        case defaultOpenMode, defaultHotkeyPrefix, defaultShellBootstrapCommand
        case defaultOpenWorkspaceInFinderOnLaunch, defaultOpenWorkspaceInVSCodeOnLaunch, defaultTabLaunchDelayMs
        case defaultKeepTryMax, defaultManualOverrideMs
        case quietChildNodeWarningsByDefault, confirmBeforeLaunch
        case maxHistoryItems, maxBookmarks
        case mongoMonitoring = "postgresMonitoring", observability
        case environmentPresets, shellBootstrapPresets
    }

    init(from decoder: Decoder) throws {
        let defaults = Self()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        defaultWorkingDirectory = try container.decodeDefault(String.self, forKey: .defaultWorkingDirectory, default: defaults.defaultWorkingDirectory)
        defaultNodeExecutable = try container.decodeDefault(String.self, forKey: .defaultNodeExecutable, default: defaults.defaultNodeExecutable)
        defaultGeminiRunnerPath = try container.decodeDefault(String.self, forKey: .defaultGeminiRunnerPath, default: defaults.defaultGeminiRunnerPath)
        defaultITermProfile = try container.decodeDefault(String.self, forKey: .defaultITermProfile, default: defaults.defaultITermProfile)
        defaultOpenMode = try container.decodeDefault(ITermOpenMode.self, forKey: .defaultOpenMode, default: defaults.defaultOpenMode)
        defaultHotkeyPrefix = try container.decodeDefault(String.self, forKey: .defaultHotkeyPrefix, default: defaults.defaultHotkeyPrefix)
        defaultShellBootstrapCommand = try container.decodeDefault(String.self, forKey: .defaultShellBootstrapCommand, default: defaults.defaultShellBootstrapCommand)
        defaultOpenWorkspaceInFinderOnLaunch = try container.decodeDefault(Bool.self, forKey: .defaultOpenWorkspaceInFinderOnLaunch, default: defaults.defaultOpenWorkspaceInFinderOnLaunch)
        defaultOpenWorkspaceInVSCodeOnLaunch = try container.decodeDefault(Bool.self, forKey: .defaultOpenWorkspaceInVSCodeOnLaunch, default: defaults.defaultOpenWorkspaceInVSCodeOnLaunch)
        defaultTabLaunchDelayMs = try container.decodeDefault(Int.self, forKey: .defaultTabLaunchDelayMs, default: defaults.defaultTabLaunchDelayMs)
        defaultKeepTryMax = try container.decodeDefault(Int.self, forKey: .defaultKeepTryMax, default: defaults.defaultKeepTryMax)
        defaultManualOverrideMs = try container.decodeDefault(Int.self, forKey: .defaultManualOverrideMs, default: defaults.defaultManualOverrideMs)
        quietChildNodeWarningsByDefault = try container.decodeDefault(Bool.self, forKey: .quietChildNodeWarningsByDefault, default: defaults.quietChildNodeWarningsByDefault)
        confirmBeforeLaunch = try container.decodeDefault(Bool.self, forKey: .confirmBeforeLaunch, default: defaults.confirmBeforeLaunch)
        maxHistoryItems = try container.decodeDefault(Int.self, forKey: .maxHistoryItems, default: defaults.maxHistoryItems)
        maxBookmarks = try container.decodeDefault(Int.self, forKey: .maxBookmarks, default: defaults.maxBookmarks)
        mongoMonitoring = try container.decodeDefault(MongoMonitoringSettings.self, forKey: .mongoMonitoring, default: defaults.mongoMonitoring)
        observability = try container.decodeDefault(ObservabilitySettings.self, forKey: .observability, default: defaults.observability)
        environmentPresets = try container.decodeDefault([EnvironmentPreset].self, forKey: .environmentPresets, default: defaults.environmentPresets)
        shellBootstrapPresets = try container.decodeDefault([ShellBootstrapPreset].self, forKey: .shellBootstrapPresets, default: defaults.shellBootstrapPresets)
    }
}

struct LaunchTemplate: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let agentKind: AgentKind
    let makeProfile: (AppSettings) -> LaunchProfile
    let cautionMessages: (LaunchProfile) -> [String]

    func buildProfile(using settings: AppSettings) -> LaunchProfile {
        makeProfile(settings)
    }

    func cautions(for profile: LaunchProfile) -> [String] {
        cautionMessages(profile)
    }
}

enum LaunchTemplateCatalog {
    private static func launchProfile(kind: AgentKind, settings: AppSettings, mutate: ((inout LaunchProfile) -> Void)? = nil) -> LaunchProfile {
        var profile = LaunchProfile.starter(kind: kind, settings: settings)
        mutate?(&profile)
        return profile
    }

    private static func template(
        id: String,
        title: String,
        systemImage: String,
        kind: AgentKind,
        mutate: ((inout LaunchProfile) -> Void)? = nil,
        cautions: ((LaunchProfile) -> [String])? = nil
    ) -> LaunchTemplate {
        let cautionMessages = cautions ?? { profile in
            profile.agentKind.defaultCautionMessages(for: profile)
        }
        return LaunchTemplate(id: id, title: title, systemImage: systemImage, agentKind: kind, makeProfile: { settings in
            launchProfile(kind: kind, settings: settings, mutate: mutate)
        }, cautionMessages: cautionMessages)
    }

    private static func quickTemplate(for kind: AgentKind, id: String, mutates: ((inout LaunchProfile) -> Void)? = nil) -> LaunchTemplate {
        let definition = kind.providerDefinition
        return template(
            id: id,
            title: definition.quickLaunchTitle,
            systemImage: definition.systemImage,
            kind: kind,
            mutate: mutates
                .map { userMutate in
                    { profile in
                        definition.defaultProfileMutation?(&profile)
                        userMutate(&profile)
                    }
                }
                ?? { profile in
                    definition.defaultProfileMutation?(&profile)
                }
        )
    }

    private static func defaultTemplate(for kind: AgentKind, id: String, mutates: ((inout LaunchProfile) -> Void)? = nil) -> LaunchTemplate {
        let definition = kind.providerDefinition
        return template(
            id: id,
            title: definition.defaultTemplateTitle,
            systemImage: definition.systemImage,
            kind: kind
        ) { profile in
                definition.defaultProfileMutation?(&profile)
                mutates?(&profile)
        }
    }

    private static func quickTemplate(for flavor: GeminiFlavor, idSuffix: String? = nil) -> LaunchTemplate {
        template(
            id: "quick-gemini-\(idSuffix ?? flavor.rawValue)",
            title: "\(flavor.displayName)",
            systemImage: flavor.systemIconName,
            kind: .gemini
        ) { profile in
            profile.geminiFlavor = flavor
            profile.applyGeminiFlavorDefaults()
        }
    }

    private static func defaultTemplate(for flavor: GeminiFlavor) -> LaunchTemplate {
        template(
            id: "default-gemini-\(flavor.rawValue)",
            title: "\(flavor.displayName)",
            systemImage: flavor.systemIconName,
            kind: .gemini
        ) { profile in
            profile.geminiFlavor = flavor
            profile.applyGeminiFlavorDefaults()
        }
    }

    static var quickLaunchTemplates: [LaunchTemplate] {
        let nonGeminiKinds = AgentKind.allCases.filter { $0 != .gemini }
        return GeminiFlavor.allCases
            .map { quickTemplate(for: $0) }
            .sorted { $0.title < $1.title }
            + nonGeminiKinds.map { quickTemplate(for: $0, id: "quick-\($0.id)") }
    }

    static var defaultTemplates: [LaunchTemplate] {
        let nonGeminiKinds = AgentKind.allCases.filter { $0 != .gemini }
        var templates: [LaunchTemplate] = GeminiFlavor.allCases
            .map { defaultTemplate(for: $0) }
            .sorted { $0.title < $1.title }
        templates.append(contentsOf: nonGeminiKinds.map { kind in
            defaultTemplate(for: kind, id: "default-\(kind.id)")
        })
        return templates
    }

    static func defaultProfiles(using settings: AppSettings) -> [LaunchProfile] {
        defaultTemplates.map { $0.buildProfile(using: settings) }
    }

    static func cautions(for profile: LaunchProfile) -> [String] {
        quickLaunchTemplates
            .first { $0.agentKind == profile.agentKind }?
            .cautions(for: profile) ??
        defaultTemplates
            .first { $0.agentKind == profile.agentKind }?
            .cautions(for: profile) ??
        []
    }
}

struct WorkbenchTemplate: Identifiable, Sendable {
    let id: String
    let title: String
    let notes: String
    let tags: [String]
    let role: WorkbenchRole
    let startupDelayMs: Int
    let postLaunchActionHints: [String]
    let buildProfileIDs: @Sendable ([LaunchProfile]) -> [UUID]

    func buildWorkbench(using profiles: [LaunchProfile]) -> LaunchWorkbench {
        var workbench = LaunchWorkbench()
        workbench.name = title
        workbench.notes = notes
        workbench.tags = tags
        workbench.role = role
        workbench.startupDelayMs = startupDelayMs
        workbench.postLaunchActionHints = postLaunchActionHints
        workbench.profileIDs = buildProfileIDs(profiles)
        return workbench
    }
}

enum WorkbenchTemplateCatalog {
    private static func firstProfileID(_ profiles: [LaunchProfile], kind: AgentKind, flavor: GeminiFlavor? = nil) -> UUID? {
        if let flavor {
            return profiles.first { $0.agentKind == kind && $0.geminiFlavor == flavor }?.id
        }
        return profiles.first { $0.agentKind == kind }?.id
    }

    private static func template(
        id: String,
        title: String,
        notes: String,
        role: WorkbenchRole,
        startupDelayMs: Int,
        tags: [String],
        postLaunchActionHints: [String] = [],
        buildProfileIDs: @escaping @Sendable ([LaunchProfile]) -> [UUID]
    ) -> WorkbenchTemplate {
        WorkbenchTemplate(
            id: id,
            title: title,
            notes: notes,
            tags: tags,
            role: role,
            startupDelayMs: startupDelayMs,
            postLaunchActionHints: postLaunchActionHints,
            buildProfileIDs: buildProfileIDs
        )
    }

    static let defaultWorkbenchTemplates: [WorkbenchTemplate] = [
        template(
            id: "wb-primary-solo",
            title: "Research Stack",
            notes: "Preview first, then your primary coding assistants.",
            role: .research,
            startupDelayMs: 300,
            tags: ["default", "research", "solo"]
        ) { profiles in
            guard let preview = firstProfileID(profiles, kind: .gemini, flavor: .preview) else { return [] }
            return [
                preview,
                firstProfileID(profiles, kind: .codex),
                firstProfileID(profiles, kind: .copilot)
            ].compactMap(\.self)
        },
        template(
            id: "wb-nightly-codex",
            title: "Coding Stack",
            notes: "Nightly reasoner plus Codex for implementation work.",
            role: .coding,
            startupDelayMs: 420,
            tags: ["default", "coding"]
        ) { profiles in
            guard let nightly = firstProfileID(profiles, kind: .gemini, flavor: .nightly), let codex = firstProfileID(profiles, kind: .codex) else {
                return []
            }
            return [nightly, codex]
        },
        template(
            id: "wb-review-stack",
            title: "Review Stack",
            notes: "Claude Bypass paired with Copilot review loops.",
            role: .review,
            startupDelayMs: 250,
            tags: ["default", "review"],
            postLaunchActionHints: ["Consider using stricter autopilot limits for review runs."]
        ) { profiles in
            guard let claude = firstProfileID(profiles, kind: .claudeBypass) else { return [] }
            return [claude, firstProfileID(profiles, kind: .copilot)].compactMap(\.self)
        }
    ]

    static func defaultWorkbenches(using profiles: [LaunchProfile]) -> [LaunchWorkbench] {
        defaultWorkbenchTemplates
            .map { $0.buildWorkbench(using: profiles) }
            .filter { !$0.profileIDs.isEmpty }
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

    var trimmedExtraCLIArgs: String {
        extraCLIArgs.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedShellBootstrapCommand: String {
        shellBootstrapCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedITermProfile: String {
        iTermProfile.trimmingCharacters(in: .whitespacesAndNewlines)
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

    mutating func applyGeminiFlavorDefaults() {
        geminiLaunchMode = .automationRunner
        geminiWrapperCommand = geminiFlavor.wrapperName
        geminiISOHome = geminiFlavor.defaultISOHome
        geminiInitialModel = geminiFlavor.defaultInitialModel
        geminiModelChain = geminiFlavor.defaultModelChain
        if geminiAutomationRunnerPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            geminiAutomationRunnerPath = BundledGeminiAutomationRunner.defaultPath
        }
        if agentKind == .gemini {
            name = geminiFlavor.displayName
        }
    }

    mutating func applyKindDefaults(settings: AppSettings) {
        workingDirectory = settings.defaultWorkingDirectory
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
        case geminiFlavor, geminiLaunchMode, geminiWrapperCommand, geminiISOHome, geminiInitialModel, geminiModelChain, geminiInitialPrompt, geminiResumeLatest, geminiKeepTryMax, geminiAutoContinueMode, geminiAutoAllowSessionPermissions, geminiAutomationEnabled, geminiNeverSwitch, geminiYolo, geminiSetHomeToIso, geminiQuietChildNodeWarnings, geminiRawOutput, geminiManualOverrideMs, geminiCapacityRetryMs, geminiHotkeyPrefix, geminiAutomationRunnerPath, nodeExecutable
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
    var profileName: String
    var description: String
    var command: String
    var companionCount: Int = 0
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

struct LogEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp = Date()
    var level: LogLevel
    var category: LogCategory = .app
    var message: String
    var details: String?
    var repeatCount: Int = 1
}

struct ToolStatus: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var name: String
    var requested: String
    var resolved: String?
    var detail: String
    var isError: Bool
    var resolutionSource: String?
    var updateCommand: String?
}

struct DiagnosticITermSnapshot: Codable {
    var applicationURL: String?
    var bundleIdentifier: String
    var isInstalled: Bool
    var isRunning: Bool
    var profileDiscoverySource: String
    var profileNames: [String]
}

struct MonitoringDiagnosticSnapshot: Codable {
    var sessionCount: Int
    var databaseStatus: String
    var lastConnectionCheck: String
    var storageSummaryStatus: String
}

struct ApplicationDiagnosticReport: Codable {
    var createdAt = Date()
    var appSupportDirectory: String
    var stateFilePath: String
    var logFilePath: String
    var selectedTab: String
    var selectedProfileName: String?
    var selectedProfileID: UUID?
    var diagnosticsErrors: [String]
    var diagnosticsWarnings: [String]
    var diagnosticStatuses: [ToolStatus]
    var iterm: DiagnosticITermSnapshot
    var monitoring: MonitoringDiagnosticSnapshot
    var commandPreview: String?
    var appleScriptPreview: String?
    var recentLogs: [LogEntry]
}

extension KeyedDecodingContainer {
    func decodeDefault<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) throws -> T {
        try decodeIfPresent(type, forKey: key) ?? defaultValue
    }
}

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let pretty: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
