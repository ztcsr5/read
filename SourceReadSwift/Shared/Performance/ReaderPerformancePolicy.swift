import Foundation

/// Small, deterministic policies used by the reader's rendering hot path.
/// Keeping these decisions pure makes the performance contract testable on CI
/// even though frame pacing itself still needs a ProMotion device.
enum ReaderPerformancePolicy {
    /// The app must never opt a phone back into a 60 Hz floor.
    static let disablesMinimumFrameDuration = true

    /// Cap the requested ceiling to the highest cadence supported by the app.
    /// On non-ProMotion hardware this returns the device's actual ceiling.
    static func preferredRefreshRate(maximumFramesPerSecond: Int) -> Int {
        guard maximumFramesPerSecond > 0 else { return 0 }
        return min(maximumFramesPerSecond, 120)
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
}
