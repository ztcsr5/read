import QuartzCore
import UIKit

/// Coordinates the frame-rate budget for active iOS windows.
/// `CADisableMinimumFrameDurationOnPhone` is declared in Info.plist and this
/// scene-level range keeps ProMotion devices on the native 120 Hz path while
/// remaining valid on 60 Hz hardware. UIKit may still adapt down when the
/// scene is idle or thermally constrained.
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

        let minimum = min(maximum, 60)
        let preferred = min(maximum, 120)
        if #available(iOS 15.0, *) {
            windowScene.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(minimum),
                maximum: Float(preferred),
                preferred: Float(preferred)
            )
        }
        PerformanceSignpost.event(
            "frame.rate",
            "scene=\(windowScene.session.persistentIdentifier) max=\(maximum) min=\(minimum) preferred=\(preferred)"
        )
    }
}
