import Foundation
import XCTest
@testable import GeminiLauncherNative

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
    func testMonitoringClampsAreApplied() {
        var settings = MongoMonitoringSettings()
        settings.recentHistoryLimit = -2
        settings.recentHistoryLookbackDays = 1000
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
        XCTAssertEqual(settings.clampedLocalTranscriptRetentionDays, 3650)
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

final class AiderCommandBuilderTests: XCTestCase {
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
        XCTAssertTrue(result.contains("exec '/Users/michalmatynia/.local/bin/aider'"))
        XCTAssertTrue(result.contains("--architect"))
        XCTAssertTrue(result.contains("--model 'gpt-4o'"))
        XCTAssertTrue(result.contains("--no-auto-commit"))
        XCTAssertTrue(result.contains("--notify"))
        XCTAssertTrue(result.contains("--light-mode"))
    }
}
