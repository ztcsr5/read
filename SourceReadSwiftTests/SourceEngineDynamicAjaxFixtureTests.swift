import Foundation
import XCTest
@testable import SourceReadSwift

/// Exercises the difficult Legado pattern where search JS performs a blocking
/// ajax call, stores a nonce/cookie, and the actual search request consumes
/// those values.  The injected network client keeps this test fully offline.
final class SourceEngineDynamicAjaxFixtureTests: XCTestCase {
    func testSearchAjaxResponseFeedsNonceCookieIntoSearchRequest() async throws {
        let source = BookSource(
            bookSourceName: "Dynamic ajax fixture",
            bookSourceUrl: "https://fixture.local/",
            searchUrl: "@js: var boot = java.ajax('https://fixture.local/bootstrap'); java.put('token', boot.header('X-Nonce')); return 'https://fixture.local/search';",
            header: #"{"X-Token":"{{token}}"}"#,
            ruleSearch: SourceRule(fields: ["bookList": "$.books", "name": "$.name", "bookUrl": "$.url"])
        )
        let network = DynamicAjaxFixtureNetwork()
        let engine = LegadoSourceEngine(network: network)

        let result = await engine.searchBooks(source: source, keyword: "swift", page: 1)
        guard case .success(let books) = result else {
            return XCTFail("ajax bootstrap did not complete: \(result)")
        }
        XCTAssertEqual(books.first?.name, "Ajax Reader")
        XCTAssertEqual(network.requestedURLs, [
            "https://fixture.local/bootstrap",
            "https://fixture.local/search"
        ])
        XCTAssertEqual(network.invalidSearchRequests, 0)
    }
}

private final class DynamicAjaxFixtureNetwork: SourceNetworkClient, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [SourceRequest] = []
    private var invalidSearch = 0

    var requestedURLs: [String] {
        lock.lock(); defer { lock.unlock() }
        return requests.map { $0.url.absoluteString }
    }

    var invalidSearchRequests: Int {
        lock.lock(); defer { lock.unlock() }
        return invalidSearch
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let url = request.url.absoluteString
        lock.lock(); requests.append(request); lock.unlock()
        if url.hasSuffix("/bootstrap") {
            let body = "cursor-from-bootstrap"
            return .success(SourceResponse(
                url: request.url,
                statusCode: 200,
                headers: ["X-Nonce": "nonce-from-bootstrap", "Set-Cookie": "sid=ajax; Path=/"],
                body: body,
                data: Data(body.utf8)
            ))
        }
        let token = request.headers.first { $0.key.caseInsensitiveCompare("X-Token") == .orderedSame }?.value
        let cookie = request.headers.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }?.value
        guard token == "nonce-from-bootstrap", cookie == "sid=ajax" else {
            lock.lock(); invalidSearch += 1; lock.unlock()
            return .failure(.network("nonce/cookie missing from ajax search"))
        }
        let body = #"{"books":[{"name":"Ajax Reader","url":"https://fixture.local/book/1"}]}"#
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8)))
    }
}
