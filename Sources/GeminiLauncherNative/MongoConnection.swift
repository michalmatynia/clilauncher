import Foundation

struct MongoConnectionDescriptor: Equatable, Sendable {
    enum Kind: Equatable {
        case local
        case remote(host: String)
        case invalid
    }

    private let rawValue: String
    private let components: URLComponents?
    private let scheme: String?
    private let host: String?

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.components = URLComponents(string: self.rawValue)
        self.scheme = components?.scheme?.lowercased()
        self.host = components?.host?.lowercased()
    }

    var isValid: Bool {
        scheme?.hasPrefix("mongodb") == true && host != nil
    }

    var kind: Kind {
        guard isValid, let host else { return .invalid }
        if Self.isLocalHost(host) {
            return .local
        }
        return .remote(host: host)
    }

    var isLocal: Bool {
        if case .local = kind {
            return true
        }
        return false
    }

    var isRemote: Bool {
        if case .remote = kind {
            return true
        }
        return false
    }

    var redactedString: String {
        guard isValid, let components else { return "Not configured" }
        var redacted = components
        if redacted.password != nil {
            redacted.password = "••••••"
        }
        return redacted.url?.absoluteString.removingPercentEncoding ?? "Configured"
    }

    static func isLocalHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        switch normalizedHost {
        case "127.0.0.1", "::1", "localhost", "0.0.0.0":
            return true

        default:
            return false
        }
    }
}
