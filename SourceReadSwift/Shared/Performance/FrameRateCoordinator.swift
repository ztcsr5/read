import UIKit

/// Coordinates high-refresh capability for active iOS windows.
/// `CADisableMinimumFrameDurationOnPhone` lets SwiftUI/UIKit use ProMotion.
/// This type records the active native ceiling without installing a persistent
/// display-link callback or forcing unsupported rates on 60 Hz hardware.
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
        // Do not keep an empty CADisplayLink alive merely to advertise a
        // ceiling. It schedules main-run-loop work even when no pixels change
        // and can compete with TextKit during real scrolling. The Info.plist
        // switch removes the app-imposed 60 Hz floor; UIKit then adapts to the
        // active display, interaction and power state.
        PerformanceSignpost.event(
            "frame.rate",
            "scene=\(windowScene.session.persistentIdentifier) max=\(maximum) preferred=\(preferred)"
        )
    }
}
