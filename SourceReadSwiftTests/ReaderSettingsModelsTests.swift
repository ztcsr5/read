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
        XCTAssertEqual(ReaderTapAction.decode(rawValue: raw), actions)
    }

    func testTapZoneDecodeFallsBackWhenMenuIsMissing() {
        let raw = Array(repeating: ReaderTapAction.nextPage.rawValue, count: 9).joined(separator: ",")
        XCTAssertEqual(ReaderTapAction.decode(rawValue: raw), ReaderTapAction.defaultActions)
    }

    func testTapZoneDecodeFallsBackWhenCountIsInvalid() {
        XCTAssertEqual(ReaderTapAction.decode(rawValue: "nextPage,menu"), ReaderTapAction.defaultActions)
    }

    func testPreloadPolicyClampsCount() {
        XCTAssertEqual(ReaderPreloadPolicy.clamp(-1), 0)
        XCTAssertEqual(ReaderPreloadPolicy.clamp(3), 3)
        XCTAssertEqual(ReaderPreloadPolicy.clamp(99), 5)
    }

    func testPreloadPolicyTitle() {
        XCTAssertEqual(ReaderPreloadPolicy.title(for: 0), "关闭")
        XCTAssertEqual(ReaderPreloadPolicy.title(for: 3), "3 章")
        XCTAssertEqual(ReaderPreloadPolicy.title(for: 99), "5 章")
    }

    func testReaderValueNormalizerClampsAndAcceptsDecimalComma() {
        XCTAssertEqual(
            ReaderValueNormalizer.clampedValue(from: " 1,25 ", range: 0.25...30),
            1.25
        )
        XCTAssertEqual(
            ReaderValueNormalizer.clampedValue(from: "99", range: 14...32),
            32
        )
        XCTAssertEqual(
            ReaderValueNormalizer.clampedValue(from: "-4", range: 14...32),
            14
        )
    }

    func testReaderValueNormalizerRejectsIncompleteOrNonFiniteInput() {
        XCTAssertNil(ReaderValueNormalizer.clampedValue(from: "", range: 0...1))
        XCTAssertNil(ReaderValueNormalizer.clampedValue(from: "1.", range: 0...1))
        XCTAssertNil(ReaderValueNormalizer.clampedValue(from: "nan", range: 0...1))
        XCTAssertNil(ReaderValueNormalizer.clampedValue(from: "infinity", range: 0...1))
    }

    func testReaderValueNormalizerFormatsSliderValues() {
        XCTAssertEqual(ReaderValueNormalizer.formatted(0.5, step: 0.01), "0.5")
        XCTAssertEqual(ReaderValueNormalizer.formatted(19, step: 1), "19")
        XCTAssertEqual(ReaderValueNormalizer.formatted(.nan, step: 1), "0")
    }
}
