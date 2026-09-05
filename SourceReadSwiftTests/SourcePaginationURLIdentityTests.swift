import XCTest
@testable import SourceReadSwift

final class SourcePaginationURLIdentityTests: XCTestCase {
    func testCanonicalIdentityNormalizesSchemeHostPortPathQueryAndFragment() throws {
        let identity = SourcePaginationURLIdentity()
        let left = try XCTUnwrap(URL(string: "HTTPS://FIXTURE.LOCAL:443/toc/./part/../2%7e?b=2&a=1#reader"))
        let right = try XCTUnwrap(URL(string: "https://fixture.local/toc/2~?a=1&b=2"))

        XCTAssertEqual(identity.canonical(left), identity.canonical(right))
    }

    func testCanonicalIdentityKeepsReservedEscapesAndCanPreserveQueryOrder() throws {
        let sorted = SourcePaginationURLIdentity(sortQueryItems: true)
        let ordered = SourcePaginationURLIdentity(sortQueryItems: false)
        let escapedSlash = try XCTUnwrap(URL(string: "https://fixture.local/a%2Fb"))
        let literalSlash = try XCTUnwrap(URL(string: "https://fixture.local/a/b"))
        XCTAssertNotEqual(sorted.canonical(escapedSlash), sorted.canonical(literalSlash))

        let first = try XCTUnwrap(URL(string: "https://fixture.local/page?b=2&a=1"))
        let second = try XCTUnwrap(URL(string: "https://fixture.local/page?a=1&b=2"))
        XCTAssertEqual(sorted.canonical(first), sorted.canonical(second))
        XCTAssertNotEqual(ordered.canonical(first), ordered.canonical(second))
    }
}
