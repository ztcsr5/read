import XCTest
@testable import SourceReadSwift

@MainActor
final class SourceStoreTests: XCTestCase {
    func testImportSingleSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        {
          "bookSourceName": "测试源",
          "bookSourceUrl": "https://example.test",
          "searchUrl": "https://example.test/search?q={{keyword}}"
        }
        """

        try store.importJSON(json)

        XCTAssertNotNil(store.source(for: "https://example.test"))
        try? FileManager.default.removeItem(at: root)
    }
}
