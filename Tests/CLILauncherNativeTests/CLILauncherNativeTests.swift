import Combine
import Foundation
@testable import GeminiLauncherNative
import XCTest

final class MongoConnectionDescriptorTests: XCTestCase {
    func testLocalMongoConnectionsAreClassifiedAsLocal() {
        let local = MongoConnectionDescriptor(rawValue: "mongodb://127.0.0.1:27017")
        XCTAssertTrue(local.isValid)
        XCTAssertTrue(local.isLocal)
        XCTAssertFalse(local.isRemote)
        XCTAssertEqual(local.kind, .local)
        XCTAssertEqual(local.redactedString, "mongodb://127.0.0.1:27017")

        let localhost = MongoConnectionDescriptor(rawValue: "mongodb://localhost:27017")
        XCTAssertTrue(localhost.isLocal)
        XCTAssertEqual(localhost.kind, .local)

        let ipv6 = MongoConnectionDescriptor(rawValue: "mongodb://[::1]:27017")
        XCTAssertTrue(ipv6.isLocal)
        XCTAssertEqual(ipv6.kind, .local)
    }

    func testRemoteMongoConnectionsAreClassifiedAsRemote() {
        let remote = MongoConnectionDescriptor(rawValue: "mongodb+srv://db.example.com/mydb")
        XCTAssertTrue(remote.isValid)
        XCTAssertFalse(remote.isLocal)
        XCTAssertTrue(remote.isRemote)
        if case let .remote(host) = remote.kind {
            XCTAssertEqual(host, "db.example.com")
        } else {
            XCTFail("Expected remote kind")
        }
    }

    func testInvalidMongoConnectionReturnsInvalidKind() {
        let invalid = MongoConnectionDescriptor(rawValue: "not-a-connection")
        XCTAssertFalse(invalid.isValid)
        XCTAssertEqual(invalid.kind, .invalid)
        XCTAssertFalse(invalid.isLocal)
        XCTAssertFalse(invalid.isRemote)
        XCTAssertEqual(invalid.redactedString, "Not configured")
    }

    func testMonitoringSettingsExposeTypedConnection() {
        var settings = MongoMonitoringSettings()
        settings.connectionURL = "mongodb://localhost:27017/launcher?authSource=admin"
        XCTAssertTrue(settings.mongoConnection.isLocal)
        XCTAssertEqual(settings.redactedConnectionDescription, "mongodb://localhost:27017/launcher?authSource=admin")

        settings.connectionURL = "mongodb://user:secret@db.example.com:27017/admin"
        XCTAssertTrue(settings.mongoConnection.isRemote)
        XCTAssertEqual(settings.redactedConnectionDescription, "mongodb://user:••••••@db.example.com:27017/admin")
    }
}

final class MongoMonitoringSettingsTests: XCTestCase {
    func testMonitoringDefaultsUseOutputOnlyCaptureMode() {
        let settings = MongoMonitoringSettings()

        XCTAssertEqual(settings.captureMode, .outputOnly)
        XCTAssertFalse(settings.captureMode.usesScriptKeyLogging)
    }

    func testMonitoringClampsAreApplied() {
        var settings = MongoMonitoringSettings()
        settings.recentHistoryLimit = -2
        settings.recentHistoryLookbackDays = 1_000
        settings.detailEventLimit = 1
        settings.detailChunkLimit = 1_000
        settings.transcriptPreviewByteLimit = 1
        settings.databaseRetentionDays = 0
        settings.localTranscriptRetentionDays = 10_000

        XCTAssertEqual(settings.clampedRecentHistoryLimit, 10)
        XCTAssertEqual(settings.clampedRecentHistoryLookbackDays, 365)
        XCTAssertEqual(settings.clampedDetailEventLimit, 10)
        XCTAssertEqual(settings.clampedDetailChunkLimit, 500)
        XCTAssertEqual(settings.clampedTranscriptPreviewByteLimit, 10_000)
        XCTAssertEqual(settings.clampedDatabaseRetentionDays, 1)
        XCTAssertEqual(settings.clampedLocalTranscriptRetentionDays, 3_650)
    }
}

final class TerminalMonitorPromptTests: XCTestCase {
    func testRecordedPromptPrefersTrimmedGeminiInitialPrompt() {
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiInitialPrompt = "  ship the feature automatically  \n"

        let recorded = TerminalMonitorStore.recordedPrompt(for: profile, command: "gemini --prompt-interactive ignored")

        XCTAssertEqual(recorded, "ship the feature automatically")
    }

    func testRecordedPromptUsesCopilotCommandWhenNoGeminiPromptExists() {
        var profile = LaunchProfile()
        profile.agentKind = .copilot

        let recorded = TerminalMonitorStore.recordedPrompt(for: profile, command: "gh copilot suggest -t shell \"deploy preview\"")

        XCTAssertEqual(recorded, "gh copilot suggest -t shell \"deploy preview\"")
    }

    func testRecordedPromptTruncatesLongCommandHints() {
        var profile = LaunchProfile()
        profile.agentKind = .aider
        let command = String(repeating: "x", count: 1_500)

        let recorded = TerminalMonitorStore.recordedPrompt(for: profile, command: command)

        XCTAssertEqual(recorded.count, 1_200)
        XCTAssertEqual(recorded, String(command.prefix(1_200)))
    }

    func testExtractGeminiSessionStatsParsesSessionIDAccountTierAndModelUsage() {
        let transcript = """
        \u{001B}[38;2;88;88;89m╭──────────────────────────────────────────────────────────────────────────────╮\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  \u{001B}[1mSession Stats\u{001B}[22m                                                               \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Interaction Summary                                                         \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Session ID:                 d1431b19-95f2-43b5-871f-ddd618e64303            \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Auth Method:               Signed in with Google (info@sparksofsindri.com)  \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Tier:                       Gemini Code Assist for individuals              \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Tool Calls:                 0 ( ✓ 0 x 0 )                                   \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Success Rate:               0.0%                                            \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Performance                                                                 \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Wall Time:                  7.1s                                            \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Agent Active:               368ms                                           \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m    » API Time:               368ms (100.0%)                                  \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m    » Tool Time:              0s (0.0%)                                       \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Model Usage                                                                 \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Use /model to view model quota information                                  \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  Model                         Reqs Input Tokens Cache Reads Output Tokens    \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m  gemini-2.5-flash                 1            0            0             0  \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m│\u{001B}[39m    ↳ main                         1            0            0             0  \u{001B}[38;2;88;88;89m│\u{001B}[39m
        \u{001B}[38;2;88;88;89m╰──────────────────────────────────────────────────────────────────────────────╯\u{001B}[39m
        """

        let stats = TerminalMonitorStore.extractGeminiSessionStats(fromTranscriptText: transcript)

        XCTAssertEqual(stats?.sessionID, "d1431b19-95f2-43b5-871f-ddd618e64303")
        XCTAssertEqual(stats?.accountIdentifier, "info@sparksofsindri.com")
        XCTAssertEqual(stats?.authMethod, "Signed in with Google (info@sparksofsindri.com)")
        XCTAssertEqual(stats?.tier, "Gemini Code Assist for individuals")
        XCTAssertEqual(stats?.toolCalls, "0 ( ✓ 0 x 0 )")
        XCTAssertEqual(stats?.wallTime, "7.1s")
        XCTAssertEqual(stats?.apiTime, "368ms (100.0%)")
        XCTAssertEqual(stats?.toolTime, "0s (0.0%)")
        XCTAssertEqual(stats?.modelUsage.count, 2)
        XCTAssertEqual(stats?.modelUsage.first?.model, "gemini-2.5-flash")
        XCTAssertEqual(stats?.modelUsage.first?.requests, 1)
        XCTAssertEqual(stats?.modelUsage.last?.model, "gemini-2.5-flash")
        XCTAssertEqual(stats?.modelUsage.last?.label, "main")
    }

    func testExtractGeminiSessionStatsParsesSessionWithoutModelUsageRows() {
        let transcript = """
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │  Session Stats                                                               │
        │  Interaction Summary                                                         │
        │  Session ID:                 2b7a5acf-fae6-49a7-b243-c3e424850832            │
        │  Auth Method:                Signed in with Google (frommmishap@gmail.com)   │
        │  Tier:                       Gemini Code Assist for individuals              │
        │  Tool Calls:                 0 ( ✓ 0 x 0 )                                   │
        │  Success Rate:               0.0%                                            │
        │  Performance                                                                 │
        │  Wall Time:                  39.4s                                           │
        │  Agent Active:               0s                                              │
        │    » API Time:               0s (0.0%)                                       │
        │    » Tool Time:              0s (0.0%)                                       │
        ╰──────────────────────────────────────────────────────────────────────────────╯
        """

        let stats = TerminalMonitorStore.extractGeminiSessionStats(fromTranscriptText: transcript)

        XCTAssertEqual(stats?.sessionID, "2b7a5acf-fae6-49a7-b243-c3e424850832")
        XCTAssertEqual(stats?.accountIdentifier, "frommmishap@gmail.com")
        XCTAssertEqual(stats?.authMethod, "Signed in with Google (frommmishap@gmail.com)")
        XCTAssertEqual(stats?.tier, "Gemini Code Assist for individuals")
        XCTAssertEqual(stats?.toolCalls, "0 ( ✓ 0 x 0 )")
        XCTAssertEqual(stats?.wallTime, "39.4s")
        XCTAssertEqual(stats?.apiTime, "0s (0.0%)")
        XCTAssertEqual(stats?.toolTime, "0s (0.0%)")
        XCTAssertEqual(stats?.modelUsage.count, 0)
    }

    func testExtractGeminiSessionStatsSkipReasonParsesCompatibilityBanner() {
        let transcript = """
        [gemini-preview-pty] Gemini CLI version: 0.32.1
        [gemini-preview-pty] Startup session stats: skipped (Gemini CLI 0.32.1 crashes on
        /stats session ("data.slice is not a function"), so startup stats capture is disabled.)
        """

        let reason = TerminalMonitorStore.extractGeminiSessionStatsSkipReason(fromTranscriptText: transcript)

        XCTAssertEqual(
            reason,
            #"Gemini CLI 0.32.1 crashes on /stats session ("data.slice is not a function"), so startup stats capture is disabled."#
        )
    }

    func testExtractGeminiSessionStatsBlockedReasonParsesRunnerBanner() {
        let transcript = """
        [gemini-preview-pty] Gemini CLI version: 0.32.1
        [gemini-preview-pty] Initial prompt delivery: blocked until startup /stats session is captured
        [gemini-preview-pty] Startup sequence: blocked (Gemini CLI 0.32.1 crashes on
        /stats session ("data.slice is not a function"), so prompt-injected launches cannot capture startup stats before sending the prompt.)
        """

        let reason = TerminalMonitorStore.extractGeminiSessionStatsBlockedReason(fromTranscriptText: transcript)

        XCTAssertEqual(
            reason,
            #"Gemini CLI 0.32.1 crashes on /stats session ("data.slice is not a function"), so prompt-injected launches cannot capture startup stats before sending the prompt."#
        )
    }

    func testExtractGeminiCompatibilityOverrideReasonParsesRunnerBanner() {
        let transcript = """
        [gemini-preview-pty] Gemini CLI version: 0.32.1
        [gemini-preview-pty] Gemini CLI compatibility override: Gemini CLI 0.32.1 self-update checks are disabled for this launch
        """

        let reason = TerminalMonitorStore.extractGeminiCompatibilityOverrideReason(fromTranscriptText: transcript)

        XCTAssertEqual(
            reason,
            "Gemini CLI 0.32.1 self-update checks are disabled for this launch"
        )
    }

    func testExtractGeminiFreshSessionResetReasonParsesRunnerBanner() {
        let transcript = """
        [gemini-preview-pty] Fresh session prep: cleared prior workspace session binding (2 path aliases)
        """

        let reason = TerminalMonitorStore.extractGeminiFreshSessionResetReason(fromTranscriptText: transcript)

        XCTAssertEqual(
            reason,
            "cleared prior workspace session binding (2 path aliases)"
        )
    }

    func testExtractGeminiLaunchContextParsesRunnerBanner() {
        let transcript = """
        [gemini-preview-pty] Gemini CLI version: 0.32.1
        [gemini-preview-pty] Runner path: /Applications/CLILauncher.app/Contents/Resources/gemini-automation-runner.mjs
        [gemini-preview-pty] Runner build: 20260424T154225Z
        [gemini-preview-pty] Wrapper resolved: /Users/michalmatynia/.local/gemini-preview/bin/gemini
        [gemini-preview-pty] Wrapper kind: binary
        [gemini-preview-pty] Launch mode: direct
        [gemini-preview-pty] Shell fallback executable: /bin/zsh
        [gemini-preview-pty] Auto-continue mode: prompt_only
        [gemini-preview-pty] PTY backend: @lydell/node-pty
        """

        let snapshot = TerminalMonitorStore.extractGeminiLaunchContext(fromTranscriptText: transcript)

        XCTAssertEqual(snapshot?.cliVersion, "0.32.1")
        XCTAssertEqual(snapshot?.runnerPath, "/Applications/CLILauncher.app/Contents/Resources/gemini-automation-runner.mjs")
        XCTAssertEqual(snapshot?.runnerBuild, "20260424T154225Z")
        XCTAssertEqual(snapshot?.wrapperResolvedPath, "/Users/michalmatynia/.local/gemini-preview/bin/gemini")
        XCTAssertEqual(snapshot?.wrapperKind, "binary")
        XCTAssertEqual(snapshot?.launchMode, "direct")
        XCTAssertEqual(snapshot?.shellFallbackExecutable, "/bin/zsh")
        XCTAssertEqual(snapshot?.autoContinueMode, "prompt_only")
        XCTAssertEqual(snapshot?.ptyBackend, "@lydell/node-pty")
        XCTAssertEqual(snapshot?.metadata["cli_version"] as? String, "0.32.1")
    }

    func testExtractGeminiTranscriptInteractionNoticesParsesSlashCommandsAndPrompts() {
        let transcript = """
        Type your message or @path/to/file
        > /stats
        Session Stats
        > continue
        """

        let notices = TerminalMonitorStore.extractGeminiTranscriptInteractionNotices(fromTranscriptText: transcript)

        XCTAssertEqual(notices.count, 2)
        XCTAssertEqual(notices.first?.text, "/stats")
        XCTAssertEqual(notices.first?.kind, .slashCommand)
        XCTAssertEqual(notices.first?.source, "echoed_transcript")
        XCTAssertEqual(notices.last?.text, "continue")
        XCTAssertEqual(notices.last?.kind, .prompt)
    }

    func testExtractGeminiStartupClearCommandParsesRunnerBanner() {
        let transcript = """
        [gemini-pty] Auto-sending startup /clear (visible prompt field)...
        [gemini-pty] Startup clear: completed (visible prompt field)
        """

        let command = TerminalMonitorStore.extractGeminiStartupClearCommand(fromTranscriptText: transcript)
        let source = TerminalMonitorStore.extractGeminiStartupClearCommandSource(fromTranscriptText: transcript)
        let completionReason = TerminalMonitorStore.extractGeminiStartupClearCompletionReason(fromTranscriptText: transcript)

        XCTAssertEqual(command, "/clear")
        XCTAssertEqual(source, "runner_banner")
        XCTAssertEqual(completionReason, "visible prompt field")
    }

    func testExtractGeminiStartupClearCommandFallsBackToEchoedSlashCommand() {
        let transcript = """
        Type your message or @path/to/file
        > /clear
        """

        let command = TerminalMonitorStore.extractGeminiStartupClearCommand(fromTranscriptText: transcript)
        let source = TerminalMonitorStore.extractGeminiStartupClearCommandSource(fromTranscriptText: transcript)

        XCTAssertEqual(command, "/clear")
        XCTAssertEqual(source, "echoed_command")
    }

    func testExtractGeminiStartupStatsCommandPrefersLatestAutoSentCommand() {
        let transcript = """
        [gemini-pty] Auto-sending startup /stats (visible prompt field)...
        """

        let command = TerminalMonitorStore.extractGeminiStartupStatsCommand(fromTranscriptText: transcript)
        let source = TerminalMonitorStore.extractGeminiStartupStatsCommandSource(fromTranscriptText: transcript)

        XCTAssertEqual(command, "/stats")
        XCTAssertEqual(source, "runner_banner")
    }

    func testExtractGeminiStartupStatsFallbackCommandParsesRetryBanner() {
        let transcript = """
        [gemini-pty] Auto-sending startup /stats session (visible prompt field)...
        [gemini-pty] startup /stats session output was not detected in time —
        retrying with /stats.
        """

        let command = TerminalMonitorStore.extractGeminiStartupStatsFallbackCommand(fromTranscriptText: transcript)

        XCTAssertEqual(command, "/stats")
    }

    func testExtractGeminiStartupStatsCommandFallsBackToEchoedSlashCommand() {
        let transcript = """
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │  Session Stats                                                               │
        │  Interaction Summary                                                         │
        │  Session ID:                 1e9b24cb-3162-43b2-b30c-40e99c126034            │
        │  Auth Method:                Signed in with Google (frommmishap@gmail.com)   │
        │  Tier:                       Gemini Code Assist for individuals              │
        │  Tool Calls:                 0 ( ✓ 0 x 0 )                                   │
        │  Wall Time:                  45.4s                                           │
        ╰──────────────────────────────────────────────────────────────────────────────╯
        > /stats
        """

        let command = TerminalMonitorStore.extractGeminiStartupStatsCommand(fromTranscriptText: transcript)
        let source = TerminalMonitorStore.extractGeminiStartupStatsCommandSource(fromTranscriptText: transcript)

        XCTAssertEqual(command, "/stats")
        XCTAssertEqual(source, "echoed_command")
    }

    func testExtractGeminiSessionStatsKeepsNearbyStartupCommandWhenLaterManualStatsAppear() {
        let transcript = """
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │  Session Stats                                                               │
        │  Interaction Summary                                                         │
        │  Session ID:                 1e9b24cb-3162-43b2-b30c-40e99c126034            │
        │  Auth Method:                Signed in with Google (frommmishap@gmail.com)   │
        │  Tier:                       Gemini Code Assist for individuals              │
        │  Tool Calls:                 0 ( ✓ 0 x 0 )                                   │
        │  Wall Time:                  45.4s                                           │
        ╰──────────────────────────────────────────────────────────────────────────────╯
        > /stats
        Type your message or @path/to/file
        later output 1
        later output 2
        later output 3
        later output 4
        later output 5
        later output 6
        later output 7
        later output 8
        later output 9
        > /stats
        """

        let snapshot = TerminalMonitorStore.extractGeminiSessionStats(fromTranscriptText: transcript)

        XCTAssertEqual(snapshot?.startupStatsCommand, "/stats")
        XCTAssertEqual(snapshot?.startupStatsCommandSource, "echoed_command")
        XCTAssertEqual(snapshot?.metadata["startup_stats_command_source"] as? String, "echoed_command")
    }

    func testSessionByApplyingGeminiSessionStatsPersistsModelUsageRows() {
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )
        let snapshot = GeminiSessionStatsSnapshot(
            sessionID: "session-123",
            authMethod: "Signed in with Google (user@example.com)",
            accountIdentifier: "user@example.com",
            tier: "Gemini Code Assist for individuals",
            toolCalls: "0",
            successRate: nil,
            wallTime: "2.1s",
            agentActive: nil,
            apiTime: nil,
            toolTime: nil,
            startupStatsCommand: "/stats",
            startupStatsCommandSource: "runner_banner",
            modelUsageNote: "Use /model to view model quota information",
            modelUsage: [
                GeminiSessionStatsModelUsageRow(
                    model: "gemini-2.5-pro",
                    label: nil,
                    requests: 3,
                    inputTokens: 120,
                    cacheReads: 7,
                    outputTokens: 42
                )
            ]
        )

        let updated = TerminalMonitorStore.sessionByApplyingGeminiSessionStats(snapshot, to: session)

