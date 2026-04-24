import Foundation

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
                    profile.migrateGeminiFlavorDefaultsIfNeeded()
                    if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.name = profile.geminiFlavor.displayName
                    }
                    if profile.geminiWrapperCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.geminiWrapperCommand = profile.geminiFlavor.wrapperName
                    }
                    if profile.geminiISOHome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.geminiISOHome = profile.geminiFlavor.defaultISOHome
                    }
                    let normalizedRunnerPath = BundledGeminiAutomationRunner.normalizedConfiguredPath(
                        profile.geminiAutomationRunnerPath,
                        fillBlankWithDefault: true
                    )
                    if profile.geminiAutomationRunnerPath != normalizedRunnerPath {
                        profile.geminiAutomationRunnerPath = normalizedRunnerPath
                    }
                    if !profile.geminiFlavor.supportsYoloFlag {
                        profile.geminiYolo = false
                    }
                },
                supportedModes: [GeminiLaunchMode.automationRunner.rawValue, GeminiLaunchMode.directWrapper.rawValue],
                description: { profile in
                    let effectiveProfile = profile.preparedForLaunch()
                    return "\(effectiveProfile.geminiFlavor.displayName) • \(effectiveProfile.geminiLaunchMode.displayName)"
                },
                defaultModel: { _ in "" },
                modelFlags: [],
                configPaths: ["~/.config/gemini", "~/.gemini", "~/.cache/gemini", "~/Library/Application Support/Gemini"],
                envKeys: ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_CREDENTIALS", "GOOGLE_APPLICATION_CREDENTIALS"],
                installDocumentation: "https://github.com/google-gemini/gemini-cli",
                updateCommand: nil, riskLevel: .low
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
                updateCommand: "claude update", riskLevel: .medium
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
                updateCommand: "kiro-cli update", riskLevel: .low
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
                updateCommand: nil, riskLevel: .low
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
            var messages: [String] = []
            switch profile.geminiLaunchMode {
            case .automationRunner:
                messages.append("Gemini automation mode requires the configured automation runner and Node. Prompt launches are blocked if the runner is unavailable so startup /clear, /stats, and /model cannot be skipped.")
                return messages

            case .directWrapper:
                return messages
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
