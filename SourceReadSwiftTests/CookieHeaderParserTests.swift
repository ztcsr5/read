import XCTest
@testable import SourceReadSwift

final class CookieHeaderParserTests: XCTestCase {
    func testCombinedSetCookiePreservesExpiresComma() {
        let raw = "sid=abc; Expires=Wed, 21 Oct 2030 07:28:00 GMT; Path=/, theme=dark; Path=/"
        XCTAssertEqual(CookieHeaderParser.splitSetCookie(raw).count, 2)
        XCTAssertEqual(CookieHeaderParser.cookiePair(fromSetCookie: CookieHeaderParser.splitSetCookie(raw)[0])?.name, "sid")
        XCTAssertEqual(CookieHeaderParser.cookiePair(fromSetCookie: CookieHeaderParser.splitSetCookie(raw)[1])?.value, "dark")
    }

    func testMergeReplacesOnlySameCookieName() {
        let merged = CookieHeaderParser.merge("sid=new; Path=/, theme=dark", into: "sid=old; lang=zh")
        XCTAssertEqual(merged, "lang=zh; sid=new; theme=dark")
    }

    func testResponseCookiesEnterRulePersistentState() {
        let context = RuleExecutionContext()
        context.ingestResponse(SourceResponse(
            url: URL(string: "https://fixture.local/")!,
            statusCode: 200,
            headers: ["Set-Cookie": "sid=abc; Expires=Wed, 21 Oct 2030 07:28:00 GMT; Path=/, theme=dark; Path=/"],
            body: "",
            data: Data()
        ))
        XCTAssertEqual(context.string(for: "cookieHeader"), "sid=abc; theme=dark")
    }
}
