import Foundation
import CoreGraphics

/// Small, deterministic policies used by the reader's rendering hot path.
/// Keeping these decisions pure makes the performance contract testable on CI
/// even though frame pacing itself still needs a ProMotion device.
enum ReaderPerformancePolicy {
    /// Used only for the first SwiftUI body pass before the container reports
    /// its size. It is replaced immediately by the measured viewport.
    static let defaultViewportSize = CGSize(width: 390, height: 844)
    struct FrameRatePlan: Equatable {
        let minimum: Float
        let maximum: Float
        let preferred: Float
    }

    struct PageMetrics: Equatable {
        let charsPerLine: Int
        let linesPerPage: Int
        let pageBudget: Int
        let paragraphBreakCost: Int
        let titleCost: Int
    }

    /// The app must never opt a phone back into a 60 Hz floor.
    static let disablesMinimumFrameDuration = true

    /// Cap the requested ceiling to the highest cadence supported by the app.
    /// On non-ProMotion hardware this returns the device's actual ceiling.
    static func preferredRefreshRate(maximumFramesPerSecond: Int) -> Int {
        guard maximumFramesPerSecond > 0 else { return 0 }
        return min(maximumFramesPerSecond, 120)
    }

    /// Returns the adaptive scene range used by UIKit. Static screens may be
    /// throttled by iOS, while interactive reader work can use the device's
    /// native ceiling without an always-running display link.
    static func frameRatePlan(maximumFramesPerSecond: Int) -> FrameRatePlan {
        let ceiling = Float(preferredRefreshRate(maximumFramesPerSecond: maximumFramesPerSecond))
        guard ceiling > 0 else { return FrameRatePlan(minimum: 1, maximum: 0, preferred: 0) }
        return FrameRatePlan(minimum: 1, maximum: ceiling, preferred: ceiling)
    }

    static func viewportCacheKey(_ viewportSize: CGSize) -> String {
        "\(Int(viewportSize.width.rounded()))x\(Int(viewportSize.height.rounded()))"
    }

    static func pageMetrics(
        viewportSize: CGSize,
        pagePadding: Double,
        footerHeight: Double,
        fontSize: Double,
        lineSpacing: Double,
        letterSpacing: Double
    ) -> PageMetrics {
        let availableWidth = max(Double(viewportSize.width) - pagePadding * 2, 260)
        let availableHeight = max(Double(viewportSize.height) - pagePadding * 2 - footerHeight - 70, 360)
        let charWidth = max(fontSize * 0.56 + letterSpacing, 7)
        let lineHeight = max(fontSize + lineSpacing, 18)
        let charsPerLine = max(Int(availableWidth / charWidth), 10)
        let linesPerPage = max(Int(availableHeight / lineHeight), 8)
        let pageBudget = max(charsPerLine * linesPerPage, 220)
        return PageMetrics(
            charsPerLine: charsPerLine,
            linesPerPage: linesPerPage,
            pageBudget: pageBudget,
            paragraphBreakCost: max(charsPerLine / 2, 10),
            titleCost: max(charsPerLine * 3, 90)
        )
    }

    /// Geometry readers are expensive in long chapters. Track every paragraph
    /// only for short chapters and sample progressively for larger documents.
    static func paragraphTrackingStride(paragraphCount: Int) -> Int {
        switch paragraphCount {
        case 0...180: return 1
        case 181...600: return 3
        case 601...1_500: return 5
        default: return 8
        }
    }

    /// Position writes serialize the whole bookshelf. A single debounce value
    /// is shared by scroll, paging and speech callbacks to keep disk I/O off
    /// the display frame path.
    static let positionPersistenceDebounceNanoseconds: UInt64 = 700_000_000

    /// Visible-paragraph state is only used for resume/highlight bookkeeping;
    /// it does not need to follow every display-link tick. Throttling this
    /// update keeps PreferenceKey propagation off the 120 Hz rendering path.
    static let visibleParagraphUpdateInterval: TimeInterval = 0.08
}
