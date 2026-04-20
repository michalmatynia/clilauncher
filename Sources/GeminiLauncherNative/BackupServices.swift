import Foundation
import Combine

actor DatabaseBackupService {
    private let builder = CommandBuilder()

    func performBackup(settings: MongoMonitoringSettings, destinationFolder: URL) async throws -> URL {
        guard settings.enableMongoWrites else {
            throw NSError(domain: "Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "MongoDB writes are disabled."])
        }
        
        let backupDir = destinationFolder.appendingPathComponent("backup-\(Date().timeIntervalSince1970)")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        guard let mongodumpPath = builder.resolvedExecutable("mongodump") else {
            throw NSError(domain: "Backup", code: 2, userInfo: [NSLocalizedDescriptionKey: "mongodump executable not found."])
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mongodumpPath)
        process.arguments = [
            "--uri", settings.trimmedConnectionURL,
            "--db", "clilauncher_monitor",
            "--out", backupDir.path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Backup", code: 3, userInfo: [NSLocalizedDescriptionKey: "Backup process failed."])
        }
        
        return backupDir
    }
    
    func performRestore(settings: MongoMonitoringSettings, backupSourceURL: URL) async throws {
        guard settings.enableMongoWrites else {
            throw NSError(domain: "Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "MongoDB writes are disabled."])
        }
        
        guard let mongorestorePath = builder.resolvedExecutable("mongorestore") else {
            throw NSError(domain: "Backup", code: 4, userInfo: [NSLocalizedDescriptionKey: "mongorestore executable not found."])
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mongorestorePath)
        process.arguments = [
            "--uri", settings.trimmedConnectionURL,
            "--drop",
            backupSourceURL.path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Backup", code: 5, userInfo: [NSLocalizedDescriptionKey: "Restore process failed."])
        }
    }
}
