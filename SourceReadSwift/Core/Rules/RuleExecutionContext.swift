import Foundation

/// Mutable state shared by every rule and JavaScript fragment in one source execution.
///
/// JavaScriptCore is thread-confined, but native callbacks may arrive on another queue.
/// Keeping the state behind a lock prevents the bridge from creating a second, divergent
/// variable store (the main compatibility problem of the previous prelude-only runtime).
final class RuleExecutionContext: @unchecked Sendable {
    typealias NetworkHandler = (String) -> String
    typealias ResponseHandler = (String) -> SourceResponse?
    typealias LogHandler = (String) -> Void

    private let lock = NSRecursiveLock()
    private var values: [String: Any] = [:]
    private let persistentState: RulePersistentState
    private var recordedLogs: [String] = []

    var networkHandler: NetworkHandler?
    var responseHandler: ResponseHandler?
    var logHandler: LogHandler?

    init(
        initialValues: [String: Any] = [:],
        persistentState: RulePersistentState = RulePersistentState(),
        networkHandler: NetworkHandler? = nil,
        responseHandler: ResponseHandler? = nil,
        logHandler: LogHandler? = nil
    ) {
        self.networkHandler = networkHandler
        self.responseHandler = responseHandler
        self.logHandler = logHandler
        self.persistentState = persistentState
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
            if key == "cookieHeader" {
                persistentState.put(Self.bridgeString(value), for: key)
            }
        } else {
            values.removeValue(forKey: key)
            if key == "cookieHeader" {
                persistentState.remove(key)
            }
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
        if let value = values[key] {
            return Self.bridgeString(value)
        }
        return persistentState.get(key)
    }

    @discardableResult
    func put(_ value: Any?, for key: String) -> String {
        let text = Self.bridgeString(value)
        lock.lock()
        values[key] = value ?? ""
        lock.unlock()
        persistentState.put(text, for: key)
        return text
    }

    func get(_ key: String) -> String {
        persistentState.get(key)
    }

    func remove(_ key: String) {
        lock.lock()
        values.removeValue(forKey: key)
        lock.unlock()
        persistentState.remove(key)
    }

    func persistentSnapshot() -> [String: String] { persistentState.snapshot() }

    /// Import response cookies into the same state used by `java.put/get`.
    /// This mirrors Android's source-scoped cookie jar and deliberately keeps
    /// only cookie names/values in diagnostics; response bodies and secrets are
    /// never logged here.
    func ingestResponse(_ response: SourceResponse) {
        let values = CookieHeaderParser.setCookieValues(from: response.headers)
            .compactMap { CookieHeaderParser.cookiePair(fromSetCookie: $0) }
            .map { "\($0.name)=\($0.value)" }
        guard !values.isEmpty else { return }
        let merged = CookieHeaderParser.merge(values.joined(separator: "; "), into: string(for: "cookieHeader").nilIfEmpty)
        setValue(merged, for: "cookieHeader")
        log("response cookies persisted: \(values.map { $0.split(separator: "=").first.map(String.init) ?? "" }.joined(separator: ","))")
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

/// Synchronous, lock-protected storage shared by all JS contexts used for one
/// source.  Legado sources commonly `java.put` a nonce/cookie in search and
/// read it again from detail or content; creating a fresh JS context per stage
/// must not erase those values.
final class RulePersistentState: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func put(_ value: String, for key: String) {
        lock.lock(); values[key] = value; lock.unlock()
    }

    func get(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return values[key] ?? ""
    }

    func remove(_ key: String) {
        lock.lock(); values.removeValue(forKey: key); lock.unlock()
    }

    func snapshot() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}
