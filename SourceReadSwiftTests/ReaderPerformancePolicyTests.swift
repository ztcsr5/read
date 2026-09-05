import XCTest
import Foundation
import CoreGraphics
import QuartzCore
@testable import SourceReadSwift

final class ReaderPerformancePolicyTests: XCTestCase {
    func testRefreshRateNeverExceedsDeviceOr120HzCeiling() {
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 60), 60)
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 120), 120)
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 144), 120)
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 0), 0)
        XCTAssertTrue(ReaderPerformancePolicy.disablesMinimumFrameDuration)
    }

    func testPreferredFrameRateRangeTargetsHighRefreshOnlyWhenSupported() {
        let proMotion = FrameRateCoordinator.preferredRange(maximumFramesPerSecond: 120)
        XCTAssertEqual(proMotion?.minimum, 80)
        XCTAssertEqual(proMotion?.maximum, 120)
        XCTAssertEqual(proMotion?.preferred, 120)

        let standard = FrameRateCoordinator.preferredRange(maximumFramesPerSecond: 60)
        XCTAssertEqual(standard?.minimum, 60)
        XCTAssertEqual(standard?.maximum, 60)
        XCTAssertEqual(standard?.preferred, 60)

        XCTAssertNil(FrameRateCoordinator.preferredRange(maximumFramesPerSecond: 0))
    }

    func testAdaptiveFrameRatePlanUsesOneHzFloorAndDeviceCeiling() {
        XCTAssertEqual(
            ReaderPerformancePolicy.frameRatePlan(maximumFramesPerSecond: 120),
            .init(minimum: 1, maximum: 120, preferred: 120)
        )
        XCTAssertEqual(
            ReaderPerformancePolicy.frameRatePlan(maximumFramesPerSecond: 60),
            .init(minimum: 1, maximum: 60, preferred: 60)
        )
        XCTAssertEqual(
            ReaderPerformancePolicy.frameRatePlan(maximumFramesPerSecond: 0),
            .init(minimum: 1, maximum: 0, preferred: 0)
        )
    }

    func testViewportCacheKeyAndPageMetricsAreDeterministic() {
        XCTAssertEqual(ReaderPerformancePolicy.viewportCacheKey(.init(width: 390.4, height: 844.6)), "390x845")
        let compact = ReaderPerformancePolicy.pageMetrics(
            viewportSize: .init(width: 390, height: 844),
            pagePadding: 24,
            footerHeight: 72,
            fontSize: 19,
            lineSpacing: 8,
            letterSpacing: 0
        )
        let wider = ReaderPerformancePolicy.pageMetrics(
            viewportSize: .init(width: 844, height: 390),
            pagePadding: 24,
            footerHeight: 72,
            fontSize: 19,
            lineSpacing: 8,
            letterSpacing: 0
        )
        XCTAssertGreaterThan(compact.pageBudget, 0)
        XCTAssertGreaterThan(wider.charsPerLine, compact.charsPerLine)
        XCTAssertGreaterThanOrEqual(compact.linesPerPage, 8)
    }

    func testVisibleParagraphResolverUsesRangeIntersection() {
        let ranges = [
            NSRange(location: 0, length: 10),
            NSRange(location: 12, length: 8),
            NSRange(location: 22, length: 7)
        ]
        XCTAssertEqual(
            ReaderParagraphIndexResolver.firstVisibleIndex(in: ranges, visibleRange: NSRange(location: 14, length: 2)),
            1
        )
        XCTAssertEqual(
            ReaderParagraphIndexResolver.firstVisibleIndex(in: ranges, visibleRange: NSRange(location: 10, length: 2)),
            1
        )
        XCTAssertNil(ReaderParagraphIndexResolver.firstVisibleIndex(in: ranges, visibleRange: NSRange(location: 0, length: 0)))
        XCTAssertNil(ReaderParagraphIndexResolver.firstVisibleIndex(in: [], visibleRange: NSRange(location: 0, length: 3)))
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

    func testVisibleParagraphUpdatesAreThrottledBelowDisplayCadence() {
        XCTAssertGreaterThanOrEqual(ReaderPerformancePolicy.visibleParagraphUpdateInterval, 0.05)
        XCTAssertLessThan(ReaderPerformancePolicy.visibleParagraphUpdateInterval, 0.2)
    }
}
