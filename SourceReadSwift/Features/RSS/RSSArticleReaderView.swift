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
    @State private var contentFingerprint = ""
    @State private var showingCachedContent = false
    @State private var visibleParagraphIndex = 0
    @State private var pendingPositionRestore: Int?
    @State private var autoScrollEnabled = false
    @State private var autoScrollTarget = 0
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var positionPersistTask: Task<Void, Never>?
    @State private var reloadToken = UUID()
    @State private var loadGeneration = 0
    @State private var lastVisibleParagraphUpdateAt = Date.distantPast
    @State private var speechPausedForScene = false
    @State private var autoScrollPausedForScene = false
    @State private var statusMessage: String?
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var speechController = ReaderSpeechController()
    @StateObject private var playbackCoordinator = ReaderPlaybackCoordinator()
    @AppStorage("reader.fontSize") private var fontSize: Double = 19
    @AppStorage("reader.lineSpacing") private var lineSpacing: Double = 8
    @AppStorage("reader.pagePadding") private var pagePadding: Double = 24
    @AppStorage("reader.paragraphSpacing") private var paragraphSpacing: Double = 16
    @AppStorage("reader.letterSpacing") private var letterSpacing: Double = 0
    @AppStorage("reader.titleSpacing") private var titleSpacing: Double = 12
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
        if let pendingPositionRestore,
           paragraphs.indices.contains(pendingPositionRestore) {
            return pendingPositionRestore
        }
        return autoScrollEnabled && paragraphs.indices.contains(autoScrollTarget) ? autoScrollTarget : nil
    }

    private var nativeScrollRequestKey: String {
        [
            currentArticle.id,
            reloadToken.uuidString,
            String(autoScrollTarget),
            String(speechController.currentParagraphIndex),
            String(pendingPositionRestore ?? -1),
            autoScrollEnabled ? "auto" : "manual"
        ].joined(separator: "|")
    }

    var body: some View {
        ZStack(alignment: .top) {
            articleReaderSurface

            if let statusMessage {
                readerStatusBanner(statusMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
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
        .onChange(of: paragraphs.count) { count in
            guard count > 0 else { return }
            let clamped = min(max(visibleParagraphIndex, 0), count - 1)
            if clamped != visibleParagraphIndex {
                visibleParagraphIndex = clamped
                persistParagraphPosition(clamped)
            }
        }
        .onDisappear {
            positionPersistTask?.cancel()
            persistParagraphPosition(visibleParagraphIndex)
            stopAutoScroll()
            stopSpeechPlayback()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                if autoScrollEnabled {
                    autoScrollPausedForScene = true
                    stopAutoScroll()
                }
                if speechController.isSpeaking && !speechController.isPaused {
                    speechController.pause()
                    playbackCoordinator.pauseSpeech()
                    speechPausedForScene = true
                }
            } else {
                if autoScrollPausedForScene {
                    autoScrollPausedForScene = false
                    startAutoScroll()
                }
                if speechPausedForScene && speechController.isPaused {
                    speechController.resume()
                    playbackCoordinator.resumeSpeech()
                    speechPausedForScene = false
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: statusMessage)
        .highRefreshRateSurface()
        .sheet(isPresented: $showSettings) {
            RSSReaderSettingsView(
                fontSize: $fontSize,
                lineSpacing: $lineSpacing,
                letterSpacing: $letterSpacing,
                paragraphSpacing: $paragraphSpacing,
                pagePadding: $pagePadding,
                titleSpacing: $titleSpacing,
                ttsRate: $ttsRate,
                autoScrollDelay: $autoScrollDelay,
                backgroundRawValue: $backgroundRawValue
            )
            .presentationDetents([.medium, .large])
        }
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
                    contentFingerprint: contentFingerprint,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    pagePadding: pagePadding,
                    letterSpacing: letterSpacing,
                    paragraphSpacing: paragraphSpacing,
                    paragraphIndent: 0,
                    titleSpacing: titleSpacing,
                    footerHeight: 110,
                    textColor: readerTextUIColor,
                    highlightColor: AppTheme.accentUIColor.withAlphaComponent(backgroundRawValue == "dark" ? 0.24 : 0.12),
                    currentParagraphIndex: speechController.currentParagraphIndex,
                    scrollTarget: nativeScrollTarget,
                    scrollRequestKey: nativeScrollRequestKey,
                    animatedScrollDuration: autoScrollEnabled ? max(ReaderAutomationPolicy.clampedDelay(autoScrollDelay) * 0.9, 0.25) : 0.28,
                    textSelectionEnabled: true,
                    onVisibleParagraph: { index in
                        guard !autoScrollEnabled, paragraphs.indices.contains(index), index != visibleParagraphIndex else { return }
                        visibleParagraphIndex = index
                        scheduleParagraphPositionPersistence(index)
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
            Menu {
                Button {
                    toggleSpeech()
                } label: {
                    Label(
                        speechController.isSpeaking
                            ? (speechController.isPaused ? "继续朗读" : "暂停朗读")
                            : "从当前段落朗读",
                        systemImage: speechController.isSpeaking && !speechController.isPaused ? "pause.fill" : "speaker.wave.2"
                    )
                }
                Button {
                    autoScrollEnabled ? stopAutoScroll() : startAutoScroll()
                } label: {
                    Label(autoScrollEnabled ? "暂停自动滚动" : "自动滚动", systemImage: autoScrollEnabled ? "pause.circle" : "arrow.down.circle")
                }
                Divider()
                Button {
                    reloadToken = UUID()
                } label: {
                    Label("刷新正文", systemImage: "arrow.clockwise")
                }
                Button {
                    showSettings = true
                } label: {
                    Label("阅读设置", systemImage: "gearshape")
                }
                Button {
                    appState.rssArticleStateStore.toggleFavorite(currentArticle)
                } label: {
                    Label(
                        appState.rssArticleStateStore.isFavorite(currentArticle) ? "取消收藏" : "收藏文章",
                        systemImage: appState.rssArticleStateStore.isFavorite(currentArticle) ? "star.slash" : "star"
                    )
                }
                if let link = currentArticle.link, let url = URL(string: link) {
                    Link(destination: url) { Label("在浏览器打开", systemImage: "safari") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("文章阅读菜单")
        }
    }

    private func readerStatusBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: showingCachedContent ? "externaldrive" : (isLoading ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle"))
            Text(message)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(readerTextColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(backgroundRawValue == "dark" ? 0.08 : 0.35), lineWidth: 0.8) }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .allowsHitTesting(false)
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
        // Commit the outgoing article before selectedIndex changes. Otherwise
        // a pending debounced callback would write the old paragraph under the
        // incoming article's identity.
        positionPersistTask?.cancel()
        persistParagraphPosition(visibleParagraphIndex)
        selectedIndex = target
        appState.rssArticleStateStore.markRead(articles[target])
    }

    private func resetReaderSession() {
        loadGeneration &+= 1
        // selectedIndex has already changed when this callback runs. Do not
        // persist the outgoing article's position using currentArticle (which
        // now points at the incoming article).
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollEnabled = false
        if case .autoScroll = playbackCoordinator.mode {
            playbackCoordinator.stop()
        }
        stopSpeechPlayback()
        paragraphs = []
        contentFingerprint = ""
        errorMessage = nil
        showingCachedContent = false
        statusMessage = nil
        visibleParagraphIndex = 0
        autoScrollTarget = 0
        pendingPositionRestore = nil
        lastVisibleParagraphUpdateAt = .distantPast
        speechPausedForScene = false
        autoScrollPausedForScene = false
        positionPersistTask?.cancel()
        positionPersistTask = nil
    }

    private func toggleSpeech() {
        if speechController.isPaused {
            speechController.resume()
            playbackCoordinator.resumeSpeech()
        }
        else if speechController.isSpeaking {
            speechController.pause()
            playbackCoordinator.pauseSpeech()
        }
        else {
            stopAutoScroll()
            let coordinator = playbackCoordinator
            let token = coordinator.beginSpeech()
            speechController.onFinished = { [weak coordinator] in
                Task { @MainActor in
                    guard let coordinator, coordinator.accepts(token, for: .speech(generation: token)) else { return }
                    coordinator.stop()
                    speechPausedForScene = false
                }
            }
            speechController.speak(title: currentArticle.title, paragraphs: paragraphs, startParagraphIndex: visibleParagraphIndex, includeTitle: false, rate: Float(ttsRate))
        }
    }

    private func startAutoScroll() {
        guard !paragraphs.isEmpty else { return }
        stopAutoScroll()
        stopSpeechPlayback()
        autoScrollEnabled = true
        autoScrollTarget = min(max(visibleParagraphIndex, 0), paragraphs.count - 1)
        let delay = ReaderAutomationPolicy.clampedDelay(autoScrollDelay)
        let coordinator = playbackCoordinator
        let token = coordinator.beginAutoScroll()
        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled,
                      coordinator.accepts(token, for: .autoScroll(generation: token)),
                      autoScrollEnabled else { return }
                switch ReaderAutomationPolicy.decision(currentTarget: autoScrollTarget, maximumTarget: paragraphs.count - 1, canAdvanceChapter: false) {
                case .advance(let target):
                    autoScrollTarget = target
                    visibleParagraphIndex = target
                    // Auto-scroll bypasses NativeReaderTextView's manual
                    // visibility callback. Persist each advance so closing
                    // the reader (or being interrupted by a scene change)
                    // resumes from the paragraph the user actually reached.
                    appState.rssArticleStateStore.updateParagraphPosition(
                        target,
                        for: currentArticle
                    )
                case .nextChapter, .stop:
                    stopAutoScroll()
                }
            }
        }
    }

    private func stopAutoScroll() {
        if paragraphs.indices.contains(visibleParagraphIndex) {
            persistParagraphPosition(visibleParagraphIndex)
        }
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollEnabled = false
        if case .autoScroll = playbackCoordinator.mode {
            playbackCoordinator.stop()
        }
    }

    private func scheduleParagraphPositionPersistence(_ index: Int) {
        positionPersistTask?.cancel()
        positionPersistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ReaderPerformancePolicy.positionPersistenceDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            persistParagraphPosition(index)
            positionPersistTask = nil
        }
    }

    private func persistParagraphPosition(_ index: Int) {
        guard !paragraphs.isEmpty else { return }
        let safeIndex = min(max(index, 0), paragraphs.count - 1)
        appState.rssArticleStateStore.updateParagraphPosition(safeIndex, for: currentArticle)
    }

    /// NativeReaderTextView preserves its current pixel offset by design. A
    /// one-shot target is needed when cached or freshly fetched paragraphs are
    /// first installed, otherwise a restored paragraph index would be stored
    /// correctly but the surface would still render from paragraph zero.
    private func requestPositionRestore(_ index: Int, generation: Int) {
        guard !paragraphs.isEmpty else { return }
        let safeIndex = min(max(index, 0), paragraphs.count - 1)
        pendingPositionRestore = safeIndex
        DispatchQueue.main.async {
            guard generation == loadGeneration else { return }
            pendingPositionRestore = nil
        }
    }

    private func stopSpeechPlayback() {
        speechController.stop()
        playbackCoordinator.stop()
        speechPausedForScene = false
    }


    @MainActor private func load(_ article: RSSArticlePreview) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        showingCachedContent = false
        statusMessage = "正在加载正文…"
        defer {
            if generation == loadGeneration {
                isLoading = false
                if !showingCachedContent, errorMessage == nil {
                    statusMessage = nil
                }
            }
        }
        if let savedPosition = appState.rssArticleStateStore.paragraphPosition(for: article) {
            visibleParagraphIndex = max(0, savedPosition)
        } else {
            visibleParagraphIndex = 0
        }
        // Read stale entries too. A reader should remain useful offline; the
        // network request below is still attempted and replaces the cache when
        // fresh content is available.
        if let cachedHTML = appState.rssArticleContentCacheStore.contentHTML(for: article) {
            let cached = RSSArticleContentParser().parseParagraphs(from: cachedHTML)
            if !cached.isEmpty {
                paragraphs = cached
                contentFingerprint = makeContentFingerprint(cached, articleID: article.id)
                showingCachedContent = true
                statusMessage = "网络加载中 · 当前显示离线缓存"
                requestPositionRestore(visibleParagraphIndex, generation: generation)
            }
        }
        if paragraphs.isEmpty, let cached = appState.rssArticleContentCacheStore.paragraphs(for: article) {
            paragraphs = cached
            contentFingerprint = makeContentFingerprint(cached, articleID: article.id)
            showingCachedContent = true
            statusMessage = "网络加载中 · 当前显示离线缓存"
            requestPositionRestore(visibleParagraphIndex, generation: generation)
        }
        guard let link = article.link, let url = URL(string: link) else {
            if paragraphs.isEmpty {
                paragraphs = fallbackParagraphs(for: article)
                contentFingerprint = makeContentFingerprint(paragraphs, articleID: article.id)
            }
            statusMessage = paragraphs.isEmpty ? "该文章没有有效链接" : "已显示文章内容"
            return
        }
        do {
            var request = URLRequest(url: url); request.setValue("Mozilla/5.0 SourceReadSwift", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) { throw URLError(.badServerResponse) }
            try Task.checkCancellation()
            guard generation == loadGeneration, article.id == currentArticle.id else { return }
            let html = ResponseTextDecoder().decode(data: data, headers: [:])
            let parsed = RSSArticleContentParser().parseParagraphs(from: html)
            guard generation == loadGeneration, article.id == currentArticle.id else { return }
            if !parsed.isEmpty {
                paragraphs = parsed
                contentFingerprint = makeContentFingerprint(parsed, articleID: article.id)
                appState.rssArticleContentCacheStore.save(parsed, for: article, contentHTML: article.contentHTML ?? html)
                showingCachedContent = false
                statusMessage = nil
                requestPositionRestore(visibleParagraphIndex, generation: generation)
            }
        } catch is CancellationError { return }
        catch {
            guard generation == loadGeneration, article.id == currentArticle.id else { return }
            if paragraphs.isEmpty {
                paragraphs = fallbackParagraphs(for: article)
                contentFingerprint = makeContentFingerprint(paragraphs, articleID: article.id)
                requestPositionRestore(visibleParagraphIndex, generation: generation)
            }
            if paragraphs.isEmpty {
                errorMessage = error.localizedDescription
                statusMessage = "正文加载失败"
            } else {
                showingCachedContent = true
                statusMessage = "网络不可用 · 已回退到离线缓存"
            }
        }
    }

    private func fallbackParagraphs(for article: RSSArticlePreview) -> [String] {
        article.contentHTML.map { RSSArticleContentParser().parseParagraphs(from: $0) } ?? article.description.map { RSSArticleContentParser().parseParagraphs(from: $0) } ?? []
    }

    private func makeContentFingerprint(_ values: [String], articleID: String) -> String {
        var hasher = Hasher()
        hasher.combine(articleID)
        hasher.combine(values.count)
        for value in values { hasher.combine(value) }
        return String(hasher.finalize())
    }
}
