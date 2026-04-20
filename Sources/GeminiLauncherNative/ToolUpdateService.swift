import Foundation

@MainActor
struct ToolUpdateService {
    static func runUpdate(command: String, logger: LaunchLogger) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["zsh", "-c", command]
        
        process.terminationHandler = { p in
            Task { @MainActor in
                if p.terminationStatus == 0 {
                    logger.log(.success, "Update finished successfully.", category: .app)
                } else {
                    logger.log(.error, "Update failed with code \(p.terminationStatus).", category: .app)
                }
            }
        }
        
        do {
            try process.run()
            logger.log(.info, "Running update command: \(command)", category: .app)
        } catch {
            logger.log(.error, "Failed to run update: \(error.localizedDescription)", category: .app)
        }
    }
}
