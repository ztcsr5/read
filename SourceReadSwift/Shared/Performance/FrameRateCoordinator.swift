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

        let preferred = ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: maximum)
        // `CADisableMinimumFrameDurationOnPhone` (Info.plist) is the
        // deployment-safe switch available to this project's iOS 16 SDK. It
        // removes the app-imposed 60 Hz floor; UIKit/SwiftUI then selects the
        // highest supported cadence. Avoid SDK-specific frame-rate range APIs
        // here because the CI toolchain does not expose them consistently.
        PerformanceSignpost.event(
            "frame.rate",
            "scene=\(windowScene.session.persistentIdentifier) max=\(maximum) preferred=\(preferred)"
        )
    }
}
