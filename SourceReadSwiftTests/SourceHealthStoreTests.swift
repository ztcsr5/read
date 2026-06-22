import XCTest
@testable import SourceReadSwift

@MainActor
final class SourceHealthStoreTests: XCTestCase {
    func testRecordsLatestHealthAndPersists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = SourceHealthPersistence(fileManager: .default, rootURL: root)
        let store = SourceHealthStore(persistence: persistence)
        let source = BookSource(
            bookSourceName: "测试源",
            bookSourceUrl: "https://source.example.com",
            searchUrl: "https://source.example.com/search"
        )

        store.record(
            source: source,
            status: .passed,
            message: "搜索通过：3 条结果。",
            keyword: "斗破苍穹",
            resultCount: 3
        )

        let record = try XCTUnwrap(store.record(for: source))
        XCTAssertEqual(record.status, .passed)
        XCTAssertEqual(record.resultCount, 3)

        let reloaded = SourceHealthStore(persistence: persistence)
        XCTAssertEqual(reloaded.record(for: source)?.message, "搜索通过：3 条结果。")
        try? FileManager.default.removeItem(at: root)
    }
}
