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

    func testImportsPresetPatternsAndBulkToggles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = PurifyRulePersistence(fileManager: .default, rootURL: root)
        let store = PurifyRuleStore(persistence: persistence)
        let preset = PurifyRulePreset.builtIn[0]

        store.add(preset.patterns[0])
        let imported = store.importPatterns(preset.patterns)

        XCTAssertEqual(imported, preset.patterns.count - 1)
        XCTAssertTrue(store.containsPattern(preset.patterns[0]))
        XCTAssertEqual(store.enabledPatterns.count, preset.patterns.count)

        store.setAllEnabled(false)
        XCTAssertTrue(store.enabledPatterns.isEmpty)

        let reloaded = PurifyRuleStore(persistence: persistence)
        XCTAssertTrue(reloaded.enabledPatterns.isEmpty)

        reloaded.setAllEnabled(true)
        XCTAssertEqual(reloaded.enabledPatterns.count, preset.patterns.count)
        try? FileManager.default.removeItem(at: root)
    }

    func testPreviewUsesEnabledRulesAndIgnoresInvalidRegex() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = PurifyRulePersistence(fileManager: .default, rootURL: root)
        let store = PurifyRuleStore(persistence: persistence)

        store.importPatterns([
            "广告.*##",
            "[",
            "保留##替换"
        ])

        XCTAssertEqual(store.preview(text: "正文\n广告内容\n保留"), "正文\n\n替换")
        try? FileManager.default.removeItem(at: root)
    }
}
