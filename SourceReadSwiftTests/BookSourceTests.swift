import XCTest
@testable import SourceReadSwift

final class BookSourceTests: XCTestCase {
    func testDecodeMinimalBookSource() throws {
        let json = """
        {
          "bookSourceName": "Test Source",
          "bookSourceUrl": "https://example.com",
          "searchUrl": "https://example.com/search?q={{keyword}}",
          "ruleSearch": {
            "bookList": ".book",
            "name": ".title@text",
            "bookUrl": "a@href"
          }
        }
        """

        let source = try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))
        XCTAssertEqual(source.bookSourceName, "Test Source")
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], ".book")
    }

    func testSearchRequestInterpolation() {
        let source = BookSource(
            bookSourceName: "Test Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q={{keyword}}&page={{page}}"
        )
        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 2
        )

        XCTAssertTrue(request.url.absoluteString.contains("page=2"))
        XCTAssertEqual(request.method, .get)
    }

    func testEncodeDecodeBookSourceRoundTrip() throws {
        let source = BookSource(
            bookSourceName: "Test Source",
            bookSourceUrl: "https://example.com",
            bookSourceGroup: "Novel",
            weight: 3,
            searchUrl: "https://example.com/search?q={{keyword}}",
            exploreUrl: "https://example.com/rank",
            ruleSearch: SourceRule(fields: [
                "bookList": ".book",
                "name": ".title@text",
                "bookUrl": "a@href"
            ]),
            customConfig: #"{"charset":"gbk"}"#,
            raw: ["webView": "true"]
        )

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(BookSource.self, from: data)

        XCTAssertEqual(decoded.bookSourceName, "Test Source")
        XCTAssertEqual(decoded.bookSourceGroup, "Novel")
        XCTAssertEqual(decoded.weight, 3)
        XCTAssertEqual(decoded.exploreUrl, "https://example.com/rank")
        XCTAssertEqual(decoded.ruleSearch?.fields["bookList"], ".book")
        XCTAssertEqual(decoded.customConfig, #"{"charset":"gbk"}"#)
        XCTAssertEqual(decoded.raw["webView"], "true")
    }

    func testRequestBuilderReadsHeadersFromCustomConfigAndRawCookie() {
        let source = BookSource(
            bookSourceName: "Header Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q={{keyword}}",
            header: #"{"Referer":"https://example.com"}"#,
            customConfig: #"{"headers":{"X-Custom":"1"}}"#,
            raw: ["cookie": "a=b"]
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.headers["Referer"], "https://example.com")
        XCTAssertEqual(request.headers["X-Custom"], "1")
        XCTAssertEqual(request.headers["Cookie"], "a=b")
    }

    func testRequestBuilderResolvesRelativeSearchURLAgainstSourceBase() {
        let source = BookSource(
            bookSourceName: "Relative Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "/search?q={{keyword}}"
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.url.absoluteString, "https://example.com/search?q=test")
    }

    func testRequestBuilderReadsPostOptionsFromCustomConfig() {
        let source = BookSource(
            bookSourceName: "Post Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/api",
            customConfig: #"{"method":"POST","body":"q={{keyword}}","headers":{"Content-Type":"application/x-www-form-urlencoded"}}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "q=test")
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded")
    }

    func testDirectiveBodyOverridesRawBody() {
        let source = BookSource(
            bookSourceName: "Post Source",
            bookSourceUrl: "https://example.com",
            searchUrl: #"https://example.com/api@Body:q=directive"#,
            raw: ["body": "q=raw", "method": "POST"]
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "q=directive")
    }
}
