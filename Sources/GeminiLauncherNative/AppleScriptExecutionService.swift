import Foundation

struct AppleScriptExecutionResult {
    var output: String
    var errorOutput: String
    var terminationStatus: Int32
}

struct AppleScriptExecutionService {
    func execute(source: String) throws -> AppleScriptExecutionResult {
        let osascriptPath = "/usr/bin/osascript"
        guard FileManager.default.isExecutableFile(atPath: osascriptPath) else {
            throw LauncherError.appleScript("AppleScript runner is missing: \(osascriptPath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: osascriptPath)
        process.arguments = ["-s", "h"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe

        try process.run()
        if let data = source.data(using: .utf8) {
            try? inputPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try? inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let errorOutput = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            let message = [errorOutput, output]
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
            throw LauncherError.appleScript(message.isEmpty ? "osascript failed with exit code \(process.terminationStatus)." : message)
        }

        return AppleScriptExecutionResult(output: output, errorOutput: errorOutput, terminationStatus: process.terminationStatus)
    }
}
