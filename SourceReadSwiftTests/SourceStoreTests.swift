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

    func testImportsSourcesFromItemsWrapper() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        {
          "items": [
            {
              "bookSourceName": "Items wrapped source",
              "bookSourceUrl": "https://items.example.com",
              "searchUrl": "/search?q={{key}}",
              "ruleSearch": { "bookList": "data.list", "name": "title" }
            }
          ]
        }
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "Items wrapped source")
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsJSONExtractedFromBrowserText() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        header text
        [
          {
            "bookSourceName": "Browser extracted source",
            "bookSourceUrl": "https://browser.example.com",
            "searchUrl": "/search?q={{key}}",
            "ruleSearch": { "bookList": "data.list", "name": "title" }
          }
        ]
        footer text
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "Browser extracted source")
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsBookSourceAliasesFromSharedJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        [
          {
            "sourceName": "Alias Source",
            "sourceUrl": "https://alias.example.com",
            "sourceGroup": "Group A",
            "rulesSearch": {
              "bookList": "$.data.list[*]",
              "name": "title",
              "bookUrl": "/detail?id={{bookId}}"
            },
            "rulesToc": {
              "chapterList": "chapters",
              "chapterName": "name",
              "chapterUrl": "url"
            },
            "ruleBookContent": { "content": "data.content" }
          }
        ]
        """

        try store.importJSON(json)

        let source = try XCTUnwrap(store.sources.first)
        XCTAssertEqual(source.bookSourceName, "Alias Source")
        XCTAssertEqual(source.bookSourceGroup, "Group A")
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], "$.data.list[*]")
        XCTAssertEqual(source.ruleContent?.fields["content"], "data.content")
        try? FileManager.default.removeItem(at: root)
    }

    func testUpdatesDuplicateBookSourceByURL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "bookSourceName": "Old Name",
            "bookSourceUrl": "https://dup.example.com",
            "searchUrl": "/old?q={{key}}",
            "ruleSearch": { "bookList": "data.list", "name": "title" }
          }
        ]
        """)
        try store.importJSON("""
        [
          {
            "bookSourceName": "New Name",
            "bookSourceUrl": "https://dup.example.com",
            "searchUrl": "/new?q={{key}}",
            "ruleSearch": { "bookList": "data.items", "name": "name" }
          }
        ]
        """)

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "New Name")
        XCTAssertEqual(store.sources.first?.searchUrl, "/new?q={{key}}")
        try? FileManager.default.removeItem(at: root)
    }

    func testSmartImportParsesPastedJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        let parsed = try store.importSmartInput("""
        [
          {
            "bookSourceName": "Smart Source",
            "bookSourceUrl": "https://smart.example.com",
            "searchUrl": "/search?q={{key}}"
          }
        ]
        """)

        XCTAssertEqual(parsed.kind, .json)
        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "Smart Source")
        try? FileManager.default.removeItem(at: root)
    }
}
