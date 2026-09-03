import SwiftSoup
import SwiftUI

struct RSSArticleReaderView: View {
    @EnvironmentObject private var appState: AppState
    let initialArticle: RSSArticlePreview
    let articles: [RSSArticlePreview]
    @State private var selectedIndex: Int
    @State private var paragraphs: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCachedContent = false
    @State private var visibleParagraphIndex = 0
    @State private var autoScrollEnabled = false
    @State private var autoScrollTarget = 0
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var reloadToken = UUID()
    @State private var lastVisibleParagraphUpdateAt = Date.distantPast
    @StateObject private var speechController = ReaderSpeechController()
    @AppStorage("reader.fontSize") private var fontSize: Double = 19
    @AppStorage("reader.lineSpacing") private var lineSpacing: Double = 8
    @AppStorage("reader.pagePadding") private var pagePadding: Double = 24
    @AppStorage("reader.paragraphSpacing") private var paragraphSpacing: Double = 16
    @AppStorage("reader.ttsRate") private var ttsRate: Double = 0.52
    @AppStorage("reader.autoScrollDelay") private var autoScrollDelay: Double = 2.0
    @AppStorage("reader.background") private var backgroundRawValue = "paper"

    init(article: RSSArticlePreview, articles: [RSSArticlePreview] = []) {
        initialArticle = article
        self.articles = articles.isEmpty ? [article] : articles
        _selectedIndex = State(initialValue: articles.firstIndex(where: { $0.id == article.id }) ?? 0)
    }

    private var currentArticle: RSSArticlePreview {
        articles.indices.contains(selectedIndex) ? articles[selectedIndex] : initialArticle
    }

    private var readerBackground: Color {
        switch backgroundRawValue {
        case "green": return Color(red: 0.89, green: 0.94, blue: 0.86)
        case "gray": return Color(.secondarySystemBackground)
        case "dark": return Color(red: 0.08, green: 0.085, blue: 0.10)
        default: return Color(red: 0.98, green: 0.96, blue: 0.90)
        }
    }

    private var readerTextColor: Color { backgroundRawValue == "dark" ? .white.opacity(0.92) : .primary }

    private var readerTextUIColor: UIColor {
        backgroundRawValue == "dark" ? UIColor.white.withAlphaComponent(0.92) : UIColor.label
    }

    private var nativeScrollTarget: Int? {
        if paragraphs.indices.contains(speechController.currentParagraphIndex) {
            return speechController.currentParagraphIndex
        }
        return autoScrollEnabled && paragraphs.indices.contains(autoScrollTarget) ? autoScrollTarget : nil
    }

    private var nativeScrollRequestKey: String {
        [
            currentArticle.id,
            reloadToken.uuidString,
            String(autoScrollTarget),
            String(speechController.currentParagraphIndex),
            autoScrollEnabled ? "auto" : "manual"
        ].joined(separator: "|")
    }

    var body: some View {
        articleReaderSurface
        .background(readerBackground.ignoresSafeArea())
        .navigationTitle("文章阅读")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { readerControls }
        .task(id: "\(currentArticle.id)|\(reloadToken.uuidString)") { await load(currentArticle) }
        .onAppear { appState.rssArticleStateStore.markRead(currentArticle) }
        .onChange(of: currentArticle.id) { _ in
            resetReaderSession()
            appState.rssArticleStateStore.markRead(currentArticle)
        }
        .onDisappear { stopAutoScroll(); speechController.stop() }
        .toolbar { readerToolbar }
    }

