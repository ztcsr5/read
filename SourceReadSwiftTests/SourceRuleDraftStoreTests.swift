import Foundation
import XCTest
@testable import SourceReadSwift

final class SourceRuleDraftStoreTests: XCTestCase {
    private func makeDraft(
        sourceURL: String = "https://draft.example/source",
        schemaVersion: Int = SourceRuleDraft.currentSchemaVersion,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> SourceRuleDraft {
        SourceRuleDraft(
            sourceURL: sourceURL,
            sourceName: "草稿源",
            searchURL: "https://draft.example/search?q={{key}}",
            searchRule: #"{"bookList":".book","name":"h2@text"}"#,
            detailRule: #"{"name":"h1@text"}"#,
            tocRule: #"{"chapterList":".chapter","chapterName":"a@text"}"#,
            contentRule: "#content@text",
            updatedAt: date,
            schemaVersion: schemaVersion
        )
    }

    func testDraftJSONRoundTripPreservesSchemaAndFields() throws {
        let draft = makeDraft()
        let decoded = try SourceRuleDraft.decode(try draft.jsonData())

        XCTAssertEqual(decoded, draft)
        XCTAssertEqual(decoded.schemaVersion, SourceRuleDraft.currentSchemaVersion)
        XCTAssertEqual(decoded.sourceURL, "https://draft.example/source")
        XCTAssertEqual(decoded.contentRule, "#content@text")
    }

    func testDraftRejectsUnsupportedSchema() throws {
        let data = try makeDraft(schemaVersion: SourceRuleDraft.currentSchemaVersion + 1).jsonData()

        XCTAssertThrowsError(try SourceRuleDraft.decode(data)) { error in
            XCTAssertEqual(
                error as? SourceRuleDraftError,
                .unsupportedSchema(SourceRuleDraft.currentSchemaVersion + 1)
            )
        }
    }

    func testStoreSaveLoadRemoveAndSourceIsolation() throws {
        let suiteName = "SourceReadSwiftTests.ruleDraft.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SourceRuleDraftStore(defaults: defaults)
        let first = makeDraft(sourceURL: "https://draft.example/one")
        let second = makeDraft(sourceURL: "https://draft.example/two")

        try store.save(first)
        try store.save(second)

        XCTAssertEqual(store.load(sourceURL: first.sourceURL), first)
        XCTAssertEqual(store.load(sourceURL: second.sourceURL), second)
        XCTAssertNil(store.load(sourceURL: "https://draft.example/unknown"))

        store.remove(sourceURL: first.sourceURL)
        XCTAssertNil(store.load(sourceURL: first.sourceURL))
        XCTAssertEqual(store.load(sourceURL: second.sourceURL), second)
    }

    func testStorePersistsAcrossStoreInstances() throws {
        let suiteName = "SourceReadSwiftTests.ruleDraft.persist.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let draft = makeDraft()

        try SourceRuleDraftStore(defaults: defaults).save(draft)
        let reloaded = SourceRuleDraftStore(defaults: defaults).load(sourceURL: draft.sourceURL)

        XCTAssertEqual(reloaded, draft)
    }

    func testFileDocumentWrapsDraftForPortableExport() {
        let draft = makeDraft()
        let document = SourceRuleDraftDocument(draft: draft)

        XCTAssertEqual(document.draft, draft)
    }
}
