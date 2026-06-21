import XCTest
@testable import SourceReadSwift

final class ResponseTextDecoderTests: XCTestCase {
    func testDecodeUTF8ByHeader() {
        let data = Data("hello".utf8)
        let text = ResponseTextDecoder().decode(data: data, headers: [
            "Content-Type": "text/html; charset=utf-8"
        ])

        XCTAssertEqual(text, "hello")
    }

    func testSniffsCharsetFromMetaTagWhenHeaderIsMissing() {
        let data = Data(#"<html><head><meta charset="utf-8"></head><body>ok</body></html>"#.utf8)
        let text = ResponseTextDecoder().decode(data: data, headers: [:])

        XCTAssertTrue(text.contains("ok"))
    }
}
