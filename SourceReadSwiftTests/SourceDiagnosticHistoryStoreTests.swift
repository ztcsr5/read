import XCTest
@testable import SourceReadSwift

@MainActor
final class SourceDiagnosticHistoryStoreTests: XCTestCase {
    func testPersistsNewestFirstAndTrimsPerSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = SourceDiagnosticHistoryPersistence(rootURL: root)
        let source = BookSource(bookSourceName: "fixture", bookSourceUrl: "https://fixture.test")
        let store = SourceDiagnosticHistoryStore(persistence: persistence, limit: 2)
        store.record(source: source, stage: "search", status: .passed, message: "one")
        store.record(source: source, stage: "detail", status: .warning, message: "two")
        store.record(source: source, stage: "toc", status: .failed, message: "three")

        XCTAssertEqual(store.records(for: source).count, 2)
        XCTAssertEqual(store.records(for: source).map(\.stage), ["toc", "detail"])
        let reloaded = SourceDiagnosticHistoryStore(persistence: persistence, limit: 2)
        XCTAssertEqual(reloaded.records(for: source).map(\.status), [.failed, .warning])
    }

    func testExportContainsStatusAndStage() {
        let source = BookSource(bookSourceName: "fixture", bookSourceUrl: "https://fixture.test")
        let store = SourceDiagnosticHistoryStore(persistence: SourceDiagnosticHistoryPersistence(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        store.record(source: source, stage: "content", status: .requiresLogin, message: "需要登录", elapsedMilliseconds: 42)
        let text = store.exportText(for: source)
        XCTAssertTrue(text.contains("requiresLogin"))
        XCTAssertTrue(text.contains("content"))
        XCTAssertTrue(text.contains("42 ms"))
    }
}
