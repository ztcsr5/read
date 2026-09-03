import XCTest
@testable import SourceReadSwift

final class AppDataBackupTests: XCTestCase {
    func testPreferenceValueRoundTripPreservesTypes() throws {
        let values: [String: BackupPreferenceValue] = [
            "string": .string("paper"),
            "double": .double(19.5),
            "integer": .integer(3),
            "bool": .bool(true)
        ]
        let data = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([String: BackupPreferenceValue].self, from: data)
        XCTAssertEqual(decoded, values)
    }

    func testFullSnapshotRoundTrip() throws {
        let book = BookshelfBook(
            id: "book-1",
            title: "测试书",
            author: "作者",
            coverURL: nil,
            sourceName: "测试源",
            sourceURL: "https://source.example",
            bookURL: "https://source.example/book/1",
            intro: nil
        )
        let bookshelf = BookshelfBackupSnapshot(
            books: [book],
            groups: [BookshelfGroup(id: "g1", name: "默认", sortOrder: 0)]
        )
        let source = BookSource(bookSourceName: "测试源", bookSourceUrl: "https://source.example")
        let snapshot = AppDataBackupSnapshot(
            bookshelf: bookshelf,
            sources: SourceLibrarySnapshot(sources: [source]),
            purifyRules: [PurifyRule(id: "rule-1", pattern: "广告")],
            rssState: RSSArticleStateSnapshot(readIDs: ["r1"], favoriteIDs: ["r2"]),
            readerPreferences: ["reader.fontSize": .double(20), "reader.mode": .string("paged")]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppDataBackupSnapshot.self, from: encoder.encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.bookshelf.books.first?.title, "测试书")
        XCTAssertEqual(decoded.readerPreferences["reader.fontSize"], .double(20))
    }
}
