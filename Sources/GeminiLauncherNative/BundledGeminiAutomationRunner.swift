import Foundation

enum BundledGeminiAutomationRunner {
    static var defaultPath: String {
        resourceURL?.path ?? ""
    }

    private static var resourceURL: URL? {
        Bundle.module.url(
            forResource: "gemini-automation-runner",
            withExtension: "mjs",
            subdirectory: "Resources"
        ) ?? Bundle.module.url(
            forResource: "gemini-automation-runner",
            withExtension: "mjs"
        )
    }
}
