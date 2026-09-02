import QuartzCore
import UIKit

/// Coordinates the frame-rate budget for active iOS windows.
/// `CADisableMinimumFrameDurationOnPhone` is declared in Info.plist. The layer
/// range requests the device-native ceiling while leaving room for iOS to
/// adapt under thermal, power, or idle conditions.
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
        // `CADisableMinimumFrameDurationOnPhone` enables ProMotion on iPhone.
        // CALayer is the SDK-stable point for expressing the preferred range;
        // SwiftUI then schedules work against the active window's layer.
        let range = CAFrameRateRange(
            minimum: maximum >= 120 ? 80 : maximum,
            maximum: preferred,
            preferred: preferred
        )
        for window in windowScene.windows {
            window.layer.preferredFrameRateRange = range
        }
        PerformanceSignpost.event(
            "frame.rate",
            "scene=\(windowScene.session.persistentIdentifier) max=\(maximum) preferred=\(preferred)"
        )
    }
}
