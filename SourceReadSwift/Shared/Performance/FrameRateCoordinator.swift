import SwiftUI
import QuartzCore
import UIKit

/// Coordinates high-refresh capability for active iOS windows.
/// `CADisableMinimumFrameDurationOnPhone` lets SwiftUI/UIKit use ProMotion.
/// This type records the active native ceiling without forcing unsupported
/// rates on 60 Hz hardware. iOS performs the final adaptive cadence choice.
enum FrameRateCoordinator {
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
        guard let range = preferredRange(maximumFramesPerSecond: maximum) else { return }
        // UIView.preferredFrameRateRange is the iOS 15+ API that actually
        // requests a cadence. The zero-sized anchor applies it to its native
        // surface; the scene hook below remains responsible for reapplying the
        // request when a window reconnects or moves between scenes.
        PerformanceSignpost.event(
            "frame.rate",
            "scene=\(windowScene.session.persistentIdentifier) max=\(maximum) preferred=\(preferred) min=\(range.minimum)"
        )
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
            if let range = FrameRateCoordinator.preferredRange(
                maximumFramesPerSecond: window.screen.maximumFramesPerSecond
            ) {
                preferredFrameRateRange = range
            }
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
