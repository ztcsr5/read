import SwiftUI

@main
struct SourceReadSwiftApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appState)
                .highRefreshRateSurface()
                .preferredColorScheme((ThemeMode(rawValue: themeModeRawValue) ?? .system).colorScheme)
                .onOpenURL { url in
                    appState.importSharedDocument(url)
                }
                .onAppear {
                    FrameRateCoordinator.apply()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { notification in
                    FrameRateCoordinator.apply(to: notification.object as? UIScene)
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    FrameRateCoordinator.apply()
                }
        }
    }
}
