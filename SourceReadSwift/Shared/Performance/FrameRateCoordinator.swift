import SwiftUI
import QuartzCore
import UIKit

/// Coordinates high-refresh capability for active iOS windows.
/// `CADisableMinimumFrameDurationOnPhone` lets SwiftUI/UIKit use ProMotion.
/// This type requests the active native ceiling through the SDK-supported
/// display-link API without forcing unsupported rates on 60 Hz hardware.
enum FrameRateCoordinator {
    /// Keep one lightweight display-link request per active scene.  UIKit does
    /// not expose a scene/window frame-rate setter on the iOS 16 SDK; the
    /// supported native API is `CADisplayLink.preferredFrameRateRange`.
    private static var drivers: [String: HighRefreshDisplayLinkDriver] = [:]

    /// Returns the scene range used for interactive surfaces.  ProMotion
    /// devices get a 120 Hz ceiling and a high enough floor to avoid the
    /// visible 60 Hz step while a reader is being dragged; 60 Hz devices keep
    /// their native cadence instead of receiving an unsupported request.
    static func preferredRange(maximumFramesPerSecond: Int) -> CAFrameRateRange? {
        let ceiling = ReaderPerformancePolicy.preferredRefreshRate(
            maximumFramesPerSecond: maximumFramesPerSecond
        )
        guard ceiling > 0 else { return nil }
        let value = Float(ceiling)
        let minimum = ceiling >= 120 ? 80 : value
        return CAFrameRateRange(minimum: minimum, maximum: value, preferred: value)
    }

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
        if #available(iOS 15.0, *), maximum >= 80,
           let range = preferredRange(maximumFramesPerSecond: maximum) {
            let sceneID = windowScene.session.persistentIdentifier
            let driver = drivers[sceneID] ?? HighRefreshDisplayLinkDriver()
            driver.start(range: range)
            drivers[sceneID] = driver
        }
        // The Info.plist switch removes the app-imposed 60 Hz floor. The
        // display-link driver above only requests pacing; iOS still adapts to
        // the active display, interaction, thermal and power state.
        PerformanceSignpost.event(
            "frame.rate",
            "scene=\(windowScene.session.persistentIdentifier) max=\(maximum) preferred=\(preferred)"
        )
    }
}

/// A no-op display-link request keeps interactive SwiftUI/UIKit surfaces on
/// the device-native ProMotion cadence.  iOS still adapts down for thermal,
/// power, and idle states, while 60 Hz hardware never receives the request.
private final class HighRefreshDisplayLinkDriver: NSObject {
    private var displayLink: CADisplayLink?

    func start(range: CAFrameRateRange) {
        if let displayLink {
            displayLink.preferredFrameRateRange = range
            displayLink.isPaused = false
            return
        }

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = range
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {}

    deinit {
        displayLink?.invalidate()
    }
}

/// A zero-sized UIKit anchor that reapplies the scene range when SwiftUI moves
/// a surface between windows (Stage Manager, split view, scene reconnect).  It
/// has no timer and does not participate in layout or hit-testing.
struct FrameRateSceneAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> AnchorView { AnchorView() }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        uiView.applyIfNeeded()
    }

    final class AnchorView: UIView {
        private var appliedWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyIfNeeded()
        }

        func applyIfNeeded() {
            guard let window,
                  window !== appliedWindow else { return }
            appliedWindow = window
            FrameRateCoordinator.apply(to: window.windowScene)
        }
    }
}

extension View {
    /// Installs the scene-level high-refresh anchor without changing layout.
    func highRefreshRateSurface() -> some View {
        background {
            FrameRateSceneAnchor()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
