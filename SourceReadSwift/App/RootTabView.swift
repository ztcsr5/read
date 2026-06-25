import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0
    @GestureState private var tabDragTranslation: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                BookshelfView()
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .offset(x: pageOffset(for: 0))
                    .allowsHitTesting(selectedTab == 0)

                DiscoverView()
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .offset(x: pageOffset(for: 1))
                    .allowsHitTesting(selectedTab == 1)

                SettingsView()
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .offset(x: pageOffset(for: 2))
                    .allowsHitTesting(selectedTab == 2)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(tabSwipeGesture)

            if !appState.isTabChromeHidden {
                customTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: appState.isTabChromeHidden)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.9), value: selectedTab)
        .onChange(of: selectedTab) { _ in
            dismissKeyboard()
        }
    }

    private var tabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .updating($tabDragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.25 else { return }
                state = value.translation.width
            }
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) * 1.25,
                      abs(horizontal) > 70 else { return }
                if horizontal < 0 {
                    selectedTab = min(selectedTab + 1, 2)
                } else {
                    selectedTab = max(selectedTab - 1, 0)
                }
            }
    }

    private func pageOffset(for index: Int) -> CGFloat {
        guard index == selectedTab else { return 0 }
        let width = UIScreen.main.bounds.width
        let clamped = min(max(tabDragTranslation, -width * 0.22), width * 0.22)
        return clamped * 0.18
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
            guard selectedTab != index else { return }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            selectedTab = index
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
