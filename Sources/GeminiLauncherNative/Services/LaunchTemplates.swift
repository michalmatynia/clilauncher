import Foundation

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
            let effectiveProfile = profile.preparedForLaunch()
            return effectiveProfile.agentKind.defaultCautionMessages(for: effectiveProfile)
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
