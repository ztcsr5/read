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
                .preferredColorScheme((ThemeMode(rawValue: themeModeRawValue) ?? .system).colorScheme)
                .onOpenURL { url in
                    appState.importSharedDocument(url)
                }
                .onAppear {
                    FrameRateCoordinator.apply()
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    FrameRateCoordinator.apply()
                }
        }
    }
}
