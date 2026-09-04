import XCTest
@testable import SourceReadSwift

final class SourceURLDirectiveTests: XCTestCase {
    func testParseHeaderDirective() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/search@Header:{"Referer":"https://example.com","X-Test":"1"}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/search")
        XCTAssertEqual(directive.headers["Referer"], "https://example.com")
        XCTAssertEqual(directive.headers["X-Test"], "1")
        XCTAssertEqual(directive.method, .get)
    }

    func testParseJSONPostDirective() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"method":"POST","body":"keyword=test","headers":{"Content-Type":"application/x-www-form-urlencoded"}}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "keyword=test")
        XCTAssertEqual(directive.headers["Content-Type"], "application/x-www-form-urlencoded")
    }

    func testParseHeaderThenBodyDirectives() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api@Header:{"Referer":"https://example.com"}@Body:q=1"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "q=1")
        XCTAssertEqual(directive.headers["Referer"], "https://example.com")
    }

    func testParseBodyThenHeaderDirectives() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api@Body:q=1@Header:{"Referer":"https://example.com"}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "q=1")
        XCTAssertEqual(directive.headers["Referer"], "https://example.com")
    }

    func testParseHeaderAndPostAliases() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api@Headers:{"X-Test":"1"}@Post:q=1"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "q=1")
        XCTAssertEqual(directive.headers["X-Test"], "1")
    }

    func testParseJSONAliases() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"httpMethod":"POST","requestBody":"keyword=test","bookSourceHeader":{"X-Book":"1"}}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "keyword=test")
        XCTAssertEqual(directive.headers["X-Book"], "1")
    }

    func testParseDictionaryBodyAsFormBodyByDefault() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"body":{"b":"2","a":"1&2"}}"#
        )

        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "a=1%262&b=2")
    }

    func testParseDictionaryBodyAsJSONWhenContentTypeIsJSON() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"headers":{"Content-Type":"application/json"},"body":{"b":"2","a":"1"}}"#
        )

        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), #"{"a":"1","b":"2"}"#)
    }

    func testParseLegadoTypeAndDataAliases() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"type":"POST","data":{"q":"test","page":"2"}}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "page=2&q=test")
    }

    func testParseJSONHeadDirectiveWithoutBody() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/health,{"method":"HEAD","headers":{"X-Probe":"1"}}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/health")
        XCTAssertEqual(directive.method, .head)
        XCTAssertNil(directive.body)
        XCTAssertEqual(directive.headers["X-Probe"], "1")
    }

    func testParseCharsetAndEncodingTrailingDirectives() {
        let charset = SourceURLDirectiveParser().parse(
            #"https://example.com/search@Charset:gbk"#
        )
        XCTAssertEqual(charset.urlText, "https://example.com/search")
        XCTAssertEqual(charset.expectedCharset, "gbk")

        let encoding = SourceURLDirectiveParser().parse(
            #"https://example.com/search@Encoding:UTF-8"#
        )
        XCTAssertEqual(encoding.expectedCharset, "UTF-8")
    }

    func testParseJSONTimeoutOptionsAsSecondsOrMilliseconds() {
        let seconds = SourceURLDirectiveParser().parse(
            #"https://example.com/search,{"timeout":2}"#
        )
        XCTAssertEqual(seconds.timeout ?? -1, 2, accuracy: 0.001)

        let milliseconds = SourceURLDirectiveParser().parse(
            #"https://example.com/search,{"timeoutMs":1500}"#
        )
        XCTAssertEqual(milliseconds.timeout ?? -1, 1.5, accuracy: 0.001)
    }

    func testParsePlainHeaderAndEscapedBody() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api@Header:X-Test: 1\nReferer: https://example.com\n@Body:a=1\nb=2"#
        )

        XCTAssertEqual(directive.headers["X-Test"], "1")
        XCTAssertEqual(directive.headers["Referer"], "https://example.com")
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "a=1\nb=2")
        XCTAssertEqual(directive.method, .post)
    }

    func testParseEscapedBodyAndCharsetTogether() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api@Charset:gbk@Body:q=hello\npage=2"#
        )

        XCTAssertEqual(directive.expectedCharset, "gbk")
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "q=hello\npage=2")
        XCTAssertEqual(directive.method, .post)
    }

    func testParseJSONBodyPreservesNumbersAndBooleans() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"headers":{"Content-Type":"application/json"},"body":{"page":2,"enabled":true}}"#
        )

        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), #"{"enabled":true,"page":2}"#)
    }
}
