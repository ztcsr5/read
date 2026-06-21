import XCTest
@testable import SourceReadSwift

@MainActor
final class PurifyRuleStoreTests: XCTestCase {
    func testImportsUniqueRulesAndPersistsEnabledState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = PurifyRulePersistence(fileManager: .default, rootURL: root)
        let store = PurifyRuleStore(persistence: persistence)

        store.add("广告.*##")
        let imported = store.importLines("""
        请收藏本站.*##
        广告.*##

        站点尾巴
        """)

        XCTAssertEqual(imported, 2)
        XCTAssertEqual(store.rules.map(\.pattern), ["请收藏本站.*##", "站点尾巴", "广告.*##"])

        let firstID = try XCTUnwrap(store.rules.first?.id)
        store.setEnabled(false, ruleID: firstID)

        let reloaded = PurifyRuleStore(persistence: persistence)
        XCTAssertEqual(reloaded.rules.map(\.pattern), ["请收藏本站.*##", "站点尾巴", "广告.*##"])
        XCTAssertEqual(reloaded.enabledPatterns, ["站点尾巴", "广告.*##"])
        try? FileManager.default.removeItem(at: root)
    }

    func testRemoveRulePersists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = PurifyRulePersistence(fileManager: .default, rootURL: root)
        let store = PurifyRuleStore(persistence: persistence)

        store.importLines("""
        A
        B
        """)
        let removedID = try XCTUnwrap(store.rules.first?.id)
        store.remove(ruleID: removedID)

        let reloaded = PurifyRuleStore(persistence: persistence)
        XCTAssertEqual(reloaded.rules.map(\.pattern), ["B"])
        try? FileManager.default.removeItem(at: root)
    }
}
