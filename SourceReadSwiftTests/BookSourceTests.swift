import XCTest
@testable import SourceReadSwift

final class BookSourceTests: XCTestCase {
    func testDecodeMinimalBookSource() throws {
        let json = """
        {
          "bookSourceName": "测试源",
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
        XCTAssertEqual(source.bookSourceName, "测试源")
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], ".book")
    }

    func testSearchRequestInterpolation() {
        let source = BookSource(
            bookSourceName: "测试源",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q={{keyword}}&page={{page}}"
        )
        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "斗破苍穹",
            page: 2
        )

        XCTAssertTrue(request.url.absoluteString.contains("page=2"))
        XCTAssertEqual(request.method, .get)
    }
}

