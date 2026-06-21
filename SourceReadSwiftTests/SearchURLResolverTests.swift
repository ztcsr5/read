import XCTest
@testable import SourceReadSwift

final class SearchURLResolverTests: XCTestCase {
    func testResolveTemplateSearchUrl() throws {
        let source = BookSource(
            bookSourceName: "测试源",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q={{keyword}}&page={{page}}"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "斗破苍穹", page: 3)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(url.contains("page=3"))
    }

    func testResolveSingleBraceKeywordAndPageArithmetic() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q={key}&offset={{(page - 1) * 10}}"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "abc def", page: 3)

        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(url, "https://example.com/search?q=abc%20def&offset=20")
    }

    func testResolveJavaScriptSearchUrl() throws {
        let source = BookSource(
            bookSourceName: "测试源",
            bookSourceUrl: "https://example.com",
            searchUrl: "@js:'https://example.com/search?q=' + java.urlEncode(keyword)"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "斗破苍穹", page: 1)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(url.hasPrefix("https://example.com/search?q="))
    }

    func testResolveJavaScriptSearchUrlWithTopLevelReturn() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            searchUrl: "@js:return 'https://example.com/search?q=' + java.urlEncode(keyword)"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "\u{6597}\u{7834}\u{82cd}\u{7a79}", page: 1)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(url.hasPrefix("https://example.com/search?q="))
    }

    func testResolveEmbeddedJavaScriptSegment() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q=<js>java.urlEncode(keyword)</js>&page={{page}}"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "abc def", page: 2)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(url, "https://example.com/search?q=abc%20def&page=2")
    }

    func testResolveSourceTemplateVariables() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            searchUrl: "{{source.api}}/{{source.path}}?q={{keyword}}&base={{source.bookSourceUrl}}",
            raw: [
                "api": "https://api.example.com",
                "path": "search"
            ]
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "abc", page: 1)

        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(url, "https://api.example.com/search?q=abc&base=https://example.com")
    }

    func testResolveJavaScriptCanReadSourceObject() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            searchUrl: "@js:source.bookSourceUrl + '/search?q=' + java.urlEncode(key)"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "abc def", page: 1)

        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(url, "https://example.com/search?q=abc%20def")
    }
}
