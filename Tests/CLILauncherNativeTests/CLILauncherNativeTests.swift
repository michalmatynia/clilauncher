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

    func testExtractGeminiSessionStatsBlockedReasonParsesUnavailableRunnerBanner() {
        let transcript = """
        [gemini-preview-pty] Startup session stats: unavailable (startup /stats output was not detected in time) — continuing startup telemetry.
        [gemini-preview-pty] Auto-sending initial prompt (visible prompt field)...
        """

        let reason = TerminalMonitorStore.extractGeminiSessionStatsBlockedReason(fromTranscriptText: transcript)

        XCTAssertEqual(reason, "startup /stats output was not detected in time")
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

    func testExtractGeminiAccountChangeDetectedParsesRunnerBanner() {
        let transcript = """
        [gemini-preview-pty] Account change detected: authentication succeeded; restarting Gemini CLI without startup /clear.
        [gemini-preview-pty] Account change telemetry: running /stats -> /model without startup /clear.
        """

        XCTAssertTrue(TerminalMonitorStore.extractGeminiAccountChangeDetected(fromTranscriptText: transcript))
    }

    func testExtractGeminiLaunchContextParsesRunnerBanner() {
        let transcript = """
        [gemini-preview-pty] Gemini CLI version: 0.32.1
        [gemini-preview-pty] Runner path: /Applications/CLILauncher.app/Contents/Resources/gemini-automation-runner.mjs
        [gemini-preview-pty] Runner build: 20260425T192100Z
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
        XCTAssertEqual(snapshot?.runnerBuild, "20260425T192100Z")
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
            providerRunnerBuild: "20260425T192100Z",
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
        XCTAssertEqual(updated.providerRunnerBuild, "20260425T192100Z")
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
            provider_runner_build: "20260425T192100Z",
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
        XCTAssertEqual(session.providerRunnerBuild, "20260425T192100Z")
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
        session.providerRunnerBuild = "20260426T090000Z"
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
                sessionRunnerBuild: "20260425T192100Z",
                bundledRunnerBuild: "20260425T192100Z"
            ),
            "Matches bundled app runner"
        )
        XCTAssertEqual(
            MonitoringDashboardView.geminiRunnerBuildStatusText(
                sessionRunnerBuild: "20260423T000000Z",
                bundledRunnerBuild: "20260425T192100Z"
            ),
            "Differs from bundled app runner (20260425T192100Z)"
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
        settings.launchCenterFireAndForgetPrompt = "lint features and fix"
        settings.launchCenterFireAndForgetSupportingPrompt = "continue refactor"
        settings.launchCenterFireAndForgetRecoveryPrompt = "continue to next refactor"
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
        XCTAssertEqual(persisted.settings.launchCenterFireAndForgetPrompt, "lint features and fix")
        XCTAssertEqual(persisted.settings.launchCenterFireAndForgetSupportingPrompt, "continue refactor")
        XCTAssertEqual(persisted.settings.launchCenterFireAndForgetRecoveryPrompt, "continue to next refactor")
        XCTAssertTrue(persisted.settings.mongoMonitoring.enabled)
        XCTAssertFalse(persisted.settings.observability.persistLogsToDisk)
    }

    func testStateChangesDoNotPersistBeforeExplicitSave() throws {
        let store = ProfileStore(persistenceMode: .fileOnly)
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let stateURL = tempDirectory.appendingPathComponent("state.json")
        store.setStateURLForTesting(stateURL)

        var settings = store.settings
        settings.launchCenterFireAndForgetPrompt = "draft prompt"
        store.settings = settings
        store.recordLaunch(
            profile: LaunchProfile(),
            plan: PlannedLaunch(
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
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))

        store.save()

        let data = try Data(contentsOf: stateURL)
        let persisted = try JSONDecoder.pretty.decode(PersistedState.self, from: data)
        XCTAssertEqual(persisted.settings.launchCenterFireAndForgetPrompt, "draft prompt")
        XCTAssertEqual(persisted.history.first?.command, "gemini")
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

    func testResolvedGeminiSupportingPromptUsesLaunchCenterOverrideOrDefault() {
        XCTAssertEqual(
            ContentView.resolvedGeminiSupportingPrompt(
                launchCenterPrompt: "  continue refactor  ",
                profilePrompt: "continue"
            ),
            "continue refactor"
        )
        XCTAssertEqual(
            ContentView.resolvedGeminiSupportingPrompt(
                launchCenterPrompt: "   ",
                profilePrompt: "   "
            ),
            "continue"
        )
    }

    func testLaunchCenterPromptDisplayTextPrefersPersistedPromptOverProfilePrompt() {
        var settings = AppSettings()
        settings.launchCenterFireAndForgetPrompt = "lint features and fix"

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiInitialPrompt = "profile prompt"

        XCTAssertEqual(
            ContentView.launchCenterPromptDisplayText(settings: settings, profile: profile),
            "lint features and fix"
        )

        settings.launchCenterFireAndForgetPrompt = "   "
        XCTAssertEqual(
            ContentView.launchCenterPromptDisplayText(settings: settings, profile: profile),
            "profile prompt"
        )
    }

    func testLaunchCenterSupportingPromptDisplayTextPrefersPersistedPromptOverProfilePrompt() {
        var settings = AppSettings()
        settings.launchCenterFireAndForgetSupportingPrompt = "continue refactor"

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiSupportingPrompt = "continue"

        XCTAssertEqual(
            ContentView.launchCenterSupportingPromptDisplayText(settings: settings, profile: profile),
            "continue refactor"
        )

        settings.launchCenterFireAndForgetSupportingPrompt = "   "
        XCTAssertEqual(
            ContentView.launchCenterSupportingPromptDisplayText(settings: settings, profile: profile),
            "continue"
        )
    }

    func testLaunchCenterRecoveryPromptDisplayTextPrefersPersistedPromptOverProfilePrompt() {
        var settings = AppSettings()
        settings.launchCenterFireAndForgetRecoveryPrompt = "continue to next domain"

        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiRecoveryPrompt = "continue to next refactor"

        XCTAssertEqual(
            ContentView.launchCenterRecoveryPromptDisplayText(settings: settings, profile: profile),
            "continue to next domain"
        )

        settings.launchCenterFireAndForgetRecoveryPrompt = "   "
        XCTAssertEqual(
            ContentView.launchCenterRecoveryPromptDisplayText(settings: settings, profile: profile),
            "continue to next refactor"
        )
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

    func testSupportingPromptDisplayTextUsesStoredGeminiPromptOnlyForGeminiProfiles() {
        var geminiProfile = LaunchProfile()
        geminiProfile.agentKind = .gemini
        geminiProfile.geminiSupportingPrompt = "  continue refactor  "

        var codexProfile = LaunchProfile()
        codexProfile.agentKind = .codex

        XCTAssertEqual(ContentView.supportingPromptDisplayText(for: geminiProfile), "continue refactor")
        XCTAssertEqual(ContentView.supportingPromptDisplayText(for: codexProfile), "")
        XCTAssertEqual(ContentView.supportingPromptDisplayText(for: nil), "")
    }

    func testRecoveryPromptDisplayTextUsesStoredGeminiPromptOnlyForGeminiProfiles() {
        var geminiProfile = LaunchProfile()
        geminiProfile.agentKind = .gemini
        geminiProfile.geminiRecoveryPrompt = "  continue to next refactor  "

        var codexProfile = LaunchProfile()
        codexProfile.agentKind = .codex

        XCTAssertEqual(ContentView.recoveryPromptDisplayText(for: geminiProfile), "continue to next refactor")
        XCTAssertEqual(ContentView.recoveryPromptDisplayText(for: codexProfile), "")
        XCTAssertEqual(ContentView.recoveryPromptDisplayText(for: nil), "")
    }

    func testResolvedGeminiRecoveryPromptUsesLaunchCenterOverrideOrDefault() {
        XCTAssertEqual(
            ContentView.resolvedGeminiRecoveryPrompt(
                launchCenterPrompt: "  continue to next domain  ",
                profilePrompt: "continue to next refactor"
            ),
            "continue to next domain"
        )
        XCTAssertEqual(
            ContentView.resolvedGeminiRecoveryPrompt(
                launchCenterPrompt: "   ",
                profilePrompt: "   "
            ),
            "continue to next refactor"
        )
    }

    func testQuickLaunchFavoriteProfilesOnlyReturnsFavorites() {
        var favoriteGemini = LaunchProfile()
        favoriteGemini.name = "Gemini Favorite"
        favoriteGemini.isFavorite = true

        var regularCodex = LaunchProfile()
        regularCodex.name = "Codex Regular"
        regularCodex.agentKind = .codex
        regularCodex.isFavorite = false

        var favoriteAider = LaunchProfile()
        favoriteAider.name = "Aider Favorite"
        favoriteAider.agentKind = .aider
        favoriteAider.isFavorite = true

        let favorites = ContentView.quickLaunchFavoriteProfiles(from: [
            favoriteGemini,
            regularCodex,
            favoriteAider
        ])

        XCTAssertEqual(favorites.map(\.id), [favoriteGemini.id, favoriteAider.id])
    }

    func testQuickLaunchModelDisplayTextUsesProfileModel() {
        var geminiProfile = LaunchProfile()
        geminiProfile.agentKind = .gemini
        geminiProfile.geminiModelMode = .fixed
        geminiProfile.geminiInitialModel = "  gemini-3-flash-preview  "

        var aiderProfile = LaunchProfile()
        aiderProfile.agentKind = .aider
        aiderProfile.aiderModel = "openrouter/anthropic/claude-sonnet-4.5"

        XCTAssertEqual(ContentView.quickLaunchModelDisplayText(for: geminiProfile), "gemini-3-flash-preview")
        XCTAssertEqual(ContentView.quickLaunchModelDisplayText(for: aiderProfile), "openrouter/anthropic/claude-sonnet-4.5")
    }

    func testQuickLaunchModelDisplayTextShowsAutoForGeminiAutoMode() {
        var geminiProfile = LaunchProfile()
        geminiProfile.agentKind = .gemini
        geminiProfile.geminiModelMode = .auto
        geminiProfile.geminiInitialModel = "gemini-3-pro-preview"

        XCTAssertEqual(ContentView.quickLaunchModelDisplayText(for: geminiProfile), "Auto model")
    }

    func testQuickLaunchModelDisplayTextFallsBackForBlankModel() {
        var codexProfile = LaunchProfile()
        codexProfile.agentKind = .codex
        codexProfile.codexModel = "   "

        XCTAssertEqual(ContentView.quickLaunchModelDisplayText(for: codexProfile), "Default model")
    }

    func testResolvedQuickLaunchFavoriteProfileUsesSelectedWorkspaceForGenericGeminiFavorite() {
        var selectedProfile = LaunchProfile()
        selectedProfile.name = "Gemini"
        selectedProfile.agentKind = .gemini
        selectedProfile.geminiFlavor = .stable
        selectedProfile.workingDirectory = "/tmp/geminitestapp"
        selectedProfile.geminiModelMode = .auto

        var previewFavorite = LaunchProfile()
        previewFavorite.name = GeminiFlavor.preview.displayName
        previewFavorite.agentKind = .gemini
        previewFavorite.geminiFlavor = .preview
        previewFavorite.workingDirectory = "/tmp/clilauncher"
        previewFavorite.geminiModelMode = .fixed

        let resolved = ContentView.resolvedQuickLaunchFavoriteProfile(
            favoriteProfile: previewFavorite,
            selectedProfile: selectedProfile
        )

        XCTAssertEqual(resolved.id, previewFavorite.id)
        XCTAssertEqual(resolved.geminiFlavor, .preview)
        XCTAssertEqual(resolved.workingDirectory, "/tmp/geminitestapp")
        XCTAssertEqual(resolved.geminiModelMode, .auto)
    }

    func testResolvedQuickLaunchFavoriteProfileUsesSelectedWorkspaceForCustomGeminiFavorite() {
        var selectedProfile = LaunchProfile()
        selectedProfile.name = "Gemini"
        selectedProfile.agentKind = .gemini
        selectedProfile.geminiFlavor = .stable
        selectedProfile.workingDirectory = "/tmp/geminitestapp"
        selectedProfile.geminiModelMode = .fixed

        var previewFavorite = LaunchProfile()
        previewFavorite.name = "Preview Review Workspace"
        previewFavorite.agentKind = .gemini
        previewFavorite.geminiFlavor = .preview
        previewFavorite.workingDirectory = "/tmp/review-workspace"
        previewFavorite.geminiModelMode = .auto

        let resolved = ContentView.resolvedQuickLaunchFavoriteProfile(
            favoriteProfile: previewFavorite,
            selectedProfile: selectedProfile
        )

        XCTAssertEqual(resolved.workingDirectory, "/tmp/geminitestapp")
        XCTAssertEqual(resolved.geminiModelMode, .fixed)
    }

    func testResolvedQuickLaunchFavoriteProfileKeepsFavoriteModelModeWhenSelectedProfileIsNotGemini() {
        var selectedProfile = LaunchProfile()
        selectedProfile.name = "Codex"
        selectedProfile.agentKind = .codex
        selectedProfile.workingDirectory = "/tmp/current-app"

        var previewFavorite = LaunchProfile()
        previewFavorite.name = GeminiFlavor.preview.displayName
        previewFavorite.agentKind = .gemini
        previewFavorite.geminiFlavor = .preview
        previewFavorite.workingDirectory = "/tmp/stale-app"
        previewFavorite.geminiModelMode = .auto

        let resolved = ContentView.resolvedQuickLaunchFavoriteProfile(
            favoriteProfile: previewFavorite,
            selectedProfile: selectedProfile
        )

        XCTAssertEqual(resolved.workingDirectory, "/tmp/current-app")
        XCTAssertEqual(resolved.geminiModelMode, .auto)
    }

    func testProfileDirtyComparisonIgnoresNormalizationOnlyDifferences() {
        var settings = AppSettings()
        var environmentPreset = EnvironmentPreset()
        environmentPreset.name = "Shared Env"
        settings.environmentPresets = [environmentPreset]

        var selectedProfile = LaunchProfile()
        selectedProfile.agentKind = .gemini
        selectedProfile.name = GeminiFlavor.preview.displayName
        selectedProfile.geminiAutomationRunnerPath = BundledGeminiAutomationRunner.defaultPath
        selectedProfile.environmentPresetID = environmentPreset.id

        var draft = selectedProfile
        draft.geminiAutomationRunnerPath = " "
        draft.companionProfileIDs = [draft.id, UUID(), draft.id]
        draft.bootstrapPresetID = UUID()

        XCTAssertTrue(
            ContentView.profilesMatchForEditorDirtyState(
                draft,
                selectedProfile,
                settings: settings,
                allProfiles: [selectedProfile]
            )
        )
    }

    func testProfileDirtyComparisonKeepsRealEditsDirty() {
        let settings = AppSettings()
        var selectedProfile = LaunchProfile()
        selectedProfile.agentKind = .gemini
        selectedProfile.geminiInitialModel = "gemini-3-flash-preview"

        var draft = selectedProfile
        draft.geminiInitialModel = "gemini-2.5-flash"

        XCTAssertFalse(
            ContentView.profilesMatchForEditorDirtyState(
                draft,
                selectedProfile,
                settings: settings,
                allProfiles: [selectedProfile]
            )
        )
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

    func testGeminiEnvironmentStartsModelChainAtInitialModel() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiModelChain = "gemini-2.5-pro,gemini-1.5-flash,gemini-flash"
        profile.geminiInitialModel = "gemini-1.5-flash"

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(
            environment["MODEL_CHAIN"],
            "gemini-1.5-flash,gemini-flash"
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

    func testGeminiEnvironmentIncludesSupportingPromptOverride() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiSupportingPrompt = "  continue refactor  "
        profile.geminiRecoveryPrompt = "  continue to next refactor  "

        var environment = builder.buildEnvironment(profile: profile, settings: AppSettings())
        XCTAssertEqual(environment["CONTINUE_COMMAND"], "continue refactor")
        XCTAssertEqual(environment["CONTINUE_FALLBACK_COMMAND"], "continue to next refactor")

        profile.geminiSupportingPrompt = "   "
        profile.geminiRecoveryPrompt = "   "
        environment = builder.buildEnvironment(profile: profile, settings: AppSettings())
        XCTAssertEqual(environment["CONTINUE_COMMAND"], "continue")
        XCTAssertEqual(environment["CONTINUE_FALLBACK_COMMAND"], "continue to next refactor")
    }

    func testGeminiEnvironmentIncludesModelChainExhaustedAction() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiModelChainExhaustedAction = .keepOpen

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(environment["MODEL_CHAIN_EXHAUSTED_ACTION"], "keep_open")
    }

    func testGeminiEnvironmentMarksAutoModelModeForRunner() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiModelMode = .auto

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(environment["GEMINI_MODEL_AUTO"], "1")
        XCTAssertEqual(environment["GEMINI_AUTO_MODEL"], "auto")
    }

    func testGeminiEnvironmentMarksFixedModelModeForRunner() {
        let builder = CommandBuilder()
        var profile = LaunchProfile()
        profile.agentKind = .gemini
        profile.geminiModelMode = .fixed

        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(environment["GEMINI_MODEL_AUTO"], "0")
    }

    func testGeminiFixedModelModeRetainsFallbackChainForEveryFlavor() {
        let builder = CommandBuilder()

        for flavor in GeminiFlavor.allCases {
            var profile = LaunchProfile()
            profile.agentKind = .gemini
            profile.geminiFlavor = flavor
            profile.geminiModelMode = .fixed
            profile.geminiInitialModel = "gemini-3-flash-preview"
            profile.geminiModelChain = "gemini-2.5-flash,gemini-3-flash-preview,gemini-2.5-flash-lite"
            profile.geminiAutoContinueMode = .promptOnly

            let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

            XCTAssertEqual(environment["CLI_FLAVOR"], flavor.cliFlavorValue)
            XCTAssertEqual(environment["NEVER_SWITCH"], "1")
            XCTAssertEqual(environment["GEMINI_MODEL_AUTO"], "0")
            XCTAssertNil(environment["GEMINI_AUTO_MODEL"])
            XCTAssertEqual(environment["AUTO_CONTINUE_MODE"], "prompt_only")
            XCTAssertEqual(
                environment["MODEL_CHAIN"],
                "gemini-3-flash-preview,gemini-2.5-flash-lite",
                "flavor: \(flavor.rawValue)"
            )
        }
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

        profile.configureGeminiFireAndForget(
            prompt: "  Ship the release and keep going.  ",
            supportingPrompt: "  continue refactor  ",
            recoveryPrompt: "  continue to next refactor  "
        )
        let environment = builder.buildEnvironment(profile: profile, settings: AppSettings())

        XCTAssertEqual(profile.geminiLaunchMode, .automationRunner)
        XCTAssertEqual(profile.geminiInitialPrompt, "Ship the release and keep going.")
        XCTAssertEqual(profile.geminiSupportingPrompt, "continue refactor")
        XCTAssertEqual(profile.geminiRecoveryPrompt, "continue to next refactor")
        XCTAssertFalse(profile.geminiResumeLatest)
        XCTAssertTrue(profile.geminiAutomationEnabled)
        XCTAssertTrue(profile.geminiAutoAllowSessionPermissions)
        XCTAssertEqual(profile.geminiAutoContinueMode, .yolo)
        XCTAssertTrue(profile.geminiYolo)
        XCTAssertEqual(profile.geminiKeepTryMax, 10)
        XCTAssertEqual(profile.geminiCapacityRetryMs, 500)
        XCTAssertEqual(environment["AUTO_CONTINUE_MODE"], "always")
        XCTAssertEqual(environment["CONTINUE_COMMAND"], "continue refactor")
        XCTAssertEqual(environment["CONTINUE_FALLBACK_COMMAND"], "continue to next refactor")
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

        profile.geminiSupportingPrompt = "continue refactor"
        let supportingPromptSignature = profile.launchStateSignatureToken
        XCTAssertNotEqual(supportingPromptSignature, promptSignature)

        profile.geminiRecoveryPrompt = "continue to next domain"
        let recoveryPromptSignature = profile.launchStateSignatureToken
        XCTAssertNotEqual(recoveryPromptSignature, supportingPromptSignature)

        profile.geminiYolo = true
        let yoloSignature = profile.launchStateSignatureToken
        XCTAssertNotEqual(yoloSignature, recoveryPromptSignature)

        profile.geminiSetHomeToIso = true
        let homeSignature = profile.launchStateSignatureToken
        XCTAssertNotEqual(homeSignature, yoloSignature)

        profile.geminiCapacityRetryMs += 250
        let capacitySignature = profile.launchStateSignatureToken
        XCTAssertNotEqual(capacitySignature, homeSignature)

        profile.geminiModelChainExhaustedAction = .keepOpen
        XCTAssertNotEqual(profile.launchStateSignatureToken, capacitySignature)
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

    func testBundledGeminiAutomationRunnerPrefersLatestCompleteUsageLimitMenu() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let sample = """
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │                                                                              │
        │ Usage limit reached for gemini-3-flash-preview.                              │
        │ Access resets at 12:53 PM GMT+2.                                             │
        │ /stats model for usage details                                               │
        │ /model to switch models.                                                     │
        │ /auth to switch to API key.                                                  │
        │                                                                              │
        │                                                                              │
        │ ● 1. Keep trying                                                             │

        ℹ Request cancelled.

        ╭──────────────────────────────────────────────────────────────────────────────╮
        │                                                                              │
        │ Usage limit reached for gemini-3-flash-preview.                              │
        │ Access resets at 12:53 PM GMT+2.                                             │
        │ /stats model for usage details                                               │
        │ /model to switch models.                                                     │
        │ /auth to switch to API key.                                                  │
        │                                                                              │
        │                                                                              │
        │   1. Keep trying                                                             │
        │ ● 2. Stop                                                                    │
        │                                                                              │
        │                                                                              │
        ╰──────────────────────────────────────────────────────────────────────────────╯
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
        let selected = try XCTUnwrap(payload["selectedOption"] as? [String: Any])
        let stop = try XCTUnwrap(payload["stopOption"] as? [String: Any])

        XCTAssertEqual(payload["kind"] as? String, "usage_limit")
        XCTAssertEqual(payload["stopOptionText"] as? String, "2")
        XCTAssertEqual(stop["canonical"] as? String, "stop")
        XCTAssertEqual(selected["numberText"] as? String, "2")
        XCTAssertEqual(selected["canonical"] as? String, "stop")
    }

    func testBundledGeminiAutomationRunnerRelaunchesWhenUsageLimitBlocksPromptCommands() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = {
            blocked: mod._test.shouldRelaunchForBlockedUsageLimit({
              kind: 'usage_limit',
              chatPromptActive: false,
              stopOption: null,
            }),
            activePromptWithoutStop: mod._test.shouldRelaunchForBlockedUsageLimit({
              kind: 'usage_limit',
              chatPromptActive: true,
              stopOption: null,
            }),
            switchActivePromptWithoutStop: mod._test.shouldSwitchImmediatelyForPromptUsageLimit({
              kind: 'usage_limit',
              chatPromptActive: true,
              usageLimitPromptActive: true,
              stopOption: null,
            }),
            switchRetainedPromptWithoutStop: mod._test.shouldSwitchImmediatelyForPromptUsageLimit({
              kind: 'usage_limit',
              chatPromptActive: true,
              usageLimitPromptActive: false,
              stopOption: null,
            }),
            switchBlockedWithoutPrompt: mod._test.shouldSwitchImmediatelyForPromptUsageLimit({
              kind: 'usage_limit',
              chatPromptActive: false,
              stopOption: null,
            }),
            switchDismissableMenu: mod._test.shouldSwitchImmediatelyForPromptUsageLimit({
              kind: 'usage_limit',
              chatPromptActive: true,
              stopOption: { numberText: '2', canonical: 'stop' },
            }),
            dismissableMenu: mod._test.shouldRelaunchForBlockedUsageLimit({
              kind: 'usage_limit',
              chatPromptActive: false,
              stopOption: { numberText: '2', canonical: 'stop' },
            }),
            normal: mod._test.shouldRelaunchForBlockedUsageLimit({
              kind: 'normal',
              chatPromptActive: false,
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
        XCTAssertEqual(payload["blocked"] as? Bool, true)
        XCTAssertEqual(payload["activePromptWithoutStop"] as? Bool, true)
        XCTAssertEqual(payload["switchActivePromptWithoutStop"] as? Bool, true)
        XCTAssertEqual(payload["switchRetainedPromptWithoutStop"] as? Bool, false)
        XCTAssertEqual(payload["switchBlockedWithoutPrompt"] as? Bool, false)
        XCTAssertEqual(payload["switchDismissableMenu"] as? Bool, false)
        XCTAssertEqual(payload["dismissableMenu"] as? Bool, false)
        XCTAssertEqual(payload["normal"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerAdoptsOnlyFinalizingModelSwitchTargetsForUsageLimit() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let chain = [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview",
            "gemini-2.5-flash"
        ]
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedChain = String(data: try JSONEncoder().encode(chain), encoding: .utf8) ?? "[]"
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const chain = \(encodedChain);
          const direct = mod._test.resolvePendingModelSwitchTargetForUsageLimit({
            kind: 'model-switch-finalize',
            targetIndex: 1,
            targetModel: 'gemini-3-flash-preview',
          }, chain);
          const manage = mod._test.resolvePendingModelSwitchTargetForUsageLimit({
            kind: 'model-manage-finalize',
            targetIndex: 2,
            targetModel: 'gemini-2.5-flash',
          }, chain);
          const route = mod._test.resolvePendingModelSwitchTargetForUsageLimit({
            kind: 'model-manage-route',
            targetIndex: 1,
            targetModel: 'gemini-3-flash-preview',
          }, chain);
          const invalid = mod._test.resolvePendingModelSwitchTargetForUsageLimit({
            kind: 'model-switch-finalize',
            targetIndex: 99,
            targetModel: 'gemini-unknown',
          }, chain);
          process.stdout.write(JSON.stringify({ direct, manage, route, invalid }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let direct = try XCTUnwrap(payload["direct"] as? [String: Any])
        let manage = try XCTUnwrap(payload["manage"] as? [String: Any])
        XCTAssertEqual(direct["targetIndex"] as? Int, 1)
        XCTAssertEqual(direct["targetModel"] as? String, "gemini-3-flash-preview")
        XCTAssertEqual(manage["targetIndex"] as? Int, 2)
        XCTAssertEqual(manage["targetModel"] as? String, "gemini-2.5-flash")
        XCTAssertTrue(payload["route"] is NSNull)
        XCTAssertTrue(payload["invalid"] is NSNull)
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
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "20260426T090000Z")
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
            nextAfterClear: mod._test.buildNextStartupCommand({
              capabilities,
              startupClearCompleted: true,
              startupStatsObserved: false,
              startupModelCapacityObserved: false,
              startupStatsBlockedReason: '',
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
        let modelManage = try XCTUnwrap(payload["modelManage"] as? [String: Any])

        XCTAssertTrue(payload["startup"] is NSNull)
        let nextAfterClear = try XCTUnwrap(payload["nextAfterClear"] as? [String: Any])
        XCTAssertEqual(nextAfterClear["kind"] as? String, "startup-model")
        XCTAssertEqual(nextAfterClear["text"] as? String, "/model")
        XCTAssertEqual(modelManage["kind"] as? String, "model-manage-open")
        XCTAssertEqual(modelManage["text"] as? String, "/model manage")
        XCTAssertEqual(modelManage["targetModel"] as? String, "gemini-2.5-pro")
    }

    func testBundledGeminiAutomationRunnerQueuesPromptWhenStartupStatsAreDisabledForPtyLaunch() throws {
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
            delayAfterSoftBlock: mod._test.shouldDelayInitialPromptForStartupStats({
              hasInitialPrompt: true,
              startupStatsObserved: false,
              startupStatsBlockedReason: 'Gemini startup /stats automation is disabled for this test capability.',
              startupStatsBlocksInitialPrompt: false,
              pendingPromptCommand: null,
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
        XCTAssertEqual(payload["delayAfterSoftBlock"] as? Bool, false)
        XCTAssertEqual(
            payload["blockedReason"] as? String,
            "Gemini startup /stats automation is disabled for this test capability."
        )
    }

    func testBundledGeminiAutomationRunnerUsesLaunchPromptWhenPtyUnavailable() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        process.env.GEMINI_INITIAL_PROMPT = "Ship beta now";
        import(\(encodedImportURL)).then((mod) => {
          const capabilities = {
            startupStatsAutomationSupported: true,
          };
          const allowLaunchPrompt = mod._test.shouldLaunchInitialPromptWithLaunchArgs(capabilities, {
            ptyAvailable: false,
          });
          const payload = {
            allowLaunchPrompt,
            args: mod._test.buildGeminiArgs("gemini-2.5-flash", {
              allowLaunchPrompt,
            }),
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
        let argsPayload = try XCTUnwrap(payload["args"] as? [String: Any])
        let args = try XCTUnwrap(argsPayload["args"] as? [String])

        XCTAssertEqual(payload["allowLaunchPrompt"] as? Bool, true)
        XCTAssertEqual(argsPayload["launchesWithInitialPrompt"] as? Bool, true)
        XCTAssertTrue(args.contains("--prompt-interactive"))
        XCTAssertTrue(args.contains("Ship beta now"))
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

    func testBundledGeminiAutomationRunnerUsesExplicitAutoModelFlagWhenGeminiModelAutoIsEnabled() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        process.env.GEMINI_MODEL_AUTO = "1";
        process.env.MODEL_CHAIN = "gemini-3-pro-preview,gemini-3-flash-preview";
        import(\(encodedImportURL)).then((mod) => {
          const payload = mod._test.buildGeminiArgs("gemini-3-pro-preview");
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

        XCTAssertEqual(Array(args.prefix(2)), ["--model", "auto"])
        XCTAssertFalse(args.contains("gemini-3-pro-preview"))
    }

    func testBundledGeminiAutomationRunnerBuildsPostAuthTelemetryWithoutStartupClear() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let authRestartPrompt = """
        ℹ Authentication succeeded
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │ You've successfully signed in with Google. Gemini CLI needs to be restarted. │
        │ Press R to restart, or Esc to choose a different authentication method.      │
        ╰──────────────────────────────────────────────────────────────────────────────╯
        """
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedPrompt = String(data: try JSONEncoder().encode(authRestartPrompt), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const prompt = \(encodedPrompt);
          const first = mod._test.buildPostAuthTelemetryCommand();
          const second = mod._test.buildNextStartupCommand({
            startupClearCompleted: true,
            startupStatsObserved: true,
            startupModelCapacityObserved: false,
            startupStatsBlockedReason: '',
            startupStatsBlocksInitialPrompt: false,
          });
          const payload = {
            hasAuthRestart: mod._test.hasAuthRestartRequiredPrompt(prompt),
            snapshot: mod._test.detectSnapshotFromText(prompt, 'sample'),
            first,
            second,
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
        let snapshot = try XCTUnwrap(payload["snapshot"] as? [String: Any])
        let first = try XCTUnwrap(payload["first"] as? [String: Any])
        let second = try XCTUnwrap(payload["second"] as? [String: Any])

        XCTAssertEqual(payload["hasAuthRestart"] as? Bool, true)
        XCTAssertEqual(snapshot["kind"] as? String, "auth_restart_required")
        XCTAssertEqual(first["kind"] as? String, "startup-stats")
        XCTAssertEqual(first["text"] as? String, "/stats")
        XCTAssertEqual(second["kind"] as? String, "startup-model")
        XCTAssertEqual(second["text"] as? String, "/model")
    }

    func testBundledGeminiAutomationRunnerRequeuesInterruptedStartupPipeline() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const normalPrompt = { kind: 'normal', chatPromptActive: true };
          const payload = {
            beforeStats: mod._test.buildNextStartupCommand({
              startupClearCompleted: false,
              startupStatsObserved: false,
              startupModelCapacityObserved: false,
            }),
            afterClear: mod._test.buildNextStartupCommand({
              startupClearCompleted: true,
              startupStatsObserved: false,
              startupModelCapacityObserved: false,
            }),
            afterStats: mod._test.buildNextStartupCommand({
              startupClearCompleted: true,
              startupStatsObserved: true,
              startupModelCapacityObserved: false,
            }),
            afterStatsUnavailable: mod._test.buildNextStartupCommand({
              startupClearCompleted: true,
              startupStatsObserved: false,
              startupModelCapacityObserved: false,
              startupStatsBlockedReason: 'startup /stats output was not detected in time',
              startupStatsBlocksInitialPrompt: false,
            }),
            afterModelUnavailable: mod._test.buildNextStartupCommand({
              startupClearCompleted: true,
              startupStatsObserved: false,
              startupModelCapacityObserved: false,
              startupStatsBlockedReason: 'startup /model output was not detected in time',
              startupStatsBlocksInitialPrompt: false,
            }),
            complete: mod._test.buildNextStartupCommand({
              startupClearCompleted: true,
              startupStatsObserved: true,
              startupModelCapacityObserved: true,
            }),
            shouldRequeue: mod._test.shouldRequeueStartupCommand(normalPrompt, {
              pendingPromptCommand: null,
              sentInitialPrompt: false,
              authWaiting: false,
              startupStatsBlockedReason: '',
              startupClearCompleted: false,
              startupStatsObserved: false,
              startupModelCapacityObserved: false,
            }),
            doesNotRequeueAfterPrompt: mod._test.shouldRequeueStartupCommand(normalPrompt, {
              pendingPromptCommand: null,
              sentInitialPrompt: true,
              authWaiting: false,
              startupStatsBlockedReason: '',
              startupClearCompleted: false,
              startupStatsObserved: false,
              startupModelCapacityObserved: false,
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
        let beforeStats = try XCTUnwrap(payload["beforeStats"] as? [String: Any])
        let afterClear = try XCTUnwrap(payload["afterClear"] as? [String: Any])
        let afterStats = try XCTUnwrap(payload["afterStats"] as? [String: Any])
        let afterStatsUnavailable = try XCTUnwrap(payload["afterStatsUnavailable"] as? [String: Any])

        XCTAssertEqual(beforeStats["kind"] as? String, "startup-clear")
        XCTAssertEqual(afterClear["kind"] as? String, "startup-stats")
        XCTAssertEqual(afterStats["kind"] as? String, "startup-model")
        XCTAssertEqual(afterStatsUnavailable["kind"] as? String, "startup-model")
        XCTAssertTrue(payload["afterModelUnavailable"] is NSNull)
        XCTAssertTrue(payload["complete"] is NSNull)
        XCTAssertEqual(payload["shouldRequeue"] as? Bool, true)
        XCTAssertEqual(payload["doesNotRequeueAfterPrompt"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerDoesNotFinalizeStartupCommandWhilePromptInputRemains() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const promptWithClear = {
            kind: 'normal',
            chatPromptActive: true,
            promptInputText: '/clear',
          };
          const promptWithStats = {
            kind: 'normal',
            chatPromptActive: true,
            promptInputText: '/stats',
          };
          const emptyPrompt = {
            kind: 'normal',
            chatPromptActive: true,
            promptInputText: '',
          };
          const historicalClearEcho = [
            '> /clear',
            '? for shortcuts',
            'Type your message or @path/to/file',
            '> '
          ].join('\\n');
          const historicalStatsEcho = [
            '> /stats',
            '? for shortcuts',
            'Type your message or @path/to/file',
            '> '
          ].join('\\n');
          const payload = {
            clearWithInput: mod._test.hasStartupClearSettled(promptWithClear, {
              screenText: '',
              visibleText: '',
              waitedForMs: 500,
            }),
            statsWithInput: mod._test.hasStartupStatsCaptureSettled(promptWithStats, {
              startupStatsObserved: true,
              screenText: '',
              visibleText: '',
              waitedForMs: 500,
            }),
            modelWithInput: mod._test.hasStartupModelCapacityClosed(promptWithStats, {
              screenText: '',
              visibleText: '',
              waitedForMs: 500,
            }),
            clearWithPendingEnter: mod._test.hasStartupClearSettled(emptyPrompt, {
              screenText: '',
              visibleText: '',
              waitedForMs: 500,
              pendingSubmitEnter: true,
            }),
            clearWithPendingSubmitSettle: mod._test.hasStartupClearSettled(emptyPrompt, {
              screenText: '',
              visibleText: '',
              waitedForMs: 500,
              pendingSubmitSettling: true,
            }),
            clearWithoutInput: mod._test.hasStartupClearSettled(emptyPrompt, {
              screenText: '',
              visibleText: '',
              waitedForMs: 1000,
              pendingSubmitEnter: false,
            }),
            clearAfterHistoricalEcho: mod._test.hasStartupClearSettled(emptyPrompt, {
              screenText: historicalClearEcho,
              visibleText: historicalClearEcho,
              waitedForMs: 1000,
              pendingSubmitEnter: false,
            }),
            statsAfterHistoricalEcho: mod._test.hasStartupStatsCaptureSettled(emptyPrompt, {
              startupStatsObserved: true,
              screenText: historicalStatsEcho,
              visibleText: historicalStatsEcho,
              waitedForMs: 500,
              pendingSubmitEnter: false,
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
        XCTAssertEqual(payload["clearWithInput"] as? Bool, false)
        XCTAssertEqual(payload["statsWithInput"] as? Bool, false)
        XCTAssertEqual(payload["modelWithInput"] as? Bool, false)
        XCTAssertEqual(payload["clearWithPendingEnter"] as? Bool, false)
	        XCTAssertEqual(payload["clearWithPendingSubmitSettle"] as? Bool, false)
	        XCTAssertEqual(payload["clearWithoutInput"] as? Bool, true)
	        XCTAssertEqual(payload["clearAfterHistoricalEcho"] as? Bool, true)
	        XCTAssertEqual(payload["statsAfterHistoricalEcho"] as? Bool, true)
	    }

    func testBundledGeminiAutomationRunnerExtractsStackedStartupSlashPromptInput() throws {
        let transcript = #"""
        Type your message or @path/to/file

         ● YOLO
        ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
         * /stats
           /model
           /model
        ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
        """#

        let promptWithWorkspaceRows = #"""
        ? for shortcuts
        * /model
        workspace (/directory)     branch     sandbox       /model
        /tmp/clilauncher          main       no sandbox    gemini-3-flash-preview
        """#
        let stackedContinuePrompt = #"""
        ? for shortcuts
         > continue

           continue

           continue
        """#
        let apiUsageLimitWithStackedContinue = #"""
        ✕ [API Error: You have exhausted your capacity on this model. Your quota will reset after 23h23m59s.]
        ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
         > continue

           continue

           continue
        ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
        """#

        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedTranscript = String(data: try JSONEncoder().encode(transcript), encoding: .utf8) ?? "\"\""
        let encodedPromptWithWorkspaceRows = String(data: try JSONEncoder().encode(promptWithWorkspaceRows), encoding: .utf8) ?? "\"\""
        let encodedStackedContinuePrompt = String(data: try JSONEncoder().encode(stackedContinuePrompt), encoding: .utf8) ?? "\"\""
        let encodedApiUsageLimitWithStackedContinue = String(data: try JSONEncoder().encode(apiUsageLimitWithStackedContinue), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const stacked = \(encodedTranscript).split('\\n');
          const workspaceRows = \(encodedPromptWithWorkspaceRows).split('\\n');
          const stackedContinue = \(encodedStackedContinuePrompt).split('\\n');
          const apiUsageLimit = mod._test.detectSnapshotFromText(\(encodedApiUsageLimitWithStackedContinue), 'screen');
          const payload = {
            stackedPromptInput: mod._test.extractPromptInputText(stacked),
            stackedCommands: mod._test.automationPromptInputCommandLines(mod._test.extractPromptInputText(stacked)),
            promptInputWithoutWorkspaceRows: mod._test.extractPromptInputText(workspaceRows),
            stackedContinuePromptInput: mod._test.extractPromptInputText(stackedContinue),
            stackedContinueCommands: mod._test.automationPromptInputCommandLines(mod._test.extractPromptInputText(stackedContinue)),
            apiUsageLimitKind: apiUsageLimit.kind,
            apiUsageLimitPromptInput: apiUsageLimit.promptInputText,
            apiUsageLimitCommands: mod._test.automationPromptInputCommandLines(apiUsageLimit.promptInputText),
            apiUsageLimitSwitchesImmediately: mod._test.shouldSwitchImmediatelyForPromptUsageLimit(apiUsageLimit),
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
        XCTAssertEqual(payload["stackedPromptInput"] as? String, "/stats\n/model\n/model")
        XCTAssertEqual(payload["stackedCommands"] as? [String], ["/stats", "/model", "/model"])
        XCTAssertEqual(payload["promptInputWithoutWorkspaceRows"] as? String, "/model")
        XCTAssertEqual(payload["stackedContinuePromptInput"] as? String, "continue\ncontinue\ncontinue")
        XCTAssertEqual(payload["stackedContinueCommands"] as? [String], ["continue", "continue", "continue"])
        XCTAssertEqual(payload["apiUsageLimitKind"] as? String, "usage_limit")
        XCTAssertEqual(payload["apiUsageLimitPromptInput"] as? String, "continue\ncontinue\ncontinue")
        XCTAssertEqual(payload["apiUsageLimitCommands"] as? [String], ["continue", "continue", "continue"])
        XCTAssertEqual(payload["apiUsageLimitSwitchesImmediately"] as? Bool, true)
    }

    func testBundledGeminiAutomationRunnerDoesNotAppendStartupSlashCommandsWithDelayedEnter() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        let input = '';
        let submitPending = false;

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(command) {
          fs.appendFileSync(logPath, command + '\n');
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          geet       no sandbox    gemini-3-flash-preview     ...\n');
          write('> ');
        }

        function handleCommand(command) {
          logCommand(command);
          if (command.includes('/clear/stats') || command.includes('/stats/model')) {
            write('\nAppended command detected: ' + command + '\n');
            setTimeout(() => process.exit(7), 40);
            return;
          }

          if (command === '/clear') {
            setTimeout(writePrompt, 120);
          } else if (command === '/stats') {
            write('\nSession Stats\n');
            write('Session ID: delayed-submit-smoke\n');
            write('Auth Method: Signed in with Google (smoke@example.com)\n');
            write('Tier: Gemini Code Assist for individuals\n');
            write('Model Usage\n');
            write('gemini-3-flash-preview          1            0            0             0\n');
            setTimeout(writePrompt, 120);
          } else if (command === '/model') {
            write('\nSelect Model\n');
            write('Manual (gemini-3-flash-preview)\n');
            write('Model usage\n');
            write('gemini-3-flash-preview 10% Resets: 1:29 PM\n');
            setTimeout(() => process.exit(0), 120);
          } else if (command) {
            write('\nUnexpected command: ' + command + '\n');
            setTimeout(() => process.exit(8), 40);
          }
        }

        process.on('SIGINT', () => {
          logCommand('__SIGINT__');
          process.exit(130);
        });

        write('Gemini CLI v0.39.0\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          const raw = String(data || '');
          for (const ch of raw) {
            if (ch === '\u0015') {
              input = '';
              write('\n> ');
            } else if (ch === '\r') {
              if (submitPending) continue;
              submitPending = true;
              setTimeout(() => {
                write('\n');
                const command = input.trim();
                input = '';
                submitPending = false;
                handleCommand(command);
              }, 180);
            } else if (ch >= ' ') {
              input += ch;
            }
          }
        });

        setTimeout(() => process.exit(3), 9000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "stable"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview,gemini-3-pro-preview,gemini-2.5-flash"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "60"
        environment["PROMPT_SUBMIT_DELAY_MS"] = "220"
        environment["PROMPT_SUBMIT_SETTLE_MS"] = "260"
        environment["QUICK_RECHECK_MS"] = "30"
        environment["STATIC_RECHECK_MS"] = "40"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "1200"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "24000"
        environment["NORMALIZED_TAIL_MAX"] = "16000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(11)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("/stats"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("/model"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertFalse(commands.contains { $0.contains("/clear/stats") || $0.contains("/stats/model") }, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertFalse(stdout.contains("/clear/stats"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertFalse(stdout.contains("/stats/model"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
    }

    func testBundledGeminiAutomationRunnerRetriesStartupSlashCommandEnterWhenInputSticks() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        let inputBuffer = '';
        let statsEnterAttempts = 0;
        let modelEnterAttempts = 0;
        let clearSeen = false;
        let statsSeen = false;
        let modelSeen = false;
        let modelClosed = false;
        let promptSeen = false;
        let modelPanelOpen = false;

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, line + '\n');
        }

        function writePrompt(text = inputBuffer) {
          write('\n'.repeat(80));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          write(' ● YOLO\n');
          write(text ? '* ' + text + '\n' : '*   Type your message or @path/to/file\n');
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    gemini-3-flash-preview     ...\n');
        }

        function writeStats() {
          write('\nSession Stats\n');
          write('Session ID: startup-enter-retry\n');
          write('Auth Method: Signed in with Google (smoke@example.com)\n');
          write('Tier: Gemini Code Assist for individuals\n');
          write('Model Usage\n');
          write('gemini-3-flash-preview          1            0            0             0\n');
        }

        function writeModelPanel() {
          modelPanelOpen = true;
          write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
          write('│ Select Model                                                                 │\n');
          write('│ ● 1. Manual (gemini-3-flash-preview)                                         │\n');
          write('│                                                                              │\n');
          write('│ Model usage                                                                  │\n');
          write('│ Flash           ▬                                      7%                    │\n');
          write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
        }

        function submit(command) {
          if (!command) return;

          if (command === '/stats' && statsEnterAttempts === 0) {
            statsEnterAttempts += 1;
            logCommand('__STATS_ENTER_SWALLOWED__');
            inputBuffer = '/stats';
            writePrompt(inputBuffer);
            return;
          }

          if (command === '/model' && modelEnterAttempts === 0) {
            modelEnterAttempts += 1;
            logCommand('__MODEL_ENTER_SWALLOWED__');
            inputBuffer = '/model';
            writePrompt(inputBuffer);
            return;
          }

          logCommand(command);
          inputBuffer = '';

          if (command === '/clear') {
            clearSeen = true;
            writePrompt('');
          } else if (command === '/stats') {
            statsSeen = true;
            statsEnterAttempts += 1;
            writeStats();
            writePrompt('');
          } else if (command === '/model') {
            modelSeen = true;
            modelEnterAttempts += 1;
            writeModelPanel();
          } else if (command === 'Ship beta now') {
            promptSeen = true;
            write('\nWorking on it\n');
            writePrompt('');
          } else {
            write('\nUnexpected command: ' + command + '\n');
            setTimeout(() => process.exit(8), 40);
          }
        }

        write('Gemini CLI v0.41.0-nightly\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt('');

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          for (const char of String(data || '')) {
            if (modelPanelOpen && char === '\u001B') {
              modelPanelOpen = false;
              modelClosed = true;
              logCommand('__MODEL_ESC__');
              writePrompt('');
              continue;
            }

            if (char === '\u0015') {
              inputBuffer = '';
              logCommand('__CTRL_U__');
              writePrompt('');
            } else if (char === '\r' || char === '\n') {
              submit(inputBuffer.trim());
            } else if (char === '\u001B') {
              logCommand('__ESC__');
            } else if (char >= ' ') {
              inputBuffer += char;
              writePrompt(inputBuffer);
            }
          }

          if (clearSeen && statsSeen && modelSeen && modelClosed && promptSeen) {
            setTimeout(() => process.exit(0), 80);
          }
        });

        setTimeout(() => process.exit(promptSeen ? 0 : 5), 9000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "nightly"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "80"
        environment["PROMPT_SUBMIT_DELAY_MS"] = "40"
        environment["PROMPT_SUBMIT_SETTLE_MS"] = "80"
        environment["PROMPT_SUBMIT_PROCESSING_GRACE_MS"] = "80"
        environment["INITIAL_PROMPT_SUBMIT_CONFIRM_MS"] = "80"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "80"
        environment["INITIAL_PROMPT_RETRY_MS"] = "50"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1200"
        environment["QUICK_RECHECK_MS"] = "30"
        environment["STATIC_RECHECK_MS"] = "40"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "1400"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "24000"
        environment["NORMALIZED_TAIL_MAX"] = "16000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(12)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("__STATS_ENTER_SWALLOWED__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("__MODEL_ENTER_SWALLOWED__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("/stats"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("/model"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("__MODEL_ESC__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("Ship beta now"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("/stats is still in the input field; retrying Enter"), stderr)
        XCTAssertTrue(stderr.contains("/model is still in the input field; retrying Enter"), stderr)
        XCTAssertFalse(commands.contains { $0.contains("/stats/model") || $0.contains("/modelShip beta now") }, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
    }

    func testBundledGeminiAutomationRunnerSubmitsStartupModelAfterAutocompleteDismissal() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        let input = '';
        let modelAutocompleteDismissed = false;
        let modelPanelOpen = false;
        let swallowedPromptEnter = false;

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(command) {
          fs.appendFileSync(logPath, command + '\n');
        }

        function writePrompt(text = input) {
          write('\n'.repeat(80));
          write('? for shortcuts\n');
          write(text ? '* ' + text + '\n' : '*   Type your message or @path/to/file\n');
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    gemini-3-flash-preview     ...\n');
        }

        function submit(command) {
          if (!command) return;
          logCommand(command);
          if (command === '/clear') {
            writePrompt('');
          } else if (command === '/stats') {
            write('\nSession Stats\n');
            write('Session ID: startup-model-autocomplete\n');
            write('Auth Method: Signed in with Google (smoke@example.com)\n');
            write('Tier: Gemini Code Assist for individuals\n');
            write('Model Usage\n');
            write('gemini-3-flash-preview          1            0            0             0\n');
            writePrompt('');
          } else if (command === '/model') {
            modelPanelOpen = true;
            write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
            write('│ Select Model                                                                 │\n');
            write('│ ● 1. Manual (gemini-3-flash-preview)                                         │\n');
            write('│ Model usage                                                                  │\n');
            write('│ Flash           ▬                                      7%                    │\n');
            write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
          } else if (command === 'lint features and fix') {
            write('\nWorking on it\n');
            setTimeout(() => process.exit(0), 80);
          }
        }

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt('');

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          for (const char of String(data || '')) {
            if (char === '\u0015') {
              input = '';
              modelAutocompleteDismissed = false;
              writePrompt('');
            } else if (char === '\u001B') {
              if (modelPanelOpen) {
                modelPanelOpen = false;
                input = '';
                writePrompt('');
              } else if (input.trim() === '/model') {
                modelAutocompleteDismissed = true;
                writePrompt(input);
              }
            } else if (char === '\r' || char === '\n') {
              const command = input.trim();
              if (command === '/model' && !modelAutocompleteDismissed) {
                logCommand('__MODEL_ENTER_SWALLOWED__');
                writePrompt(input);
                continue;
              }
              if (command === 'lint features and fix' && !swallowedPromptEnter) {
                swallowedPromptEnter = true;
                logCommand('__PROMPT_ENTER_SWALLOWED__');
                writePrompt(input);
                continue;
              }
              input = '';
              modelAutocompleteDismissed = false;
              submit(command);
            } else if (char >= ' ') {
              input += char;
              writePrompt(input);
            }
          }
        });

        setTimeout(() => process.exit(5), 9000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview"
        environment["GEMINI_INITIAL_PROMPT"] = "lint features and fix"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "100"
        environment["STARTUP_VISIBLE_PROMPT_COMMAND_SETTLE_MS"] = "40"
        environment["PROMPT_SUBMIT_DELAY_MS"] = "50"
        environment["PROMPT_SUBMIT_SETTLE_MS"] = "80"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "80"
        environment["INITIAL_PROMPT_RETRY_MS"] = "40"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1200"
        environment["INITIAL_PROMPT_SUBMIT_CONFIRM_MS"] = "80"
        environment["INITIAL_PROMPT_SUBMIT_RETRY_MAX"] = "2"
        environment["QUICK_RECHECK_MS"] = "30"
        environment["STATIC_RECHECK_MS"] = "50"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "900"
        environment["RAW_TAIL_MAX"] = "20000"
        environment["NORMALIZED_TAIL_MAX"] = "12000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(11)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertFalse(commands.contains("__MODEL_ENTER_SWALLOWED__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("__PROMPT_ENTER_SWALLOWED__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("/model"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("lint features and fix"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("retrying Enter"), stderr)
    }

    func testBundledGeminiAutomationRunnerDoesNotDelayPromptAfterSoftStartupStatsFailure() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        process.env.GEMINI_INITIAL_PROMPT = "Ship beta now";
        import(\(encodedImportURL)).then((mod) => {
          const payload = {
            pendingStartup: mod._test.shouldDelayInitialPromptForStartupStats({
              hasInitialPrompt: true,
              startupStatsObserved: false,
              startupStatsBlockedReason: '',
              startupStatsBlocksInitialPrompt: false,
              pendingPromptCommand: { kind: 'startup-stats-finalize' },
            }),
            softFailure: mod._test.shouldDelayInitialPromptForStartupStats({
              hasInitialPrompt: true,
              startupStatsObserved: false,
              startupStatsBlockedReason: 'startup /stats output was not detected in time',
              startupStatsBlocksInitialPrompt: false,
              pendingPromptCommand: null,
            }),
            softFailureWithModelPending: mod._test.shouldDelayInitialPromptForStartupStats({
              hasInitialPrompt: true,
              startupStatsObserved: false,
              startupStatsBlockedReason: 'startup /stats output was not detected in time',
              startupStatsBlocksInitialPrompt: false,
              pendingPromptCommand: { kind: 'startup-model' },
            }),
            hardFailure: mod._test.shouldDelayInitialPromptForStartupStats({
              hasInitialPrompt: true,
              startupStatsObserved: false,
              startupStatsBlockedReason: 'startup /clear did not return to the chat prompt in time',
              startupStatsBlocksInitialPrompt: true,
              pendingPromptCommand: null,
            }),
            observedBeforeModel: mod._test.shouldDelayInitialPromptForStartupStats({
              hasInitialPrompt: true,
              startupClearCompleted: true,
              startupStatsObserved: true,
              startupModelCapacityObserved: false,
              startupStatsBlockedReason: '',
              startupStatsBlocksInitialPrompt: false,
              pendingPromptCommand: null,
            }),
            observed: mod._test.shouldDelayInitialPromptForStartupStats({
              hasInitialPrompt: true,
              startupClearCompleted: true,
              startupStatsObserved: true,
              startupModelCapacityObserved: true,
              startupStatsBlockedReason: '',
              startupStatsBlocksInitialPrompt: false,
              pendingPromptCommand: null,
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
        XCTAssertEqual(payload["pendingStartup"] as? Bool, true)
        XCTAssertEqual(payload["softFailure"] as? Bool, false)
        XCTAssertEqual(payload["softFailureWithModelPending"] as? Bool, true)
        XCTAssertEqual(payload["hardFailure"] as? Bool, true)
        XCTAssertEqual(payload["observedBeforeModel"] as? Bool, true)
        XCTAssertEqual(payload["observed"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerDescribesStartupTelemetryAsBestEffort() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = {
            pipeline: mod._test.startupPipelineLabel(),
            gate: mod._test.startupPromptGateLabel(),
            promptQueue: mod._test.startupPromptDeliveryQueueLabel(),
            sequence: mod._test.startupSequenceQueuedLabel(),
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
        XCTAssertEqual(payload["pipeline"] as? String, "/clear -> /stats -> /model")
        XCTAssertEqual(payload["gate"] as? String, "/clear")
        XCTAssertEqual(payload["promptQueue"] as? String, "/clear; telemetry /stats -> /model best effort")
        XCTAssertEqual(payload["sequence"] as? String, "/clear -> /stats -> /model; telemetry best effort")
    }

    func testBundledGeminiAutomationRunnerDoesNotAutoContinueOnInitialPromptFingerprint() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const stalePrompt = {
            kind: 'normal',
            chatPromptActive: true,
            promptFingerprint: 'workspace | ready',
          };
          const returnedPrompt = {
            kind: 'normal',
            chatPromptActive: true,
            promptFingerprint: 'workspace | response finished',
          };
          const busyPrompt = {
            kind: 'normal',
            chatPromptActive: true,
            promptFingerprint: 'workspace | user typing',
            promptInputText: 'manual task in progress',
          };
          const payload = {
            stale: mod._test.shouldAutoContinuePrompt(stalePrompt, {
              autoContinueMode: 'always',
              continueLoopArmed: true,
              initialPromptSubmittedFingerprint: 'workspace | ready',
            }),
            returned: mod._test.shouldAutoContinuePrompt(returnedPrompt, {
              autoContinueMode: 'always',
              continueLoopArmed: true,
              initialPromptSubmittedFingerprint: 'workspace | ready',
            }),
            unarmed: mod._test.shouldAutoContinuePrompt(returnedPrompt, {
              autoContinueMode: 'always',
              continueLoopArmed: false,
              initialPromptSubmittedFingerprint: 'workspace | ready',
            }),
            promptOnly: mod._test.shouldAutoContinuePrompt(returnedPrompt, {
              autoContinueMode: 'prompt_only',
              continueLoopArmed: true,
              initialPromptSubmittedFingerprint: 'workspace | ready',
            }),
            manualAlwaysOverride: mod._test.shouldAutoContinuePrompt(returnedPrompt, {
              autoContinueMode: 'prompt_only',
              promptAutoContinueAlways: true,
              continueLoopArmed: true,
              initialPromptSubmittedFingerprint: 'workspace | ready',
            }),
            busyPrompt: mod._test.shouldAutoContinuePrompt(busyPrompt, {
              autoContinueMode: 'always',
              promptAutoContinueAlways: true,
              continueLoopArmed: true,
              initialPromptSubmittedFingerprint: 'workspace | ready',
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
        XCTAssertEqual(payload["stale"] as? Bool, false)
        XCTAssertEqual(payload["returned"] as? Bool, true)
        XCTAssertEqual(payload["unarmed"] as? Bool, false)
        XCTAssertEqual(payload["promptOnly"] as? Bool, false)
        XCTAssertEqual(payload["manualAlwaysOverride"] as? Bool, true)
        XCTAssertEqual(payload["busyPrompt"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerSelectsRecoveryPromptAfterRepeatedConcludedSessions() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let firstConcludedMessage = """
        ✦ The requested refactoring work is complete and verified.
          No further automated instructions are pending, so I am idle until a new task starts.
        """
        let secondConcludedMessage = """
        ✦ All linting and stabilization tasks are done successfully.
          I am standing by for a new session or another development request.
        """
        let singleConcludedTranscript = """
        > continue
        \(firstConcludedMessage)
        """
        let repeatedConcludedTranscript = """
        > continue
        \(firstConcludedMessage)

        > continue
        \(secondConcludedMessage)
        """
        let encodedSingleTranscript = String(data: try JSONEncoder().encode(singleConcludedTranscript), encoding: .utf8) ?? "\"\""
        let encodedRepeatedTranscript = String(data: try JSONEncoder().encode(repeatedConcludedTranscript), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const singleConcluded = \(encodedSingleTranscript);
          const repeatedConcluded = \(encodedRepeatedTranscript);
          const snapshot = {
            kind: 'normal',
            chatPromptActive: true,
            promptFingerprint: 'workspace | concluded',
          };
          const singleOptions = {
            visibleText: singleConcluded,
            continueCommand: 'continue',
            continueFallbackCommand: 'continue to next refactor',
          };
          const repeatedOptions = {
            visibleText: repeatedConcluded,
            continueCommand: 'continue',
            continueFallbackCommand: 'continue to next refactor',
          };
          const normal = mod._test.selectedAutoContinueCommand(snapshot, {
            visibleText: '✦ Working normally\\n> ',
            continueCommand: 'continue',
            continueFallbackCommand: 'continue to next refactor',
          });
          const fallback = mod._test.selectedAutoContinueCommand(snapshot, repeatedOptions);
          const payload = {
            singleBlockCount: mod._test.concludedSessionKeywordBlockCount(singleConcluded),
            repeatedBlockCount: mod._test.concludedSessionKeywordBlockCount(repeatedConcluded),
            firstFamilies: mod._test.concludedSessionKeywordFamilies(singleConcluded),
            secondFamilies: mod._test.concludedSessionKeywordFamilies(repeatedConcluded.split('> continue').at(-1)),
            singleShouldUseFallback: mod._test.shouldUseContinueFallbackPrompt(snapshot, singleOptions),
            shouldUseFallback: mod._test.shouldUseContinueFallbackPrompt(snapshot, repeatedOptions),
            hasRepeatedConcluded: mod._test.hasRepeatedConcludedSessionText(repeatedConcluded),
            fallback,
            normal,
            samePromptFallback: mod._test.shouldUseContinueFallbackPrompt(snapshot, {
              visibleText: repeatedConcluded,
              continueCommand: 'continue',
              continueFallbackCommand: 'continue',
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
        XCTAssertEqual(payload["singleBlockCount"] as? Int, 1)
        XCTAssertEqual(payload["repeatedBlockCount"] as? Int, 2)
        XCTAssertEqual(payload["singleShouldUseFallback"] as? Bool, false)
        XCTAssertEqual(payload["shouldUseFallback"] as? Bool, true)
        XCTAssertEqual(payload["hasRepeatedConcluded"] as? Bool, true)
        XCTAssertEqual(payload["samePromptFallback"] as? Bool, false)

        let fallback = try XCTUnwrap(payload["fallback"] as? [String: Any])
        XCTAssertEqual(fallback["text"] as? String, "continue to next refactor")
        XCTAssertEqual(fallback["reason"] as? String, "auto-continue recovery prompt")
        XCTAssertEqual(fallback["usingFallback"] as? Bool, true)

        let normal = try XCTUnwrap(payload["normal"] as? [String: Any])
        XCTAssertEqual(normal["text"] as? String, "continue")
        XCTAssertEqual(normal["reason"] as? String, "auto-continue prompt")
        XCTAssertEqual(normal["usingFallback"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerManualInputAndEnableArmContinuousContinueMode() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = {
            textOnlySubmits: mod._test.manualInputSubmitsPrompt([...Buffer.from('manual prompt')]),
            carriageReturnSubmits: mod._test.manualInputSubmitsPrompt([...Buffer.from('manual prompt\\r')]),
            lineFeedSubmits: mod._test.manualInputSubmitsPrompt([...Buffer.from('manual prompt\\n')]),
            manualEnableForcesAlways: mod._test.shouldForceAlwaysAutoContinueOnAutomationEnable('manual'),
            defaultEnableForcesAlways: mod._test.shouldForceAlwaysAutoContinueOnAutomationEnable(),
            usageRecoveryKeepsConfiguredMode: mod._test.shouldForceAlwaysAutoContinueOnAutomationEnable('usage_limit_recovery'),
            promptOnlyMode: mod._test.effectiveAutoContinueMode({ autoContinueMode: 'prompt_only' }),
            manualOverrideMode: mod._test.effectiveAutoContinueMode({
              autoContinueMode: 'prompt_only',
              promptAutoContinueAlways: true,
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
        XCTAssertEqual(payload["textOnlySubmits"] as? Bool, false)
        XCTAssertEqual(payload["carriageReturnSubmits"] as? Bool, true)
        XCTAssertEqual(payload["lineFeedSubmits"] as? Bool, true)
        XCTAssertEqual(payload["manualEnableForcesAlways"] as? Bool, true)
        XCTAssertEqual(payload["defaultEnableForcesAlways"] as? Bool, true)
        XCTAssertEqual(payload["usageRecoveryKeepsConfiguredMode"] as? Bool, false)
        XCTAssertEqual(payload["promptOnlyMode"] as? String, "prompt_only")
        XCTAssertEqual(payload["manualOverrideMode"] as? String, "always")
    }

    func testBundledGeminiAutomationRunnerManualPromptReenableContinuesEndToEnd() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        let buffered = '';
        let promptGeneration = 0;

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(command) {
          fs.appendFileSync(logPath, command + '\n');
        }

        function writePrompt() {
          promptGeneration += 1;
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    gemini-3-flash-preview     turn-' + promptGeneration + '\n');
          write('> ');
        }

        function consumeCompleteLines() {
          let newlineIndex = buffered.indexOf('\n');
          while (newlineIndex >= 0) {
            const line = buffered.slice(0, newlineIndex).trim();
            buffered = buffered.slice(newlineIndex + 1);
            if (line) {
              logCommand(line);
            }
            if (line === 'manual task') {
              write('\nWorking on manual task...\n');
              setTimeout(writePrompt, 180);
            } else if (line === 'continue refactor') {
              write('\nContinuing after manual recovery\n');
              setTimeout(() => process.exit(0), 60);
            }
            newlineIndex = buffered.indexOf('\n');
          }
        }

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          buffered += String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/\r/g, '\n')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '');
          consumeCompleteLines();
        });

        setTimeout(() => process.exit(7), 6000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview"
        environment["AUTO_CONTINUE_MODE"] = "prompt_only"
        environment["CONTINUE_COMMAND"] = "continue refactor"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["STARTUP_CLEAR_COMMAND"] = " "
        environment["STARTUP_STATS_COMMAND"] = " "
        environment["STARTUP_MODEL_COMMAND"] = " "
        environment["PROMPT_COMMAND_SETTLE_MS"] = "80"
        environment["PROMPT_SUBMIT_DELAY_MS"] = "30"
        environment["QUICK_RECHECK_MS"] = "30"
        environment["STATIC_RECHECK_MS"] = "50"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["HOTKEY_PREFIX"] = "ctrl-g"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "16000"
        environment["NORMALIZED_TAIL_MAX"] = "12000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        Thread.sleep(forTimeInterval: 0.6)
        stdinPipe.fileHandleForWriting.write(Data("manual task\r".utf8))
        Thread.sleep(forTimeInterval: 0.1)
        stdinPipe.fileHandleForWriting.write(Data([0x07, 0x6f]))

        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 && stderr.contains("Automation features and hotkeys are disabled in fallback mode") {
            throw XCTSkip("PTY input automation is unavailable in this test environment.")
        }
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(commands, ["manual task", "continue refactor"], "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Automation enabled; continuous continue refactor mode armed."), stderr)
        XCTAssertFalse(stderr.contains("Manual typing pauses automation"), stderr)
        XCTAssertFalse(stderr.contains("[fatal]"), stderr)
    }

    func testBundledGeminiAutomationRunnerDoesNotContinueIntoPartialManualPromptEndToEnd() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        let buffered = '';
        let promptGeneration = 0;

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(command) {
          fs.appendFileSync(logPath, command + '\n');
        }

        function writePrompt(input = '') {
          promptGeneration += 1;
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write(input ? '> ' + input : '> ');
          write('\nworkspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    gemini-3-flash-preview     turn-' + promptGeneration + '\n');
        }

        function consumeCompleteLines() {
          let newlineIndex = buffered.indexOf('\n');
          while (newlineIndex >= 0) {
            const line = buffered.slice(0, newlineIndex).trim();
            buffered = buffered.slice(newlineIndex + 1);
            if (line) {
              logCommand(line);
            }
            if (line.includes('continue')) {
              process.exit(6);
            }
            newlineIndex = buffered.indexOf('\n');
          }
        }

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          const cleaned = String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/\r/g, '\n')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '');
          buffered += cleaned;
          writePrompt(buffered.replace(/\n/g, ''));
          consumeCompleteLines();
        });

        setTimeout(() => process.exit(0), 1500);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview"
        environment["AUTO_CONTINUE_MODE"] = "prompt_only"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["STARTUP_CLEAR_COMMAND"] = " "
        environment["STARTUP_STATS_COMMAND"] = " "
        environment["STARTUP_MODEL_COMMAND"] = " "
        environment["PROMPT_COMMAND_SETTLE_MS"] = "80"
        environment["PROMPT_SUBMIT_DELAY_MS"] = "30"
        environment["QUICK_RECHECK_MS"] = "30"
        environment["STATIC_RECHECK_MS"] = "50"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["HOTKEY_PREFIX"] = "ctrl-g"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "16000"
        environment["NORMALIZED_TAIL_MAX"] = "12000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        Thread.sleep(forTimeInterval: 0.6)
        stdinPipe.fileHandleForWriting.write(Data("partial manual prompt".utf8))
        Thread.sleep(forTimeInterval: 0.1)
        stdinPipe.fileHandleForWriting.write(Data([0x07, 0x6f]))

        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 && stderr.contains("Automation features and hotkeys are disabled in fallback mode") {
            throw XCTSkip("PTY input automation is unavailable in this test environment.")
        }
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(commands, [], "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Automation enabled; continuous continue mode armed."), stderr)
        XCTAssertFalse(stderr.contains("[fatal]"), stderr)
    }

    func testBundledGeminiAutomationRunnerDelaysEnterForPromptAndSlashAutomation() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = {
            initialPrompt: mod._test.shouldSubmitWithDelayedEnter('vitest and fix', 'initial-prompt'),
            continuePrompt: mod._test.shouldSubmitWithDelayedEnter('continue', 'continue'),
            slashCommand: mod._test.shouldSubmitWithDelayedEnter('/clear', 'startup-clear'),
            modelCommand: mod._test.shouldSubmitWithDelayedEnter('/model set gemini-3-flash-preview', 'model-switch gemini-3-flash-preview'),
            arbitrarySlashCommand: mod._test.shouldSubmitWithDelayedEnter('/help', 'manual'),
            menuChoice: mod._test.shouldSubmitWithDelayedEnter('2', 'permission'),
            yesNoApproval: mod._test.shouldSubmitWithDelayedEnter('y', 'yolo-auto-approve'),
            arbitraryTextCommand: mod._test.shouldSubmitWithDelayedEnter('Ship beta now', 'model-manage'),
            disabled: mod._test.shouldSubmitWithDelayedEnter('vitest and fix', 'initial-prompt', { submitDelayMs: 0 }),
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
        XCTAssertEqual(payload["initialPrompt"] as? Bool, true)
        XCTAssertEqual(payload["continuePrompt"] as? Bool, true)
        XCTAssertEqual(payload["slashCommand"] as? Bool, true)
        XCTAssertEqual(payload["modelCommand"] as? Bool, true)
        XCTAssertEqual(payload["arbitrarySlashCommand"] as? Bool, false)
        XCTAssertEqual(payload["menuChoice"] as? Bool, false)
        XCTAssertEqual(payload["yesNoApproval"] as? Bool, false)
        XCTAssertEqual(payload["arbitraryTextCommand"] as? Bool, false)
        XCTAssertEqual(payload["disabled"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerSubmitsInitialPromptWithDelayedEnterEndToEnd() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        let buffered = '';

        function write(text) {
          process.stdout.write(text);
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    gemini-3-flash-preview     ...\n');
          write('> ');
        }

        function consumeCompleteLines() {
          let newlineIndex = buffered.indexOf('\n');
          while (newlineIndex >= 0) {
            const line = buffered.slice(0, newlineIndex).trim();
            buffered = buffered.slice(newlineIndex + 1);
            if (line) {
              fs.appendFileSync(logPath, line + '\n');
            }
            if (line === 'vitest and fix') {
              write('\naccepted prompt after newline\n');
              setTimeout(() => process.exit(0), 60);
            }
            newlineIndex = buffered.indexOf('\n');
          }
        }

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          buffered += String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/\r/g, '\n')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '');
          consumeCompleteLines();
        });

        setTimeout(() => process.exit(7), 3500);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview"
        environment["GEMINI_INITIAL_PROMPT"] = "vitest and fix"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["STARTUP_CLEAR_COMMAND"] = " "
        environment["STARTUP_STATS_COMMAND"] = " "
        environment["STARTUP_MODEL_COMMAND"] = " "
        environment["PROMPT_SUBMIT_DELAY_MS"] = "80"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "100"
        environment["INITIAL_PROMPT_RETRY_MS"] = "40"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "16000"
        environment["NORMALIZED_TAIL_MAX"] = "12000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(6)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(commands, ["vitest and fix"], "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Auto-sending initial prompt"), stderr)
        XCTAssertFalse(stderr.contains("[fatal]"), stderr)
    }

    func testBundledGeminiAutomationRunnerRetriesInitialPromptWhenEnterIsSwallowed() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        let input = '';
        let swallowedPromptEnter = false;

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(command) {
          fs.appendFileSync(logPath, command + '\n');
        }

        function writePrompt(text = input) {
          write('\n'.repeat(80));
          write('? for shortcuts\n');
          write(text ? '* ' + text + '\n' : '*   Type your message or @path/to/file\n');
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    gemini-3-flash-preview     ...\n');
        }

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt('');

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          for (const char of String(data || '')) {
            if (char === '\u0015') {
              input = '';
              writePrompt('');
            } else if (char === '\r' || char === '\n') {
              const command = input.trim();
              if (command === 'lint features and fix' && !swallowedPromptEnter) {
                swallowedPromptEnter = true;
                logCommand('__PROMPT_ENTER_SWALLOWED__');
                writePrompt(input);
                continue;
              }
              if (command === 'lint features and fix') {
                logCommand(command);
                input = '';
                write('\naccepted prompt after retry\n');
                setTimeout(() => process.exit(0), 60);
              }
            } else if (char >= ' ') {
              input += char;
              writePrompt(input);
            }
          }
        });

        setTimeout(() => process.exit(7), 5000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview"
        environment["GEMINI_INITIAL_PROMPT"] = "lint features and fix"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["STARTUP_CLEAR_COMMAND"] = " "
        environment["STARTUP_STATS_COMMAND"] = " "
        environment["STARTUP_MODEL_COMMAND"] = " "
        environment["PROMPT_SUBMIT_DELAY_MS"] = "60"
        environment["PROMPT_SUBMIT_SETTLE_MS"] = "80"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "80"
        environment["INITIAL_PROMPT_RETRY_MS"] = "40"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1200"
        environment["INITIAL_PROMPT_SUBMIT_CONFIRM_MS"] = "80"
        environment["INITIAL_PROMPT_SUBMIT_RETRY_MAX"] = "2"
        environment["QUICK_RECHECK_MS"] = "30"
        environment["STATIC_RECHECK_MS"] = "50"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "16000"
        environment["NORMALIZED_TAIL_MAX"] = "12000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(7)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("__PROMPT_ENTER_SWALLOWED__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("lint features and fix"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("retrying Enter"), stderr)
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

    func testBundledGeminiAutomationRunnerExtractsStartupModelSelectorWithoutUsageRows() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let transcript = """
        ╭──────────────────────────────────────────────────────────────────────────────╮
        │ Select Model                                                                 │
        │ ● 1. gemini-3-flash-preview                                                  │
        │   2. gemini-3.1-flash-lite-preview                                           │
        │   3. gemini-2.5-flash                                                        │
        │   4. gemini-2.5-flash-lite                                                   │
        │                                                                              │
        │ Remember model for future sessions: false (Press Tab to toggle)              │
        │ > To use a specific Gemini model on startup, use the --model flag.           │
        │                                                                              │
        │ (Press Esc to close)                                                         │
        ╰──────────────────────────────────────────────────────────────────────────────╯
        """
        let encodedTranscript = String(data: try JSONEncoder().encode(transcript), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const snapshot = mod._test.extractStartupModelCapacitySnapshot(\(encodedTranscript));
          const closed = mod._test.hasStartupModelCapacityClosed(
            { kind: 'normal', chatPromptActive: true, promptInputText: '' },
            { screenText: \(encodedTranscript), visibleText: \(encodedTranscript), waitedForMs: 1000 }
          );
          process.stdout.write(JSON.stringify({ snapshot, closed }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let snapshot = try XCTUnwrap(payload["snapshot"] as? [String: Any])
        let rows = try XCTUnwrap(snapshot["rows"] as? [[String: Any]])

        XCTAssertEqual(snapshot["currentModel"] as? String, "gemini-3-flash-preview")
        XCTAssertEqual(rows.count, 0)
        XCTAssertEqual(payload["closed"] as? Bool, false)
    }

    func testBundledGeminiAutomationRunnerSwitchesFromStartupFullCapacityModelBeforePrompt() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        const modelArgIndex = process.argv.indexOf('--model');
        const launchModel = modelArgIndex >= 0 ? process.argv[modelArgIndex + 1] : '';
        let activeModel = launchModel;
        let modelPanelOpen = false;

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, activeModel + ':' + line + '\n');
        }

        function writeStatusRow() {
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    ' + activeModel + '     ...\n');
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          writeStatusRow();
          write('> ');
        }

        function writeScreenWithoutPrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          writeStatusRow();
        }

        function writeModelPanel() {
          modelPanelOpen = true;
          write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
          write('│ Select Model                                                                 │\n');
          write('│ Manual (' + activeModel + ')                                                  │\n');
          write('│ Model usage                                                                  │\n');
          write('│ gemini-3-flash-preview 100% Resets: 1:29 PM                                  │\n');
          write('│ gemini-3-pro-preview 0%                                                       │\n');
          write('│ gemini-2.5-flash 0%                                                          │\n');
          write('│ Press Esc to close                                                           │\n');
          write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        write('Gemini CLI v0.39.0\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          const raw = String(data || '');
          if (modelPanelOpen && raw.includes('\u001B')) {
            modelPanelOpen = false;
            writeScreenWithoutPrompt();
            setTimeout(writePrompt, 450);
          }

          for (const command of normalizeCommand(data)) {
            logCommand(command);
            if (command === '/clear') {
              writePrompt();
            } else if (command === '/stats') {
              write('Session Stats\n');
              write('Session ID: startup-capacity\n');
              write('Auth Method: Signed in with Google (smoke@example.com)\n');
              write('Tier: Gemini Code Assist for individuals\n');
              setTimeout(writePrompt, 80);
            } else if (command === '/model') {
              writeModelPanel();
            } else if (command === '/model set gemini-2.5-flash') {
              activeModel = 'gemini-2.5-flash';
              writePrompt();
            } else if (command === '/model set gemini-3-pro-preview') {
              process.exit(6);
            } else if (command === 'vitest and fix issues') {
              if (activeModel === launchModel) {
                process.exit(5);
              }
              write('\nWorking on fallback model\n');
              setTimeout(() => process.exit(0), 80);
            }
          }
        });

        setTimeout(() => process.exit(4), 9000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "stable"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview,gemini-3-pro-preview,gemini-2.5-flash"
        environment["MODEL_SWITCH_MODE"] = "set"
        environment["GEMINI_INITIAL_PROMPT"] = "vitest and fix issues"
        environment["AUTO_CONTINUE_MODE"] = "prompt_only"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "120"
        environment["PROMPT_SUBMIT_DELAY_MS"] = "20"
        environment["STARTUP_FIRST_COMMAND_DELAY_MS"] = "0"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "100"
        environment["INITIAL_PROMPT_RETRY_MS"] = "60"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "900"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "24000"
        environment["NORMALIZED_TAIL_MAX"] = "16000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(11)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-3-flash-preview:/model"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-3-flash-preview:/model set gemini-2.5-flash"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-2.5-flash:vitest and fix issues"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertFalse(commands.contains("gemini-3-flash-preview:vitest and fix issues"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertFalse(commands.contains("gemini-3-flash-preview:/model set gemini-3-pro-preview"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Startup model capacity shows gemini-3-flash-preview is at 100% usage — queueing in-session switch to gemini-2.5-flash"), stderr)
    }

    func testBundledGeminiAutomationRunnerAllowsStartupStatsWithoutVisiblePromptWhenScreenIsSettled() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const allowed = mod._test.canSendPromptCommandWithoutVisiblePrompt(
            { kind: 'startup-stats', createdAt: Date.now() - 1500 },
            { kind: 'normal', chatPromptActive: false },
            { quietForMs: 1500, waitedForMs: 1500, authWaiting: false, promptReadySurface: true }
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

    func testBundledGeminiAutomationRunnerDoesNotSendStartupCommandOnQuietNonPromptScreen() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const allowed = mod._test.canSendPromptCommandWithoutVisiblePrompt(
            { kind: 'startup-clear', createdAt: Date.now() - 3000 },
            { kind: 'normal', chatPromptActive: false },
            { quietForMs: 3000, waitedForMs: 3000, authWaiting: false, promptReadySurface: false }
          );
          process.stdout.write(String(allowed));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "false")
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
            "gemini-2.5-flash-lite"
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

    func testBundledGeminiAutomationRunnerBuildsDirectModelSwitchForPolicyFallback() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let chain = [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview"
        ]
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedChain = String(data: try JSONEncoder().encode(chain), encoding: .utf8) ?? "[]"
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const command = mod._test.buildDirectModelSwitchCommand(
            1,
            'Free-tier policy banner detected',
            \(encodedChain)
          );
          process.stdout.write(JSON.stringify(command));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "model-switch")
        XCTAssertEqual(payload["text"] as? String, "/model set gemini-3-flash-preview")
        XCTAssertEqual(payload["targetModel"] as? String, "gemini-3-flash-preview")
    }

    func testBundledGeminiAutomationRunnerConfirmsDirectModelSwitchOnlyFromVisibleModelState() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let staleStatusTranscript = """
        workspace (/directory)     branch     sandbox       /model
        /Users/.../clilauncher     main       no sandbox    gemini-3-pro-preview     ...
        >
        """
        let switchedStatusTranscript = """
        workspace (/directory)     branch     sandbox       /model
        /Users/.../clilauncher     main       no sandbox    gemini-3-pro-preview     ...
        workspace (/directory)     branch     sandbox       /model
        /Users/.../clilauncher     main       no sandbox    gemini-3-flash-preview     ...
        >
        """
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedStaleTranscript = String(data: try JSONEncoder().encode(staleStatusTranscript), encoding: .utf8) ?? "\"\""
        let encodedSwitchedTranscript = String(data: try JSONEncoder().encode(switchedStatusTranscript), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const stale = \(encodedStaleTranscript);
          const switched = \(encodedSwitchedTranscript);
          const staleResolution = mod._test.resolveDirectModelSwitchConfirmation('gemini-3-flash-preview', {
            screenText: stale,
          });
          const switchedResolution = mod._test.resolveDirectModelSwitchConfirmation('gemini-3-flash-preview', {
            screenText: switched,
          });
          const payload = {
            staleVisibleModel: mod._test.extractVisibleCurrentModel(stale),
            switchedVisibleModel: mod._test.extractVisibleCurrentModel(switched),
            staleConfirmed: staleResolution.confirmed,
            staleObservedModel: staleResolution.observedModel,
            switchedConfirmed: switchedResolution.confirmed,
            switchedObservedModel: switchedResolution.observedModel,
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
        XCTAssertEqual(payload["staleVisibleModel"] as? String, "gemini-3-pro-preview")
        XCTAssertEqual(payload["staleObservedModel"] as? String, "gemini-3-pro-preview")
        XCTAssertEqual(payload["staleConfirmed"] as? Bool, false)
        XCTAssertEqual(payload["switchedVisibleModel"] as? String, "gemini-3-flash-preview")
        XCTAssertEqual(payload["switchedObservedModel"] as? String, "gemini-3-flash-preview")
        XCTAssertEqual(payload["switchedConfirmed"] as? Bool, true)
    }

    func testBundledGeminiAutomationRunnerReconcilesVisibleModelBeforeFallbackSelection() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let statusTranscript = """
        ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
         * /model set gemini-3-flash-preview
        ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
        workspace (/directory)     branch     sandbox       /model
        /Users/.../clilauncher     main       no sandbox    gemini-3-pro-preview     ...
        >
        """
        let chain = [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview",
            "gemini-2.5-flash"
        ]
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedTranscript = String(data: try JSONEncoder().encode(statusTranscript), encoding: .utf8) ?? "\"\""
        let encodedChain = String(data: try JSONEncoder().encode(chain), encoding: .utf8) ?? "[]"
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = mod._test.resolveModelIndexFromVisibleCurrentModel(
            \(encodedChain),
            1,
            \(encodedTranscript)
          );
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
        XCTAssertEqual(payload["modelIndex"] as? Int, 0)
        XCTAssertEqual(payload["visibleModel"] as? String, "gemini-3-pro-preview")
        XCTAssertEqual(payload["visibleIndex"] as? Int, 0)
        XCTAssertEqual(payload["changed"] as? Bool, true)
    }

    func testBundledGeminiAutomationRunnerPrefersCurrentScreenModelOverRetainedTail() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let currentScreen = """
        workspace (/directory)     branch     sandbox       /model
        /Users/.../clilauncher     main       no sandbox    gemini-3-pro-preview     ...
        >
        """
        let retainedTail = """
        workspace (/directory)     branch     sandbox       /model
        /Users/.../clilauncher     main       no sandbox    gemini-3-flash-preview     ...
        >
        """
        let chain = [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview",
            "gemini-2.5-flash"
        ]
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedCurrentScreen = String(data: try JSONEncoder().encode(currentScreen), encoding: .utf8) ?? "\"\""
        let encodedRetainedTail = String(data: try JSONEncoder().encode(retainedTail), encoding: .utf8) ?? "\"\""
        let encodedChain = String(data: try JSONEncoder().encode(chain), encoding: .utf8) ?? "[]"
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const payload = mod._test.resolveModelIndexFromVisibleTerminalTexts(
            \(encodedChain),
            1,
            \(encodedCurrentScreen),
            \(encodedRetainedTail)
          );
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
        XCTAssertEqual(payload["modelIndex"] as? Int, 0)
        XCTAssertEqual(payload["visibleModel"] as? String, "gemini-3-pro-preview")
        XCTAssertEqual(payload["visibleIndex"] as? Int, 0)
        XCTAssertEqual(payload["changed"] as? Bool, true)
    }

    func testBundledGeminiAutomationRunnerCanIgnoreBackwardVisibleModelCorrectionForUsageLimit() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let staleCurrentScreen = """
        workspace (/directory)     branch     sandbox       /model
        /Users/.../clilauncher     main       no sandbox    gemini-3-pro-preview     ...
        >
        """
        let chain = [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview",
            "gemini-2.5-flash"
        ]
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedCurrentScreen = String(data: try JSONEncoder().encode(staleCurrentScreen), encoding: .utf8) ?? "\"\""
        let encodedChain = String(data: try JSONEncoder().encode(chain), encoding: .utf8) ?? "[]"
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const chain = \(encodedChain);
          const payload = mod._test.resolveModelIndexFromVisibleTerminalTexts(
            chain,
            1,
            \(encodedCurrentScreen),
            "",
            { allowBackward: false }
          );
          const nextIndex = mod._test.findNextEligibleModelIndexInChain(chain, payload.modelIndex);
          process.stdout.write(JSON.stringify({ ...payload, nextIndex, nextModel: chain[nextIndex] }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(payload["modelIndex"] as? Int, 1)
        XCTAssertEqual(payload["visibleModel"] as? String, "gemini-3-pro-preview")
        XCTAssertEqual(payload["visibleIndex"] as? Int, 0)
        XCTAssertEqual(payload["changed"] as? Bool, false)
        XCTAssertEqual(payload["ignored"] as? Bool, true)
        XCTAssertEqual(payload["nextIndex"] as? Int, 2)
        XCTAssertEqual(payload["nextModel"] as? String, "gemini-2.5-flash")
    }

    func testBundledGeminiAutomationRunnerModelSwitchPreemptsScheduledStartupCommand() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let chain = [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview"
        ]
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let encodedChain = String(data: try JSONEncoder().encode(chain), encoding: .utf8) ?? "[]"
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const startupClear = {
            kind: 'startup-clear',
            text: '/clear',
            label: '/clear',
          };
          const directSwitch = mod._test.buildDirectModelSwitchCommand(
            1,
            'Free-tier policy banner detected',
            \(encodedChain)
          );
          const payload = {
            staleStartupCurrent: mod._test.isPromptCommandStillCurrent(startupClear, directSwitch),
            activeSwitchCurrent: mod._test.isPromptCommandStillCurrent(directSwitch, directSwitch),
            startupCurrent: mod._test.isPromptCommandStillCurrent(startupClear, startupClear),
            modelSwitchPriority: mod._test.promptCommandPriority('model-switch'),
            statsSessionPriority: mod._test.promptCommandPriority('stats-session'),
            startupPriority: mod._test.promptCommandPriority('startup-clear'),
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
        XCTAssertEqual(payload["staleStartupCurrent"] as? Bool, false)
        XCTAssertEqual(payload["activeSwitchCurrent"] as? Bool, true)
        XCTAssertEqual(payload["startupCurrent"] as? Bool, true)
        let modelSwitchPriority = try XCTUnwrap(payload["modelSwitchPriority"] as? Int)
        let statsSessionPriority = try XCTUnwrap(payload["statsSessionPriority"] as? Int)
        let startupPriority = try XCTUnwrap(payload["startupPriority"] as? Int)
        XCTAssertGreaterThan(modelSwitchPriority, startupPriority)
        XCTAssertGreaterThan(statsSessionPriority, startupPriority)
    }

    func testBundledGeminiAutomationRunnerDescribesPromptCommandSendDetail() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        import(\(encodedImportURL)).then((mod) => {
          const command = {
            kind: 'startup-clear',
            text: '/clear',
            createdAt: 1000,
          };
          const payload = {
            visible: mod._test.describePromptCommandSendDetail(command, { chatPromptActive: true }, {
              now: 2000,
              quietForMs: 0,
              waitedForMs: 1000,
            }),
            settled: mod._test.describePromptCommandSendDetail(command, { chatPromptActive: false }, {
              now: 2000,
              quietForMs: 1376,
              waitedForMs: 1000,
            }),
            timeout: mod._test.describePromptCommandSendDetail(command, { chatPromptActive: false }, {
              now: 1123,
              quietForMs: 0,
              waitedForMs: 123,
            }),
            ignored: mod._test.describePromptCommandSendDetail({ kind: 'model-switch', text: '/model set gemini-3-flash-preview' }, { chatPromptActive: true }),
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
        XCTAssertEqual(payload["visible"] as? String, "visible prompt field")
        XCTAssertEqual(payload["settled"] as? String, "settled normal screen (1376ms quiet)")
        XCTAssertEqual(payload["timeout"] as? String, "prompt timeout (123ms)")
        XCTAssertEqual(payload["ignored"] as? String, "")
    }

    func testBundledGeminiAutomationRunnerUsesShortStartupFirstCommandDelay() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let encodedImportURL = String(data: try JSONEncoder().encode(runnerURLString), encoding: .utf8) ?? "\"\""
        let script = """
        delete process.env.STARTUP_FIRST_COMMAND_DELAY_MS;
        import(\(encodedImportURL)).then((mod) => {
          const command = mod._test.buildStartupCommandPipeline({ startupStatsAutomationSupported: true });
          process.stdout.write(JSON.stringify({
            kind: command?.kind || '',
            delayMs: Math.max(0, Number(command?.notBeforeAt || 0) - Number(command?.createdAt || 0)),
          }));
        }).catch((error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """

        let result = try runNodeScript(script)
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)

        let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "startup-clear")
        let delayMs = try XCTUnwrap(payload["delayMs"] as? Int)
        XCTAssertGreaterThanOrEqual(delayMs, 120)
        XCTAssertLessThanOrEqual(delayMs, 260)
    }

    func testBundledGeminiAutomationRunnerContinuesInitialPromptWhenStartupStatsTimesOut() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        let clearSeen = false;
        let statsSeen = false;
        let modelPanelSeen = false;
        let modelPanelClosed = false;
        let promptSeen = false;

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, line + '\n');
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    gemini-3-pro-preview     ...\n');
          write('> ');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          if (modelPanelSeen && String(data).includes('\u001B')) {
            modelPanelClosed = true;
            writePrompt();
          }

          for (const command of normalizeCommand(data)) {
            logCommand(command);
            if (command === '/clear') {
              clearSeen = true;
              writePrompt();
            } else if (command === '/stats') {
              statsSeen = true;
              write('\nNo stats panel appeared for this fake CLI build.\n');
              writePrompt();
            } else if (command === '/model') {
              modelPanelSeen = true;
              write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
              write('│ Select Model                                                                 │\n');
              write('│ ● 1. Manual (gemini-3-pro-preview)                                           │\n');
              write('│                                                                              │\n');
              write('│ Model usage                                                                  │\n');
              write('│ Pro             ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬                 82% Resets: 1:29 PM   │\n');
              write('│ Flash           ▬                                      7%                    │\n');
              write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
            } else if (command === 'Ship beta now') {
              promptSeen = true;
              write('\nWorking on it\n> ');
            }
          }

          if (clearSeen && statsSeen && modelPanelSeen && modelPanelClosed && promptSeen) {
            setTimeout(() => process.exit(0), 80);
          }
        });

        setTimeout(() => process.exit(0), 12000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-pro-preview"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "100"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "80"
        environment["INITIAL_PROMPT_RETRY_MS"] = "50"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1200"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "350"
        environment["RAW_TAIL_MAX"] = "20000"
        environment["NORMALIZED_TAIL_MAX"] = "12000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(14)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Startup session stats: unavailable (startup /stats output was not detected in time)"), stderr)
        XCTAssertTrue(stderr.contains("Startup model capacity: captured"), stderr)
        XCTAssertTrue(stderr.contains("Auto-sending initial prompt"), stderr)
        XCTAssertFalse(stderr.contains("Initial prompt delivery: blocked until startup"), stderr)
        XCTAssertFalse(stderr.contains("Startup sequence: blocked"), stderr)
        XCTAssertTrue(commands.contains("/clear"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("/stats"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("/model"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("Ship beta now"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        let modelCommandIndex = try XCTUnwrap(commands.firstIndex(of: "/model"))
        let promptCommandIndex = try XCTUnwrap(commands.firstIndex(of: "Ship beta now"))
        XCTAssertLessThan(modelCommandIndex, promptCommandIndex, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
    }

    func testBundledGeminiAutomationRunnerClosesModelSelectorWithoutUsageRowsBeforeInitialPrompt() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        let clearSeen = false;
        let statsSeen = false;
        let modelPanelSeen = false;
        let modelPanelClosed = false;
        let promptSeen = false;

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, line + '\n');
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    gemini-3-flash-preview     ...\n');
          write('> ');
        }

        function writeModelSelectorWithoutUsageRows() {
          modelPanelSeen = true;
          write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
          write('│ Select Model                                                                 │\n');
          write('│ ● 1. gemini-3-flash-preview                                                  │\n');
          write('│   2. gemini-3.1-flash-lite-preview                                           │\n');
          write('│   3. gemini-2.5-flash                                                        │\n');
          write('│   4. gemini-2.5-flash-lite                                                   │\n');
          write('│                                                                              │\n');
          write('│ Remember model for future sessions: false (Press Tab to toggle)              │\n');
          write('│ > To use a specific Gemini model on startup, use the --model flag.           │\n');
          write('│                                                                              │\n');
          write('│ (Press Esc to close)                                                         │\n');
          write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        write('Gemini CLI v0.41.0-nightly\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          if (modelPanelSeen && !modelPanelClosed && String(data).includes('\u001B')) {
            modelPanelClosed = true;
            logCommand('__ESC__');
            writePrompt();
          }

          for (const command of normalizeCommand(data)) {
            logCommand(command);
            if (command === '/clear') {
              clearSeen = true;
              writePrompt();
            } else if (command === '/stats') {
              statsSeen = true;
              write('Session Stats\n');
              write('Session ID: selector-without-usage\n');
              write('Auth Method: Signed in with Google (smoke@example.com)\n');
              write('Tier: Gemini Code Assist for individuals\n');
              write('Model Usage\n');
              write('gemini-3-flash-preview          1            0            0             0\n');
              writePrompt();
            } else if (command === '/model') {
              writeModelSelectorWithoutUsageRows();
            } else if (command === 'Ship beta now') {
              promptSeen = true;
              write('\nWorking on it\n> ');
            }
          }

          if (clearSeen && statsSeen && modelPanelSeen && modelPanelClosed && promptSeen) {
            setTimeout(() => process.exit(0), 80);
          }
        });

        setTimeout(() => process.exit(promptSeen ? 0 : 6), 9000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "nightly"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "100"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "80"
        environment["INITIAL_PROMPT_RETRY_MS"] = "50"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1200"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "600"
        environment["RAW_TAIL_MAX"] = "20000"
        environment["NORMALIZED_TAIL_MAX"] = "12000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(11)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Startup model capacity: captured (current gemini-3-flash-preview)"), stderr)
        XCTAssertFalse(stderr.contains("startup /model output was not detected in time"), stderr)
        XCTAssertTrue(commands.contains("/model"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("__ESC__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("Ship beta now"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        let escIndex = try XCTUnwrap(commands.firstIndex(of: "__ESC__"))
        let promptCommandIndex = try XCTUnwrap(commands.firstIndex(of: "Ship beta now"))
        XCTAssertLessThan(escIndex, promptCommandIndex, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
    }

    func testBundledGeminiAutomationRunnerClearsStuckStartupModelInputBeforeInitialPrompt() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        let inputBuffer = '';
        let clearSeen = false;
        let statsSeen = false;
        let modelStuck = false;
        let ctrlUSeen = false;
        let promptSeen = false;

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, line + '\n');
        }

        function writePrompt(text = '') {
          write('\n'.repeat(80));
          write('? for shortcuts\n');
          write(text ? '* ' + text + '\n' : '*   Type your message or @path/to/file\n');
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    gemini-3-pro-preview     ...\n');
        }

        function submit(command) {
          if (!command) return;
          if (command === '/clear') {
            clearSeen = true;
            logCommand(command);
            writePrompt();
          } else if (command === '/stats') {
            statsSeen = true;
            logCommand(command);
            write('Session Stats\n');
            write('Session ID: startup-stuck-model\n');
            write('Auth Method: Signed in with Google (smoke@example.com)\n');
            write('Tier: Gemini Code Assist for individuals\n');
            write('Model Usage\n');
            write('gemini-3-pro-preview          1            0            0             0\n');
            writePrompt();
          } else if (command === '/model' && !modelStuck) {
            modelStuck = true;
            inputBuffer = '/model';
            logCommand('__MODEL_STUCK_IN_INPUT__');
            writePrompt(inputBuffer);
          } else if (command === 'Ship beta now') {
            promptSeen = true;
            logCommand(command);
            write('\nWorking on it\n');
            writePrompt();
          } else {
            logCommand(command);
            writePrompt();
          }
        }

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          for (const char of String(data || '')) {
            if (char === '\u0015') {
              ctrlUSeen = true;
              inputBuffer = '';
              logCommand('__CTRL_U__');
              writePrompt();
            } else if (char === '\r' || char === '\n') {
              const command = inputBuffer.trim();
              inputBuffer = '';
              submit(command);
            } else if (char >= ' ') {
              inputBuffer += char;
              writePrompt(inputBuffer);
            }
          }

          if (clearSeen && statsSeen && modelStuck && ctrlUSeen && promptSeen) {
            setTimeout(() => process.exit(0), 80);
          }
        });

        setTimeout(() => process.exit(promptSeen ? 0 : 4), 7000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-pro-preview"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "100"
        environment["PROMPT_SUBMIT_DELAY_MS"] = "60"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "80"
        environment["INITIAL_PROMPT_RETRY_MS"] = "50"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1200"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "350"
        environment["RAW_TAIL_MAX"] = "20000"
        environment["NORMALIZED_TAIL_MAX"] = "12000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Startup session stats: unavailable (startup /model output was not detected in time)"), stderr)
        XCTAssertTrue(commands.contains("__MODEL_STUCK_IN_INPUT__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("__CTRL_U__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("Ship beta now"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertFalse(commands.contains("/modelShip beta now"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
    }

    func testBundledGeminiAutomationRunnerPolicyBannerSwitchPreemptsStartupInjectionEndToEnd() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        let modelSwitchSeen = false;
        let clearSeen = false;
        let statsSeen = false;
        let modelPanelSeen = false;
        let modelPanelClosed = false;
        let promptSeen = false;

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, line + '\n');
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          write('> ');
        }

        function writeStatusRow(model) {
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    ' + model + '     ...\n');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        write('> ');

        setTimeout(() => {
          write('\nWe are making changes to Gemini CLI that may impact your workflow.\n');
          write('What is Changing: restricting models for free tier users.\n');
          write('How it affects you: upgrade to a supported paid plan.\n');
          write('Read more: https://goo.gle/geminicli-updates\n');
          write('> ');
        }, 45);

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          if (modelPanelSeen && String(data).includes('\u001B')) {
            modelPanelClosed = true;
            writePrompt();
          }

          for (const command of normalizeCommand(data)) {
            logCommand(command);
            if (command === '/model set gemini-3-flash-preview') {
              modelSwitchSeen = true;
              write('\nModel set to gemini-3-flash-preview\n');
              writeStatusRow('gemini-3-flash-preview');
              write('> ');
            } else if (command === '/clear') {
              clearSeen = true;
              writePrompt();
            } else if (command === '/stats') {
              statsSeen = true;
              write('\u001B[2J\u001B[H');
              write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
              write('│  Session Stats                                                               │\n');
              write('│  Interaction Summary                                                         │\n');
              write('│  Session ID:                 smoke-session                                   │\n');
              write('│  Auth Method:                Signed in with Google (smoke@example.com)       │\n');
              write('│  Tier:                       Gemini Code Assist for individuals              │\n');
              write('│  Tool Calls:                 0 ( ✓ 0 x 0 )                                   │\n');
              write('│  Performance                                                                 │\n');
              write('│  Wall Time:                  1.2s                                            │\n');
              write('│  Model Usage                                                                 │\n');
              write('│  Model                         Reqs Input Tokens Cache Reads Output Tokens    │\n');
              write('│  gemini-3-flash-preview          1            0            0             0   │\n');
              write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
              setTimeout(() => {
                writePrompt();
              }, 120);
            } else if (command === '/model') {
              modelPanelSeen = true;
              write('\u001B[2J\u001B[H');
              write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
              write('│ Select Model                                                                 │\n');
              write('│ ● 1. Manual (gemini-3-flash-preview)                                         │\n');
              write('│   2. Auto                                                                    │\n');
              write('│ Model usage                                                                  │\n');
              write('│ Pro             ▬▬▬▬▬▬▬▬▬▬▬▬▬▬                         82% Resets: 1:29 PM   │\n');
              write('│ Flash           ▬                                      7% Resets: 1:29 PM    │\n');
              write('│ Flash Lite                                             0%                    │\n');
              write('│ Press Esc to close                                                           │\n');
              write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
              setTimeout(() => {
                modelPanelClosed = true;
                writePrompt();
              }, 120);
            } else if (command === 'Ship beta now') {
              promptSeen = true;
              write('\nWorking on it\n> ');
            }
          }

          if (modelSwitchSeen && clearSeen && statsSeen && modelPanelSeen && modelPanelClosed && promptSeen) {
            setTimeout(() => process.exit(0), 80);
          }
        });

        setTimeout(() => process.exit(0), 12000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-pro-preview,gemini-3-flash-preview"
        environment["MODEL_SWITCH_MODE"] = "set"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "180"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "120"
        environment["INITIAL_PROMPT_RETRY_MS"] = "80"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
        environment["QUICK_RECHECK_MS"] = "50"
        environment["STATIC_RECHECK_MS"] = "80"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "1000"
        environment["RAW_TAIL_MAX"] = "20000"
        environment["NORMALIZED_TAIL_MAX"] = "12000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(14)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Runner build: 20260426T090000Z"), stderr)
        XCTAssertTrue(stderr.contains("Free-tier policy banner detected"), stderr)
        XCTAssertTrue(stderr.contains("Startup session stats: captured"), stderr)
        XCTAssertTrue(stderr.contains("Startup model capacity: captured"), stderr)
        XCTAssertTrue(stderr.contains("Auto-sending initial prompt"), stderr)
        XCTAssertFalse(stderr.contains("[fatal]"), stderr)
        XCTAssertFalse(stderr.contains("ReferenceError"), stderr)
        XCTAssertFalse(stderr.contains("sendReason"), stderr)
        XCTAssertEqual(commands, [
            "/model set gemini-3-flash-preview",
            "/clear",
            "/stats",
            "/model",
            "Ship beta now"
        ], "stdout:\n\(stdout)\nstderr:\n\(stderr)")
    }

    func testBundledGeminiAutomationRunnerRelaunchesWhenDirectModelSwitchIsNotConfirmed() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let launchLogURL = tempDirectory.appendingPathComponent("launches.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        const launchLogPath = process.env.FAKE_GEMINI_LAUNCH_LOG;
        const modelArgIndex = process.argv.indexOf('--model');
        const launchModel = modelArgIndex >= 0 ? process.argv[modelArgIndex + 1] : '';
        const startsOnFlash = launchModel === 'gemini-3-flash-preview';
        let clearSeen = false;
        let statsSeen = false;
        let modelPanelSeen = false;
        let modelPanelClosed = false;
        let promptSeen = false;

        fs.appendFileSync(launchLogPath, launchModel + '\n');

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, line + '\n');
        }

        function writeStatusRow(model) {
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    ' + model + '     ...\n');
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          writeStatusRow(launchModel || 'gemini-3-pro-preview');
          write('> ');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        process.on('SIGINT', () => {
          logCommand('__SIGINT__');
          process.exit(130);
        });

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        if (!startsOnFlash) {
          write('\nWe are making changes to Gemini CLI that may impact your workflow.\n');
          write('What is Changing: restricting models for free tier users.\n');
          write('How it affects you: upgrade to a supported paid plan.\n');
          write('Read more: https://goo.gle/geminicli-updates\n');
        }
        writeStatusRow(launchModel || 'gemini-3-pro-preview');
        write('> ');

        process.stdin.setEncoding('utf8');
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          if (modelPanelSeen && String(data).includes('\u001B')) {
            modelPanelClosed = true;
            writePrompt();
          }

          for (const command of normalizeCommand(data)) {
            logCommand(command);
            if (command === '/model set gemini-3-flash-preview') {
              write('\nModel set command ignored by fake CLI\n');
              writeStatusRow('gemini-3-pro-preview');
              write('> ');
            } else if (command === '/clear') {
              clearSeen = true;
              writePrompt();
            } else if (command === '/stats') {
              statsSeen = true;
              write('\u001B[2J\u001B[H');
              write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
              write('│  Session Stats                                                               │\n');
              write('│  Interaction Summary                                                         │\n');
              write('│  Session ID:                 smoke-session                                   │\n');
              write('│  Auth Method:                Signed in with Google (smoke@example.com)       │\n');
              write('│  Tier:                       Gemini Code Assist for individuals              │\n');
              write('│  Tool Calls:                 0 ( ✓ 0 x 0 )                                   │\n');
              write('│  Performance                                                                 │\n');
              write('│  Wall Time:                  1.2s                                            │\n');
              write('│  Model Usage                                                                 │\n');
              write('│  Model                         Reqs Input Tokens Cache Reads Output Tokens    │\n');
              write('│  gemini-3-flash-preview          1            0            0             0   │\n');
              write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
              setTimeout(() => {
                writePrompt();
              }, 90);
            } else if (command === '/model') {
              modelPanelSeen = true;
              write('\u001B[2J\u001B[H');
              write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
              write('│ Select Model                                                                 │\n');
              write('│ ● 1. Manual (gemini-3-flash-preview)                                         │\n');
              write('│   2. Auto                                                                    │\n');
              write('│ Model usage                                                                  │\n');
              write('│ Flash           ▬                                      7% Resets: 1:29 PM    │\n');
              write('│ Press Esc to close                                                           │\n');
              write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
              setTimeout(() => {
                modelPanelClosed = true;
                writePrompt();
              }, 90);
            } else if (command === 'Ship beta now') {
              promptSeen = true;
              write('\nWorking on it\n> ');
            }
          }

          if (startsOnFlash && clearSeen && statsSeen && modelPanelSeen && modelPanelClosed && promptSeen) {
            setTimeout(() => process.exit(0), 80);
          }
        });

        setTimeout(() => process.exit(startsOnFlash ? 0 : 2), 7000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)
        try "".write(to: launchLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-pro-preview,gemini-3-flash-preview"
        environment["MODEL_SWITCH_MODE"] = "set"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["FAKE_GEMINI_LAUNCH_LOG"] = launchLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "120"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "100"
        environment["INITIAL_PROMPT_RETRY_MS"] = "60"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "450"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "24000"
        environment["NORMALIZED_TAIL_MAX"] = "16000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(9)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let launches = try String(contentsOf: launchLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(launches, [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview"
        ], "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("direct model switch to gemini-3-flash-preview was not confirmed; visible model is gemini-3-pro-preview"), stderr)
        XCTAssertTrue(stderr.contains("relaunching directly on gemini-3-flash-preview"), stderr)
        XCTAssertTrue(stderr.contains("Launching model: gemini-3-flash-preview"), stderr)
        XCTAssertTrue(stderr.contains("Startup session stats: captured"), stderr)
        XCTAssertTrue(stderr.contains("Startup model capacity: captured"), stderr)
        XCTAssertTrue(stderr.contains("Auto-sending initial prompt"), stderr)
        XCTAssertFalse(stderr.contains("[fatal]"), stderr)
        XCTAssertTrue(commands.contains("__SIGINT__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(Array(commands.suffix(4)), [
            "/clear",
            "/stats",
            "/model",
            "Ship beta now"
        ], "stdout:\n\(stdout)\nstderr:\n\(stderr)")
    }

    func testBundledGeminiAutomationRunnerRelaunchesBlockedUsageLimitEndToEnd() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let launchLogURL = tempDirectory.appendingPathComponent("launches.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        const launchLogPath = process.env.FAKE_GEMINI_LAUNCH_LOG;
        const modelArgIndex = process.argv.indexOf('--model');
        const launchModel = modelArgIndex >= 0 ? process.argv[modelArgIndex + 1] : '';
        const fallbackLaunch = launchModel === 'gemini-2.5-flash';
        let clearSeen = false;
        let statsSeen = false;
        let modelPanelSeen = false;
        let modelPanelClosed = false;
        let promptSeen = false;

        fs.appendFileSync(launchLogPath, launchModel + '\n');

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, launchModel + ':' + line + '\n');
        }

        function writeStatusRow() {
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    ' + launchModel + '     ...\n');
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          writeStatusRow();
          write('> ');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        process.on('SIGINT', () => {
          logCommand('__SIGINT__');
          process.exit(130);
        });

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          if (modelPanelSeen && String(data).includes('\u001B')) {
            modelPanelClosed = true;
            writePrompt();
          }

          for (const command of normalizeCommand(data)) {
            logCommand(command);
            if (command === '/clear') {
              clearSeen = true;
              writePrompt();
            } else if (command === '/stats') {
              statsSeen = true;
              write('Session Stats\n');
              write('Session ID: smoke-session\n');
              write('Auth Method: Signed in with Google (smoke@example.com)\n');
              write('Tier: Gemini Code Assist for individuals\n');
              write('Model Usage\n');
              write('Model                         Reqs Input Tokens Cache Reads Output Tokens\n');
              write(launchModel + '          1            0            0             0\n');
              setTimeout(writePrompt, 80);
            } else if (command === '/model') {
              modelPanelSeen = true;
              write('Select Model\n');
              write('Manual (' + launchModel + ')\n');
              write('Model usage\n');
              write('Flash           24% Resets: 1:29 PM\n');
              write('Press Esc to close\n');
            } else if (command === 'Ship beta now') {
              promptSeen = true;
              if (fallbackLaunch) {
                write('\nWorking on fallback\n> ');
              } else {
                write('\nX [API Error: You have exhausted your capacity on this model. Your quota will reset after 2h0m7s.]\n');
              }
            }
          }

          if (fallbackLaunch && clearSeen && statsSeen && promptSeen) {
            setTimeout(() => process.exit(0), 80);
          }
        });

        setTimeout(() => process.exit(fallbackLaunch ? 0 : 3), 7000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)
        try "".write(to: launchLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview,gemini-3-pro-preview,gemini-2.5-flash"
        environment["MODEL_SWITCH_MODE"] = "manage"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["AUTO_CONTINUE_MODE"] = "prompt_only"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["FAKE_GEMINI_LAUNCH_LOG"] = launchLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "120"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "100"
        environment["INITIAL_PROMPT_RETRY_MS"] = "60"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "450"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "24000"
        environment["NORMALIZED_TAIL_MAX"] = "16000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(16)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let launches = try String(contentsOf: launchLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(launches, [
            "gemini-3-flash-preview",
            "gemini-2.5-flash"
        ], "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Usage limit reached on gemini-3-flash-preview (usage limit screen has no Stop option) — restarting on gemini-2.5-flash"), stderr)
        XCTAssertTrue(stderr.contains("Launching model: gemini-2.5-flash"), stderr)
        XCTAssertTrue(stderr.contains("Auto-sending initial prompt"), stderr)
        XCTAssertFalse(stderr.contains("queueing /stats session and /model manage for gemini-2.5-flash"), stderr)
        XCTAssertTrue(commands.contains("gemini-2.5-flash:Ship beta now"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
    }

    func testBundledGeminiAutomationRunnerSwitchesModelWhenUsageLimitReturnsToPrompt() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let launchLogURL = tempDirectory.appendingPathComponent("launches.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        const launchLogPath = process.env.FAKE_GEMINI_LAUNCH_LOG;
        const modelArgIndex = process.argv.indexOf('--model');
        const launchModel = modelArgIndex >= 0 ? process.argv[modelArgIndex + 1] : '';
        let activeModel = launchModel;
        let modelPanelOpen = false;
        let promptAttempts = 0;
        let switched = false;

        fs.appendFileSync(launchLogPath, launchModel + '\n');

        function write(text) { process.stdout.write(text); }
        function logCommand(line) { fs.appendFileSync(logPath, activeModel + ':' + line + '\n'); }

        function writeStatusRow() {
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    ' + activeModel + '     ...\n');
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          writeStatusRow();
          write('> ');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        process.on('SIGINT', () => {
          logCommand('__SIGINT__');
          process.exit(130);
        });

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          const raw = String(data || '');
          if (modelPanelOpen && raw.includes('\u001B')) {
            modelPanelOpen = false;
            writePrompt();
          }

          for (const command of normalizeCommand(data)) {
            logCommand(command);
            if (command === '/clear') {
              writePrompt();
            } else if (command === '/stats') {
              write('Session Stats\n');
              write('Session ID: smoke-session\n');
              write('Auth Method: Signed in with Google (smoke@example.com)\n');
              write('Tier: Gemini Code Assist for individuals\n');
              write('Model Usage\n');
              write('Model                         Reqs Input Tokens Cache Reads Output Tokens\n');
              write(activeModel + '          1            0            0             0\n');
              setTimeout(writePrompt, 80);
            } else if (command === '/model') {
              modelPanelOpen = true;
              write('Select Model\n');
              write('Manual (' + activeModel + ')\n');
              write('Model usage\n');
              write(activeModel + ' 24% Resets: 1:29 PM\n');
              write('Press Esc to close\n');
            } else if (command === 'Ship beta now') {
              promptAttempts += 1;
              if (activeModel === 'gemini-3-flash-preview') {
                write('\nX [API Error: You have exhausted your capacity on this model. Your quota will reset after 2h0m7s.]\n');
                for (let index = 0; index < 260; index += 1) {
                  write('redraw frame ' + index + '\n');
                }
                writePrompt();
              } else {
                write('\nWorking on fallback\n');
                writePrompt();
              }
            } else if (command === '/model set gemini-2.5-flash') {
              activeModel = 'gemini-2.5-flash';
              switched = true;
              write('\nModel set to gemini-2.5-flash\n');
              writePrompt();
            }
          }

          if (switched && promptAttempts >= 2) {
            setTimeout(() => process.exit(0), 80);
          }
        });

        setTimeout(() => process.exit(switched && promptAttempts >= 2 ? 0 : 3), 8000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)
        try "".write(to: launchLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview,gemini-2.5-flash"
        environment["MODEL_SWITCH_MODE"] = "set"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["AUTO_CONTINUE_MODE"] = "prompt_only"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["FAKE_GEMINI_LAUNCH_LOG"] = launchLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "120"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "100"
        environment["INITIAL_PROMPT_RETRY_MS"] = "60"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "650"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "24000"
        environment["NORMALIZED_TAIL_MAX"] = "16000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(9)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let launches = try String(contentsOf: launchLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(launches, ["gemini-3-flash-preview"], "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-3-flash-preview:/model set gemini-2.5-flash"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-2.5-flash:Ship beta now"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Usage limit reached on gemini-3-flash-preview — queueing in-session switch to gemini-2.5-flash."), stderr)
        XCTAssertFalse(commands.contains("gemini-3-flash-preview:/model set gemini-3-pro-preview"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertFalse(stderr.contains("queueing in-session switch to gemini-3-pro-preview"), stderr)
        XCTAssertFalse(stderr.contains("usage limit screen has no Stop option"), stderr)
        XCTAssertFalse(stderr.contains("restarting on gemini-2.5-flash"), stderr)
    }

    func testBundledGeminiAutomationRunnerClearsStaleContinueBeforeUsageLimitModelSwitch() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        const modelArgIndex = process.argv.indexOf('--model');
        let activeModel = modelArgIndex >= 0 ? process.argv[modelArgIndex + 1] : 'gemini-3-flash-preview';
        let inputBuffer = '';
        let switched = false;

        function write(text) { process.stdout.write(text); }
        function logCommand(line) { fs.appendFileSync(logPath, activeModel + ':' + line + '\n'); }

        function writeStatusRow() {
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    ' + activeModel + '     ...\n');
        }

        function writePrompt(text = inputBuffer) {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          writeStatusRow();
          if (text.includes('\n')) {
            const lines = text.split('\n');
            write('> ' + lines[0] + '\n');
            for (const line of lines.slice(1)) {
              write('  ' + line + '\n');
            }
          } else {
            write('> ' + text);
          }
        }

        function submit(command) {
          if (!command) return;
          logCommand(command);
          if (command === '/clear') {
            writePrompt('');
          } else if (command === '/stats') {
            write('Session Stats\nSession ID: stale-continue-usage-limit\nModel Usage\n');
            write(activeModel + '          1            0            0             0\n');
            writePrompt('');
          } else if (command === '/model') {
            write('Select Model\nManual (' + activeModel + ')\nModel usage\n');
            write(activeModel + ' 24% Resets: 1:29 PM\nPress Esc to close\n');
          } else if (command === 'Ship beta now') {
            if (activeModel === 'gemini-3-flash-preview') {
              write('\nX [API Error: You have exhausted your capacity on this model. Your quota will reset after 23h23m59s.]\n');
              inputBuffer = 'continue\ncontinue\ncontinue';
              writePrompt(inputBuffer);
            } else {
              write('\nWorking on fallback\n');
              writePrompt('');
            }
          } else if (command === '/model set gemini-2.5-flash') {
            activeModel = 'gemini-2.5-flash';
            switched = true;
            write('\nModel set to gemini-2.5-flash\n');
            writePrompt('');
            setTimeout(() => process.exit(0), 80);
          } else if (command.includes('continue') && command.includes('/model set')) {
            logCommand('__APPENDED_MODEL_SWITCH__');
            setTimeout(() => process.exit(8), 40);
          }
        }

        process.on('SIGINT', () => {
          inputBuffer = '';
          logCommand('__SIGINT__');
          writePrompt('');
        });

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt('');
        if (activeModel === 'gemini-2.5-flash') {
          setTimeout(() => process.exit(0), 500);
        }

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          for (const char of String(data || '')) {
            if (char === '\u0015') {
              inputBuffer = '';
              logCommand('__CTRL_U__');
              writePrompt('');
            } else if (char === '\u001B') {
              logCommand('__ESC__');
            } else if (char === '\r' || char === '\n') {
              const command = inputBuffer.trim();
              inputBuffer = '';
              submit(command);
            } else if (char >= ' ') {
              inputBuffer += char;
              writePrompt(inputBuffer);
            }
          }

          if (switched) setTimeout(() => process.exit(0), 80);
        });

        setTimeout(() => process.exit(switched ? 0 : 5), 9000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview,gemini-2.5-flash"
        environment["MODEL_SWITCH_MODE"] = "set"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["AUTO_CONTINUE_MODE"] = "always"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "120"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "100"
        environment["INITIAL_PROMPT_RETRY_MS"] = "60"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "650"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "24000"
        environment["NORMALIZED_TAIL_MAX"] = "16000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-3-flash-preview:__CTRL_U__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-3-flash-preview:/model set gemini-2.5-flash"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertFalse(commands.contains { $0.contains("__APPENDED_MODEL_SWITCH__") }, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Usage limit reached on gemini-3-flash-preview"), stderr)
        XCTAssertTrue(stderr.contains("queueing in-session switch to gemini-2.5-flash"), stderr)
    }

    func testBundledGeminiAutomationRunnerStopsUsageLimitDialogBeforeSwitchingModel() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        const launchLogPath = process.env.FAKE_GEMINI_LAUNCH_LOG;
        const modelArgIndex = process.argv.indexOf('--model');
        const launchModel = modelArgIndex >= 0 ? process.argv[modelArgIndex + 1] : '';
        let activeModel = launchModel;
        let clearSeen = false;
        let statsSeen = false;
        let modelPanelSeen = false;
        let promptSeen = false;
        let usageLimitOpen = false;
        let stopSeen = false;
        let switchSeen = false;

        fs.appendFileSync(launchLogPath, launchModel + '\n');

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, activeModel + ':' + line + '\n');
        }

        function writeStatusRow() {
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    ' + activeModel + '     ...\n');
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          writeStatusRow();
          write('> ');
        }

        function writeUsageLimitDialog() {
          usageLimitOpen = true;
          write('\nX [API Error: You have exhausted your capacity on this model. Your quota will reset after 2h0m7s.]\n');
          write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
          write('│ Usage limit reached for ' + activeModel + '.                              │\n');
          write('│ Access resets at 12:53 PM GMT+2.                                             │\n');
          write('│ /stats model for usage details                                               │\n');
          write('│ /model to switch models.                                                     │\n');
          write('│ /auth to switch to API key.                                                  │\n');
          write('│ ● 1. Keep trying                                                             │\n');
          write('\nℹ Request cancelled.\n\n');
          write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
          write('│ Usage limit reached for ' + activeModel + '.                              │\n');
          write('│ Access resets at 12:53 PM GMT+2.                                             │\n');
          write('│ /stats model for usage details                                               │\n');
          write('│ /model to switch models.                                                     │\n');
          write('│ /auth to switch to API key.                                                  │\n');
          write('│   1. Keep trying                                                             │\n');
          write('│ ● 2. Stop                                                                    │\n');
          write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        process.on('SIGINT', () => {
          logCommand('__SIGINT__');
          process.exit(130);
        });

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          const raw = String(data || '');
          if (modelPanelSeen && raw.includes('\u001B')) {
            modelPanelSeen = false;
            writePrompt();
          }

          if (usageLimitOpen && raw.includes('\r') && normalizeCommand(data).length === 0) {
            stopSeen = true;
            usageLimitOpen = false;
            logCommand('__ENTER__');
            write('\nRequest cancelled.\n');
            writePrompt();
            return;
          }

          for (const command of normalizeCommand(data)) {
            logCommand(command);
            if (command === '/clear') {
              clearSeen = true;
              writePrompt();
            } else if (command === '/stats') {
              statsSeen = true;
              write('Session Stats\n');
              write('Session ID: smoke-session\n');
              write('Auth Method: Signed in with Google (smoke@example.com)\n');
              write('Tier: Gemini Code Assist for individuals\n');
              write('Model Usage\n');
              write('Model                         Reqs Input Tokens Cache Reads Output Tokens\n');
              write(activeModel + '          1            0            0             0\n');
              setTimeout(writePrompt, 80);
            } else if (command === '/model') {
              modelPanelSeen = true;
              write('Select Model\n');
              write('Manual (' + activeModel + ')\n');
              write('Model usage\n');
              write('Flash           24% Resets: 1:29 PM\n');
              write('Press Esc to close\n');
            } else if (command === 'Ship beta now') {
              promptSeen = true;
              writeUsageLimitDialog();
            } else if (command === '/model set gemini-2.5-flash') {
              activeModel = 'gemini-2.5-flash';
              switchSeen = true;
              writePrompt();
            }
          }

          if (clearSeen && statsSeen && promptSeen && stopSeen && switchSeen) {
            setTimeout(() => process.exit(0), 900);
          }
        });

        setTimeout(() => process.exit(switchSeen && stopSeen ? 0 : 3), 8000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)

        for flavor in ["stable", "preview", "nightly"] {
            let runDirectory = tempDirectory.appendingPathComponent(flavor, isDirectory: true)
            let commandLogURL = runDirectory.appendingPathComponent("commands.log")
            let launchLogURL = runDirectory.appendingPathComponent("launches.log")
            let isoHomeURL = runDirectory.appendingPathComponent("gemini-home", isDirectory: true)
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
            try "".write(to: commandLogURL, atomically: true, encoding: .utf8)
            try "".write(to: launchLogURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: nodePath)
            process.arguments = [try bundledGeminiAutomationRunnerPath()]
            process.currentDirectoryURL = runDirectory

            var environment = ProcessInfo.processInfo.environment
            environment["CLI_FLAVOR"] = flavor
            environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
            environment["WRAPPER_LAUNCH_MODE"] = "direct"
            environment["MODEL_CHAIN"] = "gemini-3-flash-preview,gemini-2.5-flash"
            environment["MODEL_SWITCH_MODE"] = "set"
            environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
            environment["AUTO_CONTINUE_MODE"] = "prompt_only"
            environment["NEVER_SWITCH"] = "1"
            environment["GEMINI_ISO_HOME"] = isoHomeURL.path
            environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
            environment["FAKE_GEMINI_LAUNCH_LOG"] = launchLogURL.path
            environment["PROMPT_COMMAND_SETTLE_MS"] = "120"
            environment["MENU_CONFIRM_MIN_MS"] = "20"
            environment["INITIAL_PROMPT_SETTLE_MS"] = "100"
            environment["INITIAL_PROMPT_RETRY_MS"] = "60"
            environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
            environment["QUICK_RECHECK_MS"] = "40"
            environment["STATIC_RECHECK_MS"] = "60"
            environment["ACTION_RETRY_MIN_MS"] = "20"
            environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "650"
            environment["FORCE_KILL_AFTER_MS"] = "200"
            environment["RAW_TAIL_MAX"] = "24000"
            environment["NORMALIZED_TAIL_MAX"] = "16000"
            environment["SCREEN_CAPTURE_LINES"] = "80"
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            let deadline = Date().addingTimeInterval(12)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
            let launches = try String(contentsOf: launchLogURL, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)

            XCTAssertEqual(process.terminationStatus, 0, "flavor: \(flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            XCTAssertEqual(launches, ["gemini-3-flash-preview"], "flavor: \(flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            let stopIndex = try XCTUnwrap(commands.firstIndex(of: "gemini-3-flash-preview:__ENTER__"), "flavor: \(flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            let switchIndex = try XCTUnwrap(commands.firstIndex(of: "gemini-3-flash-preview:/model set gemini-2.5-flash"), "flavor: \(flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            XCTAssertLessThan(stopIndex, switchIndex, "flavor: \(flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            XCTAssertTrue(stderr.contains("Flavor: \(flavor)"), "flavor: \(flavor)\nstderr:\n\(stderr)")
            XCTAssertTrue(stderr.contains("Auto-continue mode: prompt_only"), "flavor: \(flavor)\nstderr:\n\(stderr)")
            XCTAssertTrue(stderr.contains("Usage limit reached on gemini-3-flash-preview — selecting Stop before switching models."), "flavor: \(flavor)\nstderr:\n\(stderr)")
            XCTAssertTrue(stderr.contains("Usage limit reached on gemini-3-flash-preview — queueing in-session switch to gemini-2.5-flash."), "flavor: \(flavor)\nstderr:\n\(stderr)")
            XCTAssertFalse(stderr.contains("usage limit screen has no Stop option"), "flavor: \(flavor)\nstderr:\n\(stderr)")
            XCTAssertFalse(stderr.contains("restarting on gemini-2.5-flash"), "flavor: \(flavor)\nstderr:\n\(stderr)")
        }
    }

    func testBundledGeminiAutomationRunnerSelectsStartupAutoModelMenuBeforePrompt() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let launchLogURL = tempDirectory.appendingPathComponent("launches.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        const launchLogPath = process.env.FAKE_GEMINI_LAUNCH_LOG;
        const modelArgIndex = process.argv.indexOf('--model');
        const launchModel = modelArgIndex >= 0 ? process.argv[modelArgIndex + 1] : '';
        const expectedAutoOption = process.env.FAKE_EXPECTED_AUTO_OPTION || '1';
        let autoSelected = false;

        fs.appendFileSync(launchLogPath, launchModel + '\n');

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, line + '\n');
        }

        function statusModel() {
          return autoSelected ? 'auto' : 'gemini-3-flash-preview';
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          geet       no sandbox    ' + statusModel() + '     ...\n');
          write('> ');
        }

        function writeAutoModelMenu() {
          write('Select your Gemini CLI model.\n');
          write('  1. Auto (Gemini 3)\n');
          write('     Let Gemini CLI decide the best model for the task: gemini-3-pro-preview, gemini-3-flash-preview\n');
          write('  2. Auto (Gemini 2.5)\n');
          write('     Let Gemini CLI decide the best model for the task: gemini-2.5-pro, gemini-2.5-flash\n');
          write('● 3. Manual (gemini-3-flash-preview)\n');
          write('     Manually select a model\n');
          write('Remember model for future sessions\n');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        process.on('SIGINT', () => {
          logCommand('__SIGINT__');
          process.exit(130);
        });

        write('Gemini CLI v0.39.0\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          for (const command of normalizeCommand(data)) {
            logCommand(command);
            if (command === '/clear') {
              writePrompt();
            } else if (command === '/stats') {
              write('Session Stats\n');
              write('Session ID: smoke-session\n');
              write('Auth Method: Signed in with Google (smoke@example.com)\n');
              write('Tier: Gemini Code Assist for individuals\n');
              write('Model Usage\n');
              write('gemini-3-flash-preview          1            0            0             0\n');
              setTimeout(writePrompt, 80);
            } else if (command === '/model') {
              writeAutoModelMenu();
            } else if (command === expectedAutoOption) {
              autoSelected = true;
              writePrompt();
            } else if (/^[12]$/.test(command)) {
              write('\nUnexpected auto option ' + command + '\n');
              setTimeout(() => process.exit(5), 120);
            } else if (command === 'lint apps and fix issues') {
              write(autoSelected ? '\nWorking in auto mode\n' : '\nStill manual\n');
              setTimeout(() => process.exit(autoSelected ? 0 : 4), 120);
            }
          }
        });

        setTimeout(() => process.exit(autoSelected ? 0 : 3), 9000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)

        let cases = [
            (flavor: "stable", chain: "gemini-2.5-flash,gemini-2.5-flash-lite", option: "2", label: "Auto (Gemini 2.5)"),
            (flavor: "preview", chain: "gemini-3-pro-preview,gemini-3-flash-preview,gemini-2.5-flash", option: "1", label: "Auto (Gemini 3)"),
            (flavor: "nightly", chain: "gemini-3-flash-preview,gemini-2.5-flash", option: "1", label: "Auto (Gemini 3)"),
        ]

        for testCase in cases {
            try "".write(to: commandLogURL, atomically: true, encoding: .utf8)
            try "".write(to: launchLogURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: nodePath)
            process.arguments = [try bundledGeminiAutomationRunnerPath()]
            process.currentDirectoryURL = tempDirectory

            var environment = ProcessInfo.processInfo.environment
            environment["CLI_FLAVOR"] = testCase.flavor
            environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
            environment["WRAPPER_LAUNCH_MODE"] = "direct"
            environment["MODEL_CHAIN"] = testCase.chain
            environment["GEMINI_MODEL_AUTO"] = "1"
            environment["GEMINI_AUTO_MODEL"] = "auto"
            environment["GEMINI_INITIAL_PROMPT"] = "lint apps and fix issues"
            environment["AUTO_CONTINUE_MODE"] = "always"
            environment["GEMINI_ISO_HOME"] = isoHomeURL.path
            environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
            environment["FAKE_GEMINI_LAUNCH_LOG"] = launchLogURL.path
            environment["FAKE_EXPECTED_AUTO_OPTION"] = testCase.option
            environment["PROMPT_COMMAND_SETTLE_MS"] = "120"
            environment["PROMPT_SUBMIT_DELAY_MS"] = "20"
            environment["MENU_CONFIRM_MIN_MS"] = "20"
            environment["INITIAL_PROMPT_SETTLE_MS"] = "100"
            environment["INITIAL_PROMPT_RETRY_MS"] = "60"
            environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
            environment["QUICK_RECHECK_MS"] = "40"
            environment["STATIC_RECHECK_MS"] = "60"
            environment["ACTION_RETRY_MIN_MS"] = "20"
            environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "900"
            environment["FORCE_KILL_AFTER_MS"] = "200"
            environment["RAW_TAIL_MAX"] = "24000"
            environment["NORMALIZED_TAIL_MAX"] = "16000"
            environment["SCREEN_CAPTURE_LINES"] = "80"
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            let deadline = Date().addingTimeInterval(11)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
            let launches = try String(contentsOf: launchLogURL, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)

            XCTAssertEqual(process.terminationStatus, 0, "flavor: \(testCase.flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            XCTAssertEqual(launches, ["auto"], "flavor: \(testCase.flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            let modelCommandIndex = try XCTUnwrap(commands.firstIndex(of: "/model"), "flavor: \(testCase.flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            let autoSelectionIndex = try XCTUnwrap(commands.firstIndex(of: testCase.option), "flavor: \(testCase.flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            let promptIndex = try XCTUnwrap(commands.firstIndex(of: "lint apps and fix issues"), "flavor: \(testCase.flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            XCTAssertLessThan(modelCommandIndex, autoSelectionIndex, "flavor: \(testCase.flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            XCTAssertLessThan(autoSelectionIndex, promptIndex, "flavor: \(testCase.flavor)\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
            XCTAssertTrue(stderr.contains("Flavor: \(testCase.flavor)"), "flavor: \(testCase.flavor)\nstderr:\n\(stderr)")
            XCTAssertTrue(stderr.contains("Launching model: Gemini CLI auto"), "flavor: \(testCase.flavor)\nstderr:\n\(stderr)")
            XCTAssertTrue(stderr.contains("Startup auto model: selecting \(testCase.label) from /model."), "flavor: \(testCase.flavor)\nstderr:\n\(stderr)")
            XCTAssertTrue(stderr.contains("Startup auto model: selected \(testCase.label); continuing startup."), "flavor: \(testCase.flavor)\nstderr:\n\(stderr)")
        }
    }

    func testBundledGeminiAutomationRunnerSelectsCapacityModelAndRetriesPromptAfterUsageLimitStop() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let launchLogURL = tempDirectory.appendingPathComponent("launches.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        const launchLogPath = process.env.FAKE_GEMINI_LAUNCH_LOG;
        const modelArgIndex = process.argv.indexOf('--model');
        const launchModel = modelArgIndex >= 0 ? process.argv[modelArgIndex + 1] : '';
        let activeModel = launchModel;
        let usageLimitOpen = false;
        let panelMode = '';
        let promptCount = 0;
        let switched = false;

        fs.appendFileSync(launchLogPath, launchModel + '\n');

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, activeModel + ':' + line + '\n');
        }

        function writeStatusRow() {
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    ' + activeModel + '     ...\n');
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          writeStatusRow();
          write('> ');
        }

        function writeUsageLimitDialog() {
          usageLimitOpen = true;
          write('\nX [API Error: You have exhausted your capacity on this model. Your quota will reset after 20h35m20s.]\n');
          write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
          write('│ Usage limit reached for ' + activeModel + '.                              │\n');
          write('│ /stats model for usage details                                               │\n');
          write('│ /model to switch models.                                                     │\n');
          write('│   1. Keep trying                                                             │\n');
          write('│ ● 2. Stop                                                                    │\n');
          write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
        }

        function writeStartupModelPanel() {
          panelMode = 'startup';
          write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
          write('│ Select Model                                                                 │\n');
          write('│ Manual (' + activeModel + ')                                                  │\n');
          write('│ Model usage                                                                  │\n');
          write('│ gemini-3-flash-preview 24% Resets: 1:29 PM                                   │\n');
          write('│ gemini-2.5-flash 100% Resets: 1:29 PM                                        │\n');
          write('│ gemini-2.5-flash-lite 24% Resets: 1:29 PM                                    │\n');
          write('│ Press Esc to close                                                           │\n');
          write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
        }

        function writeModelManagePanel() {
          panelMode = 'model-manage';
          write('╭──────────────────────────────────────────────────────────────────────────────╮\n');
          write('│ Select Model                                                                 │\n');
          write('│ Model usage                                                                  │\n');
          write('│   1. gemini-2.5-flash 100% Resets: 1:29 PM                                  │\n');
          write('│ ● 2. gemini-2.5-flash-lite 24% Resets: 1:29 PM                              │\n');
          write('╰──────────────────────────────────────────────────────────────────────────────╯\n');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        process.on('SIGINT', () => {
          logCommand('__SIGINT__');
          process.exit(130);
        });

        write('Gemini CLI v0.41.0-nightly.20260423.gd1c91f526\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          const raw = String(data || '');
          const commands = normalizeCommand(data);

          if (usageLimitOpen && raw.includes('\r') && commands.length === 0) {
            usageLimitOpen = false;
            logCommand('__STOP_ENTER__');
            write('\nRequest cancelled.\n');
            writePrompt();
            return;
          }

          if (panelMode === 'startup' && raw.includes('\u001B')) {
            panelMode = '';
            writePrompt();
            return;
          }

          if (panelMode === 'model-manage' && commands.includes('2')) {
            logCommand('2');
            activeModel = 'gemini-2.5-flash-lite';
            switched = true;
            panelMode = '';
            writePrompt();
            return;
          }

          if (panelMode === 'model-manage' && raw.includes('\r') && commands.length === 0) {
            logCommand('__MODEL_ENTER__');
            activeModel = 'gemini-2.5-flash-lite';
            switched = true;
            panelMode = '';
            writePrompt();
            return;
          }

          for (const command of commands) {
            logCommand(command);
            if (command === '/clear') {
              writePrompt();
            } else if (command === '/stats' || command === '/stats session') {
              write('Session Stats\n');
              write('Session ID: smoke-session\n');
              write('Auth Method: Signed in with Google (smoke@example.com)\n');
              write('Tier: Gemini Code Assist for individuals\n');
              write('Model Usage\n');
              write('Model                         Reqs Input Tokens Cache Reads Output Tokens\n');
              write(activeModel + '          1            0            0             0\n');
              setTimeout(writePrompt, 80);
            } else if (command === '/model') {
              writeStartupModelPanel();
            } else if (command === '/model manage') {
              writeModelManagePanel();
            } else if (command === 'Ship beta now') {
              promptCount += 1;
              if (switched) {
                write('\nWorking on fallback model\n');
                setTimeout(() => process.exit(0), 120);
              } else {
                writeUsageLimitDialog();
              }
            }
          }
        });

        setTimeout(() => process.exit(switched && promptCount >= 2 ? 0 : 3), 14000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)
        try "".write(to: launchLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "nightly"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview,gemini-2.5-flash,gemini-2.5-flash-lite"
        environment["MODEL_SWITCH_MODE"] = "manage"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["AUTO_CONTINUE_MODE"] = "prompt_only"
        environment["NEVER_SWITCH"] = "1"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["FAKE_GEMINI_LAUNCH_LOG"] = launchLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "120"
        environment["PROMPT_SUBMIT_DELAY_MS"] = "20"
        environment["MENU_CONFIRM_MIN_MS"] = "20"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "100"
        environment["INITIAL_PROMPT_RETRY_MS"] = "60"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "900"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "24000"
        environment["NORMALIZED_TAIL_MAX"] = "16000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(16)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let launches = try String(contentsOf: launchLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(launches, ["gemini-3-flash-preview"], "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-3-flash-preview:__STOP_ENTER__"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-3-flash-preview:/stats session"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-3-flash-preview:/model manage"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(
            commands.contains("gemini-3-flash-preview:2") || commands.contains("gemini-3-flash-preview:__MODEL_ENTER__"),
            "stdout:\n\(stdout)\nstderr:\n\(stderr)"
        )
        XCTAssertTrue(commands.contains("gemini-2.5-flash-lite:Ship beta now"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("gemini-2.5-flash is at 100% usage; selecting gemini-2.5-flash-lite instead"), stderr)
        XCTAssertTrue(stderr.contains("Model switch confirmed: gemini-2.5-flash-lite"), stderr)
        XCTAssertTrue(stderr.contains("Usage-limit recovery: retrying initial prompt on gemini-2.5-flash-lite"), stderr)
    }

    func testBundledGeminiAutomationRunnerQueuesAuthWhenModelChainIsExhausted() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let launchLogURL = tempDirectory.appendingPathComponent("launches.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        const launchLogPath = process.env.FAKE_GEMINI_LAUNCH_LOG;
        const modelArgIndex = process.argv.indexOf('--model');
        const launchModel = modelArgIndex >= 0 ? process.argv[modelArgIndex + 1] : '';
        const previousLaunches = fs.existsSync(launchLogPath)
          ? fs.readFileSync(launchLogPath, 'utf8').split('\n').filter(Boolean)
          : [];
        const launchOrdinal = previousLaunches.length + 1;
        let clearSeen = false;
        let statsCount = 0;
        let modelCount = 0;
        let modelPanelOpen = false;
        let promptSeen = false;
        let authSeen = false;
        let restartSeen = false;

        fs.appendFileSync(launchLogPath, launchModel + '\n');

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, line + '\n');
        }

        function writeStatusRow() {
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    ' + launchModel + '     ...\n');
        }

        function writePrompt() {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          writeStatusRow();
          write('> ');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        process.on('SIGINT', () => {
          logCommand('__SIGINT__');
          process.exit(130);
        });

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          if (modelPanelOpen && String(data).includes('\u001B')) {
            modelPanelOpen = false;
            writePrompt();
          }

          for (const command of normalizeCommand(data)) {
            logCommand(command);
            if (command === '/clear') {
              clearSeen = true;
              writePrompt();
            } else if (command === '/stats') {
              statsCount += 1;
              write('Session Stats\n');
              write('Session ID: smoke-session-' + statsCount + '\n');
              write('Auth Method: Signed in with Google (' + (restartSeen ? 'new@example.com' : 'smoke@example.com') + ')\n');
              write('Tier: Gemini Code Assist for individuals\n');
              write('Tool Calls: 0\n');
              write('Wall Time: 1s\n');
              write('Model Usage\n');
              write('Model                         Reqs Input Tokens Cache Reads Output Tokens\n');
              write(launchModel + '          1            0            0             0\n');
              setTimeout(writePrompt, 80);
            } else if (command === '/model') {
              modelCount += 1;
              modelPanelOpen = true;
              write('Select Model\n');
              write('Manual (' + launchModel + ')\n');
              write('Model usage\n');
              write('Flash           ' + (restartSeen ? '24%' : '100%') + ' Resets: 1:29 PM\n');
              write('Press Esc to close\n');
            } else if (command === 'Ship beta now') {
              promptSeen = true;
              write('\nX [API Error: You have exhausted your capacity on this model. Your quota will reset after 2h0m7s.]\n');
              writeStatusRow();
              write('> ');
            } else if (command === '/auth') {
              authSeen = true;
              write('\nWaiting for auth...\n');
              setTimeout(() => {
                write('\nAuthentication succeeded\n');
                write("You've successfully signed in with Google. Gemini CLI needs to be restarted.\n");
                write('Press R to restart, or Esc to choose a different authentication method.\n');
              }, 80);
            } else if (command === 'r' || command === 'R') {
              restartSeen = true;
              write('\nRestarting Gemini CLI...\n');
              write('Signed in with Google /auth\n');
              writePrompt();
            }
          }

          const sameProcessRestartComplete = clearSeen && statsCount >= 2 && modelCount >= 2 && promptSeen && authSeen && restartSeen && !modelPanelOpen;
          const relaunchTelemetryComplete = launchOrdinal > 1 && statsCount >= 1 && modelCount >= 1 && !modelPanelOpen;
          if (sameProcessRestartComplete || relaunchTelemetryComplete) {
            setTimeout(() => process.exit(0), 500);
          }
        });

        setTimeout(() => process.exit(restartSeen && statsCount >= 2 && modelCount >= 2 ? 0 : 3), 14000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)
        try "".write(to: launchLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-flash-preview"
        environment["MODEL_CHAIN_EXHAUSTED_ACTION"] = "auth"
        environment["MODEL_SWITCH_MODE"] = "manage"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["AUTO_CONTINUE_MODE"] = "always"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["FAKE_GEMINI_LAUNCH_LOG"] = launchLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "120"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "100"
        environment["INITIAL_PROMPT_RETRY_MS"] = "60"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "450"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "24000"
        environment["NORMALIZED_TAIL_MAX"] = "16000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(16)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let launches = try String(contentsOf: launchLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
	        XCTAssertTrue(
	            launches == ["gemini-3-flash-preview"] || launches == ["gemini-3-flash-preview", "gemini-3-flash-preview"],
	            "stdout:\n\(stdout)\nstderr:\n\(stderr)"
	        )
        XCTAssertTrue(stderr.contains("Startup model capacity shows gemini-3-flash-preview is at 100% usage — no fallback models remain. Queueing /auth"), stderr)
        XCTAssertTrue(stderr.contains("Authentication handoff started with /auth. Waiting for account change completion."), stderr)
        XCTAssertTrue(stderr.contains("Account change detected: authentication succeeded; restarting Gemini CLI without startup /clear."), stderr)
        XCTAssertTrue(stderr.contains("Account change telemetry: running /stats -> /model without startup /clear."), stderr)
        XCTAssertTrue(stderr.contains("Account change telemetry: captured refreshed /stats and /model capacity; startup /clear was skipped."), stderr)
        XCTAssertFalse(stderr.contains("Finishing session"), stderr)
        XCTAssertEqual(commands, [
            "/clear",
            "/stats",
            "/model",
            "/auth",
            "R",
            "/stats",
            "/model"
        ], "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("/auth"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(commands.filter { $0 == "/clear" }.count, 1, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(commands.filter { $0 == "/stats" }.count, 2, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(commands.filter { $0 == "/model" }.count, 2, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(commands.filter { $0 == "Ship beta now" }.count, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
    }

    func testBundledGeminiAutomationRunnerRelaunchesUsageLimitFromPendingSwitchedModelWhenStatusRowIsStale() throws {
        let builder = CommandBuilder()
        guard let nodePath = builder.resolveExecutable("node", workingDirectory: FileManager.default.currentDirectoryPath).resolved else {
            throw XCTSkip("node is not available in this test environment.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeWrapperURL = tempDirectory.appendingPathComponent("fake-gemini.cjs")
        let commandLogURL = tempDirectory.appendingPathComponent("commands.log")
        let launchLogURL = tempDirectory.appendingPathComponent("launches.log")
        let isoHomeURL = tempDirectory.appendingPathComponent("gemini-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeWrapperSource = #"""
        #!/usr/bin/env node
        const fs = require('node:fs');
        const logPath = process.env.FAKE_GEMINI_COMMAND_LOG;
        const launchLogPath = process.env.FAKE_GEMINI_LAUNCH_LOG;
        const modelArgIndex = process.argv.indexOf('--model');
        const launchModel = modelArgIndex >= 0 ? process.argv[modelArgIndex + 1] : '';
        const fallbackLaunch = launchModel === 'gemini-2.5-flash';
        let switchedToFlash = false;
        let staleStatusRow = false;
        let clearSeen = false;
        let statsSeen = false;
        let modelPanelSeen = false;
        let modelPanelClosed = false;
        let promptSeen = false;

        fs.appendFileSync(launchLogPath, launchModel + '\n');

        function write(text) {
          process.stdout.write(text);
        }

        function logCommand(line) {
          fs.appendFileSync(logPath, launchModel + ':' + line + '\n');
        }

        function displayedModel() {
          if (fallbackLaunch) return launchModel;
          if (staleStatusRow) return 'gemini-3-pro-preview';
          if (switchedToFlash) return 'gemini-3-flash-preview';
          return launchModel || 'gemini-3-pro-preview';
        }

        function writeStatusRow(model = displayedModel()) {
          write('workspace (/directory)     branch     sandbox       /model\n');
          write('/tmp/clilauncher          main       no sandbox    ' + model + '     ...\n');
        }

        function writePrompt(model = displayedModel()) {
          write('\n'.repeat(90));
          write('? for shortcuts\n');
          write('Type your message or @path/to/file\n');
          writeStatusRow(model);
          write('> ');
        }

        function normalizeCommand(data) {
          return String(data || '')
            .replace(/\u001B\[[0-9;?]*[ -/]*[@-~]/g, '')
            .replace(/\u001B/g, '')
            .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '')
            .replace(/\r/g, '\n')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        }

        process.on('SIGINT', () => {
          logCommand('__SIGINT__');
          process.exit(130);
        });

        write('Gemini CLI v0.40.0-preview.2\n');
        write('Signed in with Google /auth\n');
        write('Plan: Gemini Code Assist for individuals /upgrade\n');
        if (!fallbackLaunch) {
          write('We are making changes to Gemini CLI that may impact your workflow.\n');
          write('What is Changing: restricting models for free tier users.\n');
          write('How it affects you: upgrade to a supported paid plan.\n');
          write('Read more: https://goo.gle/geminicli-updates\n');
        }
        writePrompt();

        process.stdin.setEncoding('utf8');
        if (process.stdin.isTTY) process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on('data', (data) => {
          if (modelPanelSeen && String(data).includes('\u001B')) {
            modelPanelClosed = true;
            writePrompt();
          }

          for (const command of normalizeCommand(data)) {
            logCommand(command);
            if (command === '/model set gemini-3-flash-preview') {
              switchedToFlash = true;
              staleStatusRow = true;
              write('\nX [API Error: You have exhausted your capacity on this model. Your quota will reset after 2h0m7s.]\n');
              writeStatusRow('gemini-3-pro-preview');
              write('> ');
            } else if (command === '/clear') {
              clearSeen = true;
              writePrompt();
            } else if (command === '/stats') {
              statsSeen = true;
              write('Session Stats\n');
              write('Session ID: smoke-session\n');
              write('Auth Method: Signed in with Google (smoke@example.com)\n');
              write('Tier: Gemini Code Assist for individuals\n');
              write('Model Usage\n');
              write('Model                         Reqs Input Tokens Cache Reads Output Tokens\n');
              write((fallbackLaunch ? launchModel : 'gemini-3-flash-preview') + '          1            0            0             0\n');
              setTimeout(writePrompt, 80);
            } else if (command === '/model') {
              modelPanelSeen = true;
              write('Select Model\n');
              write('Manual (' + (fallbackLaunch ? launchModel : 'gemini-3-flash-preview') + ')\n');
              write('Model usage\n');
              write('Flash           24% Resets: 1:29 PM\n');
              write('Press Esc to close\n');
            } else if (command === 'Ship beta now') {
              promptSeen = true;
              if (fallbackLaunch) {
                write('\nWorking on fallback\n> ');
              } else {
                write('\nX [API Error: You have exhausted your capacity on this model. Your quota will reset after 2h0m7s.]\n');
                writeStatusRow('gemini-3-pro-preview');
                write('> ');
              }
            }
          }

          if (fallbackLaunch && clearSeen && statsSeen && promptSeen) {
            setTimeout(() => process.exit(0), 80);
          }
        });

        setTimeout(() => process.exit(fallbackLaunch ? 0 : 3), 8000);
        """#
        try fakeWrapperSource.write(to: fakeWrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWrapperURL.path)
        try "".write(to: commandLogURL, atomically: true, encoding: .utf8)
        try "".write(to: launchLogURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [try bundledGeminiAutomationRunnerPath()]
        process.currentDirectoryURL = tempDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["CLI_FLAVOR"] = "preview"
        environment["GEMINI_WRAPPER"] = fakeWrapperURL.path
        environment["WRAPPER_LAUNCH_MODE"] = "direct"
        environment["MODEL_CHAIN"] = "gemini-3-pro-preview,gemini-3-flash-preview,gemini-2.5-flash"
        environment["MODEL_SWITCH_MODE"] = "set"
        environment["GEMINI_INITIAL_PROMPT"] = "Ship beta now"
        environment["AUTO_CONTINUE_MODE"] = "always"
        environment["GEMINI_ISO_HOME"] = isoHomeURL.path
        environment["FAKE_GEMINI_COMMAND_LOG"] = commandLogURL.path
        environment["FAKE_GEMINI_LAUNCH_LOG"] = launchLogURL.path
        environment["PROMPT_COMMAND_SETTLE_MS"] = "120"
        environment["INITIAL_PROMPT_SETTLE_MS"] = "100"
        environment["INITIAL_PROMPT_RETRY_MS"] = "60"
        environment["INITIAL_PROMPT_MAX_WAIT_MS"] = "1500"
        environment["QUICK_RECHECK_MS"] = "40"
        environment["STATIC_RECHECK_MS"] = "60"
        environment["ACTION_RETRY_MIN_MS"] = "20"
        environment["MODEL_MANAGE_FLOW_TIMEOUT_MS"] = "450"
        environment["FORCE_KILL_AFTER_MS"] = "200"
        environment["RAW_TAIL_MAX"] = "24000"
        environment["NORMALIZED_TAIL_MAX"] = "16000"
        environment["SCREEN_CAPTURE_LINES"] = "80"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let launches = try String(contentsOf: launchLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertEqual(launches, [
            "gemini-3-pro-preview",
            "gemini-2.5-flash"
        ], "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-3-pro-preview:/model set gemini-3-flash-preview"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(commands.contains("gemini-2.5-flash:Ship beta now"), "stdout:\n\(stdout)\nstderr:\n\(stderr)")
        XCTAssertTrue(stderr.contains("Usage limit appeared while confirming gemini-3-flash-preview; treating that model as active for fallback."), stderr)
	        XCTAssertTrue(stderr.contains("Usage limit reached on gemini-3-flash-preview — queueing in-session switch to gemini-2.5-flash."), stderr)
	        XCTAssertTrue(stderr.contains("direct model switch to gemini-2.5-flash was not confirmed; visible model is gemini-3-pro-preview — relaunching directly on gemini-2.5-flash."), stderr)
        XCTAssertFalse(stderr.contains("restarting on gemini-3-flash-preview"), stderr)
        XCTAssertFalse(stderr.contains("queueing /stats session and /model manage for gemini-2.5-flash"), stderr)
    }

    func testBundledGeminiAutomationRunnerDoesNotWrapModelChainWhenPolicyRestricted() throws {
        let runnerURLString = URL(fileURLWithPath: try bundledGeminiAutomationRunnerPath()).absoluteString
        let chain = [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview",
            "gemini-2.5-pro",
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite"
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

    func testBundledGeminiAutomationRunnerResolvesStartupAutoMenuFromModelChainFamily() throws {
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

        for (chain, expectedOption) in [
            ("gemini-3-flash-preview,gemini-2.5-flash", "1"),
            ("gemini-2.5-flash,gemini-2.5-flash-lite", "2"),
        ] {
            let encodedChain = String(data: try JSONEncoder().encode(chain), encoding: .utf8) ?? "\"\""
            let script = """
            process.env.GEMINI_MODEL_AUTO = '1';
            process.env.GEMINI_AUTO_MODEL = 'auto';
            process.env.MODEL_CHAIN = \(encodedChain);
            import(\(encodedImportURL)).then((mod) => {
              const snapshot = mod._test.detectSnapshotFromText(\(encodedSample), "sample");
              const option = mod._test.resolveStartupAutoModelOption(snapshot);
              process.stdout.write(JSON.stringify({ numberText: option?.numberText || '', canonical: option?.canonical || '' }));
            }).catch((error) => {
              console.error(error && error.stack ? error.stack : String(error));
              process.exit(1);
            });
            """

            let result = try runNodeScript(script)
            XCTAssertEqual(result.terminationStatus, 0, result.stderr)

            let payloadData = try XCTUnwrap(result.stdout.data(using: .utf8))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
            XCTAssertEqual(payload["numberText"] as? String, expectedOption, "chain: \(chain)\nstdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        }
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

        XCTAssertTrue(command.contains("GEMINI_MODEL_AUTO='1'"))
        XCTAssertTrue(command.contains("GEMINI_AUTO_MODEL='auto'"))
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

        profile.configureGeminiFireAndForget(prompt: "Ship 'beta' now", supportingPrompt: "continue refactor")
        let command = try builder.buildCommand(profile: profile, settings: settings)

        XCTAssertTrue(command.contains("GEMINI_INITIAL_PROMPT='Ship '\\''beta'\\'' now'"))
        XCTAssertTrue(command.contains("AUTO_CONTINUE_MODE='always'"))
        XCTAssertTrue(command.contains("CONTINUE_COMMAND='continue refactor'"))
        XCTAssertTrue(command.contains("CONTINUE_FALLBACK_COMMAND='continue to next refactor'"))
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
