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
}

