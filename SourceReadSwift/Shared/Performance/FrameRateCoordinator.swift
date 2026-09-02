import UIKit

/// Coordinates high-refresh capability for active iOS windows.
/// `CADisableMinimumFrameDurationOnPhone` lets SwiftUI use ProMotion; this type
/// detects and records the native ceiling without forcing unsupported rates.
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
        // `CADisableMinimumFrameDurationOnPhone` in Info.plist enables ProMotion
        // for SwiftUI. SwiftUI/UIKit choose the actual pacing from this device
        // ceiling; we record it for diagnostics without driving a wasteful dummy
        // display link on the main thread.
        PerformanceSignpost.event(
            "frame.rate",
            "scene=\(windowScene.session.persistentIdentifier) max=\(maximum) preferred=\(preferred)"
        )
    }
}
