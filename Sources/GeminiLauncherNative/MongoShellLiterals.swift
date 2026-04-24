import Foundation

enum MongoShellLiterals {
    static func stringLiteral(_ raw: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [raw], options: []),
              var encoded = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        encoded.removeFirst()
        encoded.removeLast()
        return encoded
    }
}
