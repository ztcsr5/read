import Foundation

/// Mutable state shared by every rule and JavaScript fragment in one source execution.
///
/// JavaScriptCore is thread-confined, but native callbacks may arrive on another queue.
/// Keeping the state behind a lock prevents the bridge from creating a second, divergent
/// variable store (the main compatibility problem of the previous prelude-only runtime).
final class RuleExecutionContext: @unchecked Sendable {
    typealias NetworkHandler = (String) -> String
    typealias LogHandler = (String) -> Void

    private let lock = NSRecursiveLock()
    private var values: [String: Any] = [:]
    private var persistentValues: [String: String] = [:]
    private var recordedLogs: [String] = []

    var networkHandler: NetworkHandler?
    var logHandler: LogHandler?

    init(
        initialValues: [String: Any] = [:],
        networkHandler: NetworkHandler? = nil,
        logHandler: LogHandler? = nil
    ) {
        self.networkHandler = networkHandler
        self.logHandler = logHandler
        bind(initialValues)
    }

    func bind(_ newValues: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        for (key, value) in newValues {
            values[key] = value
        }
        if newValues["result"] == nil, let html = newValues["html"] {
            values["result"] = html
        }
    }

    func setValue(_ value: Any?, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }

    func value(for key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func string(for key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return Self.bridgeString(values[key])
    }

    @discardableResult
    func put(_ value: Any?, for key: String) -> String {
        let text = Self.bridgeString(value)
        lock.lock()
        persistentValues[key] = text
        lock.unlock()
        return text
    }

    func get(_ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return persistentValues[key] ?? ""
    }

    func remove(_ key: String) {
        lock.lock()
        persistentValues.removeValue(forKey: key)
        lock.unlock()
    }

    func log(_ message: String) {
        lock.lock()
        recordedLogs.append(message)
        lock.unlock()
        logHandler?(message)
    }

    func logs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedLogs
    }

    func snapshot() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    static func bridgeString(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let value = value as? String { return value }
        if let value = value as? NSString { return value as String }
        if let value = value as? NSNumber { return value.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }
}
