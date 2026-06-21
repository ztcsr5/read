import XCTest
@testable import SourceReadSwift

@MainActor
final class BookshelfStoreTests: XCTestCase {
    func testPersistsLocalTextBookContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = BookshelfStore(persistence: BookshelfPersistence(fileManager: .default, rootURL: root))

        store.addLocalTextBook(LocalTextBook(title: "Local", author: "Local", paragraphs: ["A", "B"]))

        let reloaded = BookshelfStore(persistence: BookshelfPersistence(fileManager: .default, rootURL: root))
        XCTAssertEqual(reloaded.books.count, 1)
        XCTAssertEqual(reloaded.books.first?.title, "Local")
        XCTAssertEqual(reloaded.books.first?.localContent, ["A", "B"])
        try? FileManager.default.removeItem(at: root)
    }
}
