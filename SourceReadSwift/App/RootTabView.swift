import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                tabContent(index: 0) {
                    BookshelfView()
                }

                tabContent(index: 1) {
                    DiscoverView()
                }

                tabContent(index: 2) {
                    SettingsView()
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .contentShape(Rectangle())
            .simultaneousGesture(rootTabSwipeGesture)

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

    private func tabContent<Content: View>(index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selectedTab == index ? 1 : 0)
            .allowsHitTesting(selectedTab == index)
            .accessibilityHidden(selectedTab != index)
    }

    private var rootTabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 44, coordinateSpace: .local)
            .onEnded { value in
                guard !appState.isTabChromeHidden else { return }
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > 72, abs(horizontal) > vertical * 1.35 else { return }
                if horizontal < 0 {
                    switchToTab(min(selectedTab + 1, 2))
                } else {
                    switchToTab(max(selectedTab - 1, 0))
                }
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 10)
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
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