    @ViewBuilder
    private var articleReaderSurface: some View {
        if paragraphs.isEmpty {
            ScrollView { articleBody.frame(maxWidth: .infinity).padding(CGFloat(pagePadding)).padding(.bottom, 110) }
        } else {
            ZStack(alignment: .top) {
                NativeReaderTextView(
                    title: currentArticle.title,
                    subtitle: currentArticle.pubDate,
                    paragraphs: paragraphs,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    pagePadding: pagePadding,
                    letterSpacing: 0,
                    paragraphSpacing: paragraphSpacing,
                    paragraphIndent: 0,
                    titleSpacing: 12,
                    footerHeight: 110,
                    textColor: readerTextUIColor,
                    highlightColor: AppTheme.accentUIColor.withAlphaComponent(backgroundRawValue == "dark" ? 0.24 : 0.12),
                    currentParagraphIndex: speechController.currentParagraphIndex,
                    scrollTarget: nativeScrollTarget,
                    scrollRequestKey: nativeScrollRequestKey,
                    animatedScrollDuration: autoScrollEnabled ? max(autoScrollDelay * 0.9, 0.25) : 0.28,
                    textSelectionEnabled: true,
                    onVisibleParagraph: { index in
                        guard !autoScrollEnabled, paragraphs.indices.contains(index), index != visibleParagraphIndex else { return }
                        visibleParagraphIndex = index
                    }
                )
                .ignoresSafeArea(.container, edges: .bottom)

                if showingCachedContent {
                    Label("离线缓存正文", systemImage: "externaldrive")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(readerTextColor.opacity(0.72))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder private var articleBody: some View {
        if isLoading && paragraphs.isEmpty {
            ProgressView("正在加载文章").tint(readerTextColor).frame(maxWidth: .infinity, minHeight: 180)
        } else if let errorMessage, paragraphs.isEmpty {
            VStack(spacing: 12) {
                EmptyStateCard(systemImage: "exclamationmark.triangle", title: "文章加载失败", message: errorMessage)
                Button("重新加载") { reloadToken = UUID() }.buttonStyle(.borderedProminent)
            }
        } else if paragraphs.isEmpty {
            EmptyStateCard(systemImage: "doc.text", title: "暂无正文", message: "该文章没有可显示的正文内容。")
        } else {
            if showingCachedContent {
                Label("离线缓存正文", systemImage: "externaldrive").font(.caption).foregroundStyle(readerTextColor.opacity(0.62)).frame(maxWidth: .infinity, alignment: .center).padding(.top, 10)
            }
        }
    }

    @ToolbarContentBuilder private var readerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button { reloadToken = UUID() } label: { Image(systemName: isLoading ? "hourglass" : "arrow.clockwise") }.disabled(isLoading)
            Button { appState.rssArticleStateStore.toggleFavorite(currentArticle) } label: { Image(systemName: appState.rssArticleStateStore.isFavorite(currentArticle) ? "star.fill" : "star").foregroundStyle(appState.rssArticleStateStore.isFavorite(currentArticle) ? .yellow : readerTextColor) }
            if let link = currentArticle.link, let url = URL(string: link) { Link(destination: url) { Image(systemName: "safari") } }
        }
    }

    private var readerControls: some View {
        HStack(spacing: 16) {
            controlButton("上一篇", systemImage: "chevron.left", disabled: selectedIndex <= 0) { selectArticle(offset: -1) }
            controlButton(speechController.isSpeaking ? (speechController.isPaused ? "继续" : "暂停") : "朗读", systemImage: speechController.isSpeaking && !speechController.isPaused ? "pause.fill" : "speaker.wave.2.fill") { toggleSpeech() }
            controlButton(autoScrollEnabled ? "暂停滚动" : "自动滚动", systemImage: autoScrollEnabled ? "pause.circle.fill" : "arrow.down.circle") { autoScrollEnabled ? stopAutoScroll() : startAutoScroll() }
            controlButton("下一篇", systemImage: "chevron.right", disabled: selectedIndex >= articles.count - 1) { selectArticle(offset: 1) }
        }
        .padding(.horizontal, 18).padding(.vertical, 10).background(.ultraThinMaterial).overlay(alignment: .top) { Divider() }
    }

    private func controlButton(_ title: String, systemImage: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 4) { Image(systemName: systemImage).font(.system(size: 17, weight: .semibold)); Text(title).font(.caption2.weight(.semibold)).lineLimit(1) }.frame(maxWidth: .infinity) }.disabled(disabled)
    }

    private func selectArticle(offset: Int) {
        let target = selectedIndex + offset
        guard articles.indices.contains(target) else { return }
        selectedIndex = target
        appState.rssArticleStateStore.markRead(articles[target])
    }

    private func resetReaderSession() {
        stopAutoScroll(); speechController.stop(); paragraphs = []; errorMessage = nil; showingCachedContent = false; visibleParagraphIndex = 0; autoScrollTarget = 0; lastVisibleParagraphUpdateAt = .distantPast
    }

    private func toggleSpeech() {
        if speechController.isPaused { speechController.resume() }
        else if speechController.isSpeaking { speechController.pause() }
        else { stopAutoScroll(); speechController.speak(title: currentArticle.title, paragraphs: paragraphs, startParagraphIndex: visibleParagraphIndex, includeTitle: false, rate: Float(ttsRate)) }
    }

    private func startAutoScroll() {
        guard !paragraphs.isEmpty else { return }
        speechController.stop(); autoScrollEnabled = true; autoScrollTarget = min(max(visibleParagraphIndex, 0), paragraphs.count - 1)
        let delay = autoScrollDelay
        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, autoScrollEnabled else { return }
                if autoScrollTarget < paragraphs.count - 1 { autoScrollTarget += 1; visibleParagraphIndex = autoScrollTarget } else { stopAutoScroll() }
            }
        }
    }

    private func stopAutoScroll() { autoScrollTask?.cancel(); autoScrollTask = nil; autoScrollEnabled = false }


    @MainActor private func load(_ article: RSSArticlePreview) async {
        isLoading = true; errorMessage = nil; showingCachedContent = false; defer { isLoading = false }
        if let cachedHTML = appState.rssArticleContentCacheStore.contentHTML(for: article, maxAge: RSSFeedCacheStore.defaultMaxAge) {
            let cached = RSSArticleContentParser().parseParagraphs(from: cachedHTML)
            if !cached.isEmpty { paragraphs = cached; showingCachedContent = true }
        }
        if paragraphs.isEmpty, let cached = appState.rssArticleContentCacheStore.paragraphs(for: article, maxAge: RSSFeedCacheStore.defaultMaxAge) { paragraphs = cached; showingCachedContent = true }
        guard let link = article.link, let url = URL(string: link) else { if paragraphs.isEmpty { paragraphs = fallbackParagraphs(for: article) }; return }
        do {
            var request = URLRequest(url: url); request.setValue("Mozilla/5.0 SourceReadSwift", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) { throw URLError(.badServerResponse) }
            try Task.checkCancellation()
            let html = ResponseTextDecoder().decode(data: data, headers: [:])
            let parsed = RSSArticleContentParser().parseParagraphs(from: html)
            if !parsed.isEmpty { paragraphs = parsed; appState.rssArticleContentCacheStore.save(parsed, for: article, contentHTML: article.contentHTML ?? html); showingCachedContent = false }
        } catch is CancellationError { return }
        catch { if paragraphs.isEmpty { paragraphs = fallbackParagraphs(for: article) }; if paragraphs.isEmpty { errorMessage = error.localizedDescription } else { showingCachedContent = true } }
    }

    private func fallbackParagraphs(for article: RSSArticlePreview) -> [String] {
        article.contentHTML.map { RSSArticleContentParser().parseParagraphs(from: $0) } ?? article.description.map { RSSArticleContentParser().parseParagraphs(from: $0) } ?? []
    }
}
