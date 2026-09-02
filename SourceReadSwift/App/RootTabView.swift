import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Only keep the active root alive.  The previous opacity-based
            // stack rendered three complete navigation trees every frame,
            // which was especially visible on long bookshelf lists.
            Group {
                switch selectedTab {
                case 0:
                    BookshelfView()
                        .transition(.opacity)
                case 1:
                    DiscoverView()
                        .transition(.opacity)
                default:
                    SettingsView()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.keyboard, edges: .bottom)

            if !appState.isTabChromeHidden {
                customTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: appState.isTabChromeHidden)
        .animation(.easeOut(duration: 0.16), value: selectedTab)
        .onChange(of: selectedTab) { _ in
            dismissKeyboard()
        }
    }

    private var customTabBar: some View {
        VStack(spacing: 0) {
            HStack {
                tabButton(index: 0, title: "主页", systemImage: "house")
                Spacer()
                tabButton(index: 1, title: "发现", systemImage: "square.grid.2x2")
                Spacer()
                tabButton(index: 2, title: "设置", systemImage: "gearshape")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 9)
            .glassPanel(cornerRadius: 28, material: .ultraThinMaterial, strokeOpacity: 0.08, shadowOpacity: 0.16)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func tabButton(index: Int, title: String, systemImage: String) -> some View {
        Button {
            switchToTab(index)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == index ? "\(systemImage).fill" : systemImage)
                    .font(.system(size: 22, weight: selectedTab == index ? .bold : .medium))
                    .foregroundStyle(selectedTab == index ? AppTheme.accent : .secondary)
                    .frame(width: 46, height: 28)
                    .background {
                        if selectedTab == index {
                            Capsule()
                                .fill(AppTheme.accent.opacity(0.14))
                        }
                    }

                Text(title)
                    .font(.system(size: 11, weight: selectedTab == index ? .bold : .medium))
                    .foregroundStyle(selectedTab == index ? AppTheme.accent : .secondary)
            }
            .frame(width: 64, height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(RootTabPressableButtonStyle())
    }

    private func switchToTab(_ index: Int) {
        guard selectedTab != index else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedTab = index
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct RootTabPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.105), value: configuration.isPressed)
    }
}
