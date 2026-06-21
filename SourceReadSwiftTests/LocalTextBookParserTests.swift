import XCTest
@testable import SourceReadSwift

final class LocalTextBookParserTests: XCTestCase {
    func testParsesPlainTextIntoParagraphs() {
        let text = "第一段\n\n第二段\r\n第三段"
        let book = LocalTextBookParser().parse(data: Data(text.utf8), fileName: "MyBook.txt")

        XCTAssertEqual(book.title, "MyBook")
        XCTAssertEqual(book.author, "Local")
        XCTAssertEqual(book.paragraphs, ["第一段", "第二段", "第三段"])
    }
}
