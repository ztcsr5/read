import SwiftUI

struct RootTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                BookshelfView()
                    .tag(0)

                DiscoverView()
                    .tag(1)

                SettingsView()
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            customTabBar
        }
    }

    private var customTabBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.secondary.opacity(0.15))

            HStack {
                tabButton(index: 0, title: "主页", systemImage: "house")
                Spacer()
                tabButton(index: 1, title: "发现", systemImage: "square.grid.2x2")
                Spacer()
                tabButton(index: 2, title: "设置", systemImage: "gearshape")
            }
            .padding(.horizontal, 40)
            .padding(.top, 10)
            .padding(.bottom, safeAreaBottomInset > 0 ? safeAreaBottomInset - 4 : 10)
            .background(.ultraThinMaterial)
        }
    }

    private func tabButton(index: Int, title: String, systemImage: String) -> some View {
        Button {
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.82)) {
                selectedTab = index
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == index ? "\(systemImage).fill" : systemImage)
                    .font(.system(size: 22, weight: selectedTab == index ? .bold : .medium))
                    .foregroundStyle(selectedTab == index ? AppTheme.accent : .secondary)
                    .frame(width: 44, height: 26)

                Text(title)
                    .font(.system(size: 11, weight: selectedTab == index ? .bold : .medium))
                    .foregroundStyle(selectedTab == index ? AppTheme.accent : .secondary)
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
    }

    private var safeAreaBottomInset: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return 0
        }
        return window.safeAreaInsets.bottom
    }
}
