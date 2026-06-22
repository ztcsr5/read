import SwiftUI

@main
struct SourceReadSwiftApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appState)
                .preferredColorScheme((ThemeMode(rawValue: themeModeRawValue) ?? .system).colorScheme)
        }
    }
}
