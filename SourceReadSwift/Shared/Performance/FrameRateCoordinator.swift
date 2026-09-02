import QuartzCore
import UIKit

/// Coordinates high-refresh capability for active iOS windows.
/// `CADisableMinimumFrameDurationOnPhone` lets SwiftUI use ProMotion. This type
/// requests the active native ceiling through the window layer, and records it
/// without forcing unsupported rates on 60 Hz hardware.
enum FrameRateCoordinator {
    static func apply(to scene: UIScene? = nil) {
        let scenes: [UIWindowScene]
        if let windowScene = scene as? UIWindowScene {
            scenes = [windowScene]
        } else {
            scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState != .unattached }
        }
        scenes.forEach { apply(to: $0) }
    }

    static func apply(to windowScene: UIWindowScene) {
        let maximum = windowScene.screen.maximumFramesPerSecond
        guard maximum > 0 else { return }

        let preferred = min(maximum, 120)
        // The Info.plist flag removes the iPhone 60 Hz floor.  The layer range
        // is the SDK-stable way to ask UIKit/SwiftUI for the highest available
        // cadence while still allowing the system to adapt for thermal and
        // power conditions.
        if #available(iOS 15.0, *) {
            let range = CAFrameRateRange(
                minimum: Float(maximum >= 120 ? 80 : maximum),
                maximum: Float(preferred),
                preferred: Float(preferred)
            )
            for window in windowScene.windows {
                window.layer.preferredFrameRateRange = range
            }
        }
        PerformanceSignpost.event(
            "frame.rate",
            "scene=\(windowScene.session.persistentIdentifier) max=\(maximum) preferred=\(preferred)"
        )
    }
}