        XCTAssertEqual(updated.providerSessionID, "session-123")
        XCTAssertEqual(updated.accountIdentifier, "user@example.com")
        XCTAssertEqual(updated.providerTier, "Gemini Code Assist for individuals")
        XCTAssertEqual(updated.providerStartupStatsCommand, "/stats")
        XCTAssertEqual(updated.providerStartupStatsCommandSource, "runner_banner")
        XCTAssertEqual(updated.providerModelUsageNote, "Use /model to view model quota information")
        XCTAssertEqual(updated.providerModelUsage?.count, 1)
        XCTAssertEqual(updated.providerModelUsage?.first?.model, "gemini-2.5-pro")
        XCTAssertEqual(updated.providerModelUsage?.first?.requests, 3)
    }

    func testExtractGeminiModelCapacityParsesModelDialog() {
        let transcript = """
        [gemini-preview-pty] Auto-sending startup /model (visible prompt field)...
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │ Select Model                                                                 │
        │ ● 1. Manual (gemini-3-flash-preview)                                         │
        │   2. Auto                                                                    │
        │ Model usage                                                                  │
        │ Pro             ▬▬▬▬▬▬▬▬▬▬▬▬▬▬                         82% Resets: 1:29 PM   │
        │ Flash           ▬                                      7% Resets: 1:29 PM    │
        │ Flash Lite                                             0%                    │
        │ Press Esc to close                                                           │
        ╰──────────────────────────────────────────────────────────────────────────────╯
        """

        let snapshot = TerminalMonitorStore.extractGeminiModelCapacity(fromTranscriptText: transcript)

        XCTAssertEqual(snapshot?.startupModelCommand, "/model")
        XCTAssertEqual(snapshot?.startupModelCommandSource, "runner_banner")
        XCTAssertEqual(snapshot?.currentModel, "gemini-3-flash-preview")
        XCTAssertEqual(snapshot?.rows.count, 3)
        XCTAssertEqual(snapshot?.rows.first?.model, "Pro")
        XCTAssertEqual(snapshot?.rows.first?.usedPercentage, 82)
        XCTAssertEqual(snapshot?.rows.first?.resetTime, "1:29 PM")
        XCTAssertEqual(snapshot?.rows.last?.model, "Flash Lite")
        XCTAssertEqual(snapshot?.rows.last?.usedPercentage, 0)
    }

    func testSessionByApplyingGeminiModelCapacityPersistsRows() {
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )
        let snapshot = GeminiModelCapacitySnapshot(
            startupModelCommand: "/model",
            startupModelCommandSource: "runner_banner",
            currentModel: "gemini-3-flash-preview",
            rows: [
                GeminiModelCapacityRow(
                    model: "Pro",
                    usedPercentage: 82,
                    resetTime: "1:29 PM",
                    rawText: "Pro 82% Resets: 1:29 PM"
                ),
            ],
            rawLines: ["Select Model", "Model usage", "Pro 82% Resets: 1:29 PM"]
        )

        let updated = TerminalMonitorStore.sessionByApplyingGeminiModelCapacity(snapshot, to: session)

        XCTAssertEqual(updated.providerStartupModelCommand, "/model")
        XCTAssertEqual(updated.providerStartupModelCommandSource, "runner_banner")
        XCTAssertEqual(updated.providerCurrentModel, "gemini-3-flash-preview")
        XCTAssertEqual(updated.providerModelCapacity?.count, 1)
        XCTAssertEqual(updated.providerModelCapacity?.first?.model, "Pro")
        XCTAssertEqual(updated.providerModelCapacity?.first?.usedPercentage, 82)
        XCTAssertEqual(updated.providerModelCapacityRawLines?.first, "Select Model")
    }

    func testSessionByApplyingGeminiFreshSessionResetPersistsReasonAndAliasCount() {
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )
        let notice = GeminiFreshSessionResetNotice(
            fingerprint: "fresh-session-reset",
            reason: "cleared prior workspace session binding (2 path aliases)",
            cleared: true,
            removedPathCount: 2
        )

        let updated = TerminalMonitorStore.sessionByApplyingGeminiFreshSessionReset(notice, to: session)

        XCTAssertEqual(updated.providerFreshSessionPrepared, true)
        XCTAssertEqual(updated.providerFreshSessionResetReason, "cleared prior workspace session binding (2 path aliases)")
        XCTAssertEqual(updated.providerFreshSessionRemovedPathCount, 2)
    }

    func testSessionByApplyingGeminiLaunchContextRetainsFirstCapturedValues() {
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            providerCLIVersion: "0.32.1",
            providerRunnerPath: "/Applications/CLILauncher.app/Contents/Resources/gemini-automation-runner.mjs",
            providerRunnerBuild: "20260424T154225Z",
            providerWrapperResolvedPath: "/Users/michalmatynia/.local/gemini-preview/bin/gemini",
            providerWrapperKind: "binary",
            providerLaunchMode: "direct",
            providerShellFallbackExecutable: "/bin/zsh",
            providerAutoContinueMode: "prompt_only",
            providerPTYBackend: "@lydell/node-pty",
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )
        let snapshot = GeminiLaunchContextSnapshot(
            cliVersion: "0.33.0",
            runnerPath: "/tmp/custom-runner.mjs",
            runnerBuild: "20260425T000000Z",
            wrapperResolvedPath: "/tmp/other-gemini",
            wrapperKind: "script",
            launchMode: "shell",
            shellFallbackExecutable: "/bin/sh",
            autoContinueMode: "always",
            ptyBackend: "python3 PTY bridge"
        )

        let updated = TerminalMonitorStore.sessionByApplyingGeminiLaunchContext(snapshot, to: session)

        XCTAssertEqual(updated.providerCLIVersion, "0.32.1")
        XCTAssertEqual(updated.providerRunnerPath, "/Applications/CLILauncher.app/Contents/Resources/gemini-automation-runner.mjs")
        XCTAssertEqual(updated.providerRunnerBuild, "20260424T154225Z")
        XCTAssertEqual(updated.providerWrapperResolvedPath, "/Users/michalmatynia/.local/gemini-preview/bin/gemini")
        XCTAssertEqual(updated.providerWrapperKind, "binary")
        XCTAssertEqual(updated.providerLaunchMode, "direct")
        XCTAssertEqual(updated.providerShellFallbackExecutable, "/bin/zsh")
        XCTAssertEqual(updated.providerAutoContinueMode, "prompt_only")
        XCTAssertEqual(updated.providerPTYBackend, "@lydell/node-pty")
    }

    func testSessionByApplyingGeminiTranscriptInteractionsAccumulatesUniqueSessionSummary() {
        let firstObservedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let laterObservedAt = Date(timeIntervalSince1970: 1_700_000_120)
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            observedSlashCommands: ["/stats"],
            observedPromptSubmissions: ["continue"],
            observedInteractions: [
                ObservedTranscriptInteractionSummary(
                    text: "/stats",
                    kind: .slashCommand,
                    source: "echoed_transcript",
                    firstObservedAt: firstObservedAt,
                    lastObservedAt: firstObservedAt,
                    observationCount: 1
                )
            ],
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )
        let notices = [
            GeminiTranscriptInteractionNotice(
                fingerprint: "slash_command:/stats",
                text: "/stats",
                kind: .slashCommand,
                source: "echoed_transcript"
            ),
            GeminiTranscriptInteractionNotice(
                fingerprint: "slash_command:/model set gemini-2.5-pro",
                text: "/model set gemini-2.5-pro",
                kind: .slashCommand,
                source: "echoed_transcript"
            ),
            GeminiTranscriptInteractionNotice(
                fingerprint: "prompt:continue",
                text: "continue",
                kind: .prompt,
                source: "echoed_transcript"
            ),
            GeminiTranscriptInteractionNotice(
                fingerprint: "prompt:ship the feature",
                text: "ship the feature",
                kind: .prompt,
                source: "echoed_transcript"
            ),
        ]

        let updated = TerminalMonitorStore.sessionByApplyingGeminiTranscriptInteractions(
            notices,
            observedAt: laterObservedAt,
            to: session
        )

        XCTAssertEqual(updated.observedSlashCommands, ["/stats", "/model set gemini-2.5-pro"])
        XCTAssertEqual(updated.observedPromptSubmissions, ["continue", "ship the feature"])
        XCTAssertEqual(updated.observedInteractions?.count, 4)
        XCTAssertEqual(updated.observedInteractions?.first?.text, "/stats")
        XCTAssertEqual(updated.observedInteractions?.first?.firstObservedAt, firstObservedAt)
        XCTAssertEqual(updated.observedInteractions?.first?.lastObservedAt, laterObservedAt)
        XCTAssertEqual(updated.observedInteractions?.first?.observationCount, 2)
        XCTAssertEqual(updated.observedInteractions?.first?.sourceDisplayName, "Echoed transcript")
    }

    func testSessionByBackfillingObservedTranscriptInteractionsDerivesSummaryFromEvents() {
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )
        let events = [
            TerminalSessionEvent(
                id: 1,
                sessionID: session.id,
                eventType: "slash_command_observed",
                status: .monitoring,
                eventAt: Date(timeIntervalSince1970: 1_700_000_010),
                message: nil,
                metadataJSON: #"{"text":"/stats","kind":"slash_command","source":"echoed_transcript"}"#
            ),
            TerminalSessionEvent(
                id: 2,
                sessionID: session.id,
                eventType: "slash_command_observed",
                status: .monitoring,
                eventAt: Date(timeIntervalSince1970: 1_700_000_015),
                message: nil,
                metadataJSON: #"{"text":"/stats","kind":"slash_command","source":"echoed_transcript"}"#
            ),
            TerminalSessionEvent(
                id: 3,
                sessionID: session.id,
                eventType: "prompt_observed",
                status: .monitoring,
                eventAt: Date(timeIntervalSince1970: 1_700_000_020),
                message: nil,
                metadataJSON: #"{"text":"continue","kind":"prompt","source":"echoed_transcript"}"#
            )
        ]

        let updated = TerminalMonitorStore.sessionByBackfillingObservedTranscriptInteractions(from: events, to: session)

        XCTAssertEqual(updated.observedSlashCommands, ["/stats"])
        XCTAssertEqual(updated.observedPromptSubmissions, ["continue"])
        XCTAssertEqual(updated.observedInteractions?.count, 2)
        XCTAssertEqual(updated.observedInteractions?.first?.text, "/stats")
        XCTAssertEqual(updated.observedInteractions?.first?.observationCount, 2)
        XCTAssertEqual(updated.observedInteractions?.first?.firstObservedAt, Date(timeIntervalSince1970: 1_700_000_010))
        XCTAssertEqual(updated.observedInteractions?.first?.lastObservedAt, Date(timeIntervalSince1970: 1_700_000_015))
    }

    func testSessionByBackfillingObservedTranscriptInteractionsDerivesSummaryFromChunks() {
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )
        let chunks = [
            TerminalTranscriptChunk(
                id: 1,
                sessionID: session.id,
                chunkIndex: 1,
                source: "terminal_transcript_output_only",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_010),
                byteCount: 16,
                previewText: "> /stats",
                text: "> /stats\n"
            ),
            TerminalTranscriptChunk(
                id: 2,
                sessionID: session.id,
                chunkIndex: 2,
                source: "terminal_transcript_output_only",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_015),
                byteCount: 16,
                previewText: "> continue",
                text: "> continue\n"
            ),
            TerminalTranscriptChunk(
                id: 3,
                sessionID: session.id,
                chunkIndex: 3,
                source: "terminal_transcript_output_only",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_020),
                byteCount: 16,
                previewText: "> /stats",
                text: "> /stats\n"
            )
        ]

        let updated = TerminalMonitorStore.sessionByBackfillingObservedTranscriptInteractions(from: chunks, to: session)

        XCTAssertEqual(updated.observedSlashCommands, ["/stats"])
        XCTAssertEqual(updated.observedPromptSubmissions, ["continue"])
        XCTAssertEqual(updated.observedInteractions?.count, 2)
        XCTAssertEqual(updated.observedInteractions?.first?.text, "/stats")
        XCTAssertEqual(updated.observedInteractions?.first?.observationCount, 2)
        XCTAssertEqual(updated.observedInteractions?.first?.firstObservedAt, Date(timeIntervalSince1970: 1_700_000_010))
        XCTAssertEqual(updated.observedInteractions?.first?.lastObservedAt, Date(timeIntervalSince1970: 1_700_000_020))
    }

    func testSessionByBackfillingObservedTranscriptInteractionsDerivesSummaryFromTranscriptText() {
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastActivityAt: Date(timeIntervalSince1970: 1_700_000_020)
        )

        let updated = TerminalMonitorStore.sessionByBackfillingObservedTranscriptInteractions(
            fromTranscriptText: "> /stats\n> continue\n> /stats\n",
            source: "local_transcript_file",
            observedAt: Date(timeIntervalSince1970: 1_700_000_020),
            to: session
        )

        XCTAssertEqual(updated.observedSlashCommands, ["/stats"])
        XCTAssertEqual(updated.observedPromptSubmissions, ["continue"])
        XCTAssertEqual(updated.observedInteractions?.count, 2)
        XCTAssertEqual(updated.observedInteractions?.first?.text, "/stats")
        XCTAssertEqual(updated.observedInteractions?.first?.sourceDisplayName, "Full local transcript")
        XCTAssertEqual(updated.observedInteractions?.first?.observationCount, 2)
        XCTAssertEqual(updated.observedInteractions?.first?.lastObservedAt, Date(timeIntervalSince1970: 1_700_000_020))
    }

    func testMongoTranscriptSourceDescriptionIncludesChunkCaptureSource() {
        let chunks = [
            TerminalTranscriptChunk(
                id: 1,
                sessionID: UUID(),
                chunkIndex: 1,
                source: "terminal_transcript_input_output",
                capturedAt: Date(),
                byteCount: 42,
                previewText: "> /stats",
                text: "> /stats"
            )
        ]

        let description = TerminalMonitorStore.mongoTranscriptSourceDescription(for: chunks, truncated: false)

        XCTAssertEqual(description, "Reconstructed from MongoDB chunk(s) using Transcript capture (input + output).")
    }

    func testNormalizedTranscriptChunksBackfillLegacyGenericChunkSourceUsingCaptureMode() {
        let legacyChunk = TerminalTranscriptChunk(
            id: 1,
            sessionID: UUID(),
            chunkIndex: 1,
            source: "terminal_transcript",
            capturedAt: Date(),
            byteCount: 32,
            previewText: "hello",
            text: "hello"
        )

        let normalized = TerminalMonitorStore.normalizedTranscriptChunks([legacyChunk], captureMode: .inputAndOutput)

        XCTAssertEqual(normalized.first?.source, "terminal_transcript_input_output")
        XCTAssertEqual(normalized.first?.sourceDisplayName, "Transcript capture (input + output)")
    }

    func testObservedInteractionChunkBackfillLimitCapsExpandedMongoScan() {
        XCTAssertEqual(TerminalMonitorStore.observedInteractionChunkBackfillLimit(for: 0), 1)
        XCTAssertEqual(TerminalMonitorStore.observedInteractionChunkBackfillLimit(for: 120), 120)
        XCTAssertEqual(TerminalMonitorStore.observedInteractionChunkBackfillLimit(for: 20_000), 10_000)
    }

    func testObservedInteractionChunkBackfillCompletenessRequiresFullChunkHistory() {
        XCTAssertTrue(TerminalMonitorStore.observedInteractionChunkBackfillIsComplete(scannedChunkCount: 120, sessionChunkCount: 120))
        XCTAssertFalse(TerminalMonitorStore.observedInteractionChunkBackfillIsComplete(scannedChunkCount: 120, sessionChunkCount: 121))
        XCTAssertFalse(TerminalMonitorStore.observedInteractionChunkBackfillIsComplete(scannedChunkCount: 0, sessionChunkCount: 0))
    }

    func testTranscriptDataChunksUsesStableByteLimit() {
        let data = Data("abcdefghijkl".utf8)
        let chunks = TerminalMonitorStore.transcriptDataChunks(data, byteLimit: 5)

        XCTAssertEqual(chunks.map { String(decoding: $0, as: UTF8.self) }, ["abcde", "fghij", "kl"])
        XCTAssertEqual(TerminalMonitorStore.transcriptChunkCount(forByteCount: Int64(data.count), byteLimit: 5), 3)
    }

    func testParseScriptRecordingDataExtractsInputRecordsAndTrailingData() {
        func record(length: UInt64, seconds: UInt64, microseconds: UInt32, direction: UInt32, payload: [UInt8]) -> Data {
            var data = Data()
            var length = length.littleEndian
            var seconds = seconds.littleEndian
            var microseconds = microseconds.littleEndian
            var direction = direction.littleEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &seconds) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &microseconds) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &direction) { data.append(contentsOf: $0) }
            data.append(contentsOf: payload)
            return data
        }

        let startRecord = record(length: 0, seconds: 1_700_000_000, microseconds: 10, direction: 115, payload: [])
        let inputRecord = record(length: 6, seconds: 1_700_000_001, microseconds: 20, direction: 105, payload: Array("hello\n".utf8))
        let trailing = Data([0x01, 0x02, 0x03])
        let parsed = TerminalMonitorStore.parseScriptRecordingData(startRecord + inputRecord + trailing)

        XCTAssertEqual(parsed.records.count, 2)
        XCTAssertEqual(parsed.records[0].direction, "s")
        XCTAssertEqual(parsed.records[1].direction, "i")
        XCTAssertEqual(String(decoding: parsed.records[1].data, as: UTF8.self), "hello\n")
        XCTAssertEqual(parsed.trailingData, trailing)
    }

    func testMongoSessionChunkSummaryRequiresContiguousChunkIndexes() {
        XCTAssertTrue(
            MongoSessionChunkSummary(
                chunkCount: 3,
                byteCount: 120,
                minChunkIndex: 1,
                maxChunkIndex: 3
            ).hasContiguousChunkIndexes
        )
        XCTAssertFalse(
            MongoSessionChunkSummary(
                chunkCount: 3,
                byteCount: 120,
                minChunkIndex: 2,
                maxChunkIndex: 4
            ).hasContiguousChunkIndexes
        )
        XCTAssertFalse(
            MongoSessionChunkSummary(
                chunkCount: 3,
                byteCount: 120,
                minChunkIndex: 1,
                maxChunkIndex: 4
            ).hasContiguousChunkIndexes
        )
    }

    func testShouldBackfillTranscriptToMongoWhenDatabaseTranscriptIsIncomplete() {
        XCTAssertTrue(
            TerminalMonitorStore.shouldBackfillTranscriptToMongo(
                localChunkCount: 3,
                localByteCount: 120,
                databaseSummary: MongoSessionChunkSummary(chunkCount: 2, byteCount: 120, minChunkIndex: 1, maxChunkIndex: 2)
            )
        )
        XCTAssertTrue(
            TerminalMonitorStore.shouldBackfillTranscriptToMongo(
                localChunkCount: 3,
                localByteCount: 120,
                databaseSummary: MongoSessionChunkSummary(chunkCount: 3, byteCount: 119, minChunkIndex: 1, maxChunkIndex: 3)
            )
        )
        XCTAssertTrue(
            TerminalMonitorStore.shouldBackfillTranscriptToMongo(
                localChunkCount: 3,
                localByteCount: 120,
                databaseSummary: MongoSessionChunkSummary(chunkCount: 3, byteCount: 120, minChunkIndex: 1, maxChunkIndex: 4)
            )
        )
        XCTAssertFalse(
            TerminalMonitorStore.shouldBackfillTranscriptToMongo(
                localChunkCount: 3,
                localByteCount: 120,
                databaseSummary: MongoSessionChunkSummary(chunkCount: 3, byteCount: 120, minChunkIndex: 1, maxChunkIndex: 3)
            )
        )
    }

    func testTranscriptSynchronizationMessageCoversCompletionFailureAndRefreshContexts() {
        XCTAssertEqual(
            TerminalMonitorStore.transcriptSynchronizationMessage(for: .completionSuccess, importedChunkCount: 4),
            "Completed session transcript synchronized to MongoDB (4 chunks)."
        )
        XCTAssertEqual(
            TerminalMonitorStore.transcriptSynchronizationMessage(for: .completionFailure, importedChunkCount: 4),
            "Non-zero session transcript synchronized to MongoDB (4 chunks)."
        )
        XCTAssertEqual(
            TerminalMonitorStore.transcriptSynchronizationMessage(for: .monitoringFailure, importedChunkCount: 4),
            "Monitoring failed, but the session transcript was synchronized to MongoDB (4 chunks)."
        )
        XCTAssertEqual(
            TerminalMonitorStore.transcriptSynchronizationMessage(for: .recentSessionRefresh, importedChunkCount: 4),
            "Historical session transcript synchronized to MongoDB (4 chunks)."
        )
        XCTAssertEqual(
            TerminalMonitorStore.transcriptSynchronizationMessage(for: .directoryRecovery, importedChunkCount: 4),
            "Recovered local transcript into MongoDB (4 chunks)."
        )
    }

    func testInputSynchronizationMessageCoversCompletionFailureAndRefreshContexts() {
        XCTAssertEqual(
            TerminalMonitorStore.inputSynchronizationMessage(for: .completionSuccess, importedChunkCount: 4),
            "Completed session raw input synchronized to MongoDB (4 chunks)."
        )
        XCTAssertEqual(
            TerminalMonitorStore.inputSynchronizationMessage(for: .completionFailure, importedChunkCount: 4),
            "Non-zero session raw input synchronized to MongoDB (4 chunks)."
        )
        XCTAssertEqual(
            TerminalMonitorStore.inputSynchronizationMessage(for: .monitoringFailure, importedChunkCount: 4),
            "Monitoring failed, but the raw input capture was synchronized to MongoDB (4 chunks)."
        )
        XCTAssertEqual(
            TerminalMonitorStore.inputSynchronizationMessage(for: .recentSessionRefresh, importedChunkCount: 4),
            "Historical session raw input synchronized to MongoDB (4 chunks)."
        )
        XCTAssertEqual(
            TerminalMonitorStore.inputSynchronizationMessage(for: .directoryRecovery, importedChunkCount: 4),
            "Recovered local raw input capture into MongoDB (4 chunks)."
        )
        XCTAssertEqual(
            TerminalMonitorStore.inputSynchronizationEventType(recoveredWithoutDatabaseSession: false),
            "session_input_capture_synchronized"
        )
        XCTAssertEqual(
            TerminalMonitorStore.inputSynchronizationEventType(recoveredWithoutDatabaseSession: true),
            "session_input_capture_recovered"
        )
        XCTAssertEqual(
            TerminalMonitorStore.completionSyncFailureMessage(
                error: "write failed",
                retainedRawInputCapture: false
            ),
            "MongoDB completion sync failed; local transcript file was retained: write failed"
        )
        XCTAssertEqual(
            TerminalMonitorStore.completionSyncFailureMessage(
                error: "write failed",
                retainedRawInputCapture: true
            ),
            "MongoDB completion sync failed; local transcript and raw input files were retained: write failed"
        )
    }

    func testShouldScheduleDeferredRecentSessionMaintenanceSkipsBusyOrRecentlyMaintainedStates() {
        let now = Date(timeIntervalSince1970: 1_713_960_000)

        XCTAssertFalse(
            TerminalMonitorStore.shouldScheduleDeferredRecentSessionMaintenance(
                enableMongoWrites: false,
                isLoadingRecentSessions: false,
                isRunningRecentSessionMaintenance: false,
                hasPendingMaintenanceTask: false,
                force: false,
                lastRecentSessionMaintenanceAt: nil,
                now: now,
                minimumRecentSessionMaintenanceInterval: 20
            )
        )

        XCTAssertFalse(
            TerminalMonitorStore.shouldScheduleDeferredRecentSessionMaintenance(
                enableMongoWrites: true,
                isLoadingRecentSessions: true,
                isRunningRecentSessionMaintenance: false,
                hasPendingMaintenanceTask: false,
                force: false,
                lastRecentSessionMaintenanceAt: nil,
                now: now,
                minimumRecentSessionMaintenanceInterval: 20
            )
        )

        XCTAssertFalse(
            TerminalMonitorStore.shouldScheduleDeferredRecentSessionMaintenance(
                enableMongoWrites: true,
                isLoadingRecentSessions: false,
                isRunningRecentSessionMaintenance: true,
                hasPendingMaintenanceTask: false,
                force: false,
                lastRecentSessionMaintenanceAt: nil,
                now: now,
                minimumRecentSessionMaintenanceInterval: 20
            )
        )

        XCTAssertFalse(
            TerminalMonitorStore.shouldScheduleDeferredRecentSessionMaintenance(
                enableMongoWrites: true,
                isLoadingRecentSessions: false,
                isRunningRecentSessionMaintenance: false,
                hasPendingMaintenanceTask: true,
                force: false,
                lastRecentSessionMaintenanceAt: nil,
                now: now,
                minimumRecentSessionMaintenanceInterval: 20
            )
        )

        XCTAssertFalse(
            TerminalMonitorStore.shouldScheduleDeferredRecentSessionMaintenance(
                enableMongoWrites: true,
                isLoadingRecentSessions: false,
                isRunningRecentSessionMaintenance: false,
                hasPendingMaintenanceTask: false,
                force: false,
                lastRecentSessionMaintenanceAt: now.addingTimeInterval(-5),
                now: now,
                minimumRecentSessionMaintenanceInterval: 20
            )
        )
    }

    func testShouldScheduleDeferredRecentSessionMaintenanceAllowsForcedOrStaleMaintenance() {
        let now = Date(timeIntervalSince1970: 1_713_960_000)

        XCTAssertTrue(
            TerminalMonitorStore.shouldScheduleDeferredRecentSessionMaintenance(
                enableMongoWrites: true,
                isLoadingRecentSessions: false,
                isRunningRecentSessionMaintenance: false,
                hasPendingMaintenanceTask: false,
                force: false,
                lastRecentSessionMaintenanceAt: now.addingTimeInterval(-25),
                now: now,
                minimumRecentSessionMaintenanceInterval: 20
            )
        )

        XCTAssertTrue(
            TerminalMonitorStore.shouldScheduleDeferredRecentSessionMaintenance(
                enableMongoWrites: true,
                isLoadingRecentSessions: false,
                isRunningRecentSessionMaintenance: false,
                hasPendingMaintenanceTask: false,
                force: true,
                lastRecentSessionMaintenanceAt: now.addingTimeInterval(-5),
                now: now,
                minimumRecentSessionMaintenanceInterval: 20
            )
        )
    }

    func testSessionByApplyingMongoTranscriptSyncProgressTracksCoverageState() {
        let synchronizedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )

        let streaming = TerminalMonitorStore.sessionByApplyingMongoTranscriptSyncProgress(
            source: "live_chunk_capture",
            chunkCount: 2,
            byteCount: 512,
            synchronizedAt: synchronizedAt,
            verifiedComplete: false,
            to: session
        )
        XCTAssertEqual(streaming.mongoTranscriptSyncState, .streaming)
        XCTAssertEqual(streaming.mongoTranscriptSyncSource, "live_chunk_capture")
        XCTAssertEqual(streaming.mongoTranscriptChunkCount, 2)
        XCTAssertEqual(streaming.mongoTranscriptByteCount, 512)
        XCTAssertEqual(streaming.mongoTranscriptSynchronizedAt, synchronizedAt)
        XCTAssertEqual(streaming.mongoTranscriptSyncSourceDisplayName, "Live chunk capture")

        let complete = TerminalMonitorStore.sessionByApplyingMongoTranscriptSyncProgress(
            source: "local_transcript_directory_scan",
            chunkCount: 4,
            byteCount: 2048,
            synchronizedAt: synchronizedAt,
            verifiedComplete: true,
            to: streaming
        )
        XCTAssertEqual(complete.mongoTranscriptSyncState, .complete)
        XCTAssertEqual(complete.mongoTranscriptSyncSourceDisplayName, "Recovered local transcript file")
    }

    func testSessionByApplyingMongoInputSyncProgressTracksCoverageState() {
        let synchronizedAt = Date(timeIntervalSince1970: 1_700_000_250)
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .inputAndOutput
        )

        let streaming = TerminalMonitorStore.sessionByApplyingMongoInputSyncProgress(
            source: "live_input_capture",
            chunkCount: 3,
            byteCount: 96,
            synchronizedAt: synchronizedAt,
            verifiedComplete: false,
            to: session
        )
        XCTAssertEqual(streaming.mongoInputSyncState, .streaming)
        XCTAssertEqual(streaming.mongoInputSyncSource, "live_input_capture")
        XCTAssertEqual(streaming.mongoInputChunkCount, 3)
        XCTAssertEqual(streaming.mongoInputByteCount, 96)
        XCTAssertEqual(streaming.mongoInputSynchronizedAt, synchronizedAt)
        XCTAssertEqual(streaming.mongoInputSyncSourceDisplayName, "Live raw input capture")

        let complete = TerminalMonitorStore.sessionByApplyingMongoInputSyncProgress(
            source: "local_input_capture_file",
            chunkCount: 4,
            byteCount: 128,
            synchronizedAt: synchronizedAt,
            verifiedComplete: true,
            to: streaming
        )
        XCTAssertEqual(complete.mongoInputSyncState, .complete)
        XCTAssertEqual(complete.mongoInputSyncSourceDisplayName, "Local raw input capture file")
    }

    func testSessionByApplyingMongoInputSyncCompletionFromDatabaseSummaryIfNeededMarksSessionComplete() {
        var session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .inputAndOutput
        )
        session.inputChunkCount = 3
        session.inputByteCount = 80
        session.mongoInputSyncSource = "live_input_capture"
        session.mongoInputSynchronizedAt = Date(timeIntervalSince1970: 1_700_000_400)

        let completed = TerminalMonitorStore.sessionByApplyingMongoInputSyncCompletionFromDatabaseSummaryIfNeeded(
            MongoSessionChunkSummary(chunkCount: 3, byteCount: 80, minChunkIndex: 1, maxChunkIndex: 3),
            to: session
        )
        XCTAssertEqual(completed.mongoInputSyncState, .complete)
        XCTAssertEqual(completed.mongoInputSyncSource, "live_input_capture")
        XCTAssertEqual(completed.mongoInputChunkCount, 3)
        XCTAssertEqual(completed.mongoInputByteCount, 80)

        let gapped = TerminalMonitorStore.sessionByApplyingMongoInputSyncCompletionFromDatabaseSummaryIfNeeded(
            MongoSessionChunkSummary(chunkCount: 3, byteCount: 80, minChunkIndex: 1, maxChunkIndex: 4),
            to: session
        )
        XCTAssertNil(gapped.mongoInputSyncState)
    }

    func testSessionByApplyingMongoTranscriptCompletionFromDatabaseSummaryIfNeededMarksSessionComplete() {
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastActivityAt: Date(timeIntervalSince1970: 1_700_000_020),
            chunkCount: 3,
            byteCount: 120
        )

        let completed = TerminalMonitorStore.sessionByApplyingMongoTranscriptCompletionFromDatabaseSummaryIfNeeded(
            MongoSessionChunkSummary(chunkCount: 3, byteCount: 120, minChunkIndex: 1, maxChunkIndex: 3),
            to: session
        )
        XCTAssertEqual(completed.mongoTranscriptSyncState, .complete)
        XCTAssertEqual(completed.mongoTranscriptSyncSource, "live_chunk_capture")
        XCTAssertEqual(completed.mongoTranscriptChunkCount, 3)
        XCTAssertEqual(completed.mongoTranscriptByteCount, 120)

        let unchanged = TerminalMonitorStore.sessionByApplyingMongoTranscriptCompletionFromDatabaseSummaryIfNeeded(
            MongoSessionChunkSummary(chunkCount: 2, byteCount: 120, minChunkIndex: 1, maxChunkIndex: 2),
            to: session
        )
        XCTAssertEqual(unchanged, session)

        let gapped = TerminalMonitorStore.sessionByApplyingMongoTranscriptCompletionFromDatabaseSummaryIfNeeded(
            MongoSessionChunkSummary(chunkCount: 3, byteCount: 120, minChunkIndex: 1, maxChunkIndex: 4),
            to: session
        )
        XCTAssertEqual(gapped, session)

        let staleRowSession = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )
        let staleRowCompleted = TerminalMonitorStore.sessionByApplyingMongoTranscriptCompletionFromDatabaseSummaryIfNeeded(
            MongoSessionChunkSummary(chunkCount: 5, byteCount: 2048, minChunkIndex: 1, maxChunkIndex: 5),
            to: staleRowSession
        )
        XCTAssertEqual(staleRowCompleted.mongoTranscriptSyncState, .complete)
        XCTAssertEqual(staleRowCompleted.mongoTranscriptChunkCount, 5)
        XCTAssertEqual(staleRowCompleted.mongoTranscriptByteCount, 2048)
    }

    func testShouldDeleteLocalTranscriptAfterCompletionRequiresSuccessfulMongoSyncWhenWritesEnabled() {
        XCTAssertTrue(
            TerminalMonitorStore.shouldDeleteLocalTranscriptAfterCompletion(
                completedSuccessfully: true,
                keepLocalTranscriptFiles: false,
                enableMongoWrites: false,
                mongoSyncSucceeded: false
            )
        )
        XCTAssertTrue(
            TerminalMonitorStore.shouldDeleteLocalTranscriptAfterCompletion(
                completedSuccessfully: true,
                keepLocalTranscriptFiles: false,
                enableMongoWrites: true,
                mongoSyncSucceeded: true
            )
        )
        XCTAssertFalse(
            TerminalMonitorStore.shouldDeleteLocalTranscriptAfterCompletion(
                completedSuccessfully: true,
                keepLocalTranscriptFiles: false,
                enableMongoWrites: true,
                mongoSyncSucceeded: false
            )
        )
        XCTAssertFalse(
            TerminalMonitorStore.shouldDeleteLocalTranscriptAfterCompletion(
                completedSuccessfully: true,
                keepLocalTranscriptFiles: true,
                enableMongoWrites: true,
                mongoSyncSucceeded: true
            )
        )
        XCTAssertFalse(
            TerminalMonitorStore.shouldDeleteLocalTranscriptAfterCompletion(
                completedSuccessfully: false,
                keepLocalTranscriptFiles: false,
                enableMongoWrites: true,
                mongoSyncSucceeded: true
            )
        )
    }

    func testShouldDeleteLocalCaptureFilesAfterClearRequiresSuccessfulMongoClearWhenWritesEnabled() {
        XCTAssertFalse(
            TerminalMonitorStore.shouldDeleteLocalCaptureFilesAfterClear(
                enableMongoWrites: true,
                databaseClearSucceeded: false
            )
        )
        XCTAssertTrue(
            TerminalMonitorStore.shouldDeleteLocalCaptureFilesAfterClear(
                enableMongoWrites: true,
                databaseClearSucceeded: true
            )
        )
        XCTAssertTrue(
            TerminalMonitorStore.shouldDeleteLocalCaptureFilesAfterClear(
                enableMongoWrites: false,
                databaseClearSucceeded: false
            )
        )
    }

    func testRecoveredTranscriptSessionIfManagedFileParsesFilenameAndCompletionMarker() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sessionID = UUID()
        let transcriptURL = directory.appendingPathComponent("20260424-103015-gemini-\(sessionID.uuidString).typescript")
        try Data("hello from transcript".utf8).write(to: transcriptURL)
        try """
        exit_code=0
        ended_at=2026-04-24T10:31:45Z
        reason=command_finished
        """.write(to: transcriptURL.appendingPathExtension("exit"), atomically: true, encoding: .utf8)
        try Data("raw-input".utf8).write(to: URL(fileURLWithPath: transcriptURL.path + ".stdinrec"))

        let recovered = try XCTUnwrap(TerminalMonitorStore.recoveredTranscriptSessionIfManagedFile(transcriptURL))

        XCTAssertEqual(recovered.id, sessionID)
        XCTAssertEqual(recovered.agentKind, .gemini)
        XCTAssertEqual(recovered.profileName, "Gemini (Recovered Transcript)")
        XCTAssertEqual(recovered.launchCommand, "Recovered from local transcript file")
        XCTAssertEqual(recovered.captureMode, .inputAndOutput)
        XCTAssertEqual(recovered.inputCapturePath, transcriptURL.path + ".stdinrec")
        XCTAssertEqual(recovered.status, .completed)
        XCTAssertEqual(recovered.statusReason, "command_finished")
        XCTAssertEqual(recovered.exitCode, 0)
        XCTAssertEqual(recovered.chunkCount, 1)
        XCTAssertEqual(recovered.byteCount, Data("hello from transcript".utf8).count)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(try XCTUnwrap(recovered.endedAt), try XCTUnwrap(formatter.date(from: "2026-04-24T10:31:45Z")))
        XCTAssertTrue(recovered.isHistorical)
    }

    func testRecoveredTranscriptSessionsCanFilterForPrunableFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let oldID = UUID()
        let protectedID = UUID()
        let recentID = UUID()

        let oldURL = directory.appendingPathComponent("20260301-101500-gemini-\(oldID.uuidString).typescript")
        let protectedURL = directory.appendingPathComponent("20260301-111500-gemini-\(protectedID.uuidString).typescript")
        let recentURL = directory.appendingPathComponent("20260420-101500-gemini-\(recentID.uuidString).typescript")

        try Data("old".utf8).write(to: oldURL)
        try Data("protected".utf8).write(to: protectedURL)
        try Data("recent".utf8).write(to: recentURL)

        let oldDate = Date().addingTimeInterval(-40 * 86_400)
        let recentDate = Date().addingTimeInterval(-5 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldURL.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: protectedURL.path)
        try FileManager.default.setAttributes([.modificationDate: recentDate], ofItemAtPath: recentURL.path)

        let recovered = TerminalMonitorStore.recoveredTranscriptSessions(
            at: directory.path,
            olderThanDays: 30,
            protectedPaths: [protectedURL.path]
        )

        XCTAssertEqual(recovered.map(\.id), [oldID])
    }

    @MainActor
    func testCaptureGeminiTranscriptInteractionsOnlyReturnsNewSuffix() {
        let store = TerminalMonitorStore()
        let sessionID = UUID()

        let first = store.captureGeminiTranscriptInteractionsIfPresent(
            sessionID: sessionID,
            bufferedTranscriptText: """
            Type your message or @path/to/file
            > /stats
            """
        )
        let second = store.captureGeminiTranscriptInteractionsIfPresent(
            sessionID: sessionID,
            bufferedTranscriptText: """
            Type your message or @path/to/file
            > /stats
            > continue
            """
        )
        let third = store.captureGeminiTranscriptInteractionsIfPresent(
            sessionID: sessionID,
            bufferedTranscriptText: """
            Type your message or @path/to/file
            > /stats
            > continue
            """
        )

        XCTAssertEqual(first.map(\.text), ["/stats"])
        XCTAssertEqual(second.map(\.text), ["continue"])
        XCTAssertTrue(third.isEmpty)
    }

    func testSessionByApplyingGeminiSessionStatsRetainsExistingStartupCommandAndUsageWhenSnapshotIsPartial() {
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            accountIdentifier: "user@example.com",
            providerSessionID: "session-123",
            providerAuthMethod: "Signed in with Google (user@example.com)",
            providerTier: "Gemini Code Assist for individuals",
            providerStartupStatsCommand: "/stats",
            providerStartupStatsCommandSource: "echoed_command",
            providerModelUsageNote: "Use /model to view model quota information",
            providerModelUsage: [
                GeminiSessionStatsModelUsageRow(
                    model: "gemini-2.5-pro",
                    label: nil,
                    requests: 3,
                    inputTokens: 120,
                    cacheReads: 7,
                    outputTokens: 42
                )
            ],
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )
        let snapshot = GeminiSessionStatsSnapshot(
            sessionID: "session-123",
            authMethod: "Signed in with Google (user@example.com)",
            accountIdentifier: nil,
            tier: "Gemini Code Assist for individuals",
            toolCalls: "1",
            successRate: nil,
            wallTime: "3.4s",
            agentActive: nil,
            apiTime: nil,
            toolTime: nil,
            startupStatsCommand: nil,
            modelUsageNote: nil,
            modelUsage: []
        )

        let updated = TerminalMonitorStore.sessionByApplyingGeminiSessionStats(snapshot, to: session)

        XCTAssertEqual(updated.providerStartupStatsCommand, "/stats")
        XCTAssertEqual(updated.providerStartupStatsCommandSource, "echoed_command")
        XCTAssertEqual(updated.providerModelUsageNote, "Use /model to view model quota information")
        XCTAssertEqual(updated.providerModelUsage?.count, 1)
        XCTAssertEqual(updated.providerModelUsage?.first?.model, "gemini-2.5-pro")
        XCTAssertEqual(updated.providerModelUsage?.first?.requests, 3)
    }

    func testSessionByApplyingGeminiSessionStatsDoesNotOverwriteStartupCaptureWithLaterManualStats() {
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            accountIdentifier: "user@example.com",
            providerSessionID: "session-123",
            providerAuthMethod: "Signed in with Google (user@example.com)",
            providerTier: "Gemini Code Assist for individuals",
            providerStartupStatsCommand: "/stats",
            providerStartupStatsCommandSource: "echoed_command",
            providerModelUsageNote: "Use /model to view model quota information",
            providerModelUsage: [
                GeminiSessionStatsModelUsageRow(
                    model: "gemini-2.5-pro",
                    label: nil,
                    requests: 3,
                    inputTokens: 120,
                    cacheReads: 7,
                    outputTokens: 42
                )
            ],
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )
        let snapshot = GeminiSessionStatsSnapshot(
            sessionID: "session-123",
            authMethod: "Signed in with Google (user@example.com)",
            accountIdentifier: "user@example.com",
            tier: "Gemini Code Assist for individuals",
            toolCalls: "2",
            successRate: nil,
            wallTime: "8.9s",
            agentActive: nil,
            apiTime: nil,
            toolTime: nil,
            startupStatsCommand: "/stats",
            startupStatsCommandSource: "runner_banner",
            modelUsageNote: "Later manual stats panel",
            modelUsage: [
                GeminiSessionStatsModelUsageRow(
                    model: "gemini-2.5-pro",
                    label: nil,
                    requests: 8,
                    inputTokens: 240,
                    cacheReads: 12,
                    outputTokens: 84
                )
            ]
        )

        let updated = TerminalMonitorStore.sessionByApplyingGeminiSessionStats(snapshot, to: session)

        XCTAssertEqual(updated.providerStartupStatsCommand, "/stats")
        XCTAssertEqual(updated.providerStartupStatsCommandSource, "echoed_command")
        XCTAssertEqual(updated.providerModelUsageNote, "Use /model to view model quota information")
        XCTAssertEqual(updated.providerModelUsage?.count, 1)
        XCTAssertEqual(updated.providerModelUsage?.first?.model, "gemini-2.5-pro")
        XCTAssertEqual(updated.providerModelUsage?.first?.requests, 3)
    }

    func testSessionByApplyingGeminiStartupClearPersistsReasonWithoutOverwritingLater() {
        let session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )
        let sentNotice = GeminiStartupClearNotice(
            fingerprint: "clear-sent",
            command: "/clear",
            completed: false,
            reason: nil,
            source: "echoed_command"
        )
        let completedNotice = GeminiStartupClearNotice(
            fingerprint: "clear-completed",
            command: "/clear",
            completed: true,
            reason: "visible prompt field",
            source: "runner_banner"
        )
        let laterCompletedNotice = GeminiStartupClearNotice(
            fingerprint: "clear-completed-late",
            command: "/clear",
            completed: true,
            reason: "later manual clear",
            source: "runner_banner"
        )

        let afterSent = TerminalMonitorStore.sessionByApplyingGeminiStartupClear(sentNotice, to: session)
        let afterCompleted = TerminalMonitorStore.sessionByApplyingGeminiStartupClear(completedNotice, to: afterSent)
        let final = TerminalMonitorStore.sessionByApplyingGeminiStartupClear(laterCompletedNotice, to: afterCompleted)

        XCTAssertEqual(final.providerStartupClearCommand, "/clear")
        XCTAssertEqual(final.providerStartupClearCommandSource, "echoed_command")
        XCTAssertEqual(final.providerStartupClearCompleted, true)
        XCTAssertEqual(final.providerStartupClearReason, "visible prompt field")
    }
}

