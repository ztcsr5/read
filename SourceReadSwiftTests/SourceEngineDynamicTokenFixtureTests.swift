import Foundation
import XCTest
@testable import SourceReadSwift

/// Verifies that the state written by a Legado search script is available to
/// every later request.  The fixture intentionally rejects a request if the
/// token, cursor or cookie is missing, so a parser-only test cannot pass.
final class SourceEngineDynamicTokenFixtureTests: XCTestCase {
    func testSearchDetailTOCContentShareDynamicTokenCursorAndCookie() async throws {
        let source = try loadFixture(named: "legado-dynamic-token-source")
        let searchURL = "https://fixture.example/dynamic/search"
        let bookURL = "https://fixture.example/dynamic/book/1"
        let tocURL = "https://fixture.example/dynamic/toc/1?cursor=cursor-1"
        let chapterURL = "https://fixture.example/dynamic/chapter/1?cursor=cursor-1"
        let network = DynamicTokenFixtureNetwork(
            searchURL: searchURL,
            bookURL: bookURL,
            tocURL: tocURL,
            chapterURL: chapterURL
        )
        let engine = LegadoSourceEngine(network: network)

        let books = try unwrap(await engine.searchBooks(source: source, keyword: "swift", page: 1))
        XCTAssertEqual(books.map(\.name), ["Dynamic Reader"])
        XCTAssertEqual(books.first?.bookUrl, bookURL)

        let detail = try unwrap(await engine.getBookDetail(source: source, book: try XCTUnwrap(books.first)))
        XCTAssertEqual(detail.tocUrl, tocURL)

        let chapters = try unwrap(await engine.getChapterList(source: source, book: detail))
        XCTAssertEqual(chapters.map(\.title), ["第一章"])
        XCTAssertEqual(chapters.first?.url, chapterURL)

        let content = try unwrap(await engine.getContent(source: source, chapter: try XCTUnwrap(chapters.first)))
        XCTAssertEqual(content.paragraphs, ["动态状态正文"])
        XCTAssertEqual(network.requestedURLs, [searchURL, bookURL, tocURL, chapterURL])
        XCTAssertEqual(network.invalidRequestCount, 0)
    }

    private func loadFixture(named name: String) throws -> BookSource {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: "json")
        )
        return try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: url))
    }

    private func unwrap<T>(
        _ result: Result<T, SourceEngineError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> T {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("dynamic source pipeline failed: \(error)", file: file, line: line)
            throw error
        }
    }
}

private final class DynamicTokenFixtureNetwork: SourceNetworkClient, @unchecked Sendable {
    private let searchURL: String
    private let bookURL: String
    private let tocURL: String
    private let chapterURL: String
    private let lock = NSLock()
    private var requests: [SourceRequest] = []
    private var invalidRequests = 0

    init(searchURL: String, bookURL: String, tocURL: String, chapterURL: String) {
        self.searchURL = searchURL
        self.bookURL = bookURL
        self.tocURL = tocURL
        self.chapterURL = chapterURL
    }

    var requestedURLs: [String] {
        lock.lock(); defer { lock.unlock() }
        return requests.map { $0.url.absoluteString }
    }

    var invalidRequestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return invalidRequests
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let url = request.url.absoluteString
        let token = request.headers.first { $0.key.caseInsensitiveCompare("X-Token") == .orderedSame }?.value
        let cursor = request.headers.first { $0.key.caseInsensitiveCompare("X-Cursor") == .orderedSame }?.value
        let cookie = request.headers.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }?.value
        let stateIsPresent = token == "fixture-token" && cursor == "cursor-1" && cookie == "session=dynamic"

        lock.lock()
        requests.append(request)
        if !stateIsPresent { invalidRequests += 1 }
        lock.unlock()

        guard stateIsPresent else {
            return .failure(.network("dynamic token/cursor/cookie missing"))
        }

        let body: String
        switch url {
        case searchURL:
            body = #"{"books":[{"name":"Dynamic Reader","author":"Fixture Author","url":"/dynamic/book/1"}]}"#
        case bookURL:
            body = #"{"name":"Dynamic Reader","author":"Fixture Author","toc":"/dynamic/toc/1?cursor=cursor-1"}"#
        case tocURL:
            body = #"{"chapters":[{"title":"第一章","url":"/dynamic/chapter/1?cursor=cursor-1"}]}"#
        case chapterURL:
            body = #"{"content":"动态状态正文"}"#
        default:
            return .failure(.network("fixture response missing for \(url)"))
        }
        return .success(SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: body,
            data: Data(body.utf8)
        ))
    }
}
