import Foundation
import XCTest
@testable import SourceReadSwift

/// The network layer must not trust a site's Content-Type.  Real sources
/// commonly return JSON with a BOM/XSSI guard, inside <pre>, or prefixed by a
/// small diagnostic string while still using text/html.
final class SourceEngineMixedResponseFixtureTests: XCTestCase {
    func testSearchParsesBOMXSSIAndEmbeddedJSONWithWrongContentType() async throws {
        let source = BookSource(
            bookSourceName: "Mixed response fixture",
            bookSourceUrl: "https://fixture.local/",
            searchUrl: "https://fixture.local/search?key={{key}}",
            ruleSearch: SourceRule(fields: [
                "bookList": "$.data.items",
                "name": "$.title",
                "bookUrl": "$.url"
            ])
        )
        let body = "\u{FEFF})]}',<pre>prefix {\"data\":{\"items\":[{\"title\":\"混合响应\",\"url\":\"/book/1\"}]}}</pre>"
        let engine = LegadoSourceEngine(network: SingleResponseSourceNetworkClient(body: body, headers: ["Content-Type": "text/html; charset=utf-8"]))

        let result = await engine.searchBooks(source: source, keyword: "混合", page: 1)

        guard case .success(let books) = result else {
            return XCTFail("expected mixed JSON search result: \(result)")
        }
        XCTAssertEqual(books.map(\.name), ["混合响应"])
        XCTAssertEqual(books.first?.bookUrl, "https://fixture.local/book/1")
    }
}

private final class SingleResponseSourceNetworkClient: SourceNetworkClient, @unchecked Sendable {
    private let body: String
    private let headers: [String: String]

    init(body: String, headers: [String: String]) {
        self.body = body
        self.headers = headers
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        .success(SourceResponse(url: request.url, statusCode: 200, headers: headers, body: body, data: Data(body.utf8)))
    }
}