@MainActor
final class TerminalMonitorStoreFocusTests: XCTestCase {
    func testPendingFocusedSessionIsConsumedOnce() {
        let store = TerminalMonitorStore()
        let sessionID = UUID()

        store.noteSessionForInspection(sessionID)

        XCTAssertEqual(store.consumePendingFocusedSessionID(), sessionID)
        XCTAssertNil(store.consumePendingFocusedSessionID())
    }

    func testMostRecentFocusedSessionWins() {
        let store = TerminalMonitorStore()
        let first = UUID()
        let second = UUID()

        store.noteSessionForInspection(first)
        store.noteSessionForInspection(second)

        XCTAssertEqual(store.consumePendingFocusedSessionID(), second)
    }

    func testPendingFocusedSessionIsRetainedUntilVisible() {
        let store = TerminalMonitorStore()
        let hidden = UUID()
        let visible = UUID()

        store.noteSessionForInspection(hidden)

        XCTAssertNil(store.consumePendingFocusedSessionID(ifContainedIn: [visible]))
        XCTAssertEqual(store.consumePendingFocusedSessionID(ifContainedIn: [hidden, visible]), hidden)
    }

    func testPresentHistoricalSessionMarksItHistoricalAndQueuesFocus() {
        let store = TerminalMonitorStore()
        let sessionID = UUID()
        let session = TerminalMonitorSession(
            id: sessionID,
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )

        store.presentHistoricalSession(session)

        XCTAssertEqual(store.sessions.first?.id, sessionID)
        XCTAssertTrue(store.sessions.first?.isHistorical == true)
        XCTAssertEqual(store.consumePendingFocusedSessionID(), sessionID)
    }

    func testEnsureSessionVisibleReportsUnavailableWithoutMongoHistory() {
        let store = TerminalMonitorStore()
        let logger = LaunchLogger()
        let sessionID = UUID()
        var settings = AppSettings()
        settings.mongoMonitoring.enabled = false
        settings.mongoMonitoring.enableMongoWrites = false

        store.ensureSessionVisible(sessionID: sessionID, settings: settings, logger: logger)

        XCTAssertEqual(store.databaseStatus, "Linked session history is unavailable without MongoDB.")
        XCTAssertEqual(store.consumePendingFocusedSessionID(), sessionID)
        XCTAssertEqual(logger.entries.first?.category, .monitoring)
        XCTAssertEqual(logger.entries.first?.level, .warning)
    }

    func testPresentHistoricalSessionsKeepsRequestedFocusSession() {
        let store = TerminalMonitorStore()
        let firstID = UUID()
        let secondID = UUID()
        let first = TerminalMonitorSession(
            id: firstID,
            profileID: nil,
            profileName: "First",
            agentKind: .gemini,
            workingDirectory: "/tmp/first",
            transcriptPath: "/tmp/first.typescript",
            launchCommand: "gemini first",
            captureMode: .outputOnly
        )
        let second = TerminalMonitorSession(
            id: secondID,
            profileID: nil,
            profileName: "Second",
            agentKind: .gemini,
            workingDirectory: "/tmp/second",
            transcriptPath: "/tmp/second.typescript",
            launchCommand: "gemini second",
            captureMode: .outputOnly
        )

        store.presentHistoricalSessions([first, second], focusedSessionID: firstID)

        XCTAssertEqual(Set(store.sessions.map(\.id)), Set([firstID, secondID]))
        XCTAssertEqual(store.consumePendingFocusedSessionID(), firstID)
    }

    func testPresentHistoricalSessionsPublishesSingleBatchUpdate() {
        let store = TerminalMonitorStore()
        let firstID = UUID()
        let secondID = UUID()
        let first = TerminalMonitorSession(
            id: firstID,
            profileID: nil,
            profileName: "First",
            agentKind: .gemini,
            workingDirectory: "/tmp/first",
            transcriptPath: "/tmp/first.typescript",
            launchCommand: "gemini first",
            captureMode: .outputOnly
        )
        let second = TerminalMonitorSession(
            id: secondID,
            profileID: nil,
            profileName: "Second",
            agentKind: .gemini,
            workingDirectory: "/tmp/second",
            transcriptPath: "/tmp/second.typescript",
            launchCommand: "gemini second",
            captureMode: .outputOnly
        )

        var publishedSnapshots: [[UUID]] = []
        let cancellable = store.$sessions
            .dropFirst()
            .sink { publishedSnapshots.append($0.map(\.id)) }

        store.presentHistoricalSessions([first, second], focusedSessionID: firstID)
        cancellable.cancel()

        XCTAssertEqual(publishedSnapshots.count, 1)
        XCTAssertEqual(Set(publishedSnapshots[0]), Set([firstID, secondID]))
    }

    func testPresentHistoricalSessionDoesNotRepublishIdenticalSession() {
        let store = TerminalMonitorStore()
        let sessionID = UUID()
        let session = TerminalMonitorSession(
            id: sessionID,
            profileID: nil,
            profileName: "Gemini",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .outputOnly
        )

        var publishedSnapshots: [[UUID]] = []
        let cancellable = store.$sessions
            .dropFirst()
            .sink { publishedSnapshots.append($0.map(\.id)) }

        store.presentHistoricalSession(session, queueFocus: false)
        store.presentHistoricalSession(session, queueFocus: false)
        cancellable.cancel()

        XCTAssertEqual(store.sessions.map(\.id), [sessionID])
        XCTAssertEqual(publishedSnapshots, [[sessionID]])
    }

    func testPresentHistoricalSessionReordersExistingSessionWithSinglePublish() {
        let store = TerminalMonitorStore()
        let firstID = UUID()
        let secondID = UUID()
        var first = TerminalMonitorSession(
            id: firstID,
            profileID: nil,
            profileName: "First",
            agentKind: .gemini,
            workingDirectory: "/tmp/first",
            transcriptPath: "/tmp/first.typescript",
            launchCommand: "gemini first",
            captureMode: .outputOnly
        )
        var second = TerminalMonitorSession(
            id: secondID,
            profileID: nil,
            profileName: "Second",
            agentKind: .gemini,
            workingDirectory: "/tmp/second",
            transcriptPath: "/tmp/second.typescript",
            launchCommand: "gemini second",
            captureMode: .outputOnly
        )
        first.lastActivityAt = Date(timeIntervalSince1970: 10)
        second.lastActivityAt = Date(timeIntervalSince1970: 20)
        store.presentHistoricalSessions([first, second], focusedSessionID: nil)

        first.lastActivityAt = Date(timeIntervalSince1970: 30)
        first.lastDatabaseMessage = "updated"

        var publishedSnapshots: [[UUID]] = []
        let cancellable = store.$sessions
            .dropFirst()
            .sink { publishedSnapshots.append($0.map(\.id)) }

        store.presentHistoricalSession(first, queueFocus: false)
        cancellable.cancel()

        XCTAssertEqual(store.sessions.map(\.id), [firstID, secondID])
        XCTAssertEqual(publishedSnapshots, [[firstID, secondID]])
    }

    func testPendingMonitoringFilterResetIsConsumedOnce() {
        let store = TerminalMonitorStore()
        let sessionID = UUID()

        store.noteSessionForInspection(sessionID, resetFilters: true)

        XCTAssertTrue(store.consumePendingMonitoringFilterReset())
        XCTAssertFalse(store.consumePendingMonitoringFilterReset())
    }
}

@MainActor
final class TerminalMonitorPreparationTests: XCTestCase {
    func testPrepareWrapsMonitoredLaunchViaDurableLaunchScript() throws {
        let store = TerminalMonitorStore()
        let logger = LaunchLogger()
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let transcriptDirectory = tempDirectory.appendingPathComponent("Transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        var settings = AppSettings()
        settings.mongoMonitoring.enabled = true
        settings.mongoMonitoring.enableMongoWrites = false
        settings.mongoMonitoring.transcriptDirectory = transcriptDirectory.path
        settings.mongoMonitoring.scriptExecutable = "/usr/bin/script"

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.name = "Gemini"
        profile.workingDirectory = tempDirectory.path
        profile.geminiLaunchMode = .directWrapper
        profile.geminiWrapperCommand = "/bin/echo"
        profile.geminiHotkeyPrefix = "ctrl-\\"

        let originalCommand = try CommandBuilder().buildCommand(profile: profile, settings: settings)
        let plan = PlannedLaunch(items: [
            PlannedLaunchItem(
                profileID: profile.id,
                profileName: profile.name,
                command: originalCommand,
                openMode: .newWindow,
                terminalApp: .iterm2,
                iTermProfile: "",
                description: "Gemini"
            )
        ])

        let prepared = try store.prepare(plan: plan, profiles: [profile], settings: settings, logger: logger)
        let wrappedCommand = try XCTUnwrap(prepared.items.first?.command)

        XCTAssertTrue(wrappedCommand.contains("/usr/bin/script"))
        XCTAssertFalse(wrappedCommand.contains("/bin/sh -lc "))
        XCTAssertTrue(wrappedCommand.contains("/usr/bin/mktemp -t clilauncher-monitor-launch"))
        XCTAssertTrue(wrappedCommand.contains("[ -t 0 ] || [ -t 1 ] || [ -t 2 ]"))
        XCTAssertTrue(wrappedCommand.contains("/usr/bin/tee"))
        XCTAssertTrue(wrappedCommand.contains("<<'__CLILAUNCHER_MONITOR_"))
        XCTAssertTrue(wrappedCommand.contains("trap '/bin/rm -f \"$__clilauncher_monitor_helper_path\"' EXIT"))
        XCTAssertTrue(wrappedCommand.contains("CLILAUNCHER_LAST_REASON='monitor-wrapper-failed'"))
        XCTAssertTrue(wrappedCommand.contains("CLILAUNCHER_TRANSCRIPT_PATH="))
        XCTAssertTrue(wrappedCommand.contains("exec /bin/zsh -il"))
        XCTAssertTrue(wrappedCommand.contains("HOTKEY_PREFIX='ctrl-\\'"))
        XCTAssertTrue(wrappedCommand.contains("GEMINI_WRAPPER='/bin/echo'"))
    }

    func testPreparedMonitorCommandRunsEndToEndViaScript() throws {
        let store = TerminalMonitorStore()
        let logger = LaunchLogger()
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let transcriptDirectory = tempDirectory.appendingPathComponent("Transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        var settings = AppSettings()
        settings.mongoMonitoring.enabled = true
        settings.mongoMonitoring.enableMongoWrites = false
        settings.mongoMonitoring.transcriptDirectory = transcriptDirectory.path
        settings.mongoMonitoring.scriptExecutable = "/usr/bin/script"

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.name = "Gemini"
        profile.workingDirectory = tempDirectory.path
        profile.geminiLaunchMode = .directWrapper
        profile.geminiWrapperCommand = "/bin/echo"
        profile.geminiHotkeyPrefix = "ctrl-\\"

        let originalCommand = try CommandBuilder().buildCommand(profile: profile, settings: settings)
        let plan = PlannedLaunch(items: [
            PlannedLaunchItem(
                profileID: profile.id,
                profileName: profile.name,
                command: originalCommand,
                openMode: .newWindow,
                terminalApp: .iterm2,
                iTermProfile: "",
                description: "Gemini"
            )
        ])

        let prepared = try store.prepare(plan: plan, profiles: [profile], settings: settings, logger: logger)
        let wrappedCommand = try XCTUnwrap(prepared.items.first?.command)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", wrappedCommand]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let transcriptFiles = try FileManager.default.contentsOfDirectory(
            at: transcriptDirectory,
            includingPropertiesForKeys: nil
        )
        let transcript = try XCTUnwrap(transcriptFiles.first { $0.lastPathComponent.hasSuffix(".typescript") })
        let completion = try XCTUnwrap(transcriptFiles.first { $0.lastPathComponent.hasSuffix(".typescript.exit") })

        let transcriptText = try String(contentsOf: transcript, encoding: .utf8)
        let completionText = try String(contentsOf: completion, encoding: .utf8)
        XCTAssertFalse(transcriptText.contains("No such file or directory"))
        XCTAssertTrue(completionText.contains("exit_code=0"))
    }
}

final class MongoMonitoringWriterScriptTests: XCTestCase {
    func testMongoSchemaInitializationFingerprintTracksMongoTarget() {
        var settings = MongoMonitoringSettings()
        settings.connectionURL = "mongodb://127.0.0.1:27017"
        settings.schemaName = "clilauncher_state"
        settings.localDataDirectory = "~/Library/Application Support/CLI Launcher/mongo"

        let baseline = MongoMonitoringWriter.schemaInitializationFingerprint(for: settings)

        XCTAssertEqual(
            baseline,
            MongoMonitoringWriter.schemaInitializationFingerprint(for: settings)
        )

        settings.schemaName = "clilauncher_other"
        XCTAssertNotEqual(
            baseline,
            MongoMonitoringWriter.schemaInitializationFingerprint(for: settings)
        )
    }

    func testMongoNeedsSchemaInitializationShortCircuitsMatchingFingerprint() {
        XCTAssertFalse(
            MongoMonitoringWriter.needsSchemaInitialization(
                currentFingerprint: "mongo://example|schema|/tmp/data",
                nextFingerprint: "mongo://example|schema|/tmp/data"
            )
        )
        XCTAssertTrue(
            MongoMonitoringWriter.needsSchemaInitialization(
                currentFingerprint: "mongo://example|schema|/tmp/data",
                nextFingerprint: "mongo://example|other|/tmp/data"
            )
        )
    }

    func testMongoShellStringLiteralEncodesPlainStringsForMongoshScripts() {
        XCTAssertEqual(
            MongoShellLiterals.stringLiteral("db'name\\path"),
            "\"db'name\\\\path\""
        )
    }

    func testMongoEnsureSchemaScriptAvoidsListCollectionsForShellCompatibility() {
        let script = MongoMonitoringWriter.ensureSchemaScript(databaseName: "clilauncher_state")

        XCTAssertFalse(script.contains("listCollections()"))
        XCTAssertTrue(script.contains("terminal_sessions.createIndex"))
        XCTAssertTrue(script.contains("provider_session_id: 1"))
        XCTAssertTrue(script.contains("activity_at: { $exists: false }"))
        XCTAssertTrue(script.contains("activity_at: -1"))
        XCTAssertTrue(script.contains("status: 1, activity_at: -1"))
        XCTAssertTrue(script.contains("dropIndex({ status: 1, ended_at: -1, last_activity_at: -1, started_at: -1 })"))
        XCTAssertTrue(script.contains("mongo_transcript_sync_state: 1"))
        XCTAssertTrue(script.contains("mongo_transcript_synchronized_at: -1"))
        XCTAssertTrue(script.contains("mongo_input_sync_state: 1"))
        XCTAssertTrue(script.contains("mongo_input_synchronized_at: -1"))
        XCTAssertTrue(script.contains("terminal_chunks.createIndex"))
        XCTAssertTrue(script.contains("terminal_session_events.createIndex"))
    }

    func testMongoNullableDateExpressionBuildsBsonDateConversion() {
        XCTAssertEqual(
            MongoMonitoringWriter.mongoNullableDateExpression("payload.session.ended_at"),
            "payload.session.ended_at != null ? new Date(payload.session.ended_at) : null"
        )
    }

    func testMongoUpsertOptionsScriptEnablesUpsertWrites() {
        XCTAssertEqual(MongoMonitoringWriter.mongoUpsertOptionsScript, "{ upsert: true }")
    }

    func testMongoRecordSessionStartScriptAvoidsConflictingUpsertFields() {
        let script = MongoMonitoringWriter.recordSessionStartScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#,
            payloadLiteral: #"{"session_id":"session-123"}"#
        )
        let setOnInsertBlock = script.range(
            of: #"\$setOnInsert:\s*\{[\s\S]*?\}"#,
            options: .regularExpression
        ).map { String(script[$0]) }

        XCTAssertNotNil(setOnInsertBlock)
        XCTAssertTrue(setOnInsertBlock?.contains("session_id: payload.session_id") == true)
        XCTAssertFalse(setOnInsertBlock?.contains("profile_id: payload.profile_id") == true)
        XCTAssertFalse(setOnInsertBlock?.contains("started_at: new Date(payload.started_at)") == true)
    }

    func testMongoRecordSessionStartScriptPersistsGeminiStartupStatsFields() {
        let script = MongoMonitoringWriter.recordSessionStartScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#,
            payloadLiteral: #"{"session_id":"session-123"}"#
        )

