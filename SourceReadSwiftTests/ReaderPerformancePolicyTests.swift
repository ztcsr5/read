import XCTest
@testable import SourceReadSwift

final class ReaderPerformancePolicyTests: XCTestCase {
    func testRefreshRateNeverExceedsDeviceOr120HzCeiling() {
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 60), 60)
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 120), 120)
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 144), 120)
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 0), 0)
        XCTAssertTrue(ReaderPerformancePolicy.disablesMinimumFrameDuration)
    }

    func testParagraphTrackingScalesForLongChapters() {
        XCTAssertEqual(ReaderPerformancePolicy.paragraphTrackingStride(paragraphCount: 180), 1)
        XCTAssertEqual(ReaderPerformancePolicy.paragraphTrackingStride(paragraphCount: 181), 3)
        XCTAssertEqual(ReaderPerformancePolicy.paragraphTrackingStride(paragraphCount: 600), 3)
        XCTAssertEqual(ReaderPerformancePolicy.paragraphTrackingStride(paragraphCount: 601), 5)
        XCTAssertEqual(ReaderPerformancePolicy.paragraphTrackingStride(paragraphCount: 1_501), 8)
    }

    func testPersistenceDebounceIsLongerThanOneFrame() {
        XCTAssertGreaterThan(ReaderPerformancePolicy.positionPersistenceDebounceNanoseconds, 16_000_000)
    }
}
