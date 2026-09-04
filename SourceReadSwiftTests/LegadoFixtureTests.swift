import XCTest
@testable import SourceReadSwift

final class LegadoFixtureTests: XCTestCase {
    func testAllBookSourceFixturesDecodeAndExposePipelineCoverage() throws {
        let names = [
            "legado-html-source", "legado-json-source", "legado-js-source",
            "legado-html-pagination-source", "legado-post-source", "legado-jxnode-source",
            "legado-dynamic-token-source", "legado-mixed-response-source",
            "legado-cookie-token-source", "legado-java-import-source", "legado-crypto-source"
        ]
        for name in names {
            let url = try XCTUnwrap(
                Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                    ?? Bundle(for: Self.self).url(forResource: name, withExtension: "json")
            )
            let source = try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: url))
            XCTAssertFalse(source.bookSourceName.isEmpty, name)
            XCTAssertNotNil(source.searchUrl, name)
            XCTAssertNotNil(source.ruleSearch, name)
        }
    }
}