        XCTAssertTrue(script.contains("provider_cli_version: payload.provider_cli_version"))
        XCTAssertTrue(script.contains("provider_wrapper_resolved_path: payload.provider_wrapper_resolved_path"))
        XCTAssertTrue(script.contains("provider_wrapper_kind: payload.provider_wrapper_kind"))
        XCTAssertTrue(script.contains("provider_launch_mode: payload.provider_launch_mode"))
        XCTAssertTrue(script.contains("provider_shell_fallback_executable: payload.provider_shell_fallback_executable"))
        XCTAssertTrue(script.contains("provider_auto_continue_mode: payload.provider_auto_continue_mode"))
        XCTAssertTrue(script.contains("provider_pty_backend: payload.provider_pty_backend"))
        XCTAssertTrue(script.contains("provider_startup_clear_command: payload.provider_startup_clear_command"))
        XCTAssertTrue(script.contains("provider_startup_clear_command_source: payload.provider_startup_clear_command_source"))
        XCTAssertTrue(script.contains("provider_startup_clear_completed: payload.provider_startup_clear_completed"))
        XCTAssertTrue(script.contains("provider_startup_clear_reason: payload.provider_startup_clear_reason"))
        XCTAssertTrue(script.contains("provider_startup_stats_command: payload.provider_startup_stats_command"))
        XCTAssertTrue(script.contains("provider_startup_stats_command_source: payload.provider_startup_stats_command_source"))
        XCTAssertTrue(script.contains("provider_startup_model_command: payload.provider_startup_model_command"))
        XCTAssertTrue(script.contains("provider_startup_model_command_source: payload.provider_startup_model_command_source"))
        XCTAssertTrue(script.contains("provider_current_model: payload.provider_current_model"))
        XCTAssertTrue(script.contains("provider_model_capacity: payload.provider_model_capacity"))
        XCTAssertTrue(script.contains("provider_model_capacity_raw_lines: payload.provider_model_capacity_raw_lines"))
        XCTAssertTrue(script.contains("provider_fresh_session_prepared: payload.provider_fresh_session_prepared"))
        XCTAssertTrue(script.contains("provider_fresh_session_reset_reason: payload.provider_fresh_session_reset_reason"))
        XCTAssertTrue(script.contains("provider_fresh_session_removed_path_count: payload.provider_fresh_session_removed_path_count"))
        XCTAssertTrue(script.contains("provider_model_usage_note: payload.provider_model_usage_note"))
        XCTAssertTrue(script.contains("provider_model_usage: payload.provider_model_usage"))
        XCTAssertTrue(script.contains("input_capture_path: payload.input_capture_path"))
        XCTAssertTrue(script.contains("input_chunk_count: payload.input_chunk_count"))
        XCTAssertTrue(script.contains("input_byte_count: payload.input_byte_count"))
        XCTAssertTrue(script.contains("mongo_input_sync_state: payload.mongo_input_sync_state"))
        XCTAssertTrue(script.contains("mongo_input_sync_source: payload.mongo_input_sync_source"))
        XCTAssertTrue(script.contains("mongo_input_chunk_count: payload.mongo_input_chunk_count"))
        XCTAssertTrue(script.contains("mongo_input_byte_count: payload.mongo_input_byte_count"))
        XCTAssertTrue(script.contains("mongo_input_synchronized_at: payload.mongo_input_synchronized_at != null ? new Date(payload.mongo_input_synchronized_at) : null"))
        XCTAssertTrue(script.contains("observed_slash_commands: payload.observed_slash_commands"))
        XCTAssertTrue(script.contains("observed_prompt_submissions: payload.observed_prompt_submissions"))
        XCTAssertTrue(script.contains("observed_interactions: payload.observed_interactions"))
        XCTAssertTrue(script.contains("activity_at: new Date(payload.activity_at)"))
    }

    func testMongoObservedInteractionSummaryScriptUpdatesSessionWithoutInsertingEvent() {
        let script = MongoMonitoringWriter.recordObservedInteractionSummaryScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#,
            payloadLiteral: #"{"session_id":"session-123"}"#
        )

        XCTAssertTrue(script.contains("observed_slash_commands: payload.observed_slash_commands"))
        XCTAssertTrue(script.contains("observed_prompt_submissions: payload.observed_prompt_submissions"))
        XCTAssertTrue(script.contains("observed_interactions: payload.observed_interactions"))
        XCTAssertTrue(script.contains("session_payload: payload.session_payload"))
        XCTAssertFalse(script.contains("terminal_session_events.insertOne"))
    }

    func testMongoSessionSnapshotScriptUpdatesSessionWithoutInsertingEvent() {
        let script = MongoMonitoringWriter.recordSessionSnapshotScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#,
            payloadLiteral: #"{"session_id":"session-123"}"#
        )

        XCTAssertTrue(script.contains("activity_at: new Date(payload.activity_at)"))
        XCTAssertTrue(script.contains("mongo_transcript_sync_state: payload.mongo_transcript_sync_state"))
        XCTAssertTrue(script.contains("mongo_transcript_sync_source: payload.mongo_transcript_sync_source"))
        XCTAssertTrue(script.contains("mongo_transcript_chunk_count: payload.mongo_transcript_chunk_count"))
        XCTAssertTrue(script.contains("mongo_transcript_byte_count: payload.mongo_transcript_byte_count"))
        XCTAssertTrue(script.contains("mongo_transcript_synchronized_at: payload.mongo_transcript_synchronized_at != null ? new Date(payload.mongo_transcript_synchronized_at) : null"))
        XCTAssertTrue(script.contains("mongo_input_sync_state: payload.mongo_input_sync_state"))
        XCTAssertTrue(script.contains("mongo_input_sync_source: payload.mongo_input_sync_source"))
        XCTAssertTrue(script.contains("mongo_input_chunk_count: payload.mongo_input_chunk_count"))
        XCTAssertTrue(script.contains("mongo_input_byte_count: payload.mongo_input_byte_count"))
        XCTAssertTrue(script.contains("mongo_input_synchronized_at: payload.mongo_input_synchronized_at != null ? new Date(payload.mongo_input_synchronized_at) : null"))
        XCTAssertFalse(script.contains("terminal_session_events.insertOne"))
    }

    func testMongoFetchStorageSummaryScriptCountsTranscriptCoverageStates() {
        let script = MongoMonitoringWriter.fetchStorageSummaryScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#
        )

        XCTAssertTrue(script.contains(#"countDocuments({ mongo_transcript_sync_state: "complete" })"#))
        XCTAssertTrue(script.contains(#"countDocuments({ mongo_transcript_sync_state: "streaming" })"#))
        XCTAssertTrue(script.contains(#"countDocuments({ mongo_input_sync_state: "complete" })"#))
        XCTAssertTrue(script.contains(#"countDocuments({ mongo_input_sync_state: "streaming" })"#))
        XCTAssertTrue(script.contains(#"projection: { activity_at: 1 }"#))
        XCTAssertTrue(script.contains(#"sort({ activity_at: -1 })"#))
        XCTAssertTrue(script.contains("transcript_complete_session_count: Number(transcriptCompleteSessionCount)"))
        XCTAssertTrue(script.contains("transcript_streaming_session_count: Number(transcriptStreamingSessionCount)"))
        XCTAssertTrue(script.contains("transcript_coverage_unknown_session_count: Number(transcriptCoverageUnknownSessionCount)"))
        XCTAssertTrue(script.contains("input_complete_session_count: Number(inputCompleteSessionCount)"))
        XCTAssertTrue(script.contains("input_streaming_session_count: Number(inputStreamingSessionCount)"))
        XCTAssertTrue(script.contains("input_coverage_unknown_session_count: Number(inputCoverageUnknownSessionCount)"))
        XCTAssertTrue(script.contains("const inputChunkCount = targetDb.terminal_input_chunks.countDocuments({});"))
        XCTAssertTrue(script.contains("input_chunk_count: Number(inputChunkCount)"))
        XCTAssertTrue(script.contains("const logicalInputBytesDoc = targetDb.terminal_input_chunks.aggregate(["))
        XCTAssertTrue(script.contains("logical_input_bytes: Number(inputBytes)"))
        XCTAssertTrue(script.contains("const collectionStorageBytes = (name) => {"))
        XCTAssertTrue(script.contains("const inputChunkTableBytes = collectionStorageBytes(\"terminal_input_chunks\");"))
        XCTAssertTrue(script.contains("input_chunk_table_bytes: Number(inputChunkTableBytes)"))
    }

    func testMongoFetchRecentSessionsScriptUsesMaterializedActivityAt() {
        let script = MongoMonitoringWriter.fetchRecentSessionsScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#,
            payloadLiteral: #"{"limit":25,"cutoff_ms":1700000000000}"#
        )

        XCTAssertTrue(script.contains("activity_at: { $gte: new Date(params.cutoff_ms) }"))
        XCTAssertTrue(script.contains("sort({ activity_at: -1 })"))
        XCTAssertFalse(script.contains("_sort_at"))
        XCTAssertFalse(script.contains("$ifNull"))
    }

    func testMongoPruneCompletedHistoryScriptUsesIndexedActivityAt() {
        let script = MongoMonitoringWriter.pruneCompletedHistoryScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#,
            payloadLiteral: #"{"cutoff_ms":1700000000000}"#
        )

        XCTAssertTrue(script.contains(#"status: { $in: ["completed", "failed", "stopped"] }"#))
        XCTAssertTrue(script.contains("activity_at: { $lt: new Date(params.cutoff_ms) }"))
        XCTAssertTrue(script.contains("const doomedInputChunks = targetDb.terminal_input_chunks.find({ session_id: { $in: doomedIds } }).toArray();"))
        XCTAssertTrue(script.contains("deletedInputChunks: deletedInputChunkCount"))
        XCTAssertTrue(script.contains("deletedInputChunkBytes: deletedInputChunkBytes"))
        XCTAssertFalse(script.contains("$expr"))
        XCTAssertFalse(script.contains("$ifNull"))
    }

    func testMongoClearAllHistoryScriptDeletesTranscriptAndInputRows() {
        let script = MongoMonitoringWriter.clearAllHistoryScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#
        )

        XCTAssertTrue(script.contains("const deletedSessions = targetDb.terminal_sessions.countDocuments({});"))
        XCTAssertTrue(script.contains("const deletedChunks = targetDb.terminal_chunks.countDocuments({});"))
        XCTAssertTrue(script.contains("const deletedInputChunks = targetDb.terminal_input_chunks.countDocuments({});"))
        XCTAssertTrue(script.contains("const deletedEvents = targetDb.terminal_session_events.countDocuments({});"))
        XCTAssertTrue(script.contains("targetDb.terminal_sessions.deleteMany({});"))
        XCTAssertTrue(script.contains("targetDb.terminal_chunks.deleteMany({});"))
        XCTAssertTrue(script.contains("targetDb.terminal_input_chunks.deleteMany({});"))
        XCTAssertTrue(script.contains("targetDb.terminal_session_events.deleteMany({});"))
        XCTAssertTrue(script.contains("deletedInputChunks: Number(deletedInputChunks)"))
    }

    func testDatabaseStorageSummaryRowMakeSummaryBackfillsTranscriptCoverageCounts() {
        let row = DatabaseStorageSummaryRow(
            session_count: 12,
            active_session_count: 2,
            completed_session_count: 7,
            failed_session_count: 3,
            transcript_complete_session_count: 8,
            transcript_streaming_session_count: 3,
            transcript_coverage_unknown_session_count: 1,
            input_complete_session_count: 6,
            input_streaming_session_count: 2,
            input_coverage_unknown_session_count: 4,
            chunk_count: 44,
            input_chunk_count: 21,
            event_count: 80,
            logical_transcript_bytes: 4096,
            logical_input_bytes: 2048,
            session_table_bytes: 0,
            chunk_table_bytes: 0,
            input_chunk_table_bytes: 512,
            event_table_bytes: 0,
            oldest_session_at_epoch: 1_700_000_000,
            newest_session_at_epoch: 1_700_000_500
        )

        let summary = row.makeSummary()

        XCTAssertEqual(summary.sessionCount, 12)
        XCTAssertEqual(summary.transcriptCompleteSessionCount, 8)
        XCTAssertEqual(summary.transcriptStreamingSessionCount, 3)
        XCTAssertEqual(summary.transcriptCoverageUnknownSessionCount, 1)
        XCTAssertEqual(summary.inputCompleteSessionCount, 6)
        XCTAssertEqual(summary.inputStreamingSessionCount, 2)
        XCTAssertEqual(summary.inputCoverageUnknownSessionCount, 4)
        XCTAssertEqual(summary.inputChunkCount, 21)
        XCTAssertEqual(summary.logicalTranscriptBytes, 4096)
        XCTAssertEqual(summary.logicalInputBytes, 2048)
        XCTAssertEqual(summary.inputChunkTableBytes, 512)
    }

    func testMongoStorageSummaryIncludesLocalRawInputInventoryInKnownBytesAndPresence() {
        let summary = MongoStorageSummary(
            logicalTranscriptBytes: 700,
            logicalInputBytes: 500,
            sessionTableBytes: 100,
            chunkTableBytes: 200,
            inputChunkTableBytes: 50,
            eventTableBytes: 300,
            transcriptFileCount: 2,
            transcriptFileBytes: 400,
            inputCaptureFileCount: 3,
            inputCaptureFileBytes: 500
        )

        XCTAssertEqual(summary.totalDatabaseBytes, 650)
        XCTAssertEqual(summary.logicalDatabaseBytes, 1_200)
        XCTAssertEqual(summary.effectiveDatabaseBytes, 1_200)
        XCTAssertEqual(summary.totalKnownBytes, 2_100)
        XCTAssertTrue(summary.hasPhysicalDatabaseBreakdown)
        XCTAssertTrue(summary.hasAnyData)
    }

    func testMongoPruneSummaryTreatsDeletedRawInputCapturesAsDeletion() {
        let summary = MongoPruneSummary(
            cutoffDate: Date(timeIntervalSince1970: 1_700_000_000),
            deletedSessions: 0,
            deletedChunks: 0,
            deletedEvents: 0,
            deletedChunkBytes: 0,
            deletedTranscriptFiles: 0,
            deletedTranscriptBytes: 0,
            deletedInputCaptureFiles: 2,
            deletedInputCaptureBytes: 128
        )

        XCTAssertTrue(summary.didDeleteAnything)
    }

    func testMongoPruneSummaryTreatsDeletedMongoRawInputChunksAsDeletion() {
        let summary = MongoPruneSummary(
            cutoffDate: Date(timeIntervalSince1970: 1_700_000_000),
            deletedSessions: 0,
            deletedChunks: 0,
            deletedInputChunks: 4,
            deletedEvents: 0,
            deletedChunkBytes: 0,
            deletedInputChunkBytes: 256,
            deletedTranscriptFiles: 0,
            deletedTranscriptBytes: 0,
            deletedInputCaptureFiles: 0,
            deletedInputCaptureBytes: 0
        )

        XCTAssertTrue(summary.didDeleteAnything)
    }

    func testMongoClearSummaryTreatsDeletedMongoRawInputChunksAsDeletion() {
        let summary = MongoClearSummary(
            deletedSessions: 0,
            deletedChunks: 0,
            deletedInputChunks: 3,
            deletedEvents: 0
        )

        XCTAssertTrue(summary.didDeleteAnything)
    }

    func testMongoChunkSourceBackfillScriptUpdatesLegacyChunkRowsWithoutEvents() {
        let script = MongoMonitoringWriter.recordChunkSourceBackfillScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#,
            payloadLiteral: #"{"session_id":"session-123","legacy_source":"terminal_transcript","normalized_source":"terminal_transcript_output_only"}"#
        )

        XCTAssertTrue(script.contains("terminal_chunks.updateMany"))
        XCTAssertTrue(script.contains("source: payload.legacy_source"))
        XCTAssertTrue(script.contains("source: payload.normalized_source"))
        XCTAssertFalse(script.contains("terminal_session_events.insertOne"))
    }

    func testMongoRecordChunkScriptPersistsChunkContextFields() {
        let script = MongoMonitoringWriter.recordChunkScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#,
            payloadLiteral: #"{"session_id":"session-123","chunk_index":1}"#
        )

        XCTAssertTrue(script.contains("terminal_chunks.updateOne"))
        XCTAssertTrue(script.contains("prompt: payload.prompt"))
        XCTAssertTrue(script.contains("status: payload.status"))
        XCTAssertTrue(script.contains("status_reason: payload.status_reason"))
        XCTAssertTrue(script.contains("message: payload.message"))
        XCTAssertTrue(script.contains("last_database_message: payload.message"))
        XCTAssertFalse(script.contains("terminal_session_events.insertOne"))
    }

    func testMongoRecordInputChunkScriptPersistsInputContextFields() {
        let script = MongoMonitoringWriter.recordInputChunkScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#,
            payloadLiteral: #"{"session_id":"session-123","input_index":1}"#
        )

        XCTAssertTrue(script.contains("terminal_input_chunks.updateOne"))
        XCTAssertTrue(script.contains("input_index: payload.input_index"))
        XCTAssertTrue(script.contains("prompt: payload.prompt"))
        XCTAssertTrue(script.contains("status: payload.status"))
        XCTAssertTrue(script.contains("status_reason: payload.status_reason"))
        XCTAssertTrue(script.contains("last_database_message: payload.message"))
        XCTAssertFalse(script.contains("terminal_session_events.insertOne"))
    }

    func testMongoFetchSessionChunkSummaryScriptIncludesChunkIndexCoverage() {
        let script = MongoMonitoringWriter.fetchSessionChunkSummaryScript(
            configLiteral: #"{"cfg":"clilauncher_state"}"#,
            payloadLiteral: #"{"session_id":"session-123"}"#
        )

        XCTAssertTrue(script.contains("terminal_chunks.aggregate"))
        XCTAssertTrue(script.contains("minChunkIndex"))
        XCTAssertTrue(script.contains("maxChunkIndex"))
        XCTAssertTrue(script.contains("min_chunk_index"))
        XCTAssertTrue(script.contains("max_chunk_index"))
        XCTAssertFalse(script.contains("countDocuments"))
    }

    func testDatabaseSessionRowMakeSessionBackfillsGeminiStartupStatsFieldsWithoutPayload() {
        let row = DatabaseSessionRow(
            session_id: UUID().uuidString,
            profile_id: nil,
            profile_name: "Gemini",
            agent_kind: AgentKind.gemini.rawValue,
            account_identifier: "user@example.com",
            provider_session_id: "session-123",
            provider_auth_method: "Signed in with Google (user@example.com)",
            provider_tier: "Gemini Code Assist for individuals",
            provider_cli_version: "0.32.1",
            provider_runner_path: "/Applications/CLILauncher.app/Contents/Resources/gemini-automation-runner.mjs",
            provider_runner_build: "20260424T154225Z",
            provider_wrapper_resolved_path: "/Users/michalmatynia/.local/gemini-preview/bin/gemini",
            provider_wrapper_kind: "binary",
            provider_launch_mode: "direct",
            provider_shell_fallback_executable: "/bin/zsh",
            provider_auto_continue_mode: "prompt_only",
            provider_pty_backend: "@lydell/node-pty",
            provider_startup_clear_command: "/clear",
            provider_startup_clear_command_source: "echoed_command",
            provider_startup_clear_completed: true,
            provider_startup_clear_reason: "visible prompt field",
            provider_startup_stats_command: "/stats",
            provider_startup_stats_command_source: "runner_banner",
            provider_startup_model_command: "/model",
            provider_startup_model_command_source: "runner_banner",
            provider_current_model: "gemini-3-flash-preview",
            provider_model_capacity: [
                GeminiModelCapacityRow(
                    model: "Pro",
                    usedPercentage: 82,
                    resetTime: "1:29 PM",
                    rawText: "Pro 82% Resets: 1:29 PM"
                ),
            ],
            provider_model_capacity_raw_lines: ["Select Model", "Model usage", "Pro 82% Resets: 1:29 PM"],
            mongo_transcript_sync_state: MongoTranscriptSyncState.complete.rawValue,
            mongo_transcript_sync_source: "local_transcript_file",
            mongo_transcript_chunk_count: 4,
            mongo_transcript_byte_count: 2048,
            mongo_transcript_synchronized_at_epoch: 1_700_000_125,
            input_capture_path: "/tmp/work/session.typescript.stdinrec",
            input_chunk_count: 5,
            input_byte_count: 160,
            mongo_input_sync_state: MongoInputSyncState.complete.rawValue,
            mongo_input_sync_source: "local_input_capture_file",
            mongo_input_chunk_count: 5,
            mongo_input_byte_count: 160,
            mongo_input_synchronized_at_epoch: 1_700_000_126,
            provider_fresh_session_prepared: true,
            provider_fresh_session_reset_reason: "cleared prior workspace session binding (2 path aliases)",
            provider_fresh_session_removed_path_count: 2,
            provider_model_usage_note: "Use /model to view model quota information",
            provider_model_usage: [
                GeminiSessionStatsModelUsageRow(
                    model: "gemini-2.5-pro",
                    label: nil,
                    requests: 3,
                    inputTokens: 120,
                    cacheReads: 7,
                    outputTokens: 42
                )
            ],
            observed_slash_commands: ["/stats", "/model set gemini-2.5-pro"],
            observed_prompt_submissions: ["continue", "ship the feature"],
            observed_interactions: [
                DatabaseObservedTranscriptInteractionRow(
                    text: "/stats",
                    kind: ObservedTranscriptInteraction.Kind.slashCommand.rawValue,
                    source: "echoed_transcript",
                    first_observed_at_epoch: 1_700_000_010,
                    last_observed_at_epoch: 1_700_000_015,
                    observation_count: 2
                )
            ],
            prompt: "Investigate startup flow",
            working_directory: "/tmp/work",
            transcript_path: "/tmp/work/session.typescript",
            launch_command: "gemini",
            capture_mode: TerminalTranscriptCaptureMode.outputOnly.rawValue,
            status: TerminalMonitorStatus.monitoring.rawValue,
            started_at_epoch: 1_700_000_000,
            activity_at_epoch: 1_700_000_125,
            last_activity_at_epoch: 1_700_000_120,
            ended_at_epoch: nil,
            chunk_count: 4,
            byte_count: 2048,
            last_error: nil,
            last_preview: "Session Stats",
            last_database_message: "Captured Gemini session stats.",
            status_reason: nil,
            exit_code: nil,
            session_payload: nil
        )

        let session = row.makeSession()

        XCTAssertEqual(session.providerCLIVersion, "0.32.1")
        XCTAssertEqual(session.providerRunnerPath, "/Applications/CLILauncher.app/Contents/Resources/gemini-automation-runner.mjs")
        XCTAssertEqual(session.providerRunnerBuild, "20260424T154225Z")
        XCTAssertEqual(session.providerWrapperResolvedPath, "/Users/michalmatynia/.local/gemini-preview/bin/gemini")
        XCTAssertEqual(session.providerWrapperKind, "binary")
        XCTAssertEqual(session.providerLaunchMode, "direct")
        XCTAssertEqual(session.providerShellFallbackExecutable, "/bin/zsh")
        XCTAssertEqual(session.providerAutoContinueMode, "prompt_only")
        XCTAssertEqual(session.providerPTYBackend, "@lydell/node-pty")
        XCTAssertEqual(session.providerStartupClearCommand, "/clear")
        XCTAssertEqual(session.providerStartupClearCommandSource, "echoed_command")
        XCTAssertEqual(session.providerStartupClearCompleted, true)
        XCTAssertEqual(session.providerStartupClearReason, "visible prompt field")
        XCTAssertEqual(session.providerStartupStatsCommand, "/stats")
        XCTAssertEqual(session.providerStartupStatsCommandSource, "runner_banner")
        XCTAssertEqual(session.providerStartupModelCommand, "/model")
        XCTAssertEqual(session.providerStartupModelCommandSource, "runner_banner")
        XCTAssertEqual(session.providerCurrentModel, "gemini-3-flash-preview")
        XCTAssertEqual(session.providerModelCapacity?.count, 1)
        XCTAssertEqual(session.providerModelCapacity?.first?.model, "Pro")
        XCTAssertEqual(session.providerModelCapacity?.first?.usedPercentage, 82)
        XCTAssertEqual(session.providerModelCapacityRawLines?.first, "Select Model")
        XCTAssertEqual(session.mongoTranscriptSyncState, .complete)
        XCTAssertEqual(session.mongoTranscriptSyncSource, "local_transcript_file")
        XCTAssertEqual(session.mongoTranscriptChunkCount, 4)
        XCTAssertEqual(session.mongoTranscriptByteCount, 2048)
        XCTAssertEqual(session.mongoTranscriptSynchronizedAt, Date(timeIntervalSince1970: 1_700_000_125))
        XCTAssertEqual(session.inputCapturePath, "/tmp/work/session.typescript.stdinrec")
        XCTAssertEqual(session.inputChunkCount, 5)
        XCTAssertEqual(session.inputByteCount, 160)
        XCTAssertEqual(session.mongoInputSyncState, .complete)
        XCTAssertEqual(session.mongoInputSyncSource, "local_input_capture_file")
        XCTAssertEqual(session.mongoInputChunkCount, 5)
        XCTAssertEqual(session.mongoInputByteCount, 160)
        XCTAssertEqual(session.mongoInputSynchronizedAt, Date(timeIntervalSince1970: 1_700_000_126))
        XCTAssertEqual(session.providerFreshSessionPrepared, true)
        XCTAssertEqual(session.providerFreshSessionResetReason, "cleared prior workspace session binding (2 path aliases)")
        XCTAssertEqual(session.providerFreshSessionRemovedPathCount, 2)
        XCTAssertEqual(session.providerModelUsageNote, "Use /model to view model quota information")
        XCTAssertEqual(session.providerModelUsage?.count, 1)
        XCTAssertEqual(session.providerModelUsage?.first?.model, "gemini-2.5-pro")
        XCTAssertEqual(session.providerModelUsage?.first?.requests, 3)
        XCTAssertEqual(session.observedSlashCommands, ["/stats", "/model set gemini-2.5-pro"])
        XCTAssertEqual(session.observedPromptSubmissions, ["continue", "ship the feature"])
        XCTAssertEqual(session.observedInteractions?.count, 1)
        XCTAssertEqual(session.observedInteractions?.first?.text, "/stats")
        XCTAssertEqual(session.observedInteractions?.first?.observationCount, 2)
    }

    func testDatabaseSessionRowMakeSessionFallsBackToActivityAtWhenLastActivityMissing() {
        let row = DatabaseSessionRow(
            session_id: UUID().uuidString,
            profile_id: nil,
            profile_name: "Gemini",
            agent_kind: AgentKind.gemini.rawValue,
            account_identifier: nil,
            provider_session_id: nil,
            provider_auth_method: nil,
            provider_tier: nil,
            provider_cli_version: nil,
            provider_runner_path: nil,
            provider_runner_build: nil,
            provider_wrapper_resolved_path: nil,
            provider_wrapper_kind: nil,
            provider_launch_mode: nil,
            provider_shell_fallback_executable: nil,
            provider_auto_continue_mode: nil,
            provider_pty_backend: nil,
            provider_startup_clear_command: nil,
            provider_startup_clear_command_source: nil,
            provider_startup_clear_completed: nil,
            provider_startup_clear_reason: nil,
            provider_startup_stats_command: nil,
            provider_startup_stats_command_source: nil,
            provider_startup_model_command: nil,
            provider_startup_model_command_source: nil,
            provider_current_model: nil,
            provider_model_capacity: nil,
            provider_model_capacity_raw_lines: nil,
            mongo_transcript_sync_state: nil,
            mongo_transcript_sync_source: nil,
            mongo_transcript_chunk_count: nil,
            mongo_transcript_byte_count: nil,
            mongo_transcript_synchronized_at_epoch: nil,
            input_capture_path: nil,
            input_chunk_count: nil,
            input_byte_count: nil,
            mongo_input_sync_state: nil,
            mongo_input_sync_source: nil,
            mongo_input_chunk_count: nil,
            mongo_input_byte_count: nil,
            mongo_input_synchronized_at_epoch: nil,
            provider_fresh_session_prepared: nil,
            provider_fresh_session_reset_reason: nil,
            provider_fresh_session_removed_path_count: nil,
            provider_model_usage_note: nil,
            provider_model_usage: nil,
            observed_slash_commands: nil,
            observed_prompt_submissions: nil,
            observed_interactions: nil,
            prompt: nil,
            working_directory: "/tmp",
            transcript_path: "/tmp/session.typescript",
            launch_command: "gemini",
            capture_mode: TerminalTranscriptCaptureMode.outputOnly.rawValue,
            status: TerminalMonitorStatus.monitoring.rawValue,
            started_at_epoch: 1_700_000_000,
            activity_at_epoch: 1_700_000_125,
            last_activity_at_epoch: nil,
            ended_at_epoch: nil,
            chunk_count: 0,
            byte_count: 0,
            last_error: nil,
            last_preview: nil,
            last_database_message: nil,
            status_reason: nil,
            exit_code: nil,
            session_payload: nil
        )

        let session = row.makeSession()

        XCTAssertEqual(session.lastActivityAt, Date(timeIntervalSince1970: 1_700_000_125))
        XCTAssertEqual(session.activityDate, Date(timeIntervalSince1970: 1_700_000_125))
    }

    func testOrderedSessionsPreservesRequestedSessionIDOrder() {
        let firstID = UUID()
        let secondID = UUID()
        let first = TerminalMonitorSession(
            id: firstID,
            profileID: nil,
            profileName: "First",
            agentKind: .gemini,
            workingDirectory: "/tmp/first",
            transcriptPath: "/tmp/first.typescript",
            launchCommand: "gemini first",
            captureMode: .outputOnly
        )
        let second = TerminalMonitorSession(
            id: secondID,
            profileID: nil,
            profileName: "Second",
            agentKind: .gemini,
            workingDirectory: "/tmp/second",
            transcriptPath: "/tmp/second.typescript",
            launchCommand: "gemini second",
            captureMode: .outputOnly
        )

        let ordered = MongoMonitoringWriter.orderedSessions([second, first], by: [firstID, secondID])

        XCTAssertEqual(ordered.map(\.id), [firstID, secondID])
    }
}

final class MongoStateStoreScriptTests: XCTestCase {
    func testLoadStateScriptAvoidsListCollectionsCheck() {
        let script = MongoStateStore.loadStateScript(databaseName: "clilauncher_state", collectionName: "launcher_state")

        XCTAssertFalse(script.contains("listCollections()"))
        XCTAssertTrue(script.contains("findOne({ _id: \"singleton\" })"))
    }

    func testEnsureSchemaScriptUsesIndexCreationWithoutCollectionProbe() {
        let script = MongoStateStore.ensureSchemaScript(databaseName: "clilauncher_state", collectionName: "launcher_state")

        XCTAssertFalse(script.contains("listCollections()"))
        XCTAssertTrue(script.contains("createIndex({ updated_at: -1 })"))
    }
}

final class PrettyCoderCacheTests: XCTestCase {
    func testPrettyEncoderIsSharedInstance() {
        XCTAssertTrue(JSONEncoder.pretty === JSONEncoder.pretty,
                      "JSONEncoder.pretty should be a static let so callers reuse a single instance.")
    }

    func testPrettyDecoderIsSharedInstance() {
        XCTAssertTrue(JSONDecoder.pretty === JSONDecoder.pretty,
                      "JSONDecoder.pretty should be a static let so callers reuse a single instance.")
    }

    func testPrettyEncoderRoundTripsWithSortedKeys() throws {
        struct Sample: Codable, Equatable {
            let b: Int
            let a: String
        }
        let sample = Sample(b: 2, a: "one")
        let data = try JSONEncoder.pretty.encode(sample)
        let text = String(data: data, encoding: .utf8) ?? ""
        let aIndex = text.range(of: "\"a\"")?.lowerBound
        let bIndex = text.range(of: "\"b\"")?.lowerBound
        XCTAssertNotNil(aIndex)
        XCTAssertNotNil(bIndex)
        if let aIndex, let bIndex {
            XCTAssertLessThan(aIndex, bIndex, "Pretty encoder should emit keys in sorted order.")
        }

        let decoded = try JSONDecoder.pretty.decode(Sample.self, from: data)
        XCTAssertEqual(decoded, sample)
    }
}

final class TerminalSessionEventParsingTests: XCTestCase {
    func testTerminalMonitorSessionDetailsIOTimelineInterleavesTranscriptAndInputChronologically() {
        let sessionID = UUID()
        let baseTime = Date(timeIntervalSince1970: 1_713_960_000)
        let details = TerminalMonitorSessionDetails(
            sessionID: sessionID,
            sessionStatus: .monitoring,
            sessionChunkCount: 2,
            sessionByteCount: 64,
            sessionInputChunkCount: 1,
            sessionInputByteCount: 12,
            chunks: [
                TerminalTranscriptChunk(
                    id: 1,
                    sessionID: sessionID,
                    chunkIndex: 1,
                    source: "terminal_transcript_input_output",
                    capturedAt: baseTime.addingTimeInterval(2),
                    byteCount: 32,
                    previewText: "assistant output",
                    text: "assistant output"
                ),
                TerminalTranscriptChunk(
                    id: 2,
                    sessionID: sessionID,
                    chunkIndex: 2,
                    source: "terminal_transcript_input_output",
                    capturedAt: baseTime.addingTimeInterval(4),
                    byteCount: 32,
                    previewText: "follow-up output",
                    text: "follow-up output"
                )
            ],
            inputChunks: [
                TerminalInputChunk(
                    id: 1,
                    sessionID: sessionID,
                    inputIndex: 1,
                    source: "terminal_stdin_raw_capture",
                    capturedAt: baseTime.addingTimeInterval(1),
                    byteCount: 12,
                    previewText: "/stats",
                    text: "/stats"
                )
            ]
        )

        let timeline = details.ioTimelineEntries

        XCTAssertEqual(timeline.map(\.kind), [.stdin, .transcript, .transcript])
        XCTAssertEqual(timeline.map(\.text), ["/stats", "assistant output", "follow-up output"])
        XCTAssertEqual(timeline.map(\.sequenceNumber), [1, 1, 2])
    }

    func testTerminalMonitorSessionDetailsIOTimelinePrefersStdinWhenTimestampsTie() {
        let sessionID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_713_960_000)
        let details = TerminalMonitorSessionDetails(
            sessionID: sessionID,
            sessionStatus: .monitoring,
            sessionChunkCount: 1,
            sessionByteCount: 32,
            sessionInputChunkCount: 2,
            sessionInputByteCount: 24,
            chunks: [
                TerminalTranscriptChunk(
                    id: 1,
                    sessionID: sessionID,
                    chunkIndex: 1,
                    source: "terminal_transcript_input_output",
                    capturedAt: capturedAt,
                    byteCount: 32,
                    previewText: "assistant output",
                    text: "assistant output"
                )
            ],
            inputChunks: [
                TerminalInputChunk(
                    id: 1,
                    sessionID: sessionID,
                    inputIndex: 2,
                    source: "terminal_stdin_raw_capture",
                    capturedAt: capturedAt,
                    byteCount: 12,
                    previewText: "continue",
                    text: "continue"
                ),
                TerminalInputChunk(
                    id: 2,
                    sessionID: sessionID,
                    inputIndex: 1,
                    source: "terminal_stdin_raw_capture",
                    capturedAt: capturedAt,
                    byteCount: 12,
                    previewText: "/clear",
                    text: "/clear"
                )
            ]
        )

        let timeline = details.ioTimelineEntries

        XCTAssertEqual(timeline.map(\.kind), [.stdin, .stdin, .transcript])
        XCTAssertEqual(timeline.map(\.text), ["/clear", "continue", "assistant output"])
        XCTAssertEqual(timeline.first?.kind.displayName, "Stdin")
        XCTAssertEqual(timeline.last?.kind.displayName, "Transcript")
    }

    func testTerminalTranscriptChunkSourceDisplayNameHumanizesTranscriptCaptureModes() {
        let inputOutputChunk = TerminalTranscriptChunk(
            id: 1,
            sessionID: UUID(),
            chunkIndex: 1,
            source: "terminal_transcript_input_output",
            capturedAt: Date(),
            byteCount: 64,
            previewText: "> continue",
            text: "> continue"
        )
        let outputOnlyChunk = TerminalTranscriptChunk(
            id: 2,
            sessionID: UUID(),
            chunkIndex: 2,
            source: "terminal_transcript_output_only",
            capturedAt: Date(),
            byteCount: 64,
            previewText: "response",
            text: "response"
        )

        XCTAssertEqual(inputOutputChunk.sourceDisplayName, "Transcript capture (input + output)")
        XCTAssertEqual(outputOnlyChunk.sourceDisplayName, "Transcript capture (output only)")
    }

    func testObservedTranscriptInteractionSourceDisplayNameHumanizesLocalTranscriptSources() {
        let summaryFromFullTranscript = ObservedTranscriptInteractionSummary(
            text: "/stats",
            kind: .slashCommand,
            source: "local_transcript_file",
            firstObservedAt: Date(),
            lastObservedAt: Date(),
            observationCount: 1
        )
        let interactionFromPreview = ObservedTranscriptInteraction(
            text: "continue",
            kind: .prompt,
            source: "local_transcript_preview"
        )

        XCTAssertEqual(summaryFromFullTranscript.sourceDisplayName, "Full local transcript")
        XCTAssertEqual(interactionFromPreview.sourceDisplayName, "Local transcript preview")
    }

    func testMonitoringDashboardNormalizedSessionSearchBlobIncludesHumanizedSyncAndStartupSources() {
        var session = TerminalMonitorSession(
            profileID: nil,
            profileName: "Gemini Stable",
            agentKind: .gemini,
            workingDirectory: "/tmp/work",
            transcriptPath: "/tmp/work/session.typescript",
            launchCommand: "gemini",
            captureMode: .inputAndOutput
        )
        session.providerStartupClearCommandSource = "runner_banner"
        session.providerStartupStatsCommandSource = "echoed_command"
        session.providerStartupModelCommandSource = "runner_banner"
        session.providerCurrentModel = "gemini-3-flash-preview"
        session.mongoTranscriptSyncState = .complete
        session.mongoTranscriptSyncSource = "local_transcript_file"
        session.mongoInputSyncState = .streaming
        session.mongoInputSyncSource = "live_input_capture"
        session.providerRunnerPath = "/tmp/custom-runner.mjs"
        session.providerRunnerBuild = "20260424T154225Z"
        session.providerModelUsage = [
            GeminiSessionStatsModelUsageRow(
                model: "gemini-2.5-pro",
                label: "pro tier",
                requests: nil,
                inputTokens: nil,
                cacheReads: nil,
                outputTokens: nil
            )
        ]
        session.providerModelCapacity = [
            GeminiModelCapacityRow(
                model: "Flash",
                usedPercentage: 7,
                resetTime: "1:29 PM",
                rawText: "Flash 7% Resets: 1:29 PM"
            )
        ]
        session.observedSlashCommands = ["/stats"]
        session.observedPromptSubmissions = ["continue"]

        let blob = MonitoringDashboardView.normalizedSessionSearchBlob(for: session)

        XCTAssertTrue(blob.contains("runner banner"))
        XCTAssertTrue(blob.contains("echoed transcript command"))
        XCTAssertTrue(blob.contains("verified in mongodb"))
        XCTAssertTrue(blob.contains("local transcript file"))
        XCTAssertTrue(blob.contains("streaming raw input to mongodb"))
        XCTAssertTrue(blob.contains("live raw input capture"))
        XCTAssertTrue(blob.contains("/tmp/custom-runner.mjs"))
        XCTAssertTrue(blob.contains("differs from bundled app runner path"))
        XCTAssertTrue(blob.contains("matches bundled app runner"))
        XCTAssertTrue(blob.contains("gemini-2.5-pro"))
        XCTAssertTrue(blob.contains("gemini-3-flash-preview"))
        XCTAssertTrue(blob.contains("flash 7% resets: 1:29 pm"))
        XCTAssertTrue(blob.contains("/stats"))
        XCTAssertTrue(blob.contains("continue"))
    }

    func testMonitoringDashboardGeminiRunnerBuildStatusTextReportsMatchAndMismatch() {
        XCTAssertEqual(
            MonitoringDashboardView.geminiRunnerBuildStatusText(
                sessionRunnerBuild: "20260424T154225Z",
                bundledRunnerBuild: "20260424T154225Z"
            ),
            "Matches bundled app runner"
        )
        XCTAssertEqual(
            MonitoringDashboardView.geminiRunnerBuildStatusText(
                sessionRunnerBuild: "20260423T000000Z",
                bundledRunnerBuild: "20260424T154225Z"
            ),
            "Differs from bundled app runner (20260424T154225Z)"
        )
    }

    func testMonitoringDashboardGeminiRunnerPathStatusTextReportsMatchAndMismatch() {
        XCTAssertEqual(
            MonitoringDashboardView.geminiRunnerPathStatusText(
                sessionRunnerPath: "/tmp/current-runner.mjs",
                bundledRunnerPath: "/tmp/current-runner.mjs"
            ),
            "Matches bundled app runner path"
        )
        XCTAssertEqual(
            MonitoringDashboardView.geminiRunnerPathStatusText(
                sessionRunnerPath: "/tmp/old-runner.mjs",
                bundledRunnerPath: "/tmp/current-runner.mjs"
            ),
            "Differs from bundled app runner path"
        )
    }

    func testTerminalMonitorSessionDetailsSatisfiesRequestedWorkloadOnlyWhenHistoryIsLoaded() {
        let baseDetails = TerminalMonitorSessionDetails(
            sessionID: UUID(),
            workload: .summary,
            sessionStatus: .monitoring,
            sessionChunkCount: 0,
            sessionByteCount: 0
        )

        XCTAssertTrue(baseDetails.satisfies(.summary))
        XCTAssertFalse(baseDetails.satisfies(.history))

        var historyDetails = baseDetails
        historyDetails.workload = .history

        XCTAssertTrue(historyDetails.satisfies(.summary))
        XCTAssertTrue(historyDetails.satisfies(.history))
    }

    func testObservedTranscriptInteractionParsesSlashCommandMetadata() {
        let event = TerminalSessionEvent(
            id: 1,
            sessionID: UUID(),
            eventType: "slash_command_observed",
            status: .monitoring,
            eventAt: Date(),
            message: "Observed Gemini slash command /stats in transcript.",
            metadataJSON: #"{"text":"/stats","kind":"slash_command","source":"echoed_transcript"}"#
        )

        let interaction = event.observedTranscriptInteraction

        XCTAssertEqual(interaction?.text, "/stats")
        XCTAssertEqual(interaction?.kind, .slashCommand)
        XCTAssertEqual(interaction?.source, "echoed_transcript")
        XCTAssertEqual(interaction?.sourceDisplayName, "Echoed transcript")
    }

    func testObservedTranscriptInteractionParsesPromptMetadata() {
        let event = TerminalSessionEvent(
            id: 2,
            sessionID: UUID(),
            eventType: "prompt_observed",
            status: .monitoring,
            eventAt: Date(),
            message: "Observed Gemini prompt submission: continue",
            metadataJSON: #"{"text":"continue","kind":"prompt","source":"echoed_transcript"}"#
        )

        let interaction = event.observedTranscriptInteraction

        XCTAssertEqual(interaction?.text, "continue")
        XCTAssertEqual(interaction?.kind, .prompt)
    }

    func testObservedTranscriptInteractionReturnsNilForNonInteractionEvent() {
        let event = TerminalSessionEvent(
            id: 3,
            sessionID: UUID(),
            eventType: "session_idle",
            status: .idle,
            eventAt: Date(),
            message: nil,
            metadataJSON: #"{"text":"/stats","source":"echoed_transcript"}"#
        )

        XCTAssertNil(event.observedTranscriptInteraction)
    }
}

final class AppSettingsDefaultsTests: XCTestCase {
    func testDefaultTerminalAppFallsBackWhenMissingFromState() throws {
        let data = Data("""
        {
          "defaultWorkingDirectory": "/tmp"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.defaultTerminalApp, .iterm2)
    }

    func testDefaultGeminiRunnerPathHealsStaleBundledPath() throws {
        let currentRunnerPath = BundledGeminiAutomationRunner.defaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentRunnerPath.isEmpty else {
            throw XCTSkip("Bundled Gemini automation runner is unavailable in this test environment.")
        }

        let data = Data("""
        {
          "defaultGeminiRunnerPath": "/Users/test/Library/Developer/Xcode/DerivedData/clilauncher/Build/Products/Debug/CLILauncherNative_GeminiLauncherNative.bundle/Contents/Resources/Resources/gemini-automation-runner.mjs"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.defaultGeminiRunnerPath, currentRunnerPath)
    }

    func testDefaultGeminiRunnerPathHealsCopiedLauncherRunnerWithBuildIdentifier() throws {
        let currentRunnerPath = BundledGeminiAutomationRunner.defaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentRunnerPath.isEmpty else {
            throw XCTSkip("Bundled Gemini automation runner is unavailable in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let staleRunner = tempDirectory.appendingPathComponent("gemini-automation-runner.mjs")
        try "const RUNNER_BUILD_ID = '20260401T000000Z';\n".write(to: staleRunner, atomically: true, encoding: .utf8)

        let encodedPath = String(data: try JSONEncoder().encode(staleRunner.path), encoding: .utf8) ?? "\"\""
        let data = Data("""
        {
          "defaultGeminiRunnerPath": \(encodedPath)
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.defaultGeminiRunnerPath, currentRunnerPath)
    }

    func testLaunchProfilesInheritDefaultTerminalApp() {
        var settings = AppSettings()
        settings.defaultTerminalApp = .terminal
        settings.defaultWorkingDirectory = "/tmp"
        settings.defaultITermProfile = "Ops"
        settings.defaultOpenMode = .newTab

        var profile = LaunchProfile()
        profile.applyKindDefaults(settings: settings)

        XCTAssertEqual(profile.terminalApp, .terminal)
        XCTAssertEqual(profile.workingDirectory, "/tmp")
        XCTAssertEqual(profile.iTermProfile, "Ops")
        XCTAssertEqual(profile.openMode, .newTab)
    }

    func testSessionRecordingBootstrapEnablesMonitoringAndPersistsBootstrapFlag() {
        var settings = AppSettings()
        settings.mongoMonitoring.enabled = false
        settings.mongoMonitoring.enableMongoWrites = false
        settings.mongoMonitoring.connectionURL = ""
        settings.mongoMonitoring.localDataDirectory = ""
        settings.didBootstrapSessionRecording = false

        let changed = settings.bootstrapSessionRecordingIfNeeded()

        XCTAssertTrue(changed)
        XCTAssertTrue(settings.didBootstrapSessionRecording)
        XCTAssertTrue(settings.mongoMonitoring.enabled)
        XCTAssertTrue(settings.mongoMonitoring.enableMongoWrites)
        XCTAssertEqual(settings.mongoMonitoring.captureMode, .outputOnly)
        XCTAssertEqual(settings.mongoMonitoring.connectionURL, "mongodb://127.0.0.1:27017")
        XCTAssertFalse(settings.mongoMonitoring.localDataDirectory.isEmpty)
    }

    func testSessionRecordingBootstrapDoesNotReenableAfterInitialMigration() {
        var settings = AppSettings()
        settings.didBootstrapSessionRecording = true
        settings.mongoMonitoring.enabled = false
        settings.mongoMonitoring.enableMongoWrites = false

        let changed = settings.bootstrapSessionRecordingIfNeeded()

        XCTAssertFalse(changed)
        XCTAssertFalse(settings.mongoMonitoring.enabled)
        XCTAssertFalse(settings.mongoMonitoring.enableMongoWrites)
    }
}

final class DiagnosticReportCompatibilityTests: XCTestCase {
    func testDiagnosticReportDecodesLegacyStateFilePathIntoPersistenceStorePath() throws {
        let data = Data("""
        {
          "appSupportDirectory": "/tmp/appsupport",
          "stateFilePath": "/tmp/state.json",
          "logFilePath": "/tmp/runtime.log",
          "selectedTab": "Settings",
          "diagnosticsErrors": [],
          "diagnosticsWarnings": [],
          "diagnosticStatuses": [],
          "iterm": {
            "applicationURL": null,
            "bundleIdentifier": "com.googlecode.iterm2",
            "isInstalled": true,
            "isRunning": false,
            "profileDiscoverySource": "",
            "profileNames": []
          },
          "monitoring": {
            "sessionCount": 0,
            "databaseStatus": "",
            "lastConnectionCheck": "",
            "storageSummaryStatus": ""
          },
          "recentLogs": []
        }
        """.utf8)

        let decoded = try JSONDecoder.pretty.decode(ApplicationDiagnosticReport.self, from: data)

        XCTAssertEqual(decoded.persistenceStorePath, "/tmp/state.json")
    }

    func testLaunchHistoryItemDecodesLegacyPayloadWithoutMonitorSessionIDs() throws {
        let data = Data("""
        {
          "profileID": null,
          "profileName": "Gemini",
          "description": "Legacy launch",
          "command": "gemini",
          "companionCount": 0
        }
        """.utf8)

        let decoded = try JSONDecoder.pretty.decode(LaunchHistoryItem.self, from: data)

        XCTAssertEqual(decoded.profileName, "Gemini")
        XCTAssertEqual(decoded.monitorSessionIDs, [])
        XCTAssertNil(decoded.workbenchID)
        XCTAssertTrue(decoded.isWorkbenchLaunch)
        XCTAssertFalse(decoded.hasRelaunchTarget)
    }
}

final class LaunchHistoryItemSearchTests: XCTestCase {
    func testLaunchHistoryItemSearchMatchesProfileNameCommandAndSessionID() {
        let sessionID = UUID()
        let item = LaunchHistoryItem(
            profileID: UUID(),
            profileName: "Gemini Preview",
            description: "Prompt injection launch",
            command: "gemini --prompt-interactive 'ship it'",
            monitorSessionIDs: [sessionID]
        )

        XCTAssertTrue(item.hasMonitoringLink)
        XCTAssertTrue(item.matchesSearchQuery("preview"))
        XCTAssertTrue(item.matchesSearchQuery("ship it"))
        XCTAssertTrue(item.matchesSearchQuery(String(sessionID.uuidString.prefix(8))))
        XCTAssertFalse(item.matchesSearchQuery("nightly"))
    }

    func testLaunchHistoryItemSearchMatchesWorkbenchLabelAndWorkbenchID() {
        let workbenchID = UUID()
        let item = LaunchHistoryItem(
            profileID: nil,
            workbenchID: workbenchID,
            profileName: "Team Workspace",
            description: "Workbench launch",
            command: "gemini"
        )

        XCTAssertFalse(item.hasMonitoringLink)
        XCTAssertTrue(item.matchesSearchQuery("workbench"))
        XCTAssertTrue(item.matchesSearchQuery(String(workbenchID.uuidString.prefix(8))))
        XCTAssertTrue(item.matchesSearchQuery("team"))
    }
}

final class ProfileStoreGeminiWorkspaceSyncTests: XCTestCase {
    func testPropagateGeminiWorkingDirectoryChangeUpdatesMatchingGeminiSiblingsOnly() {
        let oldPath = "/tmp/old"
        let newPath = "/tmp/new"

        var primary = LaunchProfile()
        primary.agentKind = .gemini
        primary.geminiFlavor = .stable
        primary.workingDirectory = newPath

        var preview = LaunchProfile()
        preview.agentKind = .gemini
        preview.geminiFlavor = .preview
        preview.workingDirectory = oldPath

        var nightly = LaunchProfile()
        nightly.agentKind = .gemini
        nightly.geminiFlavor = .nightly
        nightly.workingDirectory = "/tmp/keep"

        var codex = LaunchProfile()
        codex.agentKind = .codex
        codex.workingDirectory = oldPath

        var profiles = [primary, preview, nightly, codex]
        let updatedCount = ProfileStore.propagateGeminiWorkingDirectoryChange(
            in: &profiles,
            replacing: oldPath,
            with: newPath,
            excluding: primary.id
        )

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(profiles[1].workingDirectory, newPath)
        XCTAssertEqual(profiles[2].workingDirectory, "/tmp/keep")
        XCTAssertEqual(profiles[3].workingDirectory, oldPath)
    }

    func testPropagateGeminiWorkingDirectoryChangeSkipsBlankOrUnchangedPaths() {
        var stable = LaunchProfile()
        stable.agentKind = .gemini
        stable.geminiFlavor = .stable
        stable.workingDirectory = "/tmp/workspace"

        var preview = LaunchProfile()
        preview.agentKind = .gemini
        preview.geminiFlavor = .preview
        preview.workingDirectory = "/tmp/workspace"

        var profiles = [stable, preview]

        XCTAssertEqual(
            ProfileStore.propagateGeminiWorkingDirectoryChange(
                in: &profiles,
                replacing: "/tmp/workspace",
                with: "/tmp/workspace",
                excluding: stable.id
            ),
            0
        )
        XCTAssertEqual(
            ProfileStore.propagateGeminiWorkingDirectoryChange(
                in: &profiles,
                replacing: "/tmp/workspace",
                with: "   ",
                excluding: stable.id
            ),
            0
        )
        XCTAssertEqual(profiles[1].workingDirectory, "/tmp/workspace")
    }
}

@MainActor
final class ProfileStorePersistenceTests: XCTestCase {
    func testFileOnlyModeReportsJsonFallbackBackend() {
        let store = ProfileStore(persistenceMode: .fileOnly)

        XCTAssertEqual(store.persistenceBackendDescription, "JSON file fallback")
        XCTAssertTrue(store.persistenceLocationDescription.hasSuffix("state.json"))
        XCTAssertEqual(
            URL(fileURLWithPath: store.persistenceLocationDescription).deletingLastPathComponent().path,
            store.persistenceContainerPath
        )
    }

    func testRecordLaunchPersistsMonitorSessionIDsIntoHistory() {
        let store = ProfileStore(persistenceMode: .fileOnly)
        let sessionID = UUID()
        var profile = LaunchProfile()
        profile.name = "Gemini"

        let plan = PlannedLaunch(
            items: [
                PlannedLaunchItem(
                    profileID: profile.id,
                    profileName: profile.name,
                    command: "gemini",
                    openMode: .newTab,
                    terminalApp: .iterm2,
                    iTermProfile: "Default",
                    description: "Gemini",
                    monitorSessionID: sessionID
                )
            ]
        )

        store.recordLaunch(profile: profile, plan: plan)

        XCTAssertEqual(store.history.first?.monitorSessionIDs, [sessionID])
    }

    func testRecordLaunchDeduplicatesMonitorSessionIDsWhilePreservingOrder() {
        let store = ProfileStore(persistenceMode: .fileOnly)
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        var profile = LaunchProfile()
        profile.name = "Gemini"

        let plan = PlannedLaunch(
            items: [
                PlannedLaunchItem(
                    profileID: profile.id,
                    profileName: profile.name,
                    command: "gemini first",
                    openMode: .newTab,
                    terminalApp: .iterm2,
                    iTermProfile: "Default",
                    description: "Gemini first",
                    monitorSessionID: firstSessionID
                ),
                PlannedLaunchItem(
                    profileID: profile.id,
                    profileName: profile.name,
                    command: "gemini second",
                    openMode: .newTab,
                    terminalApp: .iterm2,
                    iTermProfile: "Default",
                    description: "Gemini second",
                    monitorSessionID: secondSessionID
                ),
                PlannedLaunchItem(
                    profileID: profile.id,
                    profileName: profile.name,
                    command: "gemini duplicate",
                    openMode: .newTab,
                    terminalApp: .iterm2,
                    iTermProfile: "Default",
                    description: "Gemini duplicate",
                    monitorSessionID: firstSessionID
                )
            ]
        )

        store.recordLaunch(profile: profile, plan: plan)

        XCTAssertEqual(store.history.first?.monitorSessionIDs, [firstSessionID, secondSessionID])
    }

    func testRecordWorkbenchLaunchPersistsWorkbenchIDIntoHistory() {
        let store = ProfileStore(persistenceMode: .fileOnly)
        let workbench = LaunchWorkbench(name: "Team Workspace", role: .coding, profileIDs: [])

        let plan = PlannedLaunch(
            items: [
                PlannedLaunchItem(
                    profileID: UUID(),
                    profileName: "Gemini",
                    command: "gemini",
                    openMode: .newTab,
                    terminalApp: .iterm2,
                    iTermProfile: "Default",
                    description: "Gemini"
                )
            ]
        )

        store.recordLaunch(workbench: workbench, plan: plan)

        XCTAssertEqual(store.history.first?.workbenchID, workbench.id)
        XCTAssertTrue(store.history.first?.isWorkbenchLaunch == true)
        XCTAssertTrue(store.history.first?.hasRelaunchTarget == true)
    }

    func testRelaunchTargetResolvesExistingWorkbenchHistoryEntry() {
        let store = ProfileStore(persistenceMode: .fileOnly)
        let workbench = LaunchWorkbench(name: "Team Workspace", role: .coding, profileIDs: [])
        store.workbenches = [workbench]

        let item = LaunchHistoryItem(
            profileID: nil,
            workbenchID: workbench.id,
            profileName: workbench.name,
            description: "Workbench launch",
            command: "gemini"
        )

        XCTAssertEqual(store.relaunchTarget(for: item), .workbench(workbench))
    }

    func testRelaunchLastTargetSkipsNewestLegacyEntryWithoutTarget() {
        let store = ProfileStore(persistenceMode: .fileOnly)
        var profile = LaunchProfile()
        profile.name = "Gemini"
        store.profiles = [profile]

        let legacyWorkbenchItem = LaunchHistoryItem(
            timestamp: Date(),
            profileID: nil,
            profileName: "Legacy Workbench",
            description: "Legacy workbench launch",
            command: "legacy command"
        )
        let profileItem = LaunchHistoryItem(
            timestamp: Date().addingTimeInterval(-60),
            profileID: profile.id,
            profileName: profile.name,
            description: "Gemini launch",
            command: "gemini"
        )
        store.history = [legacyWorkbenchItem, profileItem]

        XCTAssertEqual(store.relaunchLastItem(), profileItem)
        XCTAssertEqual(store.relaunchLastTarget(), .profile(profile))
    }

    func testRelaunchLastTargetReturnsNilWhenNoHistoryEntriesResolve() {
        let store = ProfileStore(persistenceMode: .fileOnly)
        store.history = [
            LaunchHistoryItem(
                profileID: nil,
                profileName: "Legacy Workbench",
                description: "Legacy workbench launch",
                command: "legacy command"
            )
        ]

        XCTAssertNil(store.relaunchLastTarget())
    }

    func testExplicitSavePersistsSettingsChangesToStateFile() throws {
        let store = ProfileStore(persistenceMode: .fileOnly)
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let stateURL = tempDirectory.appendingPathComponent("state.json")
        store.setStateURLForTesting(stateURL)

        var settings = store.settings
        settings.defaultWorkingDirectory = "/tmp/launcher-settings"
        settings.defaultNodeExecutable = "/usr/local/bin/node"
        settings.defaultHotkeyPrefix = "ctrl-t"
        settings.confirmBeforeLaunch = false
        settings.mongoMonitoring.enabled = true
        settings.observability.persistLogsToDisk = false
        store.settings = settings

        store.save()

        let data = try Data(contentsOf: stateURL)
        let persisted = try JSONDecoder.pretty.decode(PersistedState.self, from: data)

        XCTAssertEqual(persisted.settings.defaultWorkingDirectory, "/tmp/launcher-settings")
        XCTAssertEqual(persisted.settings.defaultNodeExecutable, "/usr/local/bin/node")
        XCTAssertEqual(persisted.settings.defaultHotkeyPrefix, "ctrl-t")
        XCTAssertFalse(persisted.settings.confirmBeforeLaunch)
        XCTAssertTrue(persisted.settings.mongoMonitoring.enabled)
        XCTAssertFalse(persisted.settings.observability.persistLogsToDisk)
    }

    func testApplySettingsPersistsPresetCleanupWithProfileMutations() throws {
        let store = ProfileStore(persistenceMode: .fileOnly)
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let stateURL = tempDirectory.appendingPathComponent("state.json")
        store.setStateURLForTesting(stateURL)

        var preset = EnvironmentPreset()
        preset.name = "Shared Test Env"
        var entry = EnvironmentEntry()
        entry.key = "API_TOKEN"
        entry.value = "secret"
        preset.entries = [entry]

        var settings = store.settings
        settings.environmentPresets = [preset]

        store.applySettings(settings) { profiles in
            guard !profiles.isEmpty else { return }
            profiles[0].environmentPresetID = preset.id
        }
        store.save()

        settings.environmentPresets = []
        store.applySettings(settings) { profiles in
            for index in profiles.indices where profiles[index].environmentPresetID == preset.id {
                profiles[index].environmentPresetID = nil
            }
        }
        store.save()

        let data = try Data(contentsOf: stateURL)
        let persisted = try JSONDecoder.pretty.decode(PersistedState.self, from: data)

        XCTAssertTrue(persisted.settings.environmentPresets.isEmpty)
        XCTAssertNil(persisted.profiles.first?.environmentPresetID)
    }
}

@MainActor
final class LaunchPreviewStoreTests: XCTestCase {
    func testDefaultsAreEmpty() {
        let store = LaunchPreviewStore()
        XCTAssertNil(store.planPreview)
        XCTAssertNil(store.workbenchPlanPreview)
        XCTAssertNil(store.commandPreview)
        XCTAssertTrue(store.availableITermProfiles.isEmpty)
        XCTAssertTrue(store.iTermProfileSourceDescription.isEmpty)
        XCTAssertFalse(store.isVSCodeAvailable)
        XCTAssertTrue(store.diagnostics.errors.isEmpty)
        XCTAssertTrue(store.diagnostics.warnings.isEmpty)
        XCTAssertTrue(store.selectedWorkbenchDiagnostics.errors.isEmpty)
    }

    func testMutationsArePublished() {
        let store = LaunchPreviewStore()
        store.isVSCodeAvailable = true
        store.availableITermProfiles = ["Default", "Work"]
        store.iTermProfileSourceDescription = "iterm-profiles.json"

        XCTAssertTrue(store.isVSCodeAvailable)
        XCTAssertEqual(store.availableITermProfiles, ["Default", "Work"])
        XCTAssertEqual(store.iTermProfileSourceDescription, "iterm-profiles.json")
    }
}

@MainActor
final class ToolUpdateServiceTests: XCTestCase {
    func testBuildTerminalUpdateCommandBootstrapsHelperScriptForLoginShellExecution() {
        let command = ToolUpdateService.buildTerminalUpdateCommand(
            updateCommand: "npm install -g --prefix ~/.local/gemini-stable @google/gemini-cli@latest",
            workingDirectory: "/tmp",
            toolName: "Gemini"
        )

        XCTAssertTrue(command.contains("/bin/cat > "))
        XCTAssertTrue(command.contains("clilauncher-update-"))
        XCTAssertTrue(command.contains("trap '/bin/rm -f "))
        XCTAssertTrue(command.contains("/bin/zsh -ilc "))
        XCTAssertTrue(command.contains("exec /bin/zsh -il"))
        XCTAssertTrue(command.contains("Gemini update finished successfully."))
    }

    func testBuildTerminalUpdateCommandRunsEndToEndAndLeavesReviewShellReachable() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let transcriptURL = tempDirectory.appendingPathComponent("update.typescript")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let command = ToolUpdateService.buildTerminalUpdateCommand(
            updateCommand: "/usr/bin/printf 'update-ran\\n'",
            workingDirectory: tempDirectory.path,
            toolName: "Gemini"
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", transcriptURL.path, "/bin/zsh", "-lc", command]
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        try process.run()
        Thread.sleep(forTimeInterval: 0.5)
        stdinPipe.fileHandleForWriting.write(Data("exit\n".utf8))
        stdinPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
        XCTAssertTrue(transcript.contains("update-ran"))
        XCTAssertTrue(transcript.contains("Gemini update finished successfully."))
        XCTAssertTrue(transcript.contains("This shell will remain open so you can review the update output."))
    }
}

@MainActor
final class ContentViewLaunchPromptTests: XCTestCase {
    func testResolvedGeminiLaunchPromptFallsBackToStoredProfilePrompt() {
        let resolved = ContentView.resolvedGeminiLaunchPrompt(
            launchCenterPrompt: "   ",
            profilePrompt: "  Ship the release  "
        )

        XCTAssertEqual(resolved, "Ship the release")
    }

    func testResolvedGeminiLaunchPromptPrefersLaunchCenterPromptOverride() {
        let resolved = ContentView.resolvedGeminiLaunchPrompt(
            launchCenterPrompt: "  Explain the failure  ",
            profilePrompt: "Ship the release"
        )

        XCTAssertEqual(resolved, "Explain the failure")
    }

    func testLaunchPromptDisplayTextUsesStoredGeminiInitialPromptOnlyForGeminiProfiles() {
        var geminiProfile = LaunchProfile()
        geminiProfile.agentKind = .gemini
        geminiProfile.geminiInitialPrompt = "  Keep this prompt  "

        var codexProfile = LaunchProfile()
        codexProfile.agentKind = .codex

        XCTAssertEqual(ContentView.launchPromptDisplayText(for: geminiProfile), "Keep this prompt")
        XCTAssertEqual(ContentView.launchPromptDisplayText(for: codexProfile), "")
        XCTAssertEqual(ContentView.launchPromptDisplayText(for: nil), "")
    }

    func testResolvedQuickLaunchProfileKeepsSelectedGeminiProfileSettingsForMatchingFlavor() {
        var selectedProfile = LaunchProfile()
        selectedProfile.agentKind = .gemini
        selectedProfile.geminiFlavor = .stable
        selectedProfile.geminiInitialModel = "gemini-3-flash-preview"
        selectedProfile.geminiModelChain = "gemini-3-flash-preview,gemini-2.5-flash"

        var templateProfile = LaunchProfile()
        templateProfile.agentKind = .gemini
        templateProfile.geminiFlavor = .stable
        templateProfile.applyGeminiFlavorDefaults()

        let resolved = ContentView.resolvedQuickLaunchProfile(
            templateProfile: templateProfile,
            selectedProfile: selectedProfile,
            allProfiles: [selectedProfile]
        )

        XCTAssertEqual(resolved.geminiInitialModel, "gemini-3-flash-preview")
        XCTAssertEqual(resolved.geminiModelChain, "gemini-3-flash-preview,gemini-2.5-flash")
    }

    func testResolvedQuickLaunchProfilePrefersSavedFlavorMatchOverResettingSelectedGeminiProfile() {
        var selectedProfile = LaunchProfile()
        selectedProfile.agentKind = .gemini
        selectedProfile.geminiFlavor = .preview
        selectedProfile.geminiInitialModel = "gemini-3-pro-preview"

        var savedStableProfile = LaunchProfile()
        savedStableProfile.agentKind = .gemini
        savedStableProfile.geminiFlavor = .stable
        savedStableProfile.geminiInitialModel = "gemini-2.5-pro"
        savedStableProfile.geminiModelChain = "gemini-2.5-pro,gemini-2.5-flash"

        var templateProfile = LaunchProfile()
        templateProfile.agentKind = .gemini
        templateProfile.geminiFlavor = .stable
        templateProfile.applyGeminiFlavorDefaults()

        let resolved = ContentView.resolvedQuickLaunchProfile(
            templateProfile: templateProfile,
            selectedProfile: selectedProfile,
            allProfiles: [selectedProfile, savedStableProfile]
        )

        XCTAssertEqual(resolved.id, savedStableProfile.id)
        XCTAssertEqual(resolved.geminiInitialModel, "gemini-2.5-pro")
        XCTAssertEqual(resolved.geminiModelChain, "gemini-2.5-pro,gemini-2.5-flash")
    }
}

final class AiderCommandBuilderTests: XCTestCase {
    private func makeExecutable(at url: URL, contents: String = "#!/bin/sh\nexit 0\n") throws {
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data(contents.utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func bundledGeminiAutomationRunnerSource() throws -> String {
        let path = BundledGeminiAutomationRunner.defaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw XCTSkip("Bundled Gemini automation runner is unavailable in this test environment.")
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private func bundledGeminiAutomationRunnerPath() throws -> String {
        let path = BundledGeminiAutomationRunner.defaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw XCTSkip("Bundled Gemini automation runner is unavailable in this test environment.")
        }
        return path
    }

    private func defaultModelChain(in source: String, for flavor: String) throws -> [String] {
        guard let functionRange = source.range(of: "function defaultModelChainForFlavor(flavor) {") else {
            XCTFail("Missing defaultModelChainForFlavor helper in bundled runner.")
            return []
        }

        let functionTail = source[functionRange.upperBound...]
        let caseMarker = "case '\(flavor)':"
        guard let caseRange = functionTail.range(of: caseMarker) else {
            XCTFail("Missing default model chain case for flavor \(flavor).")
            return []
        }

        let tail = functionTail[caseRange.upperBound...]
        guard let returnRange = tail.range(of: "return ["),
              let endRange = tail.range(of: "];", range: returnRange.upperBound..<tail.endIndex) else {
            XCTFail("Missing return block for flavor \(flavor).")
            return []
        }

        let block = tail[returnRange.upperBound..<endRange.lowerBound]
        let pattern = try NSRegularExpression(pattern: #"'([^']+)'"#)
        let nsBlock = String(block) as NSString

        return pattern.matches(in: String(block), range: NSRange(location: 0, length: nsBlock.length)).compactMap {
            guard $0.numberOfRanges > 1 else { return nil }
            return nsBlock.substring(with: $0.range(at: 1))
        }
    }

    private func runNodeScript(_ script: String) throws -> (terminationStatus: Int32, stdout: String, stderr: String) {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    func testAiderCommandBuilding() throws {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .aider
        profile.aiderExecutable = "/usr/local/bin/aider"
        profile.aiderMode = .architect
        profile.aiderModel = "gpt-4o"
        profile.aiderAutoCommit = false
        profile.aiderNotify = true
        profile.aiderDarkTheme = false
        profile.workingDirectory = "/tmp"

        // Mocking resolveProviderExecutableOrThrow to return the aiderExecutable
        // In real tests we might need to mock ExecutableResolver or actually have aider installed.
        // Since we are testing CommandBuilder, let's assume it finds it if we give absolute path.

        let result = try builder.buildCommand(profile: profile, settings: AppSettings())

        // The command now includes 'cd ... && ...'
        XCTAssertTrue(result.contains("cd '/tmp'"))
        XCTAssertTrue(result.contains("'/Users/michalmatynia/.local/bin/aider'"))
        XCTAssertTrue(result.contains("--architect"))
        XCTAssertTrue(result.contains("--model 'gpt-4o'"))
        XCTAssertTrue(result.contains("--no-auto-commit"))
        XCTAssertTrue(result.contains("--notify"))
        XCTAssertTrue(result.contains("--light-mode"))
    }

    func testGeminiEnvironmentPrioritizesInitialModelInModelChain() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiModelChain = "gemini-2.5-pro,gemini-1.5-flash,gemini-flash"
        profile.geminiInitialModel = "gemini-1.5-flash"

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(
            environment["MODEL_CHAIN"],
            "gemini-1.5-flash,gemini-2.5-pro,gemini-flash"
        )
    }

    func testGeminiEnvironmentIncludesInitialPromptOverride() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiInitialPrompt = "Explain the architecture first."

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(environment["GEMINI_INITIAL_PROMPT"], "Explain the architecture first.")
    }

    func testGeminiEnvironmentExportsMergedLaunchPath() throws {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.environmentEntries = [
            EnvironmentEntry(key: "PATH", value: "/custom/bin")
        ]

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())
        let launchPath = try XCTUnwrap(environment["PATH"])

        XCTAssertTrue(launchPath.hasPrefix("/custom/bin"))
        XCTAssertNotEqual(launchPath, "/custom/bin")
    }

    func testGeminiEnvironmentExportsCliHome() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiISOHome = "~/.gemini-nightly-home"

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(
            environment["GEMINI_CLI_HOME"],
            NSString(string: "~/.gemini-nightly-home").expandingTildeInPath
        )
    }

    func testGeminiResolvedRunnerPathHealsStaleBundledRunnerPath() throws {
        let currentRunnerPath = BundledGeminiAutomationRunner.defaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentRunnerPath.isEmpty else {
            throw XCTSkip("Bundled Gemini automation runner is unavailable in this test environment.")
        }

        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiAutomationRunnerPath = "/Users/test/Library/Developer/Xcode/DerivedData/clilauncher/Build/Products/Debug/CLILauncherNative_GeminiLauncherNative.bundle/Contents/Resources/Resources/gemini-automation-runner.mjs"

        let resolved = builder.resolvedRunnerPath(profile: profile, settings: AppSettings())

        XCTAssertEqual(resolved, currentRunnerPath)
    }

    func testGeminiResolvedRunnerPathHealsCopiedLauncherRunnerWithBuildIdentifier() throws {
        let currentRunnerPath = BundledGeminiAutomationRunner.defaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentRunnerPath.isEmpty else {
            throw XCTSkip("Bundled Gemini automation runner is unavailable in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let staleRunner = tempDirectory.appendingPathComponent("gemini-automation-runner.mjs")
        try "const RUNNER_BUILD_ID = '20260401T000000Z';\n".write(to: staleRunner, atomically: true, encoding: .utf8)

        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiAutomationRunnerPath = staleRunner.path

        let resolved = builder.resolvedRunnerPath(profile: profile, settings: AppSettings())

        XCTAssertEqual(resolved, currentRunnerPath)
    }

    func testGeminiNormalizationPreservesCustomAutomationRunnerPath() {
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiAutomationRunnerPath = "/tmp/custom-gemini-runner.mjs"

        profile.agentKind.providerDefinition.normalizeMissingFields?(&profile)

        XCTAssertEqual(profile.geminiAutomationRunnerPath, "/tmp/custom-gemini-runner.mjs")
    }

    func testGeminiFireAndForgetConfiguresContinuousAutomationLaunch() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiLaunchMode = .directWrapper
        profile.geminiResumeLatest = true
        profile.geminiAutomationEnabled = false
        profile.geminiAutoAllowSessionPermissions = false
        profile.geminiAutoContinueMode = .off
        profile.geminiYolo = false
        profile.geminiKeepTryMax = 1
        profile.geminiCapacityRetryMs = 5_000

        profile.configureGeminiFireAndForget(prompt: "  Ship the release and keep going.  ")
        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(profile.geminiLaunchMode, .automationRunner)
        XCTAssertEqual(profile.geminiInitialPrompt, "Ship the release and keep going.")
        XCTAssertFalse(profile.geminiResumeLatest)
        XCTAssertTrue(profile.geminiAutomationEnabled)
        XCTAssertTrue(profile.geminiAutoAllowSessionPermissions)
        XCTAssertEqual(profile.geminiAutoContinueMode, .yolo)
        XCTAssertTrue(profile.geminiYolo)
        XCTAssertEqual(profile.geminiKeepTryMax, 10)
        XCTAssertEqual(profile.geminiCapacityRetryMs, 500)
        XCTAssertEqual(environment["AUTO_CONTINUE_MODE"], "always")
        XCTAssertEqual(environment["GEMINI_YOLO"], "1")
    }

    func testGeminiPromptInjectionOnlySetsInitialPrompt() {
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiLaunchMode = .directWrapper
        profile.geminiResumeLatest = true
        profile.geminiAutoContinueMode = .promptOnly
        profile.geminiYolo = false

        profile.configureGeminiPromptInjection(prompt: "  Explain the failure and wait.  ")

        XCTAssertEqual(profile.geminiInitialPrompt, "Explain the failure and wait.")
        XCTAssertEqual(profile.geminiLaunchMode, .directWrapper)
        XCTAssertFalse(profile.geminiResumeLatest)
        XCTAssertEqual(profile.geminiAutoContinueMode, .promptOnly)
        XCTAssertFalse(profile.geminiYolo)
    }

    func testGeminiModelModeMapsToNeverSwitchFlag() {
        var profile = LaunchProfile()
        profile.agentKind = .gemini

        XCTAssertEqual(profile.geminiModelMode, .auto)
        XCTAssertFalse(profile.geminiNeverSwitch)

        profile.geminiModelMode = .fixed
        XCTAssertEqual(profile.geminiModelMode, .fixed)
        XCTAssertTrue(profile.geminiNeverSwitch)

        profile.geminiModelMode = .auto
        XCTAssertEqual(profile.geminiModelMode, .auto)
        XCTAssertFalse(profile.geminiNeverSwitch)
    }

    func testLaunchStateSignatureTokenChangesForGeminiAutomationFields() {
        var profile = LaunchProfile()
        profile.agentKind = .gemini

        let baseline = profile.launchStateSignatureToken

        profile.geminiInitialPrompt = "Ship it"
        let promptSignature = profile.launchStateSignatureToken
        XCTAssertNotEqual(promptSignature, baseline)

        profile.geminiYolo = true
        let yoloSignature = profile.launchStateSignatureToken
        XCTAssertNotEqual(yoloSignature, promptSignature)

        profile.geminiSetHomeToIso = true
        let homeSignature = profile.launchStateSignatureToken
        XCTAssertNotEqual(homeSignature, yoloSignature)

        profile.geminiCapacityRetryMs += 250
        XCTAssertNotEqual(profile.launchStateSignatureToken, homeSignature)
    }

    func testLaunchStateSignatureTokenChangesForAiderFields() {
        var profile = LaunchProfile()
        profile.agentKind = .aider

        let baseline = profile.launchStateSignatureToken

        profile.aiderMode = .architect
        let modeSignature = profile.launchStateSignatureToken
        XCTAssertNotEqual(modeSignature, baseline)

        profile.aiderNotify = true
        let notifySignature = profile.launchStateSignatureToken
        XCTAssertNotEqual(notifySignature, modeSignature)

        profile.aiderDarkTheme = false
        XCTAssertNotEqual(profile.launchStateSignatureToken, notifySignature)
    }

    func testGeminiNightlyFlavorDefaultsUseAutomationRunnerMode() {
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .nightly

        profile.applyGeminiFlavorDefaults()

        XCTAssertEqual(profile.geminiLaunchMode, .automationRunner)
        XCTAssertEqual(profile.geminiWrapperCommand, GeminiFlavor.nightly.wrapperName)
        XCTAssertEqual(profile.geminiInitialModel, GeminiFlavor.nightly.defaultInitialModel)
    }

    func testGeminiNightlyPrepareForLaunchPreservesAutomationRunner() {
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .nightly
        profile.geminiLaunchMode = .automationRunner
        profile.configureGeminiFireAndForget(prompt: "Ship it")

        profile.prepareForLaunch()

        XCTAssertEqual(profile.geminiLaunchMode, .automationRunner)
        XCTAssertEqual(profile.geminiInitialPrompt, "Ship it")
        XCTAssertEqual(profile.geminiAutoContinueMode, .yolo)
        XCTAssertFalse(profile.geminiYolo)
    }

    func testGeminiNightlyBuildCommandKeepsAutomationRunnerState() throws {
        let builder = CommandBuilder()
        var settings = AppSettings()
        settings.defaultGeminiRunnerPath = "/bin/echo"
        settings.defaultNodeExecutable = "/bin/echo"

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .nightly
        profile.applyGeminiFlavorDefaults()
        profile.geminiLaunchMode = .automationRunner
        profile.geminiWrapperCommand = "/bin/echo"
        profile.geminiAutomationRunnerPath = "/bin/echo"
        profile.nodeExecutable = "/bin/echo"
        profile.workingDirectory = "/tmp"
        profile.geminiResumeLatest = false
        profile.geminiInitialPrompt = "Ship it"

        let command = try builder.buildCommand(profile: profile, settings: settings)

        XCTAssertTrue(command.contains("GEMINI_CLI_HOME='\(profile.expandedGeminiISOHome)'"))
        XCTAssertTrue(command.contains("GEMINI_INITIAL_PROMPT='Ship it'"))
        XCTAssertTrue(command.contains("Gemini session finished. Opening an interactive shell"))
        XCTAssertTrue(command.contains("Opening an interactive shell for inspection"))
        XCTAssertTrue(command.contains("CLILAUNCHER_LAST_REASON='gemini-session-finished'"))
        XCTAssertTrue(command.contains("CLILAUNCHER_LAST_STATUS"))
        XCTAssertTrue(command.contains("[ \"$__clilauncher_status\" -eq 86 ]"))
        XCTAssertTrue(command.contains("exec /bin/zsh -il"))
        XCTAssertTrue(command.contains("'/bin/echo' '/bin/echo'"))
    }

    func testGeminiNightlyEnvironmentDisablesUnsupportedYoloFlag() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .nightly
        profile.geminiYolo = true

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(environment["GEMINI_YOLO"], "0")
    }

    func testGeminiNightlyDirectWrapperOmitsUnsupportedYoloFlag() throws {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .nightly
        profile.geminiLaunchMode = .directWrapper
        profile.geminiModelMode = .fixed
        profile.geminiWrapperCommand = "/bin/echo"
        profile.workingDirectory = "/tmp"
        profile.geminiYolo = true

        let command = try builder.buildCommand(profile: profile, settings: AppSettings())

        XCTAssertTrue(command.contains("'/bin/echo'"))
        XCTAssertFalse(command.contains("--yolo"))
    }

    func testGeminiNightlyLegacyDefaultsMigrateToFlashFirstChain() {
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .nightly
        profile.geminiInitialModel = "gemini-3-pro-preview"
        profile.geminiModelChain = "gemini-3-pro-preview,gemini-3-flash-preview,gemini-2.5-pro,gemini-2.5-flash,gemini-2.5-flash-lite"

        profile.agentKind.providerDefinition.normalizeMissingFields?(&profile)

        XCTAssertEqual(profile.geminiInitialModel, "gemini-3-flash-preview")
        XCTAssertEqual(profile.geminiModelChain, GeminiFlavor.nightly.defaultModelChain)
        XCTAssertEqual(profile.geminiFlavorDefaultsVersion, GeminiFlavor.nightly.defaultsVersion)
    }

    func testGeminiNightlyCurrentVersionPreservesExplicitProFirstChain() {
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .nightly
        profile.geminiFlavorDefaultsVersion = GeminiFlavor.nightly.defaultsVersion
        profile.geminiInitialModel = "gemini-3-pro-preview"
        profile.geminiModelChain = "gemini-3-pro-preview,gemini-3-flash-preview,gemini-2.5-pro,gemini-2.5-flash,gemini-2.5-flash-lite"

        profile.agentKind.providerDefinition.normalizeMissingFields?(&profile)

        XCTAssertEqual(profile.geminiInitialModel, "gemini-3-pro-preview")
        XCTAssertEqual(profile.geminiModelChain, "gemini-3-pro-preview,gemini-3-flash-preview,gemini-2.5-pro,gemini-2.5-flash,gemini-2.5-flash-lite")
    }

    func testBundledGeminiAutomationRunnerFlavorDefaultChainsMatchProfileDefaults() throws {
        let source = try bundledGeminiAutomationRunnerSource()

        XCTAssertEqual(
            try defaultModelChain(in: source, for: "stable"),
            GeminiFlavor.stable.defaultModelChain.split(separator: ",").map(String.init)
        )
        XCTAssertEqual(
            try defaultModelChain(in: source, for: "nightly"),
            GeminiFlavor.nightly.defaultModelChain.split(separator: ",").map(String.init)
        )
    }

    func testBundledGeminiAutomationRunnerDetectsUsageExhaustionScreenAsUsageLimit() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let sample = """
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │                                                                              │
        │ Usage limit reached for gemini-3-flash-preview.                              │
        │ Access resets at 1:29 PM GMT+2.                                              │
        │ /stats model for usage details                                               │
        │ /model to switch models.                                                     │
        ✕ [API Error: You have exhausted your capacity on this model. Your quota will
          reset after 11h23m12s.]
        │ ● 1. Keep trying                                                             │
        │   2. Stop                                                                    │
        ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
         > continuecontinuecontinuecontinuecontinue

           2

           2

           2
        ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
        """

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedSample = String(data: try JSONEncoder().encode(sample), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const sample = \(encodedSample);
          const snapshot = mod._test.detectSnapshotFromText(sample, "sample");
          process.stdout.write(JSON.stringify(snapshot));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "usage_limit")
        XCTAssertEqual(payload["reason"] as? String, "usage limit reached")
        XCTAssertEqual(payload["stopOptionText"] as? String, "2")
    }

    func testBundledGeminiAutomationRunnerDetectsBracketedPermissionPromptAsPermissionMenu() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let sample = """
        ╭──────────────────────────────────────────────────────────────────────────╮
        │ ? Shell  Finding all test files in Kangur that mock useKangurAuth.      │
        │ ╭──────────────────────────────────────────────────────────────────────╮ │
        │ │ find src/features/kangur -name "*.test.tsx" -exec grep -l           │ │
        │ │ "useKangurAuth:" {} +                                               │ │
        │ ╰──────────────────────────────────────────────────────────────────────╯ │
        │ Allow execution of [find]?                                             │
        │                                                                        │
        │ ● 1. Allow once                                                        │
        │   2. Allow for this session                                            │
        │   3. No, suggest changes (esc)                                         │
        ╰──────────────────────────────────────────────────────────────────────────╯
        """

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedSample = String(data: try JSONEncoder().encode(sample), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const snapshot = mod._test.detectSnapshotFromText(\(encodedSample), "sample");
          process.stdout.write(JSON.stringify(snapshot));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "permission")
        XCTAssertEqual(payload["reason"] as? String, "permission prompt")
        XCTAssertEqual(payload["targetOptionText"] as? String, "2")
    }

    func testBundledGeminiAutomationRunnerCapturesPromptContextForNormalPrompt() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let sample = """
        I have successfully addressed multiple linting issues across critical files.
        The npm run lint command completed with 44158 issues (44156 errors, 2 warnings).
        Would you like me to proceed with attempting to fix some of these remaining issues manually, or would you prefer to move on to another task?
        ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
         > 
        ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
        """

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedSample = String(data: try JSONEncoder().encode(sample), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const snapshot = mod._test.detectSnapshotFromText(\(encodedSample), "sample");
          process.stdout.write(JSON.stringify(snapshot));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "normal")
        XCTAssertEqual(payload["chatPromptActive"] as? Bool, true)
        XCTAssertTrue((payload["promptContext"] as? String)?.contains("would you like me to proceed") == true)
    }

    func testBundledGeminiAutomationRunnerCapturesPromptContextForPlaceholderPrompt() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let sample = """
        I have successfully addressed multiple linting issues across critical files,
          including src/app/layout.tsx and various handlers in src/app/api/ai-paths/.

        ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
         *   Type your message or @path/to/file
        ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
         ~/.../geminitestapp (geet*)      no sandbox      /model gemini-3-flash-preview
        """

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedSample = String(data: try JSONEncoder().encode(sample), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const snapshot = mod._test.detectSnapshotFromText(\(encodedSample), "sample");
          process.stdout.write(JSON.stringify(snapshot));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "normal")
        XCTAssertEqual(payload["chatPromptActive"] as? Bool, true)
        XCTAssertTrue((payload["promptContext"] as? String)?.contains("i have successfully addressed multiple linting issues") == true)
    }

    func testBundledGeminiAutomationRunnerBuildsModelSwitchSlashCommand() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          process.stdout.write(mod._test.buildModelSwitchCommand("gemini-2.5-flash"));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "/model set gemini-2.5-flash")
    }

    func testBundledGeminiAutomationRunnerDetectsKnownBadGeminiCliVersionFromPackagePath() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let packageRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let distDirectory = packageRoot.appendingPathComponent("dist", isDirectory: true)
        let entrypointURL = distDirectory.appendingPathComponent("index.js")
        try FileManager.default.createDirectory(at: distDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        let packageJSON = """
        {
          "name": "@google/gemini-cli",
          "version": "0.32.1"
        }
        """
        try packageJSON.write(to: packageRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "// test entrypoint\n".write(to: entrypointURL, atomically: true, encoding: .utf8)

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedEntrypoint = String(data: try JSONEncoder().encode(entrypointURL.path), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const packageInfo = mod._test.inspectGeminiCliPackage({ realPath: \(encodedEntrypoint) });
          const capabilities = mod._test.resolveGeminiCliCapabilities({ realPath: \(encodedEntrypoint) });
          process.stdout.write(JSON.stringify({ packageInfo, capabilities }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let packageInfo = try XCTUnwrap(payload["packageInfo"] as? [String: Any])
        let capabilities = try XCTUnwrap(payload["capabilities"] as? [String: Any])

        XCTAssertEqual(packageInfo["packageName"] as? String, "@google/gemini-cli")
        XCTAssertEqual(packageInfo["version"] as? String, "0.32.1")
        XCTAssertEqual(capabilities["startupStatsAutomationSupported"] as? Bool, true)
        XCTAssertEqual(capabilities["statsSessionAutomationSupported"] as? Bool, false)
        XCTAssertEqual(
            capabilities["statsSessionAutomationDisabledReason"] as? String,
            #"Gemini CLI 0.32.1 crashes on /stats session ("data.slice is not a function"), so /stats session automation is disabled for session-scoped model management."#
        )
        XCTAssertEqual(
            capabilities["systemSettingsOverrideReason"] as? String,
            "Gemini CLI 0.32.1 self-update checks are disabled for this launch"
        )
        let systemSettingsOverride = try XCTUnwrap(capabilities["systemSettingsOverride"] as? [String: Any])
        let general = try XCTUnwrap(systemSettingsOverride["general"] as? [String: Any])
        XCTAssertEqual(general["enableAutoUpdate"] as? Bool, false)
        XCTAssertEqual(general["enableAutoUpdateNotification"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerDisablesSelfUpdateChecksForSupportedGeminiCliVersion() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let packageRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let distDirectory = packageRoot.appendingPathComponent("dist", isDirectory: true)
        let entrypointURL = distDirectory.appendingPathComponent("index.js")
        try FileManager.default.createDirectory(at: distDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        let packageJSON = """
        {
          "name": "@google/gemini-cli",
          "version": "0.39.0"
        }
        """
        try packageJSON.write(to: packageRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "// test entrypoint\n".write(to: entrypointURL, atomically: true, encoding: .utf8)

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedEntrypoint = String(data: try JSONEncoder().encode(entrypointURL.path), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const capabilities = mod._test.resolveGeminiCliCapabilities({ realPath: \(encodedEntrypoint) });
          process.stdout.write(JSON.stringify(capabilities));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let capabilities = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(capabilities["startupStatsAutomationSupported"] as? Bool, true)
        XCTAssertEqual(capabilities["statsSessionAutomationSupported"] as? Bool, true)
        XCTAssertEqual(
            capabilities["systemSettingsOverrideReason"] as? String,
            "Gemini CLI 0.39.0 self-update checks are disabled for this launch"
        )
        let systemSettingsOverride = try XCTUnwrap(capabilities["systemSettingsOverride"] as? [String: Any])
        let general = try XCTUnwrap(systemSettingsOverride["general"] as? [String: Any])
        XCTAssertEqual(general["enableAutoUpdate"] as? Bool, false)
        XCTAssertEqual(general["enableAutoUpdateNotification"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerExportsBuildIdentifier() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          process.stdout.write(String(mod._test.RUNNER_BUILD_ID || ''));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "20260424T154225Z")
    }

    func testBundledGeminiAutomationRunnerBundleHelperMatchesRunnerModuleBuildIdentifier() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          process.stdout.write(String(mod._test.RUNNER_BUILD_ID || ''));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
        XCTAssertEqual(
            BundledGeminiAutomationRunner.buildID,
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        XCTAssertFalse(BundledGeminiAutomationRunner.buildID.isEmpty)
    }

    func testBundledGeminiAutomationRunnerTreatsPosixOpenptFailureAsDirectSpawnFallback() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const shouldFallback = mod._test.shouldFallbackToDirectSpawnForPtyError(
            new Error('posix_openpt failed: Device not configured')
          );
          const shouldIgnore = mod._test.shouldFallbackToDirectSpawnForPtyError(
            new Error('ENOENT: no such file or directory')
          );
          process.stdout.write(JSON.stringify({ shouldFallback, shouldIgnore }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(payload["shouldFallback"] as? Bool, true)
        XCTAssertEqual(payload["shouldIgnore"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerIgnoresBenignStdoutWriteErrors() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = {
            eio: mod._test.isBenignStdoutWriteError(new Error('write EIO')),
            epipe: mod._test.isBenignStdoutWriteError(new Error('write EPIPE')),
            unrelated: mod._test.isBenignStdoutWriteError(new Error('permission denied')),
          };
          process.stdout.write(JSON.stringify(payload));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(payload["eio"] as? Bool, true)
        XCTAssertEqual(payload["epipe"] as? Bool, true)
        XCTAssertEqual(payload["unrelated"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerCreatesSessionLocalSystemSettingsOverrideForKnownBadVersion() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let isoHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: isoHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isoHome) }

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedISOHome = String(data: try JSONEncoder().encode(isoHome.path), encoding: .utf8) ?? "\"\""
        let script = """
        delete process.env.GEMINI_CLI_SYSTEM_SETTINGS_PATH;
        process.env.GEMINI_ISO_HOME = \(encodedISOHome);
        Promise.all([import(\(encodedImportURL)), import('node:fs')]).then(([mod, fs]) => {
          const capabilities = {
            packageName: "@google/gemini-cli",
            version: "0.32.1",
            systemSettingsOverride: {
              general: {
                enableAutoUpdate: false,
                enableAutoUpdateNotification: false,
              },
            },
            systemSettingsOverrideReason: "Gemini CLI 0.32.1 self-update checks are disabled for this launch",
          };
          const env = mod._test.buildChildEnv(capabilities);
          const overridePath = env.GEMINI_CLI_SYSTEM_SETTINGS_PATH;
          const override = JSON.parse(fs.readFileSync(overridePath, 'utf8'));
          process.stdout.write(JSON.stringify({ overridePath, override }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let overridePath = try XCTUnwrap(payload["overridePath"] as? String)
        let override = try XCTUnwrap(payload["override"] as? [String: Any])
        let general = try XCTUnwrap(override["general"] as? [String: Any])

        XCTAssertTrue(overridePath.hasPrefix(isoHome.path))
        XCTAssertEqual(general["enableAutoUpdate"] as? Bool, false)
        XCTAssertEqual(general["enableAutoUpdateNotification"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerSkipsStartupStatsForKnownBadGeminiCliVersion() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        process.env.GEMINI_INITIAL_PROMPT = "Ship beta now";
        import(\(encodedImportURL)).then((mod) => {
          const capabilities = {
            packageName: "@google/gemini-cli",
            version: "test-disabled",
            startupStatsAutomationSupported: false,
            statsSessionAutomationSupported: false,
          };
          const payload = {
            startup: mod._test.buildStartupStatsCommand(capabilities),
            modelManage: mod._test.buildModelManageStarterCommand(2, "gemini-2.5-pro", capabilities),
          };
          process.stdout.write(JSON.stringify(payload));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let modelManage = try XCTUnwrap(payload["modelManage"] as? [String: Any])

        XCTAssertTrue(payload["startup"] is NSNull)
        XCTAssertEqual(modelManage["kind"] as? String, "model-manage-open")
        XCTAssertEqual(modelManage["text"] as? String, "/model manage")
        XCTAssertEqual(modelManage["targetModel"] as? String, "gemini-2.5-pro")
    }

    func testBundledGeminiAutomationRunnerBlocksPromptWhenStartupStatsAreDisabled() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        process.env.GEMINI_INITIAL_PROMPT = "Ship beta now";
        import(\(encodedImportURL)).then((mod) => {
          const capabilities = {
            startupStatsAutomationSupported: false,
            startupStatsAutomationDisabledReason: 'Gemini startup /stats automation is disabled for this test capability.',
          };
          const payload = {
            startupStatsRequired: mod._test.shouldRequireStartupStatsBeforeInitialPrompt(),
            blockedReason: mod._test.resolveStartupStatsBlockReason({
              hasInitialPrompt: true,
              capabilities,
              ptyAvailable: true,
            }),
            allowLaunchPrompt: mod._test.shouldLaunchInitialPromptWithLaunchArgs(capabilities),
            args: mod._test.buildGeminiArgs("gemini-2.5-flash", {
              allowLaunchPrompt: mod._test.shouldLaunchInitialPromptWithLaunchArgs(capabilities),
            }),
          };
          process.stdout.write(JSON.stringify(payload));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let argsPayload = try XCTUnwrap(payload["args"] as? [String: Any])
        let args = try XCTUnwrap(argsPayload["args"] as? [String])

        XCTAssertEqual(payload["startupStatsRequired"] as? Bool, true)
        XCTAssertEqual(payload["allowLaunchPrompt"] as? Bool, false)
        XCTAssertEqual(argsPayload["launchesWithInitialPrompt"] as? Bool, false)
        XCTAssertFalse(args.contains("--prompt-interactive"))
        XCTAssertFalse(args.contains("Ship beta now"))
        XCTAssertEqual(
            payload["blockedReason"] as? String,
            "Gemini startup /stats automation is disabled for this test capability."
        )
    }

    func testBundledGeminiAutomationRunnerBlocksPromptWhenPtyUnavailable() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        process.env.GEMINI_INITIAL_PROMPT = "Ship beta now";
        import(\(encodedImportURL)).then((mod) => {
          const capabilities = {
            startupStatsAutomationSupported: true,
          };
          const payload = {
            allowLaunchPrompt: mod._test.shouldLaunchInitialPromptWithLaunchArgs(capabilities),
            blockedReason: mod._test.resolveStartupStatsBlockReason({
              hasInitialPrompt: true,
              capabilities,
              ptyAvailable: false,
            }),
          };
          process.stdout.write(JSON.stringify(payload));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])

        XCTAssertEqual(payload["allowLaunchPrompt"] as? Bool, false)
        XCTAssertEqual(
            payload["blockedReason"] as? String,
            "PTY backend unavailable, so /clear -> /stats -> /model cannot be automated before prompt injection"
        )
    }

    func testBundledGeminiAutomationRunnerQueuesStartupStatsBeforeInitialPrompt() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        process.env.GEMINI_INITIAL_PROMPT = "Ship beta now";
        process.env.RESUME_LATEST = "0";
        import(\(encodedImportURL)).then((mod) => {
          const payload = {
            args: mod._test.buildGeminiArgs("gemini-2.5-flash"),
            startupClear: mod._test.buildStartupClearCommand(),
            startup: mod._test.buildStartupStatsCommand(),
            startupModel: mod._test.buildStartupModelCommand(),
            pipeline: mod._test.buildStartupCommandPipeline(),
          };
          process.stdout.write(JSON.stringify(payload));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        let argsPayload = try XCTUnwrap(payload["args"] as? [String: Any])
        let args = try XCTUnwrap(argsPayload["args"] as? [String])
        let startupClear = try XCTUnwrap(payload["startupClear"] as? [String: Any])
        let startup = try XCTUnwrap(payload["startup"] as? [String: Any])
        let startupModel = try XCTUnwrap(payload["startupModel"] as? [String: Any])
        let pipeline = try XCTUnwrap(payload["pipeline"] as? [String: Any])

        XCTAssertEqual(argsPayload["hasInitialPrompt"] as? Bool, true)
        XCTAssertEqual(argsPayload["launchesWithInitialPrompt"] as? Bool, false)
        XCTAssertFalse(args.contains("--prompt-interactive"))
        XCTAssertEqual(startupClear["kind"] as? String, "startup-clear")
        XCTAssertEqual(startupClear["text"] as? String, "/clear")
        XCTAssertEqual(startup["kind"] as? String, "startup-stats")
        XCTAssertEqual(startup["text"] as? String, "/stats")
        XCTAssertEqual(startup["fallbackText"] as? String, "")
        XCTAssertEqual(startupModel["kind"] as? String, "startup-model")
        XCTAssertEqual(startupModel["text"] as? String, "/model")
        XCTAssertEqual(pipeline["kind"] as? String, "startup-clear")
    }

    func testBundledGeminiAutomationRunnerForcesFreshSessionWhenPromptExistsEvenIfResumeLatestIsEnabled() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let isoHomeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: isoHomeURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
            try? FileManager.default.removeItem(at: isoHomeURL)
        }

        let projectID = "project-123"
        let geminiDirectory = isoHomeURL.appendingPathComponent(".gemini", isDirectory: true)
        let tmpDirectory = geminiDirectory.appendingPathComponent("tmp/\(projectID)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDirectory.appendingPathComponent("chats", isDirectory: true), withIntermediateDirectories: true)
        try Data().write(to: tmpDirectory.appendingPathComponent("chats/session-existing.json"))

        let projectsJSON = """
        {
          "projects": {
            "\(workspaceURL.path.replacingOccurrences(of: "\\", with: "\\\\"))": "\(projectID)"
          }
        }
        """
        try FileManager.default.createDirectory(at: geminiDirectory, withIntermediateDirectories: true)
        try projectsJSON.write(to: geminiDirectory.appendingPathComponent("projects.json"), atomically: true, encoding: .utf8)
        try Data().write(to: isoHomeURL.appendingPathComponent(".iso-initialized"))

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedWorkspacePath = String(data: try JSONEncoder().encode(workspaceURL.path), encoding: .utf8) ?? "\"\""
        let encodedISOHomePath = String(data: try JSONEncoder().encode(isoHomeURL.path), encoding: .utf8) ?? "\"\""
        let script = """
        process.env.GEMINI_INITIAL_PROMPT = "Ship beta now";
        process.env.RESUME_LATEST = "1";
        process.env.GEMINI_ISO_HOME = \(encodedISOHomePath);
        process.chdir(\(encodedWorkspacePath));
        import(\(encodedImportURL)).then((mod) => {
          const payload = mod._test.buildGeminiArgs("gemini-2.5-flash");
          process.stdout.write(JSON.stringify(payload));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let args = try XCTUnwrap(payload["args"] as? [String])

        XCTAssertEqual(payload["hasInitialPrompt"] as? Bool, true)
        XCTAssertEqual(payload["canResume"] as? Bool, false)
        XCTAssertFalse(args.contains("--resume"))
        XCTAssertFalse(args.contains("latest"))
    }

    func testBundledGeminiAutomationRunnerClearsWorkspaceSessionBindingForPromptLaunchWithoutDeletingHistory() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let isoHomeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: isoHomeURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
            try? FileManager.default.removeItem(at: isoHomeURL)
        }

        let projectID = "project-123"
        let geminiDirectory = isoHomeURL.appendingPathComponent(".gemini", isDirectory: true)
        let chatFileURL = geminiDirectory.appendingPathComponent("tmp/\(projectID)/chats/session-existing.json")
        try FileManager.default.createDirectory(at: chatFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: chatFileURL)

        let projectsJSON = """
        {
          "projects": {
            "\(workspaceURL.path.replacingOccurrences(of: "\\", with: "\\\\"))": "\(projectID)"
          }
        }
        """
        try FileManager.default.createDirectory(at: geminiDirectory, withIntermediateDirectories: true)
        try projectsJSON.write(to: geminiDirectory.appendingPathComponent("projects.json"), atomically: true, encoding: .utf8)
        try Data().write(to: isoHomeURL.appendingPathComponent(".iso-initialized"))

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedWorkspacePath = String(data: try JSONEncoder().encode(workspaceURL.path), encoding: .utf8) ?? "\"\""
        let encodedISOHomePath = String(data: try JSONEncoder().encode(isoHomeURL.path), encoding: .utf8) ?? "\"\""
        let encodedChatFilePath = String(data: try JSONEncoder().encode(chatFileURL.path), encoding: .utf8) ?? "\"\""
        let script = """
        process.env.GEMINI_INITIAL_PROMPT = "Ship beta now";
        process.env.GEMINI_ISO_HOME = \(encodedISOHomePath);
        process.chdir(\(encodedWorkspacePath));
        import(\(encodedImportURL)).then(async (mod) => {
          const fs = await import('node:fs');
          const result = mod._test.prepareFreshWorkspaceSessionForPromptLaunch();
          const registry = JSON.parse(fs.readFileSync(\(encodedISOHomePath) + "/.gemini/projects.json", "utf8"));
          process.stdout.write(JSON.stringify({
            result,
            projects: registry.projects,
            chatFileStillExists: fs.existsSync(\(encodedChatFilePath)),
          }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let nodeResult = try runNodeScript(script)
        XCTAssertEqual(nodeResult.terminationStatus, 0, nodeResult.stderr)

        let payloadData = try XCTUnwrap(nodeResult.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let result = try XCTUnwrap(payload["result"] as? [String: Any])
        let projects = try XCTUnwrap(payload["projects"] as? [String: Any])

        XCTAssertEqual(result["requested"] as? Bool, true)
        XCTAssertEqual(result["cleared"] as? Bool, true)
        XCTAssertEqual(result["projectIdentifier"] as? String, projectID)
        XCTAssertEqual(result["removedPathCount"] as? Int, 1)
        XCTAssertNil(projects[workspaceURL.path])
        XCTAssertEqual(payload["chatFileStillExists"] as? Bool, true)
    }

    func testBundledGeminiAutomationRunnerClearsWorkspaceSessionBindingWhenRegistryUsesAlternatePathAlias() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let isoHomeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: isoHomeURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
            try? FileManager.default.removeItem(at: isoHomeURL)
        }

        let projectID = "project-123"
        let geminiDirectory = isoHomeURL.appendingPathComponent(".gemini", isDirectory: true)
        let chatFileURL = geminiDirectory.appendingPathComponent("tmp/\(projectID)/chats/session-existing.json")
        try FileManager.default.createDirectory(at: chatFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: chatFileURL)
        try FileManager.default.createDirectory(at: geminiDirectory, withIntermediateDirectories: true)
        try Data().write(to: isoHomeURL.appendingPathComponent(".iso-initialized"))

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedWorkspacePath = String(data: try JSONEncoder().encode(workspaceURL.path), encoding: .utf8) ?? "\"\""
        let encodedISOHomePath = String(data: try JSONEncoder().encode(isoHomeURL.path), encoding: .utf8) ?? "\"\""
        let encodedProjectsPath = String(data: try JSONEncoder().encode(geminiDirectory.appendingPathComponent("projects.json").path), encoding: .utf8) ?? "\"\""
        let encodedChatFilePath = String(data: try JSONEncoder().encode(chatFileURL.path), encoding: .utf8) ?? "\"\""
        let script = """
        process.env.GEMINI_INITIAL_PROMPT = "Ship beta now";
        process.env.GEMINI_ISO_HOME = \(encodedISOHomePath);
        process.chdir(\(encodedWorkspacePath));
        import(\(encodedImportURL)).then(async (mod) => {
          const fs = await import('node:fs');
          const cwdPath = process.cwd();
          const alternatePath = mod._test.alternateWorkspacePathAlias(process.cwd()) || process.cwd();
          fs.writeFileSync(
            \(encodedProjectsPath),
            JSON.stringify({ projects: { [alternatePath]: "project-123" } }, null, 2) + "\\n"
          );
          const result = mod._test.prepareFreshWorkspaceSessionForPromptLaunch();
          const registry = JSON.parse(fs.readFileSync(\(encodedProjectsPath), "utf8"));
          process.stdout.write(JSON.stringify({
            result,
            cwdPath,
            alternatePath,
            projects: registry.projects,
            chatFileStillExists: fs.existsSync(\(encodedChatFilePath)),
          }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let nodeResult = try runNodeScript(script)
        XCTAssertEqual(nodeResult.terminationStatus, 0, nodeResult.stderr)

        let payloadData = try XCTUnwrap(nodeResult.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let result = try XCTUnwrap(payload["result"] as? [String: Any])
        let projects = try XCTUnwrap(payload["projects"] as? [String: Any])
        let cwdPath = try XCTUnwrap(payload["cwdPath"] as? String)
        let alternatePath = try XCTUnwrap(payload["alternatePath"] as? String)

        XCTAssertNotEqual(alternatePath, cwdPath)
        XCTAssertEqual(result["cleared"] as? Bool, true)
        XCTAssertEqual(result["projectIdentifier"] as? String, projectID)
        XCTAssertNil(projects[alternatePath])
        XCTAssertEqual(payload["chatFileStillExists"] as? Bool, true)
    }

    func testBundledGeminiAutomationRunnerExtractsStartupStatsSnapshot() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let transcript = """
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │  Session Stats                                                               │
        │  Interaction Summary                                                         │
        │  Session ID:                 d1431b19-95f2-43b5-871f-ddd618e64303            │
        │  Auth Method:               Signed in with Google (info@sparksofsindri.com)  │
        │  Tier:                       Gemini Code Assist for individuals              │
        │  Tool Calls:                 0 ( ✓ 0 x 0 )                                   │
        │  Performance                                                                 │
        │  Wall Time:                  7.1s                                            │
        │  Model Usage                                                                 │
        │  Use /model to view model quota information                                  │
        │  Model                         Reqs Input Tokens Cache Reads Output Tokens    │
        │  gemini-2.5-flash                 1            0            0             0  │
        │    ↳ main                         1            0            0             0  │
        ╰──────────────────────────────────────────────────────────────────────────────╯
        """
        let encodedTranscript = String(data: try JSONEncoder().encode(transcript), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = mod._test.extractStartupStatsSnapshot(\(encodedTranscript));
          process.stdout.write(JSON.stringify(payload));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let modelUsage = try XCTUnwrap(payload["modelUsage"] as? [[String: Any]])

        XCTAssertEqual(payload["sessionID"] as? String, "d1431b19-95f2-43b5-871f-ddd618e64303")
        XCTAssertEqual(payload["tier"] as? String, "Gemini Code Assist for individuals")
        XCTAssertEqual(modelUsage.count, 2)
        XCTAssertEqual(modelUsage.first?["model"] as? String, "gemini-2.5-flash")
    }

    func testBundledGeminiAutomationRunnerExtractsStartupStatsSnapshotWithoutModelUsageRows() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let transcript = """
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │  Session Stats                                                               │
        │  Interaction Summary                                                         │
        │  Session ID:                 2b7a5acf-fae6-49a7-b243-c3e424850832            │
        │  Auth Method:                Signed in with Google (frommmishap@gmail.com)   │
        │  Tier:                       Gemini Code Assist for individuals              │
        │  Tool Calls:                 0 ( ✓ 0 x 0 )                                   │
        │  Success Rate:               0.0%                                            │
        │  Performance                                                                 │
        │  Wall Time:                  39.4s                                           │
        │  Agent Active:               0s                                              │
        │    » API Time:               0s (0.0%)                                       │
        │    » Tool Time:              0s (0.0%)                                       │
        ╰──────────────────────────────────────────────────────────────────────────────╯
        """
        let encodedTranscript = String(data: try JSONEncoder().encode(transcript), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = mod._test.extractStartupStatsSnapshot(\(encodedTranscript));
          process.stdout.write(JSON.stringify(payload));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let modelUsage = try XCTUnwrap(payload["modelUsage"] as? [[String: Any]])

        XCTAssertEqual(payload["sessionID"] as? String, "2b7a5acf-fae6-49a7-b243-c3e424850832")
        XCTAssertEqual(payload["authMethod"] as? String, "Signed in with Google (frommmishap@gmail.com)")
        XCTAssertEqual(payload["tier"] as? String, "Gemini Code Assist for individuals")
        XCTAssertEqual(payload["toolCalls"] as? String, "0 ( ✓ 0 x 0 )")
        XCTAssertEqual(payload["wallTime"] as? String, "39.4s")
        XCTAssertEqual(modelUsage.count, 0)
    }

    func testBundledGeminiAutomationRunnerExtractsStartupModelCapacitySnapshot() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let transcript = """
        [gemini-preview-pty] Auto-sending startup /model (visible prompt field)...
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │ Select Model                                                                 │
        │ ● 1. Manual (gemini-3-flash-preview)                                         │
        │   2. Auto                                                                    │
        │ Model usage                                                                  │
        │ Pro             ▬▬▬▬▬▬▬▬▬▬▬▬▬▬                         82% Resets: 1:29 PM   │
        │ Flash           ▬                                      7% Resets: 1:29 PM    │
        │ Flash Lite                                             0%                    │
        │ Press Esc to close                                                           │
        ╰──────────────────────────────────────────────────────────────────────────────╯
        """
        let encodedTranscript = String(data: try JSONEncoder().encode(transcript), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = mod._test.extractStartupModelCapacitySnapshot(\(encodedTranscript));
          process.stdout.write(JSON.stringify(payload));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let rows = try XCTUnwrap(payload["rows"] as? [[String: Any]])

        XCTAssertEqual(payload["startupModelCommand"] as? String, "/model")
        XCTAssertEqual(payload["startupModelCommandSource"] as? String, "runner_banner")
        XCTAssertEqual(payload["currentModel"] as? String, "gemini-3-flash-preview")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.first?["model"] as? String, "Pro")
        XCTAssertEqual(rows.first?["usedPercentage"] as? Int, 82)
        XCTAssertEqual(rows.first?["resetTime"] as? String, "1:29 PM")
        XCTAssertEqual(rows.last?["model"] as? String, "Flash Lite")
    }

    func testBundledGeminiAutomationRunnerAllowsStartupStatsWithoutVisiblePromptWhenScreenIsSettled() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const allowed = mod._test.canSendPromptCommandWithoutVisiblePrompt(
            { kind: 'startup-stats', createdAt: Date.now() - 1500 },
            { kind: 'normal', chatPromptActive: false },
            { quietForMs: 1500, waitedForMs: 1500, authWaiting: false }
          );
          process.stdout.write(String(allowed));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "true")
    }

    func testBundledGeminiAutomationRunnerWaitsForStartupStatsPanelToClearBeforeFinalizing() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let visibleStatsTranscript = """
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │  Session Stats                                                               │
        │  Interaction Summary                                                         │
        │  Session ID:                 2b7a5acf-fae6-49a7-b243-c3e424850832            │
        │  Auth Method:                Signed in with Google (frommmishap@gmail.com)   │
        │  Tier:                       Gemini Code Assist for individuals              │
        │  Tool Calls:                 0 ( ✓ 0 x 0 )                                   │
        │  Success Rate:               0.0%                                            │
        │  Performance                                                                 │
        │  Wall Time:                  39.4s                                           │
        ╰──────────────────────────────────────────────────────────────────────────────╯
        """
        let settledScreen = """
        ? for shortcuts
        Type your message or @path/to/file
        /model gemini-3-flash-preview
        """
        let encodedVisibleStats = String(data: try JSONEncoder().encode(visibleStatsTranscript), encoding: .utf8) ?? "\"\""
        let encodedSettledScreen = String(data: try JSONEncoder().encode(settledScreen), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const stillVisible = mod._test.hasStartupStatsCaptureSettled(
            { kind: 'normal', chatPromptActive: false },
            {
              startupStatsObserved: true,
              visibleText: \(encodedVisibleStats),
              quietForMs: 1_500,
              waitedForMs: 1_500,
            }
          );
          const settled = mod._test.hasStartupStatsCaptureSettled(
            { kind: 'normal', chatPromptActive: false },
            {
              startupStatsObserved: true,
              visibleText: \(encodedSettledScreen),
              quietForMs: 1_500,
              waitedForMs: 1_500,
            }
          );
          process.stdout.write(JSON.stringify({ stillVisible, settled }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(payload["stillVisible"] as? Bool, false)
        XCTAssertEqual(payload["settled"] as? Bool, true)
    }

    func testBundledGeminiAutomationRunnerIgnoresHistoricalStatsTailAfterPanelClears() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let visibleStatsTranscript = """
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │  Session Stats                                                               │
        │  Interaction Summary                                                         │
        │  Session ID:                 2b7a5acf-fae6-49a7-b243-c3e424850832            │
        │  Auth Method:                Signed in with Google (frommmishap@gmail.com)   │
        │  Tier:                       Gemini Code Assist for individuals              │
        │  Tool Calls:                 0 ( ✓ 0 x 0 )                                   │
        │  Success Rate:               0.0%                                            │
        │  Performance                                                                 │
        │  Wall Time:                  39.4s                                           │
        ╰──────────────────────────────────────────────────────────────────────────────╯
        """
        let settledScreen = """
        ? for shortcuts
        Type your message or @path/to/file
        /model gemini-3-flash-preview
        """
        let staleHistory = visibleStatsTranscript + "\n" + settledScreen
        let encodedSettledScreen = String(data: try JSONEncoder().encode(settledScreen), encoding: .utf8) ?? "\"\""
        let encodedStaleHistory = String(data: try JSONEncoder().encode(staleHistory), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const settled = mod._test.hasStartupStatsCaptureSettled(
            { kind: 'normal', chatPromptActive: false },
            {
              startupStatsObserved: true,
              screenText: \(encodedSettledScreen),
              visibleText: \(encodedStaleHistory),
              quietForMs: 1_500,
              waitedForMs: 1_500,
            }
          );
          process.stdout.write(String(Boolean(settled)));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "true")
    }

    func testBundledGeminiAutomationRunnerDescribesCapturedStartupStats() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const summary = mod._test.describeStartupStatsCapture({
            sessionID: '2b7a5acf-fae6-49a7-b243-c3e424850832',
            tier: 'Gemini Code Assist for individuals',
            authMethod: 'Signed in with Google (frommmishap@gmail.com)',
          });
          process.stdout.write(String(summary));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
        XCTAssertEqual(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "session 2b7a5acf-fae6-49a7-b243-c3e424850832, tier Gemini Code Assist for individuals, Signed in with Google (frommmishap@gmail.com)"
        )
    }

    func testBundledGeminiAutomationRunnerBuildsStartupStatsFallbackCommand() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = mod._test.buildStartupStatsFallbackCommand({
            text: '/stats session',
            fallbackText: '/stats',
            fallbackUsed: false,
          });
          process.stdout.write(JSON.stringify(payload));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "startup-stats")
        XCTAssertEqual(payload["text"] as? String, "/stats")
        XCTAssertEqual(payload["fallbackUsed"] as? Bool, true)
    }

    func testBundledGeminiAutomationRunnerSkipsProModelsAfterFreeTierPolicyBanner() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let chain = [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview",
            "gemini-2.5-pro",
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite",
        ]
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedChain = String(data: try JSONEncoder().encode(chain), encoding: .utf8) ?? "[]"
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const chain = \(encodedChain);
          const nextIndex = mod._test.findNextEligibleModelIndexInChain(chain, 1, { avoidProModels: true });
          process.stdout.write(String(nextIndex));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "3")
    }

    func testBundledGeminiAutomationRunnerDoesNotWrapModelChainWhenPolicyRestricted() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let chain = [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview",
            "gemini-2.5-pro",
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite",
        ]
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedChain = String(data: try JSONEncoder().encode(chain), encoding: .utf8) ?? "[]"
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const chain = \(encodedChain);
          const nextIndex = mod._test.findNextEligibleModelIndexInChain(chain, 4, { avoidProModels: true });
          process.stdout.write(String(nextIndex));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "-1")
    }

    func testBundledGeminiAutomationRunnerDetectsModelManageRoutingMenu() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let sample = """
        Select your Gemini CLI model.
        1. Auto (Gemini 3)
           Let Gemini CLI decide the best model for the task: gemini-3-pro-preview, gemini-3-flash-preview
        2. Auto (Gemini 2.5)
           Let Gemini CLI decide the best model for the task: gemini-2.5-pro, gemini-2.5-flash
        ● 3. Manual (gemini-3-flash-preview)
           Manually select a model
        Remember model for future sessions
        """

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedSample = String(data: try JSONEncoder().encode(sample), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const snapshot = mod._test.detectSnapshotFromText(\(encodedSample), "sample");
          process.stdout.write(JSON.stringify(snapshot));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "model_manage_routing")
        XCTAssertEqual(payload["targetOptionText"] as? String, "3")
    }

    func testBundledGeminiAutomationRunnerDetectsModelManageModelListMenu() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let sample = """
        Manual
        1. gemini-3-pro-preview
        2. gemini-3-flash-preview
        ● 3. gemini-2.5-pro
        4. gemini-2.5-flash
        5. gemini-2.5-flash-lite
        Remember model for future sessions
        """

        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedSample = String(data: try JSONEncoder().encode(sample), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const snapshot = mod._test.detectSnapshotFromText(\(encodedSample), "sample");
          process.stdout.write(JSON.stringify(snapshot));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "model_manage_models")
        let options = payload["modelOptions"] as? [[String: Any]]
        XCTAssertTrue(options?.contains(where: { $0["canonical"] as? String == "gemini-2.5-flash" }) == true)
    }

    func testBundledGeminiAutomationRunnerRecoversTimedOutModelManageFlowWithDirectSwitchWhenPromptVisible() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const action = mod._test.resolvePendingModelManageRecoveryAction({
            pendingKind: "model-manage-open",
            snapshotKind: "normal",
            chatPromptActive: true,
            authWaiting: false,
            elapsedMs: 8500,
            timeoutMs: 8000,
          });
          process.stdout.write(JSON.stringify({ action }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(payload["action"] as? String, "direct-switch")
    }

    func testBundledGeminiAutomationRunnerRecoversTimedOutModelManageFlowByRelaunchWhenPromptIsBlocked() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const action = mod._test.resolvePendingModelManageRecoveryAction({
            pendingKind: "model-manage-open",
            snapshotKind: "usage_limit",
            chatPromptActive: false,
            authWaiting: true,
            elapsedMs: 15000,
            timeoutMs: 8000,
          });
          process.stdout.write(JSON.stringify({ action }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(payload["action"] as? String, "relaunch-target")
    }

    func testBundledGeminiAutomationRunnerIgnoresTransientSighupDuringRestartWindow() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const ignore = mod._test.shouldIgnoreProcessSighupForState({
            shuttingDown: false,
            hasActiveSession: false,
            hasTransitioningAction: false,
            lastChildExitAt: 1000,
            now: 2000,
            graceMs: 1500,
          });
          process.stdout.write(JSON.stringify({ ignore }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(payload["ignore"] as? Bool, true)
    }

    func testBundledGeminiAutomationRunnerDoesNotIgnoreSighupOutsideRestartWindow() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const ignore = mod._test.shouldIgnoreProcessSighupForState({
            shuttingDown: false,
            hasActiveSession: false,
            hasTransitioningAction: false,
            lastChildExitAt: 1000,
            now: 5000,
            graceMs: 1500,
          });
          process.stdout.write(JSON.stringify({ ignore }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(payload["ignore"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerTreatsRestartAndFinishAsTransitioningActions() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = {
            restart: mod._test.isTransitioningPlannedAction("restart"),
            finish: mod._test.isTransitioningPlannedAction("finish"),
            none: mod._test.isTransitioningPlannedAction(""),
          };
          process.stdout.write(JSON.stringify(payload));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let snapshotData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(payload["restart"] as? Bool, true)
        XCTAssertEqual(payload["finish"] as? Bool, true)
        XCTAssertEqual(payload["none"] as? Bool, false)
    }

    func testGeminiAutoModelModeBuildCommandPromotesDirectWrapperToAutomationRunner() throws {
        let builder = CommandBuilder()
        var settings = AppSettings()
        settings.defaultGeminiRunnerPath = "/bin/echo"
        settings.defaultNodeExecutable = "/bin/echo"

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .stable
        profile.geminiLaunchMode = .directWrapper
        profile.geminiWrapperCommand = "/bin/echo"
        profile.geminiAutomationRunnerPath = "/bin/echo"
        profile.nodeExecutable = "/bin/echo"
        profile.workingDirectory = "/tmp"
        profile.geminiInitialModel = "gemini-2.5-pro"
        profile.geminiModelChain = "gemini-2.5-pro,gemini-2.5-flash"

        let command = try builder.buildCommand(profile: profile, settings: settings)

        XCTAssertTrue(command.contains("MODEL_CHAIN='gemini-2.5-pro,gemini-2.5-flash'"))
        XCTAssertTrue(command.contains("'/bin/echo' '/bin/echo'"))
        XCTAssertFalse(command.contains("--model 'gemini-2.5-pro'"))
    }

    func testGeminiFireAndForgetBuildCommandCarriesInitialPromptIntoRunnerEnvironment() throws {
        let builder = CommandBuilder()
        var settings = AppSettings()
        settings.defaultGeminiRunnerPath = "/bin/echo"
        settings.defaultNodeExecutable = "/bin/echo"

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.workingDirectory = "/tmp"
        profile.geminiLaunchMode = .automationRunner
        profile.geminiWrapperCommand = "/bin/echo"
        profile.nodeExecutable = "/bin/echo"
        profile.geminiAutomationRunnerPath = "/bin/echo"

        profile.configureGeminiFireAndForget(prompt: "Ship 'beta' now")
        let command = try builder.buildCommand(profile: profile, settings: settings)

        XCTAssertTrue(command.contains("GEMINI_INITIAL_PROMPT='Ship '\\''beta'\\'' now'"))
        XCTAssertTrue(command.contains("AUTO_CONTINUE_MODE='always'"))
        XCTAssertTrue(command.contains("'/bin/echo' '/bin/echo'"))
    }

    func testGeminiDirectWrapperPromptInjectionBuildCommandUsesAutomationRunner() throws {
        let builder = CommandBuilder()
        var settings = AppSettings()
        settings.defaultGeminiRunnerPath = "/bin/echo"
        settings.defaultNodeExecutable = "/bin/echo"

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .stable
        profile.geminiLaunchMode = .directWrapper
        profile.geminiModelMode = .fixed
        profile.geminiWrapperCommand = "/bin/echo"
        profile.geminiAutomationRunnerPath = "/bin/echo"
        profile.nodeExecutable = "/bin/echo"
        profile.workingDirectory = "/tmp"
        profile.geminiInitialModel = "gemini-2.5-flash"
        profile.geminiInitialPrompt = "Ship 'beta' now"
        profile.geminiResumeLatest = true

        let command = try builder.buildCommand(profile: profile, settings: settings)

        XCTAssertTrue(command.contains("GEMINI_INITIAL_PROMPT='Ship '\\''beta'\\'' now'"))
        XCTAssertTrue(command.contains("RESUME_LATEST='0'"))
        XCTAssertTrue(command.contains("MODEL_CHAIN='"))
        XCTAssertTrue(command.contains("'/bin/echo' '/bin/echo'"))
        XCTAssertFalse(command.contains("--resume latest"))
        XCTAssertFalse(command.contains("--prompt-interactive 'Ship '\\''beta'\\'' now'"))
    }

    func testGeminiPromptLaunchFailsWhenAutomationRunnerIsMissing() throws {
        let builder = CommandBuilder()
        var settings = AppSettings()
        settings.defaultNodeExecutable = "/bin/echo"

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiLaunchMode = .directWrapper
        profile.geminiWrapperCommand = "/bin/echo"
        profile.nodeExecutable = "/bin/echo"
        profile.workingDirectory = "/tmp"
        profile.geminiInitialPrompt = "Ship beta now"
        profile.geminiAutomationRunnerPath = "/tmp/missing-gemini-automation-runner-\(UUID().uuidString).mjs"

        XCTAssertThrowsError(try builder.buildCommand(profile: profile, settings: settings)) { error in
            let message = (error as? LauncherError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("Gemini automation runner was not found"), message)
            XCTAssertTrue(message.contains("/clear"), message)
            XCTAssertTrue(message.contains("/stats"), message)
        }
    }

    func testGeminiDescriptionUsesEffectiveLaunchModeForAutoModelSwitching() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .stable
        profile.geminiLaunchMode = .directWrapper
        profile.geminiModelMode = .auto

        XCTAssertEqual(builder.descriptionForProfile(profile), "Gemini • Automation runner")
    }

    func testGeminiFireAndForgetPrefersWorkspaceGeminiBinaryForAutomationTarget() throws {
        let builder = CommandBuilder()
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let binURL = workspaceURL.appendingPathComponent("node_modules/.bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let geminiURL = binURL.appendingPathComponent("gemini")
        try makeExecutable(at: geminiURL)

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .stable
        profile.geminiWrapperCommand = GeminiFlavor.preview.wrapperName
        profile.workingDirectory = workspaceURL.path
        profile.geminiLaunchMode = .automationRunner
        profile.configureGeminiFireAndForget(prompt: "Ship it")

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(environment["GEMINI_WRAPPER"], geminiURL.path)
    }

    func testGeminiAutoModelModePrefersWorkspaceGeminiBinaryForPromptAutomationTarget() throws {
        let builder = CommandBuilder()
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let binURL = workspaceURL.appendingPathComponent("node_modules/.bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let geminiURL = binURL.appendingPathComponent("gemini")
        try makeExecutable(at: geminiURL)

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .stable
        profile.geminiLaunchMode = .directWrapper
        profile.geminiModelMode = .auto
        profile.geminiWrapperCommand = GeminiFlavor.preview.wrapperName
        profile.workingDirectory = workspaceURL.path
        profile.configureGeminiPromptInjection(prompt: "Ship it")

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(environment["GEMINI_WRAPPER"], geminiURL.path)
    }

    func testLegacyStableGeminiIsoProfilesPreferGeminiStableWrapperWhenAvailable() throws {
        let builder = CommandBuilder()
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let binURL = workspaceURL.appendingPathComponent("node_modules/.bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let stableWrapperURL = binURL.appendingPathComponent("gemini-stable")
        let legacyWrapperURL = binURL.appendingPathComponent("gemini-iso")
        try makeExecutable(at: stableWrapperURL)
        try makeExecutable(at: legacyWrapperURL)

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .stable
        profile.geminiWrapperCommand = "gemini-iso"
        profile.workingDirectory = workspaceURL.path

        let resolution = builder.resolveGeminiWrapper(profile: profile, workingDirectory: workspaceURL.path)

        XCTAssertEqual(resolution.resolved, stableWrapperURL.path)
    }

    func testGeminiNightlyFireAndForgetPrefersNightlyDirectBinaryForAutomationTarget() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .nightly
        profile.geminiLaunchMode = .automationRunner
        profile.geminiWrapperCommand = GeminiFlavor.nightly.wrapperName
        profile.configureGeminiFireAndForget(prompt: "Ship it")

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())
        let resolvedWrapper = environment["GEMINI_WRAPPER"] ?? ""

        XCTAssertEqual(
            resolvedWrapper,
            GeminiFlavor.nightly.directExecutableCandidates.first.map { NSString(string: $0).expandingTildeInPath }
        )
    }

    func testGeminiFireAndForgetPreservesExplicitCustomWrapperCommand() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .stable
        profile.geminiLaunchMode = .automationRunner
        profile.geminiWrapperCommand = "/bin/echo"
        profile.configureGeminiFireAndForget(prompt: "Ship it")

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(environment["GEMINI_WRAPPER"], "/bin/echo")
    }
}

final class CodexCommandBuilderTests: XCTestCase {
    func testCodexSuggestModeUsesReadOnlySandboxArguments() throws {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .codex
        profile.codexExecutable = "/bin/echo"
        profile.codexMode = .suggest
        profile.codexModel = "gpt-5"
        profile.workingDirectory = "/tmp"

        let result = try builder.buildCommand(profile: profile, settings: AppSettings())

        XCTAssertTrue(result.contains("'/bin/echo'"))
        XCTAssertTrue(result.contains("-s 'read-only'"))
        XCTAssertTrue(result.contains("-a 'untrusted'"))
        XCTAssertTrue(result.contains("-m 'gpt-5'"))
        XCTAssertFalse(result.contains("--suggest"))
    }

    func testCodexAutoEditModeUsesWorkspaceWriteSandboxArguments() throws {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .codex
        profile.codexExecutable = "/bin/echo"
        profile.codexMode = .autoEdit
        profile.workingDirectory = "/tmp"

        let result = try builder.buildCommand(profile: profile, settings: AppSettings())

        XCTAssertTrue(result.contains("'/bin/echo'"))
        XCTAssertTrue(result.contains("-s 'workspace-write'"))
        XCTAssertTrue(result.contains("-a 'untrusted'"))
        XCTAssertFalse(result.contains("--auto-edit"))
    }

    func testCodexFullAutoModeUsesSupportedFlag() throws {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .codex
        profile.codexExecutable = "/bin/echo"
        profile.codexMode = .fullAuto
        profile.workingDirectory = "/tmp"

        let result = try builder.buildCommand(profile: profile, settings: AppSettings())

        XCTAssertTrue(result.contains("'/bin/echo' --full-auto"))
        XCTAssertFalse(result.contains("--suggest"))
        XCTAssertFalse(result.contains("--auto-edit"))
    }
}

final class ToolDiscoveryServiceTests: XCTestCase {
    private func makeExecutable(at url: URL, contents: String = "#!/bin/sh\nexit 0\n") throws {
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data(contents.utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeGeminiCLIPackage(version: String) throws -> (root: URL, executable: URL) {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let binURL = rootURL.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)

        let packageJSON = """
        {
          "name": "@google/gemini-cli",
          "version": "\(version)"
        }
        """
        try packageJSON.write(to: rootURL.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let executableURL = binURL.appendingPathComponent("gemini")
        try makeExecutable(at: executableURL)
        return (rootURL, executableURL)
    }

    func testGeminiDiscoveryIncludesUpdateCommandMetadata() {
        let discovery = ToolDiscoveryService()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path

        let result = discovery.inspect(profile: profile, settings: AppSettings())

        let geminiStatus = result.statuses.first { $0.name == "Gemini wrapper" }
        XCTAssertNotNil(geminiStatus)
        XCTAssertEqual(geminiStatus?.updateCommand, "npm install -g --prefix ~/.local/gemini-preview @google/gemini-cli@preview")
        XCTAssertEqual(geminiStatus?.installDocumentation, "https://github.com/google-gemini/gemini-cli")
        XCTAssertEqual(geminiStatus?.providerRiskLevel, .low)
    }

    func testGeminiResolvedUpdateCommandVariesByFlavor() {
        var profile = LaunchProfile()
        profile.agentKind = .gemini

        profile.geminiFlavor = .stable
        XCTAssertEqual(profile.resolvedUpdateCommand, "npm install -g --prefix ~/.local/gemini-stable @google/gemini-cli@latest")

        profile.geminiFlavor = .preview
        XCTAssertEqual(profile.resolvedUpdateCommand, "npm install -g --prefix ~/.local/gemini-preview @google/gemini-cli@preview")

        profile.geminiFlavor = .nightly
        XCTAssertEqual(profile.resolvedUpdateCommand, "npm install -g --prefix ~/.local/gemini-nightly @google/gemini-cli@nightly")
    }

    func testStableGeminiFlavorDefaultsUseDedicatedStableWrapperAndDirectBinary() {
        XCTAssertEqual(GeminiFlavor.stable.wrapperName, "gemini-stable")
        XCTAssertEqual(
            GeminiFlavor.stable.directExecutableCandidates.first,
            "~/.local/gemini-stable/bin/gemini"
        )
        XCTAssertTrue(GeminiFlavor.stable.wrapperAliasNames.contains("gemini-iso"))
    }

    func testGeminiDiscoveryReportsKnownBadGeminiCLIVersionCompatibilityWarning() throws {
        let discovery = ToolDiscoveryService()
        let package = try makeGeminiCLIPackage(version: "0.32.1")
        defer { try? FileManager.default.removeItem(at: package.root) }

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiWrapperCommand = package.executable.path
        profile.geminiLaunchMode = .directWrapper
        profile.workingDirectory = package.root.path

        let result = discovery.inspect(profile: profile, settings: AppSettings())
        let compatibilityStatus = try XCTUnwrap(result.statuses.first { $0.name == "Gemini CLI compatibility" })

        XCTAssertEqual(compatibilityStatus.resolved, "0.32.1")
        XCTAssertTrue(compatibilityStatus.detail.contains("Startup /clear -> /stats -> /model automation is enabled"))
        XCTAssertTrue(compatibilityStatus.detail.contains("self-update checks are disabled"))
        XCTAssertEqual(compatibilityStatus.updateCommand, "npm install -g --prefix ~/.local/gemini-preview @google/gemini-cli@preview")
        XCTAssertFalse(result.warnings.contains { $0.contains("Fire & Forget startup /stats session automation is blocked") })
    }

    func testKiroDiscoveryUsesKiroUpdateCommand() {
        let discovery = ToolDiscoveryService()
        var profile = LaunchProfile()
        profile.agentKind = .kiroCLI
        profile.workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path

        let result = discovery.inspect(profile: profile, settings: AppSettings())

        let kiroStatus = result.statuses.first { $0.name == "Kiro CLI" }
        XCTAssertNotNil(kiroStatus)
        XCTAssertEqual(kiroStatus?.updateCommand, "kiro-cli update")
        XCTAssertEqual(kiroStatus?.installDocumentation, "https://github.com/iambenf/kiro-cli")
        XCTAssertEqual(kiroStatus?.providerRiskLevel, .low)
    }

    func testClaudeDiscoveryUsesManualUpdateCommand() {
        let discovery = ToolDiscoveryService()
        var profile = LaunchProfile()
        profile.agentKind = .claudeBypass
        profile.workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path

        let result = discovery.inspect(profile: profile, settings: AppSettings())

        let claudeStatus = result.statuses.first { $0.name == "Claude Code" }
        XCTAssertNotNil(claudeStatus)
        XCTAssertEqual(claudeStatus?.updateCommand, "claude update")
        XCTAssertEqual(claudeStatus?.installDocumentation, "https://docs.anthropic.com/en/docs/claude-code")
        XCTAssertEqual(claudeStatus?.providerRiskLevel, .medium)
    }

    func testOllamaDiscoveryDoesNotExposeCliUpdateCommand() {
        let discovery = ToolDiscoveryService()
        var profile = LaunchProfile()
        profile.agentKind = .ollamaLaunch
        profile.workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path

        let result = discovery.inspect(profile: profile, settings: AppSettings())

        let ollamaStatus = result.statuses.first { $0.name == "Ollama Launch" }
        XCTAssertNotNil(ollamaStatus)
        XCTAssertNil(ollamaStatus?.updateCommand)
        XCTAssertEqual(ollamaStatus?.installDocumentation, "https://ollama.com")
    }

    func testWorkbenchPreflightPreservesUpdateCommandMetadata() {
        let preflight = PreflightService()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.name = "Gemini Preview"
        profile.workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path

        let workbench = LaunchWorkbench(name: "WB", role: .coding, profileIDs: [profile.id])
        let result = preflight.run(workbench: workbench, profiles: [profile], bookmarks: [], settings: AppSettings())

        let geminiStatus = result.statuses.first { $0.name == "Gemini Preview • Gemini wrapper" }
        XCTAssertNotNil(geminiStatus)
        XCTAssertEqual(geminiStatus?.updateCommand, "npm install -g --prefix ~/.local/gemini-preview @google/gemini-cli@preview")
        XCTAssertEqual(geminiStatus?.installDocumentation, "https://github.com/google-gemini/gemini-cli")
        XCTAssertEqual(geminiStatus?.providerRiskLevel, .low)
    }

    func testWorkbenchPreflightPreservesGeminiCompatibilityStatusAndWarning() throws {
        let preflight = PreflightService()
        let package = try makeGeminiCLIPackage(version: "0.32.1")
        defer { try? FileManager.default.removeItem(at: package.root) }

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.name = "Gemini Preview"
        profile.geminiWrapperCommand = package.executable.path
        profile.geminiLaunchMode = .directWrapper
        profile.workingDirectory = package.root.path

        let workbench = LaunchWorkbench(name: "WB", role: .coding, profileIDs: [profile.id])
        let result = preflight.run(workbench: workbench, profiles: [profile], bookmarks: [], settings: AppSettings())

        let compatibilityStatus = result.statuses.first { $0.name == "Gemini Preview • Gemini CLI compatibility" }
        XCTAssertNotNil(compatibilityStatus)
        XCTAssertEqual(compatibilityStatus?.resolved, "0.32.1")
        XCTAssertEqual(compatibilityStatus?.updateCommand, "npm install -g --prefix ~/.local/gemini-preview @google/gemini-cli@preview")
        XCTAssertTrue(compatibilityStatus?.detail.contains("Startup /clear -> /stats -> /model automation is enabled") == true)
        XCTAssertTrue(compatibilityStatus?.detail.contains("self-update checks are disabled") == true)
        XCTAssertFalse(result.warnings.contains { $0.contains("Fire & Forget startup /stats session automation is blocked") })
    }

    func testGeminiDiscoveryReportsPythonPtyFallbackWhenWorkspaceHasNoPtyModule() throws {
        let discovery = ToolDiscoveryService()
        let builder = CommandBuilder()
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        guard builder.resolveExecutable("python3", workingDirectory: workspaceURL.path).resolved != nil else {
            throw XCTSkip("python3 is not available in this test environment.")
        }

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.workingDirectory = workspaceURL.path
        profile.geminiLaunchMode = .automationRunner

        let result = discovery.inspect(profile: profile, settings: AppSettings())
        let ptyStatus = try XCTUnwrap(result.statuses.first { $0.name == "Gemini PTY backend" })

        XCTAssertEqual(ptyStatus.resolved, "python3 PTY bridge")
        XCTAssertTrue(ptyStatus.detail.contains("python3"))
    }

    func testGeminiDiscoveryUsesEffectiveAutomationRunnerModeForAutoModelSwitching() {
        let discovery = ToolDiscoveryService()
        var settings = AppSettings()
        settings.defaultGeminiRunnerPath = "/bin/echo"
        settings.defaultNodeExecutable = "/bin/echo"

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .stable
        profile.geminiLaunchMode = .directWrapper
        profile.geminiModelMode = .auto
        profile.geminiWrapperCommand = "/bin/echo"
        profile.geminiAutomationRunnerPath = "/bin/echo"
        profile.nodeExecutable = "/bin/echo"
        profile.workingDirectory = "/tmp"

        let result = discovery.inspect(profile: profile, settings: settings)
        let runnerStatus = result.statuses.first { $0.name == "Automation runner" }
        let nodeStatus = result.statuses.first { $0.name == "Node" }

        XCTAssertNotNil(runnerStatus)
        XCTAssertEqual(runnerStatus?.resolved, "/bin/echo")
        XCTAssertEqual(runnerStatus?.detail, "Automation runner will be used.")
        XCTAssertNotNil(nodeStatus)
        XCTAssertNotEqual(nodeStatus?.detail, "Not required in direct-wrapper mode.")
    }

    func testGeminiNightlyAutoModePromotesDirectWrapperToAutomationRunner() {
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiFlavor = .nightly
        profile.geminiModelMode = .auto
        profile.geminiLaunchMode = .directWrapper

        let prepared = profile.preparedForLaunch()
        let cautions = prepared.agentKind.defaultCautionMessages(for: prepared)

        XCTAssertEqual(prepared.geminiLaunchMode, .automationRunner)
        XCTAssertFalse(cautions.contains { $0.contains("Auto model switching is unavailable") })
    }
}
