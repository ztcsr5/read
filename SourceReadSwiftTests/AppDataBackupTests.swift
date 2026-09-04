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
        // ISO-8601 without fractional seconds is used by the portable
        // document encoder. Keep fixture dates at second precision so the
        // round-trip assertion tests the schema rather than formatter loss.
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let book = BookshelfBook(
            id: "book-1",
            title: "测试书",
            author: "作者",
            coverURL: nil,
            sourceName: "测试源",
            sourceURL: "https://source.example",
            bookURL: "https://source.example/book/1",
            intro: nil,
            addedAt: fixedDate
        )
        let bookshelf = BookshelfBackupSnapshot(
            exportedAt: fixedDate,
            books: [book],
            groups: [BookshelfGroup(id: "g1", name: "默认", sortOrder: 0, createdAt: fixedDate)]
        )
        let source = BookSource(bookSourceName: "测试源", bookSourceUrl: "https://source.example")
        let snapshot = AppDataBackupSnapshot(
            exportedAt: fixedDate,
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
        XCTAssertEqual(decoded.schemaVersion, snapshot.schemaVersion)
        XCTAssertEqual(decoded.exportedAt, snapshot.exportedAt)
        XCTAssertEqual(decoded.bookshelf, snapshot.bookshelf)
        XCTAssertEqual(decoded.sources.sources.first?.bookSourceName, "测试源")
        XCTAssertEqual(decoded.sources.sources.first?.bookSourceUrl, source.bookSourceUrl)
        XCTAssertEqual(decoded.purifyRules, snapshot.purifyRules)
        XCTAssertEqual(decoded.rssState, snapshot.rssState)
        XCTAssertEqual(decoded.readerPreferences, snapshot.readerPreferences)
        XCTAssertEqual(decoded.bookshelf.books.first?.title, "测试书")
        XCTAssertEqual(decoded.readerPreferences["reader.fontSize"], BackupPreferenceValue.double(20))
    }

    func testBackupCodecRejectsEmptyWhitespaceAndMalformedInput() {
        let sources = SourceLibrarySnapshot(sources: [])
        let rules: [PurifyRule] = []
        let state = RSSArticleStateSnapshot(readIDs: [], favoriteIDs: [])
        for data in [Data(), Data(" \n\t".utf8), Data("{not-json}".utf8)] {
            XCTAssertThrowsError(try AppDataBackupCodec.decode(
                data: data,
                fallbackSources: sources,
                fallbackPurifyRules: rules,
                fallbackRSSState: state
            ))
        }
    }

    func testBackupCodecReadsLegacyBookshelfWithoutOverwritingOtherStores() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let book = BookshelfBook(
            id: "legacy-book", title: "旧书", author: "作者", coverURL: nil,
            sourceName: "本地", sourceURL: "local://text", bookURL: "legacy-book",
            intro: nil, addedAt: fixedDate
        )
        let legacy = BookshelfBackupSnapshot(exportedAt: fixedDate, books: [book], groups: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(legacy)
        let fallbackSource = SourceLibrarySnapshot(sources: [BookSource(bookSourceName: "保留", bookSourceUrl: "local://source")])
        let decoded = try AppDataBackupCodec.decode(
            data: data,
            fallbackSources: fallbackSource,
            fallbackPurifyRules: [],
            fallbackRSSState: RSSArticleStateSnapshot(readIDs: ["r"], favoriteIDs: [])
        )
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.bookshelf.books.first?.id, "legacy-book")
        XCTAssertEqual(decoded.sources.sources.first?.bookSourceName, "保留")
        XCTAssertEqual(decoded.rssState.readIDs, ["r"])
    }

    func testBackupCodecRejectsUnsupportedSchema() throws {
        let snapshot = AppDataBackupSnapshot(
            schemaVersion: 99,
            bookshelf: BookshelfBackupSnapshot(books: [], groups: []),
            sources: SourceLibrarySnapshot(sources: []),
            purifyRules: [],
            rssState: RSSArticleStateSnapshot(readIDs: [], favoriteIDs: []),
            readerPreferences: [:]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        XCTAssertThrowsError(try AppDataBackupCodec.decode(
            data: data,
            fallbackSources: SourceLibrarySnapshot(sources: []),
            fallbackPurifyRules: [],
            fallbackRSSState: RSSArticleStateSnapshot(readIDs: [], favoriteIDs: [])
        )) { error in
            XCTAssertEqual(error as? AppDataBackupError, .unsupportedSchema(99))
        }
    }

    @MainActor
    func testBackupRestorerRollsBackWhenPurifyRulesFail() {
        let previous = AppDataBackupSnapshot(
            bookshelf: BookshelfBackupSnapshot(books: [], groups: []),
            sources: SourceLibrarySnapshot(sources: []),
            purifyRules: [PurifyRule(id: "old", pattern: "old")],
            rssState: RSSArticleStateSnapshot(readIDs: ["old"], favoriteIDs: []),
            readerPreferences: ["reader.mode": .string("scroll")]
        )
        let incoming = AppDataBackupSnapshot(
            bookshelf: BookshelfBackupSnapshot(books: [], groups: []),
            sources: SourceLibrarySnapshot(sources: []),
            purifyRules: [PurifyRule(id: "new", pattern: "new")],
            rssState: RSSArticleStateSnapshot(readIDs: ["new"], favoriteIDs: []),
            readerPreferences: ["reader.mode": .string("paged")]
        )
        var bookshelf = previous.bookshelf
        var sources = previous.sources
        var rules = previous.purifyRules
        var rss = previous.rssState
        var preferences = previous.readerPreferences

        XCTAssertThrowsError(try AppDataBackupRestorer.restore(
            incoming,
            previous: previous,
            restoreBookshelf: { bookshelf = $0; return true },
            restoreSources: { sources = $0; return true },
            restorePurifyRules: { snapshot in
                if snapshot == incoming.purifyRules { return false }
                rules = snapshot
                return true
            },
            restoreRSSState: { rss = $0 },
            restorePreferences: { preferences = $0 }
        )) { error in
            XCTAssertEqual(error as? AppDataBackupError, .purifyRulesRestoreFailed)
        }
        XCTAssertEqual(bookshelf, previous.bookshelf)
        XCTAssertEqual(sources, previous.sources)
        XCTAssertEqual(rules, previous.purifyRules)
        XCTAssertEqual(rss, previous.rssState)
        XCTAssertEqual(preferences, previous.readerPreferences)
    }
}
