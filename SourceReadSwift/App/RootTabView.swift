import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0
    @State private var presentedBook: BookshelfBook?
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
        .sheet(item: $presentedBook) { book in
            NavigationStack {
                BookshelfReaderGatewayView(book: book)
            }
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
            if let currentBook = appState.bookshelfStore.recentBooks.first {
                Button {
                    presentedBook = currentBook
                } label: {
                    HStack(spacing: 12) {
                        miniCover(currentBook)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentBook.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(currentBook.currentChapterTitle ?? "继续阅读")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("继续阅读 \(currentBook.title)")
            }

            Divider()
                .background(Color.secondary.opacity(0.12))

            HStack {
                tabButton(index: 0, title: "主页", systemImage: "house")
                Spacer()
                tabButton(index: 1, title: "发现", systemImage: "square.grid.2x2")
                Spacer()
                tabButton(index: 2, title: "设置", systemImage: "gearshape")
            }
            .padding(.horizontal, 40)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
        .background(.ultraThinMaterial)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func miniCover(_ book: BookshelfBook) -> some View {
        Group {
            if let coverURL = book.coverURL, let url = URL(string: coverURL) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        miniCoverPlaceholder
                    }
                }
            } else {
                miniCoverPlaceholder
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var miniCoverPlaceholder: some View {
        ZStack {
            AppTheme.accent.opacity(0.14)
            Image(systemName: "book.closed.fill")
                .foregroundStyle(AppTheme.accent)
        }
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
                    .frame(width: 44, height: 26)

                Text(title)
                    .font(.system(size: 11, weight: selectedTab == index ? .bold : .medium))
                    .foregroundStyle(selectedTab == index ? AppTheme.accent : .secondary)
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
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
