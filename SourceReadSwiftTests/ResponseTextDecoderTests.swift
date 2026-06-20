import XCTest
@testable import SourceReadSwift

final class ResponseTextDecoderTests: XCTestCase {
    func testDecodeUTF8ByHeader() {
        let data = Data("斗破苍穹".utf8)
        let text = ResponseTextDecoder().decode(data: data, headers: [
            "Content-Type": "text/html; charset=utf-8"
        ])

        XCTAssertEqual(text, "斗破苍穹")
    }
}

