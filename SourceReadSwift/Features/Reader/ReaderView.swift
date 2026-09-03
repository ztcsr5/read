import AVFoundation
import SwiftUI
import UIKit

struct ReaderView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    let bookID: String
    let content: ChapterContent
    let chapterIndex: Int
    let totalChapters: Int?
    var chapters: [BookChapter] = []
    var statusMessage: String?
    var extraToolbarActions: () -> AnyView = { AnyView(EmptyView()) }
    var onRequestSourceSwitch: (() -> Void)?
    /// Opens the owning book detail screen from the reader's overflow menu.
    /// When omitted, the reader simply closes so the caller's previous screen
    /// remains the fallback detail context.
    var onRequestBookDetail: (() -> Void)?
    var onSelectChapter: ((BookChapter) -> Void)?
    var onRefreshChapter: (() -> Void)?
    var onCacheNextChapters: (() -> Void)?
    /// Called after speech reaches the end of the current chapter. The owning
    /// screen can swap in the next chapter without coupling the speech engine
    /// to navigation or networking.
    var onSpeechFinished: (() -> Void)? = nil
    /// Used by the chapter owner to continue speech after an automatic
    /// chapter handoff. It is intentionally one-shot and consumed on appear.
    var autoplaySpeechOnAppear: Bool = false
    var onSpeechAutoplayConsumed: (() -> Void)? = nil
    /// Keeps the reader controls visible when navigation originated in the
    /// chapter list. A fresh chapter view otherwise starts with the chrome
    /// hidden and can be mistaken for the root tab UI.
    var initialOverlayVisible: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOverlay = false
    @State private var tabChromeOwner = UUID()
    @State private var showSettings = false
    @State private var showChapterList = false
    @State private var showBookmarks = false
    @State private var settingsTab = 0
    @State private var tocTab = 0
    @State private var tocQuery = ""
    @State private var tocReversed = false
    @State private var autoScrollEnabled = false
    @State private var autoScrollTarget = 0
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var sleepTimerTask: Task<Void, Never>?
    @State private var positionPersistTask: Task<Void, Never>?
    @State private var paragraphJumpRequest: ParagraphJumpRequest?
    @State private var pagedBlocksCache: [ReaderPageBlock] = []
    @State private var pagedBlocksCacheKey = ""
    @State private var sessionStartedAt = Date()
    @State private var previousIdleTimerDisabled = false
    @State private var visibleParagraphIndex = 0
    @State private var lastVisibleParagraphUpdateAt = Date.distantPast
    @State private var speechPausedForScene = false
    @StateObject private var playbackCoordinator = ReaderPlaybackCoordinator()
    @StateObject private var speechController = ReaderSpeechController()
    @AppStorage("reader.fontSize") private var fontSize: Double = 19
    @AppStorage("reader.lineSpacing") private var lineSpacing: Double = 8
    @AppStorage("reader.pagePadding") private var pagePadding: Double = 24
    @AppStorage("reader.letterSpacing") private var letterSpacing: Double = 0
    @AppStorage("reader.paragraphSpacing") private var paragraphSpacing: Double = 16
    @AppStorage("reader.paragraphIndent") private var paragraphIndent: Double = 0
    @AppStorage("reader.titleSpacing") private var titleSpacing: Double = 12
    @AppStorage("reader.footerHeight") private var footerHeight: Double = 72
    @AppStorage("reader.ttsRate") private var ttsRate: Double = 0.52
    @AppStorage("reader.autoScrollDelay") private var autoScrollDelay: Double = 2.0
    @AppStorage("reader.sleepTimerMinutes") private var sleepTimerMinutes: Int = 0
    @AppStorage("reader.background") private var backgroundRawValue: String = ReaderBackground.paper.rawValue
    @AppStorage("reader.mode") private var readerModeRawValue: String = ReaderMode.scroll.rawValue
    @AppStorage("reader.tapZones") private var tapZonesRawValue: String = ReaderTapAction.defaultRawValue
    @AppStorage("reader.keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("reader.preloadChapterCount") private var preloadChapterCount = ReaderPreloadPolicy.defaultCount
    @AppStorage("reader.textSelectionEnabled") private var textSelectionEnabled = false

    private var background: ReaderBackground {
        ReaderBackground(rawValue: backgroundRawValue) ?? .paper
    }

    private var readerMode: ReaderMode {
        ReaderMode(rawValue: readerModeRawValue) ?? .scroll
    }

    private var tapZoneActions: [ReaderTapAction] {
        ReaderTapAction.decode(rawValue: tapZonesRawValue)
    }

    private var bookmarks: [ReaderBookmark] {
        appState.bookshelfStore.book(id: bookID)?.bookmarks ?? []
    }

    private var sortedBookmarks: [ReaderBookmark] {
        bookmarks.sorted { lhs, rhs in
            if lhs.chapterIndex != rhs.chapterIndex {
                return lhs.chapterIndex < rhs.chapterIndex
            }
            if lhs.paragraphIndex != rhs.paragraphIndex {
                return (lhs.paragraphIndex ?? -1) < (rhs.paragraphIndex ?? -1)
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var currentChapterBookmarkCount: Int {
        bookmarks.filter { $0.chapterIndex == chapterIndex }.count
    }

    private var isCurrentChapterBookmarked: Bool {
        appState.bookshelfStore.isBookmarked(
            bookID: bookID,
            chapterIndex: chapterIndex,
            paragraphIndex: currentBookmarkParagraphIndex
        )
    }

    private var currentBookmarkParagraphIndex: Int {
        currentParagraphIndexForPersistence()
    }

    private var progressTitle: String {
        var parts: [String] = []
        if let totalChapters, totalChapters > 0 {
            let percentage = Int((Double(chapterIndex + 1) / Double(totalChapters) * 100).rounded())
            parts.append("第 \(chapterIndex + 1) / \(totalChapters) 章")
            parts.append("\(percentage)%")
        } else {
            parts.append("第 \(chapterIndex + 1) 章")
        }
        if readerMode != .scroll {
            let pageCount = max(pagedBlocks.count, 1)
            let page = min(max(autoScrollTarget + 1, 1), pageCount)
            parts.append("页 \(page)/\(pageCount)")
        }
        return parts.joined(separator: " · ")
    }

    private var maximumReaderTarget: Int {
        switch readerMode {
        case .scroll:
            return max(content.paragraphs.count - 1, 0)
        case .pageTurn, .cover:
            return max(pagedBlocks.count - 1, 0)
        }
    }

    private var filteredChapters: [BookChapter] {
        let query = tocQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = chapters.filter { chapter in
            query.isEmpty
                || chapter.title.lowercased().contains(query)
                || "\(chapter.index + 1)".contains(query)
        }
        if tocReversed {
            result.reverse()
        }
        return result
    }

    private var pagedBlocks: [ReaderPageBlock] {
        // Keep the last page model while a settings change is being committed.
        // SwiftUI may evaluate `body` several times before `.onChange` runs;
        // rebuilding a long chapter in each pass was a major source of jank.
        if !pagedBlocksCache.isEmpty {
            return pagedBlocksCache
        }
        // A valid empty cache is still a cache (empty chapters are legal).
        if pagedBlocksCacheKey == readerPageCacheKey { return pagedBlocksCache }
        // Before `onAppear` seeds the cache, render a cheap placeholder rather
        // than laying out every paragraph once per SwiftUI body evaluation.
        return [ReaderPageBlock(id: 0, includesTitle: true, paragraphs: [])]
    }

    private var readerPageCacheKey: String {
        // Pagination depends on the viewport. Include the current screen
        // bounds so rotation, split-view and Stage Manager resize invalidate
        // the model instead of showing pages calculated for the old width.
        let viewport = UIScreen.main.bounds
        [
            readerLayoutKey,
            String(Int(viewport.width.rounded())),
            String(Int(viewport.height.rounded())),
            content.title,
            String(content.paragraphs.count),
            String(content.paragraphs.first?.hashValue ?? 0),
            String(content.paragraphs.last?.hashValue ?? 0)
        ].joined(separator: "|")
    }

    private var readerLayoutKey: String {
        [
            readerModeRawValue,
            backgroundRawValue,
            String(format: "%.1f", fontSize),
            String(format: "%.1f", lineSpacing),
            String(format: "%.1f", pagePadding),
            String(format: "%.1f", letterSpacing),
            String(format: "%.1f", paragraphSpacing),
            String(format: "%.1f", paragraphIndent),
            String(format: "%.1f", titleSpacing),
            String(format: "%.1f", footerHeight)
        ].joined(separator: "|")
    }

    var body: some View {
        ZStack {
            readerBackdrop

            readerContent
            .id(readerLayoutKey)
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        handleReaderTap(at: value.location)
                    }
            )

            if showSettings && settingsTab == 2 {
                tapZoneOverlay
                    .allowsHitTesting(false)
                }

            if showOverlay {
                readerOverlay
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .center)),
                            removal: .opacity
                        )
                    )
            }

            if let statusMessage {
                readerStatusBanner(message: statusMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showSettings {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showSettings = false
                        }
                    }
                    .transition(.opacity)

                settingsPanel
                    .zIndex(2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!showOverlay)
        .preferredColorScheme(background == .dark ? .dark : .light)
        .sheet(isPresented: $showChapterList) {
            chapterListSheet
        }
        .sheet(isPresented: $showBookmarks) {
            bookmarkSheet
        }
        .onAppear {
            appState.acquireTabChromeHidden(owner: tabChromeOwner)
            showOverlay = initialOverlayVisible
            sessionStartedAt = Date()
            rebuildPagedBlocksCache()
            autoScrollTarget = initialAutoScrollTarget()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            applyIdleTimerPreference()
            scheduleSleepTimer()
            appState.bookshelfStore.markReaderOpened(bookID: bookID)
            persistReadingPosition()
            if autoplaySpeechOnAppear {
                onSpeechAutoplayConsumed?()
                DispatchQueue.main.async {
                    beginSpeechPlayback()
                }
            }
        }
        .onDisappear {
            positionPersistTask?.cancel()
            persistReadingPosition(paragraphIndexOverride: currentParagraphIndexForPersistence())
            stopAutoScroll()
            sleepTimerTask?.cancel()
            sleepTimerTask = nil
            speechController.stop()
            playbackCoordinator.stop()
            restoreIdleTimerPreference()
            appState.releaseTabChromeHidden(owner: tabChromeOwner)
            appState.bookshelfStore.recordReadingSession(
                bookID: bookID,
                duration: Date().timeIntervalSince(sessionStartedAt)
            )
        }
        .onChange(of: keepScreenAwake) { _ in
            applyIdleTimerPreference()
        }
        .onChange(of: sleepTimerMinutes) { _ in
            scheduleSleepTimer()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                autoScrollTask?.cancel()
                autoScrollTask = nil
                if autoScrollEnabled {
                    autoScrollEnabled = false
                    playbackCoordinator.stop()
                }
                if speechController.isSpeaking && !speechController.isPaused {
                    speechController.pause()
                    playbackCoordinator.pauseSpeech()
                    speechPausedForScene = true
                }
            } else if speechPausedForScene && speechController.isPaused {
                speechController.resume()
                playbackCoordinator.resumeSpeech()
                speechPausedForScene = false
            }
        }
        .onChange(of: autoScrollTarget) { _ in
            // Persisting the whole bookshelf serializes JSON to disk. Debounce
            // target changes so paging/auto-scroll stays on the rendering path.
            scheduleReadingPositionPersistence(paragraphIndex: currentParagraphIndexForPersistence())
        }
            .onChange(of: readerModeRawValue) { _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                stopAutoScroll()
                speechController.stop()
                playbackCoordinator.stop()
                speechPausedForScene = false
                autoScrollTarget = initialAutoScrollTarget()
        }
            .onChange(of: readerPageCacheKey) { _ in
            rebuildPagedBlocksCache()
            autoScrollTarget = min(max(autoScrollTarget, 0), maximumReaderTarget)
            scheduleReadingPositionPersistence(paragraphIndex: currentParagraphIndexForPersistence())
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: showOverlay)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: showSettings)
        .animation(.easeOut(duration: 0.18), value: statusMessage)
    }

    private var readerBackdrop: some View {
        ZStack {
            background.color
            LinearGradient(
                colors: [
                    Color.white.opacity(background == .dark ? 0.02 : 0.16),
                    Color.clear,
                    Color.black.opacity(background == .dark ? 0.28 : 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    AppTheme.accent.opacity(background == .dark ? 0.16 : 0.08),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
            .blendMode(background == .dark ? .screen : .multiply)
        }
        .ignoresSafeArea()
    }

    private var chromeForeground: Color {
        background == .dark ? .white.opacity(0.94) : .primary
    }

    private var chromeSecondaryForeground: Color {
        background == .dark ? .white.opacity(0.62) : .secondary
    }

    @ViewBuilder
    private var readerContent: some View {
        switch readerMode {
        case .scroll:
            scrollReaderContent
        case .pageTurn, .cover:
            pagedReaderContent
        }
    }

    private var scrollReaderContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CGFloat(paragraphSpacing)) {
                    Text(content.title)
                        .font(.system(size: fontSize + 8, weight: .bold, design: .default))
                        .foregroundStyle(background.textColor)
                        .padding(.bottom, CGFloat(titleSpacing))
                        .id(-1)

                    ForEach(content.paragraphs.indices, id: \.self) { index in
                        paragraphText(content.paragraphs[index], index: index)
                            .id(index)
                            .background {
                                if shouldTrackParagraphPosition(index) {
                                    paragraphPositionReader(index: index)
                                }
                            }
                    }
                }
                .padding(CGFloat(pagePadding))
                .padding(.bottom, CGFloat(footerHeight))
            }
            .coordinateSpace(name: "readerScroll")
            .onChange(of: autoScrollTarget) { target in
                guard content.paragraphs.indices.contains(target) else { return }
                // Advance on the same cadence as the timer. A short fixed
                // animation made auto-scroll appear to do nothing between
                // jumps; matching the configured interval produces a
                // continuous, readable movement on 60/90/120 Hz displays.
                withAnimation(.linear(duration: max(autoScrollDelay * 0.9, 0.25))) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
            .onChange(of: paragraphJumpRequest) { target in
                guard let target, content.paragraphs.indices.contains(target.index) else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(target.index, anchor: .top)
                }
            }
            .onChange(of: speechController.currentParagraphIndex) { target in
                guard target >= 0 else { return }
                // Speech can advance once per paragraph. Do not serialize the
                // whole bookshelf synchronously on the display frame path.
                scheduleReadingPositionPersistence(paragraphIndex: target)
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
            .onAppear {
                let target = autoScrollTarget
                guard target > 0, content.paragraphs.indices.contains(target) else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
            .onPreferenceChange(ParagraphPositionPreferenceKey.self) { positions in
                updateVisibleParagraph(from: positions)
            }
        }
    }

    @ViewBuilder
    private var pagedReaderContent: some View {
        if readerMode == .cover {
            coverPagedReaderContent
        } else {
            horizontalPagedReaderContent
        }
    }

    private var horizontalPagedReaderContent: some View {
        TabView(selection: $autoScrollTarget) {
            ForEach(pagedBlocks) { page in
                readerPage(for: page)
                .tag(page.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: autoScrollTarget) { target in
            updatePagedVisibleParagraph(pageIndex: target)
        }
        .onChange(of: speechController.currentParagraphIndex) { target in
            guard target >= 0 else { return }
            autoScrollTarget = pageIndex(containingParagraph: target)
        }
    }

    private var coverPagedReaderContent: some View {
        let safeIndex = min(max(autoScrollTarget, 0), max(pagedBlocks.count - 1, 0))
        return ZStack {
            if pagedBlocks.indices.contains(safeIndex) {
                readerPage(for: pagedBlocks[safeIndex])
                    .id(pagedBlocks[safeIndex].id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -42 {
                        moveReaderTarget(to: autoScrollTarget + 1)
                    } else if value.translation.width > 42 {
                        moveReaderTarget(to: autoScrollTarget - 1)
                    }
                }
        )
        .animation(.easeInOut(duration: 0.22), value: autoScrollTarget)
        .onChange(of: autoScrollTarget) { target in
            updatePagedVisibleParagraph(pageIndex: target)
        }
        .onChange(of: speechController.currentParagraphIndex) { target in
            guard target >= 0 else { return }
            autoScrollTarget = pageIndex(containingParagraph: target)
        }
    }

    private func readerPage(for page: ReaderPageBlock) -> some View {
        pageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(paragraphSpacing)) {
                    if page.includesTitle {
                        Text(content.title)
                            .font(.system(size: fontSize + 8, weight: .bold, design: .default))
                            .foregroundStyle(background.textColor)
                            .padding(.bottom, CGFloat(titleSpacing))
                            .readerSelectableText(textSelectionEnabled)
                    }

                    ForEach(page.paragraphs, id: \.index) { entry in
                        paragraphText(entry.text, index: entry.index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func pageSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(CGFloat(pagePadding))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if readerMode == .cover {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(background.color.opacity(background == .dark ? 0.92 : 0.98))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(background == .dark ? 0.08 : 0.35), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(background == .dark ? 0.42 : 0.14), radius: 24, x: -8, y: 2)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                }
            }
    }

    private func paragraphText(_ paragraph: String, index: Int) -> some View {
        Text(paragraph)
            .font(.system(size: fontSize, weight: .regular, design: .default))
            .foregroundStyle(background.textColor)
            .kerning(letterSpacing)
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, CGFloat(paragraphIndent))
            .padding(.vertical, speechController.currentParagraphIndex == index ? 6 : 0)
            .background {
                if speechController.currentParagraphIndex == index {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.opacity(background == .dark ? 0.22 : 0.12))
                }
            }
            .readerSelectableText(textSelectionEnabled)
    }

    private func paragraphPositionReader(index: Int) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ParagraphPositionPreferenceKey.self,
                value: [ParagraphPosition(index: index, minY: proxy.frame(in: .named("readerScroll")).minY)]
            )
        }
    }

    private func shouldTrackParagraphPosition(_ index: Int) -> Bool {
        index == 0
            || index == visibleParagraphIndex
            || index == speechController.currentParagraphIndex
            || index % paragraphTrackingStride == 0
    }

    private var paragraphTrackingStride: Int {
        ReaderPerformancePolicy.paragraphTrackingStride(paragraphCount: content.paragraphs.count)
    }

    private var readerOverlay: some View {
        VStack {
            HStack {
                chromeIconButton(systemName: "chevron.left") {
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(chromeForeground)
                        .lineLimit(1)
                    Text(progressTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(chromeSecondaryForeground)
                        .lineLimit(1)
                }

                Spacer()

                extraToolbarActions()

                if let onRefreshChapter {
                    chromeIconButton(systemName: "arrow.clockwise") {
                        onRefreshChapter()
                    }
                }

                chromeIconButton(systemName: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark") {
                    toggleCurrentBookmark(openList: false)
                }

                Menu {
                    Button {
                        onRequestBookDetail?()
                    } label: {
                        Label("书籍详情", systemImage: "info.circle")
                    }
                    .disabled(onRequestBookDetail == nil)

                    Button {
                        showOverlay = false
                        showSettings = false
                        onRequestSourceSwitch?()
                    } label: {
                        Label("换源", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(onRequestSourceSwitch == nil)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("书籍详情和换源")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassPanel(cornerRadius: 26, material: .ultraThinMaterial, strokeOpacity: background == .dark ? 0.09 : 0.12, shadowOpacity: background == .dark ? 0.42 : 0.14)
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    toolButton(icon: "chevron.left", title: "上一章") {
                        selectRelativeChapter(offset: -1)
                    }
                    .disabled(!canSelectRelativeChapter(offset: -1))

                    Text(progressTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(chromeSecondaryForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial, in: Capsule())

                    toolButton(icon: "chevron.right", title: "下一章") {
                        selectRelativeChapter(offset: 1)
                    }
                    .disabled(!canSelectRelativeChapter(offset: 1))
                }

                HStack(spacing: 10) {

                    toolButton(icon: "list.bullet", title: "目录") {
                        tocTab = 0
                        showChapterList = true
                        showSettings = false
                    }

                    if let onRequestSourceSwitch {
                        toolButton(icon: "arrow.triangle.2.circlepath", title: "换源") {
                            showOverlay = false
                            showSettings = false
                            onRequestSourceSwitch()
                        }
                    }

                    toolButton(icon: speechController.isPaused ? "play.fill" : (speechController.isSpeaking ? "pause.fill" : "speaker.wave.2"), title: speechController.isPaused ? "继续" : (speechController.isSpeaking ? "暂停" : "朗读")) {
                        toggleSpeech()
                        showSettings = false
                    }
                    if speechController.isSpeaking {
                        toolButton(icon: "stop.fill", title: "停止") {
                            speechController.stop()
                            showSettings = false
                        }
                    }
                    toolButton(icon: autoScrollEnabled ? "pause.fill" : "play.fill", title: autoScrollEnabled ? "暂停" : "自动") {
                        toggleAutoScroll()
                        showSettings = false
                    }
                    if let onCacheNextChapters {
                        toolButton(icon: "square.and.arrow.down", title: "缓存") {
                            onCacheNextChapters()
                            showSettings = false
                        }
                    }
                    toolButton(icon: "gearshape", title: "设置") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showSettings.toggle()
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .glassPanel(cornerRadius: 26, material: .ultraThinMaterial, strokeOpacity: background == .dark ? 0.09 : 0.12, shadowOpacity: background == .dark ? 0.42 : 0.14)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .foregroundStyle(chromeForeground)
    }

    private func toolButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func chromeIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.thinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var settingsPanel: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                HStack {
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 38, height: 5)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showSettings = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭阅读设置")
                }
                .padding(.top, 10)
                .padding(.horizontal)

                Picker("设置", selection: $settingsTab) {
                    Text("外观").tag(0)
                    Text("排版").tag(1)
                    Text("高级").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                HStack {
                    Text(settingsTab == 0 ? "外观" : (settingsTab == 1 ? "排版" : "高级"))
                        .font(.headline)
                    Spacer()
                    Button("完成") {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showSettings = false
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch settingsTab {
                        case 0:
                            appearanceSettings
                        case 1:
                            layoutSettings
                        default:
                            advancedSettings
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 500)
            .glassPanel(cornerRadius: 28, material: .regularMaterial, strokeOpacity: colorScheme == .dark ? 0.08 : 0.12, shadowOpacity: colorScheme == .dark ? 0.35 : 0.18)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var appearanceSettings: some View {
        Group {
            appearancePreview

            Text("翻页模式")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("翻页模式", selection: $readerModeRawValue) {
                ForEach(ReaderMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)

            Text("背景颜色")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(ReaderBackground.allCases) { item in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        backgroundRawValue = item.rawValue
                    } label: {
                        Circle()
                            .fill(item.color)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Circle()
                                    .stroke(background == item ? AppTheme.accent : Color.secondary.opacity(0.25), lineWidth: background == item ? 3 : 1)
                            }
                    }
                    .accessibilityLabel(item.title)
                }
            }
        }
    }

    private var appearancePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("阅读预览")
                .font(.caption.weight(.semibold))
                .foregroundStyle(background.textColor.opacity(0.64))

            Text("夜色沉下来以后，文字应该安静、清楚、耐看。调整外观时，这里会立刻跟随字号、行距和背景变化。")
                .font(.system(size: min(fontSize, 24), weight: .regular, design: .default))
                .foregroundStyle(background.textColor)
                .lineSpacing(lineSpacing)
                .lineLimit(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(background == .dark ? 0.12 : 0.06), lineWidth: 0.8)
        }
    }

    private func readerStatusBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(background.textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(background == .dark ? 0.08 : 0.35), lineWidth: 0.8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var layoutSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            readerValueSlider("字号", value: $fontSize, range: 14...32, step: 1, unit: "pt", help: "正文文字大小，输入数值或拖动滑块")
            readerValueSlider("行高", value: $lineSpacing, range: 2...18, step: 1, unit: "pt", help: "每行文字之间的垂直间距")
            readerValueSlider("字距", value: $letterSpacing, range: 0...4, step: 0.2, unit: "pt", help: "字符之间的水平间距")
            readerValueSlider("段距", value: $paragraphSpacing, range: 8...32, step: 1, unit: "pt", help: "相邻段落之间的留白")
            readerValueSlider("段首缩进", value: $paragraphIndent, range: 0...40, step: 2, unit: "pt", help: "每段第一行向右缩进")
            readerValueSlider("标题间距", value: $titleSpacing, range: 0...36, step: 2, unit: "pt", help: "章节标题与正文之间的留白")
            readerValueSlider("左右间距", value: $pagePadding, range: 14...40, step: 1, unit: "pt", help: "正文距离屏幕左右边缘的距离")
            readerValueSlider("底部留白", value: $footerHeight, range: 48...180, step: 8, unit: "pt", help: "为底部阅读操作预留的安全空间")
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("高级设置只保留不重复的阅读辅助功能。翻页、字号和自动翻页请在阅读器主菜单调整。")
                .font(.caption)
                .foregroundStyle(.secondary)

            readerValueSlider("朗读速度", value: $ttsRate, range: 0.35...0.65, step: 0.01, unit: "倍速", help: "从当前可见段落开始朗读，不会跳回章节开头")

            Text("睡眠定时")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("睡眠定时", selection: $sleepTimerMinutes) {
                Text("关闭").tag(0)
                Text("15 分钟").tag(15)
                Text("30 分钟").tag(30)
                Text("60 分钟").tag(60)
            }
            .pickerStyle(.segmented)

            Toggle("阅读时保持屏幕常亮", isOn: $keepScreenAwake)
                .font(.subheadline.weight(.semibold))

            Toggle("允许正文文字选择", isOn: $textSelectionEnabled)
                .font(.subheadline.weight(.semibold))

            settingStepper(title: "预加载章节", value: ReaderPreloadPolicy.title(for: preloadChapterCount)) {
                preloadChapterCount = ReaderPreloadPolicy.clamp(preloadChapterCount - 1)
            } increase: {
                preloadChapterCount = ReaderPreloadPolicy.clamp(preloadChapterCount + 1)
            }

            tapZoneSettings
        }
    }

    private func readerValueSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                TextField(
                    title,
                    text: Binding(
                        get: {
                            step < 1
                                ? String(format: "%.2f", value.wrappedValue)
                                : String(format: "%.0f", value.wrappedValue)
                        },
                        set: { raw in
                            guard let parsed = Double(raw) else { return }
                            value.wrappedValue = min(max(parsed, range.lowerBound), range.upperBound)
                        }
                    )
                )
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
            Text(help)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var tapZoneSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("九宫格点击区域")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(0..<9, id: \.self) { index in
                    Menu {
                        ForEach(ReaderTapAction.allCases) { action in
                            Button(action.title) {
                                setTapZone(index: index, action: action)
                            }
                        }
                    } label: {
                        Text(tapZoneActions[index].shortTitle)
                            .font(.caption2.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(tapZoneActions[index].color.opacity(0.16))
                            .foregroundStyle(tapZoneActions[index].color)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            Button("恢复默认点击区域") {
                tapZonesRawValue = ReaderTapAction.defaultRawValue
            }
            .font(.caption.weight(.semibold))
        }
    }

    private var tapZoneOverlay: some View {
        VStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        Text(tapZoneActions[index].shortTitle)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tapZoneActions[index].color)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(tapZoneActions[index].color.opacity(0.08))
                    }
                }
            }
        }
        .padding(CGFloat(pagePadding))
    }

    private func settingStepper(
        title: String,
        value: String,
        decrease: @escaping () -> Void,
        increase: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: decrease) {
                Image(systemName: "minus.circle.fill")
            }
            Text(value)
                .font(.headline)
                .frame(width: 44)
            Button(action: increase) {
                Image(systemName: "plus.circle.fill")
            }
        }
    }

    private var chapterListSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("目录", selection: $tocTab) {
                    Text("目录").tag(0)
                    Text("书签").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 10)

                if tocTab == 0 {
                    tocList
                } else {
                    bookmarkList(includeAddButton: true)
                }
            }
            .navigationTitle(tocTab == 0 ? "目录" : "书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if tocTab == 0 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(tocReversed ? "倒序" : "顺序") {
                            tocReversed.toggle()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        showChapterList = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var tocList: some View {
        VStack(spacing: 8) {
            TextField("筛选章节名或序号", text: $tocQuery)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal)
                .padding(.top, 10)

            List {
                if chapters.isEmpty {
                    Text("当前章节没有可切换目录")
                        .foregroundStyle(.secondary)
                } else if filteredChapters.isEmpty {
                    Text("没有匹配章节")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredChapters) { chapter in
                        Button {
                            showChapterList = false
                            // Keep the reader chrome visible after a chapter
                            // switch. Hiding it here made the next reader
                            // render look like the root/home menu.
                            showOverlay = true
                            onSelectChapter?(chapter)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(chapter.index + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(chapter.index == chapterIndex ? AppTheme.accent : .secondary)
                                    .frame(width: 42, alignment: .leading)

                                Text(chapter.title)
                                    .foregroundStyle(chapter.index == chapterIndex ? AppTheme.accent : .primary)
                                    .fontWeight(chapter.index == chapterIndex ? .semibold : .regular)
                                    .lineLimit(1)

                                Spacer()
                                if chapter.index == chapterIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                        .disabled(onSelectChapter == nil || chapter.index == chapterIndex)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var bookmarkSheet: some View {
        NavigationStack {
            bookmarkList(includeAddButton: true)
            .navigationTitle("书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        showBookmarks = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func bookmarkList(includeAddButton: Bool) -> some View {
        List {
            if includeAddButton {
                Button {
                    toggleCurrentBookmark(openList: false)
                } label: {
                    Label(
                        isCurrentChapterBookmarked ? "取消当前段落书签" : "加入当前段落书签",
                        systemImage: isCurrentChapterBookmarked ? "bookmark.slash" : "bookmark"
                    )
                }
            }

            if bookmarks.isEmpty {
                Text("暂无书签")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    HStack {
                        Label("\(bookmarks.count) 个书签", systemImage: "bookmark")
                        Spacer()
                        Text("本章 \(currentChapterBookmarkCount)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold))
                }

                Section("我的书签") {
                    ForEach(sortedBookmarks) { bookmark in
                        Button {
                            jumpToBookmark(bookmark)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(bookmark.chapterTitle)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        Text(bookmarkLocationText(bookmark))
                                        Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        if isCurrentBookmark(bookmark) {
                                            Text("当前")
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AppTheme.accent.opacity(0.12))
                                                .foregroundStyle(AppTheme.accent)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(isCurrentBookmark(bookmark) ? AppTheme.accent : .secondary)
                                    Text(bookmark.snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if bookmark.chapterIndex == chapterIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.accent)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .disabled(bookmark.chapterIndex != chapterIndex && onSelectChapter == nil)
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                appState.bookshelfStore.removeBookmark(bookID: bookID, bookmarkID: bookmark.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func bookmarkLocationText(_ bookmark: ReaderBookmark) -> String {
        if let paragraphIndex = bookmark.paragraphIndex {
            return "第 \(bookmark.chapterIndex + 1) 章 · 第 \(paragraphIndex + 1) 段"
        }
        return "第 \(bookmark.chapterIndex + 1) 章"
    }

    private func isCurrentBookmark(_ bookmark: ReaderBookmark) -> Bool {
        bookmark.chapterIndex == chapterIndex
            && bookmark.paragraphIndex == currentBookmarkParagraphIndex
    }

    private func jumpToBookmark(_ bookmark: ReaderBookmark) {
        showBookmarks = false
        showOverlay = false
        if bookmark.chapterIndex == chapterIndex {
            jumpToParagraph(bookmark.paragraphIndex)
        } else {
            guard let target = chapters.first(where: { $0.index == bookmark.chapterIndex }) else { return }
            if let paragraphIndex = bookmark.paragraphIndex {
                appState.bookshelfStore.updateReadingProgress(
                    bookID: bookID,
                    chapterIndex: bookmark.chapterIndex,
                    chapterTitle: bookmark.chapterTitle,
                    totalChapters: totalChapters ?? 0,
                    paragraphIndex: paragraphIndex
                )
            }
            onSelectChapter?(target)
        }
    }

    private func jumpToParagraph(_ paragraphIndex: Int?) {
        guard let paragraphIndex else { return }
        let safeIndex = min(max(paragraphIndex, 0), max(content.paragraphs.count - 1, 0))
        visibleParagraphIndex = safeIndex
        switch readerMode {
        case .scroll:
            autoScrollTarget = safeIndex
            paragraphJumpRequest = ParagraphJumpRequest(index: safeIndex)
        case .pageTurn, .cover:
            autoScrollTarget = pageIndex(containingParagraph: safeIndex)
        }
        persistReadingPosition(paragraphIndexOverride: safeIndex)
    }

    private func canSelectRelativeChapter(offset: Int) -> Bool {
        guard onSelectChapter != nil else { return false }
        return chapters.contains { $0.index == chapterIndex + offset }
    }

    private func selectRelativeChapter(offset: Int) {
        guard let target = chapters.first(where: { $0.index == chapterIndex + offset }) else { return }
        showSettings = false
        showOverlay = false
        stopAutoScroll()
        speechController.stop()
        onSelectChapter?(target)
    }

    private func handleReaderTap(at location: CGPoint) {
        guard !showSettings else { return }
        let size = UIScreen.main.bounds.size
        let column = min(max(Int(location.x / max(size.width / 3, 1)), 0), 2)
        let row = min(max(Int(location.y / max(size.height / 3, 1)), 0), 2)
        let index = row * 3 + column
        let actions = tapZoneActions
        guard actions.indices.contains(index) else {
            toggleOverlay()
            return
        }
        runTapAction(actions[index])
    }

    private func runTapAction(_ action: ReaderTapAction) {
        switch action {
        case .previousPage:
            moveReaderTarget(to: autoScrollTarget - 1)
        case .nextPage:
            moveReaderTarget(to: autoScrollTarget + 1)
        case .previousChapter:
            selectRelativeChapter(offset: -1)
        case .nextChapter:
            selectRelativeChapter(offset: 1)
        case .menu:
            toggleOverlay()
        case .disabled:
            break
        }
    }

    private func moveReaderTarget(to rawTarget: Int) {
        let target = min(max(rawTarget, 0), maximumReaderTarget)
        autoScrollTarget = target
        let resolvedParagraphIndex: Int
        switch readerMode {
        case .scroll:
            resolvedParagraphIndex = min(target, max(content.paragraphs.count - 1, 0))
        case .pageTurn, .cover:
            resolvedParagraphIndex = paragraphIndex(forPage: target)
        }
        visibleParagraphIndex = resolvedParagraphIndex
        scheduleReadingPositionPersistence(paragraphIndex: resolvedParagraphIndex)
    }

    private func toggleOverlay() {
        withAnimation(.easeOut(duration: 0.2)) {
            showOverlay.toggle()
            if !showOverlay {
                showSettings = false
            }
        }
    }

    private func setTapZone(index: Int, action: ReaderTapAction) {
        var actions = tapZoneActions
        guard actions.indices.contains(index) else { return }
        actions[index] = action
        if !actions.contains(.menu) {
            actions[4] = .menu
        }
        tapZonesRawValue = ReaderTapAction.encode(actions)
    }

    private func toggleCurrentBookmark(openList: Bool = true) {
        let paragraphIndex = currentBookmarkParagraphIndex
        let snippet = content.paragraphs.indices.contains(paragraphIndex)
            ? content.paragraphs[paragraphIndex]
            : content.title
        appState.bookshelfStore.toggleBookmark(
            bookID: bookID,
            chapterIndex: chapterIndex,
            chapterTitle: content.title,
            paragraphIndex: paragraphIndex,
            snippet: snippet
        )
        if openList {
            showBookmarks = true
        }
    }

    private func toggleSpeech() {
        if speechController.isPaused {
            speechController.resume()
            playbackCoordinator.resumeSpeech()
            speechPausedForScene = false
        } else if speechController.isSpeaking {
            speechController.pause()
            playbackCoordinator.pauseSpeech()
        } else {
            beginSpeechPlayback()
        }
    }

    private func beginSpeechPlayback() {
        stopAutoScroll()
        let coordinator = playbackCoordinator
        let token = coordinator.beginSpeech()
        speechController.onFinished = { [onSpeechFinished] in
            guard let onSpeechFinished else { return }
            Task { @MainActor in
                guard coordinator.accepts(token, for: .speech(generation: token)) else { return }
                coordinator.stop()
                onSpeechFinished()
            }
        }
        speechPausedForScene = false
        speechController.speak(
            title: content.title,
            paragraphs: content.paragraphs,
            startParagraphIndex: currentParagraphIndexForPersistence(),
            includeTitle: false,
            rate: Float(ttsRate)
        )
    }

    private func toggleAutoScroll() {
        if autoScrollEnabled {
            stopAutoScroll()
        } else {
            speechController.stop()
            speechPausedForScene = false
            startAutoScroll()
        }
    }

    private func startAutoScroll() {
        stopAutoScroll()
        autoScrollEnabled = true
        autoScrollTarget = min(max(autoScrollTarget, 0), maximumReaderTarget)
        let delay = autoScrollDelay
        let coordinator = playbackCoordinator
        let token = coordinator.beginAutoScroll()
        autoScrollTask = Task { [weak coordinator] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    guard let coordinator,
                          coordinator.accepts(token, for: .autoScroll(generation: token)),
                          autoScrollEnabled else { return }
                    switch ReaderAutomationPolicy.decision(
                        currentTarget: autoScrollTarget,
                        maximumTarget: maximumReaderTarget,
                        canAdvanceChapter: canSelectRelativeChapter(offset: 1)
                    ) {
                    case .advance(let target):
                        autoScrollTarget = target
                    case .nextChapter:
                        stopAutoScroll()
                        selectRelativeChapter(offset: 1)
                    case .stop:
                        stopAutoScroll()
                    }
                }
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollEnabled = false
        autoScrollTask?.cancel()
        autoScrollTask = nil
        if case .autoScroll = playbackCoordinator.mode {
            playbackCoordinator.stop()
        }
    }

    private func scheduleSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        guard sleepTimerMinutes > 0 else { return }
        let duration = UInt64(sleepTimerMinutes) * 60 * 1_000_000_000
        sleepTimerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else { return }
            stopAutoScroll()
            speechController.stop()
            sleepTimerMinutes = 0
            appState.record(DiagnosticEvent(level: .info, stage: "reader.sleepTimer", sourceName: content.title, message: "睡眠定时已结束"))
            sleepTimerTask = nil
        }
    }

    private func applyIdleTimerPreference() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
    }

    private func restoreIdleTimerPreference() {
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
    }

    private func updateVisibleParagraph(from positions: [ParagraphPosition]) {
        guard readerMode == .scroll, !autoScrollEnabled, !positions.isEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastVisibleParagraphUpdateAt) >= ReaderPerformancePolicy.visibleParagraphUpdateInterval else {
            return
        }
        lastVisibleParagraphUpdateAt = now
        let topInset = CGFloat(pagePadding)
        let visible = positions
            .filter { $0.minY >= topInset }
            .min { $0.minY < $1.minY }
            ?? positions
                .filter { $0.minY < topInset }
                .max { $0.minY < $1.minY }
        guard let index = visible?.index,
              index != visibleParagraphIndex,
              content.paragraphs.indices.contains(index) else { return }
        visibleParagraphIndex = index
        scheduleReadingPositionPersistence(paragraphIndex: index)
    }

    private func initialAutoScrollTarget() -> Int {
        guard let stored = appState.bookshelfStore.book(id: bookID),
              stored.currentChapterIndex == chapterIndex,
              let paragraphIndex = stored.currentParagraphIndex else {
            return 0
        }
        let safeParagraph = min(max(paragraphIndex, 0), max(content.paragraphs.count - 1, 0))
        visibleParagraphIndex = safeParagraph
        switch readerMode {
        case .scroll:
            return safeParagraph
        case .pageTurn, .cover:
            return pageIndex(containingParagraph: safeParagraph)
        }
    }

    private func persistReadingPosition(paragraphIndexOverride: Int? = nil) {
        let paragraphIndex: Int
        if let paragraphIndexOverride {
            paragraphIndex = min(max(paragraphIndexOverride, 0), max(content.paragraphs.count - 1, 0))
        } else {
            paragraphIndex = currentParagraphIndexForPersistence()
        }
        appState.bookshelfStore.updateReadingProgress(
            bookID: bookID,
            chapterIndex: chapterIndex,
            chapterTitle: content.title,
            totalChapters: totalChapters ?? 0,
            paragraphIndex: paragraphIndex
        )
    }

    private func scheduleReadingPositionPersistence(paragraphIndex: Int) {
        positionPersistTask?.cancel()
        positionPersistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ReaderPerformancePolicy.positionPersistenceDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            persistReadingPosition(paragraphIndexOverride: paragraphIndex)
            positionPersistTask = nil
        }
    }

    private func currentParagraphIndexForPersistence() -> Int {
        guard !content.paragraphs.isEmpty else { return 0 }
        switch readerMode {
        case .scroll:
            return min(max(visibleParagraphIndex, 0), content.paragraphs.count - 1)
        case .pageTurn, .cover:
            return paragraphIndex(forPage: autoScrollTarget)
        }
    }

    private func updatePagedVisibleParagraph(pageIndex: Int) {
        guard readerMode != .scroll, !content.paragraphs.isEmpty else { return }
        let paragraphIndex = paragraphIndex(forPage: pageIndex)
        guard paragraphIndex != visibleParagraphIndex else { return }
        visibleParagraphIndex = paragraphIndex
        scheduleReadingPositionPersistence(paragraphIndex: paragraphIndex)
    }

    private func paragraphIndex(forPage pageIndex: Int) -> Int {
        guard !content.paragraphs.isEmpty else { return 0 }
        let pages = pagedBlocks
        guard !pages.isEmpty else { return 0 }
        let safePage = min(max(pageIndex, 0), pages.count - 1)
        return pages[safePage].firstParagraphIndex ?? 0
    }

    private func pageIndex(containingParagraph paragraphIndex: Int) -> Int {
        let pages = pagedBlocks
        guard !pages.isEmpty else { return 0 }
        let safeParagraph = min(max(paragraphIndex, 0), max(content.paragraphs.count - 1, 0))
        if let match = pages.first(where: { page in
            guard let first = page.firstParagraphIndex, let last = page.lastParagraphIndex else {
                return false
            }
            return safeParagraph >= first && safeParagraph <= last
        }) {
            return match.id
        }
        return min(max(safeParagraph, 0), pages.count - 1)
    }

    private func rebuildPagedBlocksCache() {
        pagedBlocksCache = buildReaderPageBlocks()
        pagedBlocksCacheKey = readerPageCacheKey
    }

    private func buildReaderPageBlocks() -> [ReaderPageBlock] {
        let signpost = PerformanceSignpost.begin("reader.layout")
        defer { PerformanceSignpost.end("reader.layout", id: signpost) }
        guard !content.paragraphs.isEmpty else {
            return [ReaderPageBlock(id: 0, includesTitle: true, paragraphs: [])]
        }

        let screen = UIScreen.main.bounds.size
        let screenWidth = Double(screen.width)
        let screenHeight = Double(screen.height)
        let availableWidth = max(screenWidth - pagePadding * 2, 260)
        let availableHeight = max(screenHeight - pagePadding * 2 - footerHeight - 70, 360)
        let charWidth = max(fontSize * 0.56 + letterSpacing, 7)
        let lineHeight = max(fontSize + lineSpacing, 18)
        let charsPerLine = max(Int(availableWidth / charWidth), 10)
        let linesPerPage = max(Int(availableHeight / lineHeight), 8)
        let pageBudget = max(charsPerLine * linesPerPage, 220)
        let paragraphBreakCost = max(charsPerLine / 2, 10)
        let titleCost = max(charsPerLine * 3, 90)

        var pages: [ReaderPageBlock] = []
        var currentEntries: [ReaderPageEntry] = []
        var currentCost = titleCost
        var currentIncludesTitle = true

        func flush() {
            pages.append(
                ReaderPageBlock(
                    id: pages.count,
                    includesTitle: currentIncludesTitle,
                    paragraphs: currentEntries
                )
            )
            currentEntries = []
            currentCost = 0
            currentIncludesTitle = false
        }

        for (index, paragraph) in content.paragraphs.enumerated() {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            let charCount = max(trimmed.count, 1)
            let lineCount = max(Int(ceil(Double(charCount) / Double(charsPerLine))), 1)
            let cost = lineCount * charsPerLine + paragraphBreakCost
            if !currentEntries.isEmpty && currentCost + cost > pageBudget {
                flush()
            }
            currentEntries.append(ReaderPageEntry(index: index, text: paragraph))
            currentCost += cost
            if cost >= pageBudget, !currentEntries.isEmpty {
                flush()
            }
        }

        if currentIncludesTitle || !currentEntries.isEmpty {
            flush()
        }
        return pages
    }
}

private struct ParagraphPosition: Equatable {
    let index: Int
    let minY: CGFloat
}

private struct ParagraphPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [ParagraphPosition] = []

    static func reduce(value: inout [ParagraphPosition], nextValue: () -> [ParagraphPosition]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ParagraphJumpRequest: Equatable {
    let id = UUID()
    let index: Int
}

private struct ReaderPageEntry: Equatable {
    let index: Int
    let text: String
}

private struct ReaderPageBlock: Identifiable, Equatable {
    let id: Int
    let includesTitle: Bool
    let paragraphs: [ReaderPageEntry]

    var firstParagraphIndex: Int? {
        paragraphs.first?.index
    }

    var lastParagraphIndex: Int? {
        paragraphs.last?.index
    }
}

private extension View {
    @ViewBuilder
    func readerSelectableText(_ enabled: Bool) -> some View {
        if enabled {
            textSelection(.enabled)
        } else {
            self
        }
    }
}

final class ReaderSpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentParagraphIndex = -1

    private let synthesizer = AVSpeechSynthesizer()
    private var queue = ReaderSpeechQueue()
    private var rate: Float = 0.52
    private var activeUtterance: AVSpeechUtterance?
    var onFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        title: String,
        paragraphs: [String],
        startParagraphIndex: Int = 0,
        includeTitle: Bool = true,
        rate: Float
    ) {
        stop(clearCompletion: false)
        queue.reset(
            title: title,
            paragraphs: paragraphs,
            startParagraphIndex: startParagraphIndex,
            includeTitle: includeTitle
        )
        self.rate = rate
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        isSpeaking = true
        isPaused = false
        speakNext()
    }

    func pause() {
        guard isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        guard isSpeaking else { return }
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
        isPaused = false
    }

    func stop() {
        stop(clearCompletion: true)
    }

    private func stop(clearCompletion: Bool) {
        synthesizer.stopSpeaking(at: .immediate)
        activeUtterance = nil
        if clearCompletion {
            onFinished = nil
        }
        isSpeaking = false
        isPaused = false
        currentParagraphIndex = -1
        queue.clear()
    }

    private func speakNext() {
        guard let segment = queue.dequeue() else {
            let completion = onFinished
            onFinished = nil
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            isPaused = false
            currentParagraphIndex = -1
            queue.clear()
            completion?()
            return
        }
        currentParagraphIndex = segment.index
        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = rate
        activeUtterance = utterance
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.isSpeaking, self.activeUtterance === utterance else { return }
            self.activeUtterance = nil
            self.speakNext()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            self.activeUtterance = nil
            self.isSpeaking = false
            self.isPaused = false
            self.currentParagraphIndex = -1
            self.queue.clear()
            self.onFinished = nil
        }
    }
}

private enum ReaderBackground: String, CaseIterable, Identifiable {
    case paper
    case green
    case gray
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return "纸张"
        case .green: return "护眼"
        case .gray: return "浅灰"
        case .dark: return "深色"
        }
    }

    var color: Color {
        switch self {
        case .paper: return Color(red: 0.96, green: 0.93, blue: 0.86)
        case .green: return Color(red: 0.88, green: 0.94, blue: 0.86)
        case .gray: return Color(.systemGray6)
        case .dark: return Color(red: 0.12, green: 0.12, blue: 0.13)
        }
    }

    var textColor: Color {
        switch self {
        case .dark: return .white.opacity(0.9)
        default: return .primary
        }
    }
}
