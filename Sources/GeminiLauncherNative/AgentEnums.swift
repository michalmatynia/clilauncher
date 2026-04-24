import Foundation

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
        case .codex: return "OpenAI Codex CLI in read-only, workspace-write, or full-auto mode."
        case .claudeBypass: return "Claude Code in bypass mode for trusted workspaces."
        case .kiroCLI: return "Kiro CLI interactive or chat-resume workflows."
        case .ollamaLaunch: return "Ollama launch integrations for Claude Code or Codex."
        case .aider: return "AI pair programming in your terminal."
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
        case .stable: return "gemini-stable"
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
        let aliases: [String]
        switch self {
        case .stable:
            aliases = [wrapperName, "gemini-iso", "gemini", "gemini-cli"]
        case .preview, .nightly:
            aliases = [wrapperName, "gemini", "gemini-cli"]
        }
        var unique: [String] = []
        for alias in aliases {
            guard !alias.isEmpty, !unique.contains(alias) else { continue }
            unique.append(alias)
        }
        return unique
    }

    var directExecutableCandidates: [String] {
        switch self {
        case .stable:
            return ["~/.local/gemini-stable/bin/gemini", "gemini", "gemini-cli"]

        case .preview:
            return ["~/.local/gemini-preview/bin/gemini"]

        case .nightly:
            return ["~/.local/gemini-nightly/bin/gemini"]
        }
    }

    var cliFlavorValue: String {
        switch self {
        case .stable: return "stable"
        case .preview: return "preview"
        case .nightly: return "nightly"
        }
    }

    var defaultsVersion: Int {
        switch self {
        case .stable, .preview:
            return 1
        case .nightly:
            return 2
        }
    }

    var supportsYoloFlag: Bool {
        switch self {
        case .nightly:
            return false
        case .stable, .preview:
            return true
        }
    }

    var defaultISOHome: String {
        switch self {
        case .stable: return "~/.gemini-home"
        case .preview: return "~/.gemini-preview-home"
        case .nightly: return "~/.gemini-nightly-home"
        }
    }

    var cliUpdateCommand: String {
        switch self {
        case .stable:
            return "npm install -g --prefix ~/.local/gemini-stable @google/gemini-cli@latest"
        case .preview:
            return "npm install -g --prefix ~/.local/gemini-preview @google/gemini-cli@preview"
        case .nightly:
            return "npm install -g --prefix ~/.local/gemini-nightly @google/gemini-cli@nightly"
        }
    }

    var defaultInitialModel: String {
        switch self {
        case .stable: return "gemini-2.5-flash"
        case .preview: return "gemini-3-pro-preview"
        case .nightly: return "gemini-3-flash-preview"
        }
    }

    var defaultModelChain: String {
        switch self {
        case .stable:
            return ["gemini-2.5-flash", "gemini-2.5-flash-lite"].joined(separator: ",")

        case .preview:
            return ["gemini-3-pro-preview", "gemini-3-flash-preview", "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite"].joined(separator: ",")

        case .nightly:
            return ["gemini-3-flash-preview", "gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-3-pro-preview", "gemini-2.5-pro"].joined(separator: ",")
        }
    }

    var legacyDefaultInitialModelForMigration: String? {
        switch self {
        case .nightly:
            return "gemini-3-pro-preview"
        case .stable, .preview:
            return nil
        }
    }

    var legacyDefaultModelChainForMigration: String? {
        switch self {
        case .nightly:
            return ["gemini-3-pro-preview", "gemini-3-flash-preview", "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite"].joined(separator: ",")
        case .stable, .preview:
            return nil
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

    var cliArguments: [String] {
        switch self {
        case .suggest:
            return ["-s", "read-only", "-a", "untrusted"]
        case .autoEdit:
            return ["-s", "workspace-write", "-a", "untrusted"]
        case .fullAuto:
            return ["--full-auto"]
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

    var displayName: String {
        switch self {
        case .low: return "Low risk"
        case .medium: return "Medium risk"
        case .high: return "High risk"
        }
    }
}
