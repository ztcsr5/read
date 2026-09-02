import QuartzCore
import UIKit

/// Requests the highest refresh rate supported by each active iOS window.
/// ProMotion devices may reach 120 Hz; fixed-refresh devices keep their native ceiling.
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

        let preferred = Float(min(maximum, 120))
        let minimum = Float(maximum >= 120 ? 80 : maximum)
        windowScene.preferredFrameRateRange = CAFrameRateRange(
            minimum: minimum,
            maximum: preferred,
            preferred: preferred
        )
    }
}
