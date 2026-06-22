import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0
    @State private var presentedBook: BookshelfBook?

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
            .toolbar(.hidden, for: .tabBar)

            if !appState.isTabChromeHidden {
                customTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: appState.isTabChromeHidden)
        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.88), value: selectedTab)
        .onChange(of: selectedTab) { _ in
            dismissKeyboard()
        }
        .sheet(item: $presentedBook) { book in
            NavigationStack {
                BookshelfReaderGatewayView(book: book)
            }
        }
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
