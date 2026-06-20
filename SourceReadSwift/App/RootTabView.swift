import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            BookshelfView()
                .tabItem {
                    Label("主页", systemImage: "house")
                }

            DiscoverView()
                .tabItem {
                    Label("发现", systemImage: "square.grid.2x2")
                }

            SourceManagerView()
                .tabItem {
                    Label("书源", systemImage: "tray.full")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .tint(AppTheme.accent)
    }
}
