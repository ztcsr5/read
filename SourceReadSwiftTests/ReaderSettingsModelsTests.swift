import XCTest
@testable import SourceReadSwift

final class ReaderSettingsModelsTests: XCTestCase {
    func testTapZoneEncodingRoundTrip() {
        let actions: [ReaderTapAction] = [
            .previousChapter, .previousPage, .nextPage,
            .disabled, .menu, .nextPage,
            .previousPage, .nextChapter, .disabled
        ]

        let raw = ReaderTapAction.encode(actions)
        let decoded = ReaderTapAction.decode(rawValue: raw)

        XCTAssertEqual(decoded, actions)
    }

    func testTapZoneDecodeFallsBackWhenMenuIsMissing() {
        let raw = Array(repeating: ReaderTapAction.nextPage.rawValue, count: 9)
            .joined(separator: ",")

        XCTAssertEqual(ReaderTapAction.decode(rawValue: raw), ReaderTapAction.defaultActions)
    }

    func testTapZoneDecodeFallsBackWhenCountIsInvalid() {
        XCTAssertEqual(ReaderTapAction.decode(rawValue: "nextPage,menu"), ReaderTapAction.defaultActions)
    }
}
