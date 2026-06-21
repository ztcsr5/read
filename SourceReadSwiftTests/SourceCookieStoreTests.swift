import XCTest
@testable import SourceReadSwift

final class SourceCookieStoreTests: XCTestCase {
    func testCookieHeaderRoundTrip() async throws {
        let store = SourceCookieStore()
        let url = URL(string: "https://example.com/path")!
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: [
            "Set-Cookie": "sid=abc; Path=/; Domain=example.com"
        ], for: url)

        await store.store(cookies, for: url)
        let header = await store.cookieHeader(for: url)

        XCTAssertEqual(header, "sid=abc")
    }

    func testStoreWebViewCookiesUsesCookieDomain() async throws {
        let store = SourceCookieStore()
        let url = URL(string: "https://example.com/path")!
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: [
            "Set-Cookie": "cf_clearance=ok; Path=/; Domain=example.com"
        ], for: url)

        await store.storeWebViewCookies(cookies)
        let header = await store.cookieHeader(for: url)

        XCTAssertEqual(header, "cf_clearance=ok")
    }
}
