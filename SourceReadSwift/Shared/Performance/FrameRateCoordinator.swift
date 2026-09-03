import UIKit
import QuartzCore

/// Coordinates high-refresh capability for active iOS windows.
/// `CADisableMinimumFrameDurationOnPhone` lets SwiftUI use ProMotion. This type
/// requests the active native ceiling through the window layer, and records it
/// without forcing unsupported rates on 60 Hz hardware.
enum FrameRateCoordinator {
    private static var drivers: [String: HighRefreshDisplayLinkDriver] = [:]

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
        if maximum >= 80 {
            let ceiling = Float(min(maximum, 120))
            let sceneID = windowScene.session.persistentIdentifier
            let driver = drivers[sceneID] ?? HighRefreshDisplayLinkDriver()
            driver.start(maximumFramesPerSecond: ceiling)
            drivers[sceneID] = driver
        }
        PerformanceSignpost.event(
            "frame.rate",
            "scene=\(windowScene.session.persistentIdentifier) max=\(maximum) preferred=\(preferred)"
        )
    }
}

/// A lightweight display-link request keeps UIKit's active render cadence at
/// the native ProMotion ceiling. iOS still throttles static screens and
/// unsupported devices, while scrolling/interactive animations can reach
/// 80-120 Hz instead of being pinned to 60 Hz.
private final class HighRefreshDisplayLinkDriver: NSObject {
    private var displayLink: CADisplayLink?

    func start(maximumFramesPerSecond: Float) {
        if let displayLink {
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                // Keep the link adaptive. A hard 80 Hz minimum makes the
                // otherwise idle app render continuously on devices that
                // support ProMotion, wasting power and competing with the
                // reader's own layout work. The maximum/preferred values are
                // still allowed to reach the native 120 Hz ceiling.
                minimum: 1,
                maximum: maximumFramesPerSecond,
                preferred: maximumFramesPerSecond
            )
            return
        }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 1,
            maximum: maximumFramesPerSecond,
            preferred: maximumFramesPerSecond
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {}

    deinit {
        displayLink?.invalidate()
    }
}
