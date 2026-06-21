import XCTest
@testable import SourceReadSwift

final class SourceImportLinkParserTests: XCTestCase {
    func testKeepsHTTPJSONURLsAsURLs() {
        let input = SourceImportLinkParser.parse("https://example.com/a.json")

        XCTAssertEqual(input.kind, .url)
        XCTAssertEqual(input.value, "https://example.com/a.json")
    }

    func testRecognizesPastedJSON() {
        let input = SourceImportLinkParser.parse(#"[{"bookSourceName":"A"}]"#)

        XCTAssertEqual(input.kind, .json)
        XCTAssertEqual(input.value, #"[{"bookSourceName":"A"}]"#)
    }

    func testExtractsSrcFromYueduImportLinks() {
        let input = SourceImportLinkParser.parse(
            "yuedu://booksource/importonline?src=https%3A%2F%2Fexample.com%2Fsources.json"
        )

        XCTAssertEqual(input.kind, .url)
        XCTAssertEqual(input.value, "https://example.com/sources.json")
    }

    func testExtractsURLFromOtherImportSchemes() {
        let input = SourceImportLinkParser.parse(
            "legado://import?url=https%3A%2F%2Fexample.com%2Fpack.json"
        )

        XCTAssertEqual(input.kind, .url)
        XCTAssertEqual(input.value, "https://example.com/pack.json")
    }

    func testExtractsSrcFromModernLegadoLinks() {
        let input = SourceImportLinkParser.parse(
            "legado://import/bookSource?src=https%3A%2F%2Fexample.com%2Fsource.json"
        )

        XCTAssertEqual(input.kind, .url)
        XCTAssertEqual(input.value, "https://example.com/source.json")
    }

    func testExtractsURLFromNestedShareText() {
        let input = SourceImportLinkParser.parse(
            "Reading import yuedu://rsssource/importonline?url=https%3A%2F%2Fexample.com%2Frss.json"
        )

        XCTAssertEqual(input.kind, .url)
        XCTAssertEqual(input.value, "https://example.com/rss.json")
    }

    func testTrimsTextAfterImportSchemeToken() {
        let input = SourceImportLinkParser.parse(
            "Share legado://import/bookSource?src=https%3A%2F%2Fexample.com%2Fsource.json please import"
        )

        XCTAssertEqual(input.kind, .url)
        XCTAssertEqual(input.value, "https://example.com/source.json")
    }

    func testExtractsURLsFromSharedText() {
        let input = SourceImportLinkParser.parse(
            "Shared source https://example.com/source.json can be imported"
        )

        XCTAssertEqual(input.kind, .url)
        XCTAssertEqual(input.value, "https://example.com/source.json")
    }

    func testTrimsPunctuationAroundSharedURLs() {
        let input = SourceImportLinkParser.parse(
            "Import URL: https://example.com/source.json);"
        )

        XCTAssertEqual(input.kind, .url)
        XCTAssertEqual(input.value, "https://example.com/source.json")
    }

    func testMarksImportSchemeWithoutSrcAsUnsupported() {
        let input = SourceImportLinkParser.parse("yuedu://booksource/importonline")

        XCTAssertEqual(input.kind, .unsupportedScheme)
    }

    func testExtractsEmbeddedJSONFromImportLink() {
        let payload = #"[{"bookSourceName":"A","bookSourceUrl":"https://a.example.com"}]"#
        let encoded = payload.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = SourceImportLinkParser.parse("legado://import/bookSource?data=\(encoded)")

        XCTAssertEqual(input.kind, .json)
        XCTAssertEqual(input.value, payload)
    }
}
