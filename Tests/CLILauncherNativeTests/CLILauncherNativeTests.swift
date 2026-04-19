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
        var settings = PostgresMonitoringSettings()
        settings.connectionURL = "mongodb://localhost:27017/launcher?authSource=admin"
        XCTAssertTrue(settings.mongoConnection.isLocal)
        XCTAssertEqual(settings.redactedConnectionDescription, "mongodb://localhost:27017/launcher?authSource=admin")

        settings.connectionURL = "mongodb://user:secret@db.example.com:27017/admin"
        XCTAssertTrue(settings.mongoConnection.isRemote)
        XCTAssertEqual(settings.redactedConnectionDescription, "mongodb://user:••••••@db.example.com:27017/admin")
    }
}

final class PostgresMonitoringSettingsTests: XCTestCase {
    func testMonitoringClampsAreApplied() {
        var settings = PostgresMonitoringSettings()
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
