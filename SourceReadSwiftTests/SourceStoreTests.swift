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

    func testImportsSingleBookSourceFromWrapper() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        {
          "bookSource": {
            "bookSourceName": "Single wrapped source",
            "bookSourceUrl": "https://single-wrapper.example.com",
            "searchUrl": "/search?q={{key}}"
          }
        }
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "Single wrapped source")
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

    func testImportsExtendedBookSourceFieldsForSwiftEngine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "bookSourceName": "Extended Source",
            "bookSourceUrl": "https://extended.example.com",
            "bookSourceType": 0,
            "weight": 7,
            "searchUrl": "/search?q={{key}}",
            "exploreUrl": "/rank/{{page}}",
            "ruleExplore": { "bookList": "data.books", "name": "title" },
            "header": "{\\"User-Agent\\":\\"UnitTest\\"}",
            "customConfig": "{\\"charset\\":\\"gbk\\"}"
          }
        ]
        """)

        let source = try XCTUnwrap(store.sources.first)
        XCTAssertEqual(source.bookSourceType, 0)
        XCTAssertEqual(source.weight, 7)
        XCTAssertEqual(source.exploreUrl, "/rank/{{page}}")
        XCTAssertEqual(source.ruleExplore?.fields["bookList"], "data.books")
        XCTAssertEqual(source.header, "{\"User-Agent\":\"UnitTest\"}")
        XCTAssertEqual(source.customConfig, "{\"charset\":\"gbk\"}")
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

    func testImportReportCountsAddedAndUpdatedItems() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        let first = try store.importJSON("""
        [
          {
            "bookSourceName": "First",
            "bookSourceUrl": "https://report.example.com/one",
            "searchUrl": "/search?q={{key}}"
          }
        ]
        """)

        let second = try store.importJSON("""
        [
          {
            "bookSourceName": "First Updated",
            "bookSourceUrl": "https://report.example.com/one",
            "searchUrl": "/new?q={{key}}"
          },
          {
            "bookSourceName": "Second",
            "bookSourceUrl": "https://report.example.com/two",
            "searchUrl": "/search?q={{key}}"
          }
        ]
        """)

        XCTAssertEqual(first.addedBookSources, 1)
        XCTAssertEqual(first.updatedBookSources, 0)
        XCTAssertEqual(second.addedBookSources, 1)
        XCTAssertEqual(second.updatedBookSources, 1)
        XCTAssertEqual(store.sources.count, 2)
        try? FileManager.default.removeItem(at: root)
    }

    func testUpsertsBookSourceFromEditedJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        {
          "bookSourceName": "Before Edit",
          "bookSourceUrl": "https://edit.example.com",
          "searchUrl": "/old?q={{key}}"
        }
        """)

        let updated = try store.upsertBookSourceJSON("""
        {
          "bookSourceName": "After Edit",
          "bookSourceUrl": "https://edit.example.com",
          "searchUrl": "/new?q={{key}}",
          "ruleSearch": { "bookList": ".book", "name": ".title" }
        }
        """)

        XCTAssertEqual(updated.bookSourceName, "After Edit")
        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "After Edit")
        XCTAssertEqual(store.sources.first?.ruleSearch?.fields["bookList"], ".book")
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

    func testImportsCatalogSeparatelyFromRSS() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "sourceName": "Yiove Catalog",
            "sourceUrl": "https://shuyuan.yiove.com",
            "sourceGroup": "Sources",
            "sourceComment": "Catalog home"
          }
        ]
        """)

        XCTAssertEqual(store.catalogs.count, 1)
        XCTAssertEqual(store.rssSources.count, 0)
        XCTAssertEqual(store.sources.count, 0)
        XCTAssertEqual(store.catalogs.first?.name, "Yiove Catalog")
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsMixedBookSourceRSSAndCatalog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        {
          "items": [
            {
              "bookSourceName": "Book Source",
              "bookSourceUrl": "https://book.example.com",
              "searchUrl": "/search?q={{key}}",
              "ruleSearch": { "bookList": "data.list", "name": "title" }
            },
            {
              "sourceName": "RSS Source",
              "sourceUrl": "https://news.example.com/feed.xml",
              "ruleArticles": "channel.item",
              "ruleTitle": "title"
            },
            {
              "sourceName": "Catalog Source",
              "sourceUrl": "https://catalog.example.com/sources.json",
              "importUrl": "https://catalog.example.com/sources.json"
            }
          ]
        }
        """)

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.rssSources.count, 1)
        XCTAssertEqual(store.catalogs.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "Book Source")
        XCTAssertEqual(store.rssSources.first?.sourceName, "RSS Source")
        XCTAssertEqual(store.catalogs.first?.name, "Catalog Source")
        try? FileManager.default.removeItem(at: root)
    }

    func testPersistsRSSAndCatalogsWithBookSources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "bookSourceName": "Book Source",
            "bookSourceUrl": "https://book.example.com",
            "searchUrl": "/search?q={{key}}"
          },
          {
            "sourceName": "RSS Source",
            "sourceUrl": "https://news.example.com/rss",
            "ruleArticles": "items"
          },
          {
            "sourceName": "Catalog Source",
            "sourceUrl": "https://shuyuan.example.com"
          }
        ]
        """)

        let reloaded = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        XCTAssertEqual(reloaded.sources.count, 1)
        XCTAssertEqual(reloaded.rssSources.count, 1)
        XCTAssertEqual(reloaded.catalogs.count, 1)
        try? FileManager.default.removeItem(at: root)
    }

    func testClassifiesPlainFeedURLAsRSS() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "sourceName": "Plain Feed",
            "sourceUrl": "https://example.com/feed.xml"
          }
        ]
        """)

        XCTAssertEqual(store.rssSources.count, 1)
        XCTAssertEqual(store.catalogs.count, 0)
        try? FileManager.default.removeItem(at: root)
    }

    func testClassifiesPlainSourceNameAsCatalogInsteadOfRSS() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "sourceName": "Plain Catalog",
            "sourceUrl": "https://catalog.example.com"
          }
        ]
        """)

        XCTAssertEqual(store.catalogs.count, 1)
        XCTAssertEqual(store.rssSources.count, 0)
        try? FileManager.default.removeItem(at: root)
    }
}
