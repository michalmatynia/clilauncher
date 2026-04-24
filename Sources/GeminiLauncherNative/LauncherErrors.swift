import Foundation

enum LauncherError: LocalizedError {
    case validation(String)
    case appleScript(String)

    var errorDescription: String? {
        switch self {
        case .validation(let value): return value
        case .appleScript(let value): return value
        }
    }
}

final class LockedLaunchErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    func set(_ error: Error?) {
        lock.lock()
        storedError = error
        lock.unlock()
    }

    func get() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }
}

final class LockedBooleanBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
