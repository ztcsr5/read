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

    func testRequestBuilderReadsBookSourceHeaderAndDictionaryBody() {
        let source = BookSource(
            bookSourceName: "Dictionary Post Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/api",
            customConfig: #"{"requestBody":{"q":"{{keyword}}&x","page":"{{page}}"},"bookSourceHeader":{"X-Book":"1"}}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 2
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "page=2&q=test%26x")
        XCTAssertEqual(request.headers["X-Book"], "1")
    }

    func testRequestBuilderEncodesDictionaryBodyAsJSON() {
        let source = BookSource(
            bookSourceName: "JSON Post Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/api",
            customConfig: #"{"headers":{"Content-Type":"application/json"},"body":{"q":"{{keyword}}","page":"{{page}}"}}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 2
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), #"{"page":"2","q":"test"}"#)
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
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

    func testRequestBuilderReadsCharsetFromCustomConfig() {
        let source = BookSource(
            bookSourceName: "Charset Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search",
            customConfig: #"{"charset":"gbk"}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.expectedCharset, "gbk")
    }

    func testRequestBuilderReadsCharsetFromURLDirectiveOptions() {
        let source = BookSource(
            bookSourceName: "Directive Charset Source",
            bookSourceUrl: "https://example.com",
            searchUrl: #"https://example.com/search?q={{keyword}},{"charset":"gbk"}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.url.absoluteString, "https://example.com/search?q=test")
        XCTAssertEqual(request.expectedCharset, "gbk")
    }

    func testRequestBuilderReadsLegadoTypeDataAndUserAgentAliases() {
        let source = BookSource(
            bookSourceName: "Legado Alias Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/api",
            customConfig: #"{"type":"POST","data":{"q":"{{keyword}}","page":"{{page}}"},"ua":"AliasUA/1.0"}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 3
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "page=3&q=test")
        XCTAssertEqual(request.headers["User-Agent"], "AliasUA/1.0")
        XCTAssertEqual(request.headers["Referer"], "https://example.com/")
        XCTAssertEqual(request.headers["Origin"], "https://example.com")
    }

    func testDecodeLegacyLegadoBookSourceFields() throws {
        let json = """
        {
          "bookSourceName": "Legacy Source",
          "bookSourceUrl": "https://example.com",
          "bookSourceGroup": "legacy",
          "enabled": "y",
          "serialNumber": 9,
          "ruleSearchUrl": "https://example.com/search/searchKey/searchPage|charset=gbk@q=searchKey&page=searchPage",
          "ruleSearchList": ".result",
          "ruleSearchName": ".name",
          "ruleSearchAuthor": ".author",
          "ruleSearchNoteUrl": "a@href",
          "ruleBookInfoInit": "#main",
          "ruleBookName": "h1",
          "ruleBookAuthor": ".author",
          "ruleIntroduce": ".intro",
          "ruleChapterList": ".chapter",
          "ruleChapterName": "a",
          "ruleContentUrl": "a@href",
          "ruleBookContent": ".content@html",
          "ruleBookContentReplace": "ads##",
          "ruleContentUrlNext": ".next@href",
          "httpUserAgent": "LegacyUA/1.0"
        }
        """

        let source = try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))

        XCTAssertEqual(source.bookSourceGroup, "legacy")
        XCTAssertTrue(source.enabled)
        XCTAssertEqual(source.weight, 9)
        XCTAssertEqual(source.searchUrl, #"https://example.com/search/{{key}}/{{page}},{"body":"q={{key}}&page={{page}}","charset":"gbk","method":"POST"}"#)
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], ".result")
        XCTAssertEqual(source.ruleSearch?.fields["name"], ".name")
        XCTAssertEqual(source.ruleSearch?.fields["bookUrl"], "a@href")
        XCTAssertEqual(source.ruleBookInfo?.fields["name"], "h1")
        XCTAssertEqual(source.ruleBookInfo?.fields["init"], "#main")
        XCTAssertEqual(source.ruleBookInfo?.fields["intro"], ".intro")
        XCTAssertEqual(source.ruleToc?.fields["chapterList"], ".chapter")
        XCTAssertEqual(source.ruleToc?.fields["chapterUrl"], "a@href")
        XCTAssertEqual(source.ruleContent?.fields["content"], ".content@html")
        XCTAssertEqual(source.ruleContent?.fields["replaceRegex"], "ads##")
        XCTAssertEqual(source.ruleContent?.fields["nextContentUrl"], ".next@href")

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "abc",
            page: 2
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.expectedCharset, "gbk")
        XCTAssertEqual(request.headers["User-Agent"], "LegacyUA/1.0")
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "q=abc&page=2")
    }

    func testDecodeRuleObjectStoredAsJSONString() throws {
        let json = #"""
        {
          "bookSourceName": "JSONString Rule Source",
          "bookSourceUrl": "https://example.com",
          "searchUrl": "https://example.com/search?q={{key}}",
          "ruleSearch": "{\"bookList\":\".item\",\"name\":\".title\",\"bookUrl\":\"a@href\"}"
        }
        """#

        let source = try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))

        XCTAssertEqual(source.ruleSearch?.fields["bookList"], ".item")
        XCTAssertEqual(source.ruleSearch?.fields["name"], ".title")
        XCTAssertEqual(source.ruleSearch?.fields["bookUrl"], "a@href")
        XCTAssertNil(source.ruleSearch?.raw)
    }

    func testRuleBookContentObjectIsKeptStructured() throws {
        let json = """
        {
          "bookSourceName": "Structured Content Source",
          "bookSourceUrl": "https://example.com",
          "searchUrl": "https://example.com/search?q={{key}}",
          "ruleBookContent": {
            "content": ".content@html",
            "nextContentUrl": ".next@href"
          }
        }
        """

        let source = try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))

        XCTAssertEqual(source.ruleContent?.fields["content"], ".content@html")
        XCTAssertEqual(source.ruleContent?.fields["nextContentUrl"], ".next@href")
    }
}
