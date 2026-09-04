import XCTest
@testable import SourceReadSwift

final class SourceRequestBuilderDynamicStateTests: XCTestCase {
    func testPersistentTokenInterpolatesURLHeadersAndBody() throws {
        let source = BookSource(
            bookSourceName: "Dynamic fixture",
            bookSourceUrl: "https://fixture.example/",
            header: #"{"X-Nonce":"{{nonce}}"}"#,
            raw: ["cookie": "sid={{session}}"]
        )
        let request = SourceRequestBuilder().buildPageRequest(
            source: source,
            urlText: "https://fixture.example/detail/{token}@Body:cursor={{cursor}}&token={{token}}",
            persistentValues: [
                "token": "abc-123",
                "cursor": "p 2",
                "nonce": "n-9",
                "session": "s-7"
            ]
        )

        XCTAssertEqual(request.url.absoluteString, "https://fixture.example/detail/abc-123")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "cursor=p%202&token=abc-123")
        XCTAssertEqual(request.headers["X-Nonce"], "n-9")
        XCTAssertEqual(request.headers["Cookie"], "sid=s-7")
    }

    func testPersistentValuesApplyToJSONSourceOptionsWithoutChangingTypes() throws {
        let source = BookSource(
            bookSourceName: "JSON dynamic fixture",
            bookSourceUrl: "https://fixture.example/",
            customConfig: #"{"method":"POST","headers":{"Content-Type":"application/json","X-Token":"{{token}}"},"body":{"page":2,"cursor":"{{cursor}}"}}"#
        )
        let request = SourceRequestBuilder().buildPageRequest(
            source: source,
            urlText: "https://fixture.example/api",
            persistentValues: ["token": "abc", "cursor": "next"]
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.headers["X-Token"], "abc")
        XCTAssertEqual(
            String(data: request.body ?? Data(), encoding: .utf8),
            #"{"cursor":"next","page":2}"#
        )
    }

    func testDynamicCookieOverridesSourceCookieButDirectiveCookieWins() throws {
        let source = BookSource(
            bookSourceName: "Cookie precedence fixture",
            bookSourceUrl: "https://fixture.example/",
            header: #"{"cookie":"source=stale"}"#
        )
        let dynamic = SourceRequestBuilder().buildPageRequest(
            source: source,
            urlText: "https://fixture.example/detail",
            persistentValues: ["cookieHeader": "session=dynamic"]
        )
        XCTAssertEqual(dynamic.headers["Cookie"], "session=dynamic")
        XCTAssertNil(dynamic.headers["cookie"])

        let directive = SourceRequestBuilder().buildPageRequest(
            source: source,
            urlText: "https://fixture.example/detail@Header:{\"Cookie\":\"session=directive\"}",
            persistentValues: ["cookieHeader": "session=dynamic"]
        )
        XCTAssertEqual(directive.headers["Cookie"], "session=directive")
    }
}
