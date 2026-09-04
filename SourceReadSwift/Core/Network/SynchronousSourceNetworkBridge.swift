import Foundation

/// Runs an injected async SourceNetworkClient from JavaScriptCore's synchronous
/// callback boundary.  A detached task is intentional: waiting on a task
/// scheduled on the cooperative executor from inside JSCore can deadlock.
struct SynchronousSourceNetworkBridge {
    static func loadResult(
        urlText: String,
        source: BookSource,
        network: SourceNetworkClient,
        timeout: TimeInterval? = nil,
        cookieHeader: String? = nil,
        persistentValues: [String: String] = [:],
        persistentState: RulePersistentState? = nil
    ) -> Result<SourceResponse, SourceEngineError>? {
        var values = persistentValues
        if let cookieHeader, !cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["cookieHeader"] = cookieHeader
        }
        let request = SourceRequestBuilder().buildPageRequest(
            source: source,
            urlText: urlText,
            persistentValues: values
        )
        let effectiveTimeout = timeout ?? request.timeout
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        Task.detached(priority: nil) {
            box.store(await network.load(request))
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + effectiveTimeout) == .success else { return nil }
        let result = box.load()
        if case .success(let response) = result {
            persistentState?.ingestResponse(response)
        }
        return result
    }

    static func loadResponse(
        urlText: String,
        source: BookSource,
        network: SourceNetworkClient,
        timeout: TimeInterval? = nil,
        cookieHeader: String? = nil,
        persistentValues: [String: String] = [:],
        persistentState: RulePersistentState? = nil
    ) -> SourceResponse? {
        guard let result = loadResult(
            urlText: urlText,
            source: source,
            network: network,
            timeout: timeout,
            cookieHeader: cookieHeader,
            persistentValues: persistentValues,
            persistentState: persistentState
        ), case .success(let response) = result else { return nil }
        return response
    }

    static func loadBody(
        urlText: String,
        source: BookSource,
        network: SourceNetworkClient,
        timeout: TimeInterval? = nil,
        cookieHeader: String? = nil,
        persistentValues: [String: String] = [:],
        persistentState: RulePersistentState? = nil
    ) -> String {
        loadResponse(
            urlText: urlText,
            source: source,
            network: network,
            timeout: timeout,
            cookieHeader: cookieHeader,
            persistentValues: persistentValues,
            persistentState: persistentState
        )?.body ?? ""
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<SourceResponse, SourceEngineError>?

        func store(_ value: Result<SourceResponse, SourceEngineError>) {
            lock.lock(); self.value = value; lock.unlock()
        }

        func load() -> Result<SourceResponse, SourceEngineError>? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }
}
