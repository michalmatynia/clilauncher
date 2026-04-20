import SwiftUI

struct UpdateButton: View {
    let name: String
    let command: String
    let logger: LaunchLogger
    
    var body: some View {
        Button("Update \(name)") {
            ToolUpdateService.runUpdate(command: command, logger: logger)
        }
        .buttonStyle(.borderedProminent)
    }
}
