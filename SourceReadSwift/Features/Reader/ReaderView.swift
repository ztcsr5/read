import AVFoundation
import SwiftUI
import UIKit

struct ReaderView: View {
    @EnvironmentObject private var appState: AppState
    let bookID: String
    let content: ChapterContent
    let chapterIndex: Int
    let totalChapters: Int?
    var chapters: [BookChapter] = []
    var statusMessage: String?
    var extraToolbarActions: () -> AnyView = { AnyView(EmptyView()) }
    var onSelectChapter: ((BookChapter) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showOverlay = false
    @State private var showSettings = false
    @State private var showChapterList = false
    @State private var showBookmarks = false
    @State private var settingsTab = 0
    @State private var autoScrollEnabled = false
    @State private var autoScrollTarget = 0
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var positionPersistTask: Task<Void, Never>?
    @State private var paragraphJumpRequest: ParagraphJumpRequest?
    @State private var sessionStartedAt = Date()
    @State private var previousIdleTimerDisabled = false
    @State private var visibleParagraphIndex = 0
    @StateObject private var speechController = ReaderSpeechController()
    @AppStorage("reader.fontSize") private var fontSize: Double = 20
    @AppStorage("reader.lineSpacing") private var lineSpacing: Double = 8
    @AppStorage("reader.pagePadding") private var pagePadding: Double = 24
    @AppStorage("reader.letterSpacing") private var letterSpacing: Double = 0
    @AppStorage("reader.paragraphSpacing") private var paragraphSpacing: Double = 16
    @AppStorage("reader.paragraphIndent") private var paragraphIndent: Double = 0
    @AppStorage("reader.titleSpacing") private var titleSpacing: Double = 12
    @AppStorage("reader.footerHeight") private var footerHeight: Double = 120
    @AppStorage("reader.ttsRate") private var ttsRate: Double = 0.52
    @AppStorage("reader.autoScrollDelay") private var autoScrollDelay: Double = 2.0
    @AppStorage("reader.background") private var backgroundRawValue: String = ReaderBackground.paper.rawValue
    @AppStorage("reader.mode") private var readerModeRawValue: String = ReaderMode.scroll.rawValue
    @AppStorage("reader.tapZones") private var tapZonesRawValue: String = ReaderTapAction.defaultRawValue
    @AppStorage("reader.keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("reader.preloadChapterCount") private var preloadChapterCount = ReaderPreloadPolicy.defaultCount

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

    private var isCurrentChapterBookmarked: Bool {
        appState.bookshelfStore.isBookmarked(
            bookID: bookID,
            chapterIndex: chapterIndex,
            paragraphIndex: currentBookmarkParagraphIndex
        )
    }

    private var currentBookmarkParagraphIndex: Int {
        switch readerMode {
        case .scroll:
            return min(max(visibleParagraphIndex, 0), max(content.paragraphs.count - 1, 0))
        case .pageTurn, .cover:
            return min(max(autoScrollTarget - 1, 0), max(content.paragraphs.count - 1, 0))
        }
    }

    private var progressTitle: String {
        guard let totalChapters, totalChapters > 0 else {
            return "第 \(chapterIndex + 1) 章"
        }
        let percentage = Int((Double(chapterIndex + 1) / Double(totalChapters) * 100).rounded())
        return "第 \(chapterIndex + 1) / \(totalChapters) 章 · \(percentage)%"
    }

    private var maximumReaderTarget: Int {
        switch readerMode {
        case .scroll:
            return max(content.paragraphs.count - 1, 0)
        case .pageTurn, .cover:
            return max(content.paragraphs.count, 0)
        }
    }

    var body: some View {
        ZStack {
            background.color.ignoresSafeArea()

            readerContent
            .contentShape(Rectangle())
            .gesture(
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
                    .transition(.opacity)
            }

            if let statusMessage {
                readerStatusBanner(message: statusMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showSettings {
                settingsPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showChapterList) {
            chapterListSheet
        }
        .sheet(isPresented: $showBookmarks) {
            bookmarkSheet
        }
        .onAppear {
            sessionStartedAt = Date()
            autoScrollTarget = initialAutoScrollTarget()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            applyIdleTimerPreference()
            appState.bookshelfStore.markReaderOpened(bookID: bookID)
            persistReadingPosition()
        }
        .onDisappear {
            positionPersistTask?.cancel()
            persistReadingPosition(paragraphIndexOverride: visibleParagraphIndex)
            stopAutoScroll()
            speechController.stop()
            restoreIdleTimerPreference()
            appState.bookshelfStore.recordReadingSession(
                bookID: bookID,
                duration: Date().timeIntervalSince(sessionStartedAt)
            )
        }
        .onChange(of: keepScreenAwake) { _ in
            applyIdleTimerPreference()
        }
        .onChange(of: autoScrollTarget) { _ in
            persistReadingPosition()
        }
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
                        .font(.system(size: fontSize + 8, weight: .bold, design: .serif))
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
                withAnimation(.easeInOut(duration: 0.45)) {
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
                persistReadingPosition(paragraphIndexOverride: target)
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

    private var pagedReaderContent: some View {
        TabView(selection: $autoScrollTarget) {
            VStack(alignment: .leading, spacing: 18) {
                Text(content.title)
                    .font(.system(size: fontSize + 8, weight: .bold, design: .serif))
                    .foregroundStyle(background.textColor)
                Text("第 \(chapterIndex + 1) 章")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(CGFloat(pagePadding))
            .tag(0)

            ForEach(content.paragraphs.indices, id: \.self) { index in
                ScrollView {
                    paragraphText(content.paragraphs[index], index: index)
                        .padding(CGFloat(pagePadding))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tag(index + 1)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(readerMode == .cover ? .easeInOut(duration: 0.2) : nil, value: autoScrollTarget)
        .onChange(of: speechController.currentParagraphIndex) { target in
            guard target >= 0 else { return }
            autoScrollTarget = target + 1
        }
    }

    private func paragraphText(_ paragraph: String, index: Int) -> some View {
        Text(paragraph)
            .font(.system(size: fontSize, weight: .regular, design: .serif))
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
        switch content.paragraphs.count {
        case 0...180:
            return 1
        case 181...600:
            return 3
        case 601...1_500:
            return 5
        default:
            return 8
        }
    }

    private var readerOverlay: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }

                Text(content.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                extraToolbarActions()

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .background(.ultraThinMaterial)

            Spacer()

            VStack(spacing: 10) {
                HStack {
                    toolButton(icon: "chevron.left", title: "上一章") {
                        selectRelativeChapter(offset: -1)
                    }
                    .disabled(!canSelectRelativeChapter(offset: -1))

                    Text(progressTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)

                    toolButton(icon: "chevron.right", title: "下一章") {
                        selectRelativeChapter(offset: 1)
                    }
                    .disabled(!canSelectRelativeChapter(offset: 1))
                }

                HStack {

                    toolButton(icon: "list.bullet", title: "目录") {
                        showChapterList = true
                        showSettings = false
                    }
                    toolButton(icon: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark", title: "书签") {
                        toggleCurrentBookmark()
                        showSettings = false
                    }
                    toolButton(icon: speechController.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2", title: speechController.isSpeaking ? "暂停" : "朗读") {
                        toggleSpeech()
                        showSettings = false
                    }
                    toolButton(icon: autoScrollEnabled ? "pause.fill" : "play.fill", title: autoScrollEnabled ? "暂停" : "自动") {
                        toggleAutoScroll()
                        showSettings = false
                    }
                    toolButton(icon: "gearshape", title: "设置") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showSettings.toggle()
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 22)
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(.primary)
    }

    private func toolButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .buttonStyle(.plain)
    }

    private var settingsPanel: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)

                Picker("设置", selection: $settingsTab) {
                    Text("外观").tag(0)
                    Text("排版").tag(1)
                    Text("高级").tag(2)
                }
                .pickerStyle(.segmented)
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
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: -5)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var appearanceSettings: some View {
        Group {
            Text("字号大小")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(value: $fontSize, in: 14...32, step: 1)

            Text("背景颜色")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(ReaderBackground.allCases) { item in
                    Button {
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
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 18)
            .padding(.top, 12)

            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var layoutSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingStepper(title: "字号", value: String(format: "%.0f", fontSize)) {
                fontSize = max(14, fontSize - 1)
            } increase: {
                fontSize = min(32, fontSize + 1)
            }

            Text("行高")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(value: $lineSpacing, in: 2...18, step: 1)

            Text("字距")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(value: $letterSpacing, in: 0...4, step: 0.2)

            Text("段距")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(value: $paragraphSpacing, in: 8...32, step: 1)

            Text("段首缩进")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(value: $paragraphIndent, in: 0...40, step: 2)

            Text("标题间距")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(value: $titleSpacing, in: 0...36, step: 2)

            Text("左右间距")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(value: $pagePadding, in: 14...40, step: 1)

            Text("底部留白")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(value: $footerHeight, in: 80...180, step: 10)
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("阅读模式")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("阅读模式", selection: $readerModeRawValue) {
                ForEach(ReaderMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text("朗读速度")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(value: $ttsRate, in: 0.35...0.65, step: 0.01)

            Text("自动滚动间隔")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(value: $autoScrollDelay, in: 0.8...5.0, step: 0.2)

            Toggle("阅读时保持屏幕常亮", isOn: $keepScreenAwake)
                .font(.subheadline.weight(.semibold))

            settingStepper(title: "预加载章节", value: ReaderPreloadPolicy.title(for: preloadChapterCount)) {
                preloadChapterCount = ReaderPreloadPolicy.clamp(preloadChapterCount - 1)
            } increase: {
                preloadChapterCount = ReaderPreloadPolicy.clamp(preloadChapterCount + 1)
            }

            HStack(spacing: 12) {
                Button(autoScrollEnabled ? "停止自动滚动" : "开始自动滚动") {
                    toggleAutoScroll()
                }
                .buttonStyle(.borderedProminent)

                Button(speechController.isSpeaking ? "停止朗读" : "开始朗读") {
                    toggleSpeech()
                }
                .buttonStyle(.bordered)
            }

            tapZoneSettings
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
            List {
                if chapters.isEmpty {
                    Text("当前章节没有可切换目录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(chapters) { chapter in
                        Button {
                            showChapterList = false
                            showOverlay = false
                            onSelectChapter?(chapter)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chapter.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text("第 \(chapter.index + 1) 章")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        showChapterList = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var bookmarkSheet: some View {
        NavigationStack {
            List {
                Button {
                    toggleCurrentBookmark()
                } label: {
                    Label(
                        isCurrentChapterBookmarked ? "取消当前段落书签" : "加入当前段落书签",
                        systemImage: isCurrentChapterBookmarked ? "bookmark.slash" : "bookmark"
                    )
                }

                if bookmarks.isEmpty {
                    Text("暂无书签")
                        .foregroundStyle(.secondary)
                } else {
                    Section("我的书签") {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                jumpToBookmark(bookmark)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(bookmark.chapterTitle)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        if let paragraphIndex = bookmark.paragraphIndex {
                                            Text("第 \(paragraphIndex + 1) 段")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(AppTheme.accent)
                                        }
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
            autoScrollTarget = min(safeIndex + 1, maximumReaderTarget)
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
            autoScrollTarget = max(0, autoScrollTarget - 1)
        case .nextPage:
            autoScrollTarget = min(maximumReaderTarget, autoScrollTarget + 1)
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

    private func toggleCurrentBookmark() {
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
        showBookmarks = true
    }

    private func toggleSpeech() {
        if speechController.isSpeaking {
            speechController.stop()
        } else {
            stopAutoScroll()
            speechController.speak(title: content.title, paragraphs: content.paragraphs, rate: Float(ttsRate))
        }
    }

    private func toggleAutoScroll() {
        if autoScrollEnabled {
            stopAutoScroll()
        } else {
            speechController.stop()
            startAutoScroll()
        }
    }

    private func startAutoScroll() {
        stopAutoScroll()
        autoScrollEnabled = true
        autoScrollTarget = 0
        let delay = autoScrollDelay
        let maxIndex = maximumReaderTarget
        autoScrollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    guard autoScrollEnabled else { return }
                    if autoScrollTarget >= maxIndex {
                        stopAutoScroll()
                    } else {
                        autoScrollTarget += 1
                    }
                }
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollEnabled = false
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    private func applyIdleTimerPreference() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
    }

    private func restoreIdleTimerPreference() {
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
    }

    private func updateVisibleParagraph(from positions: [ParagraphPosition]) {
        guard readerMode == .scroll, !autoScrollEnabled, !positions.isEmpty else { return }
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
            return min(safeParagraph + 1, maximumReaderTarget)
        }
    }

    private func persistReadingPosition(paragraphIndexOverride: Int? = nil) {
        let paragraphIndex: Int
        if let paragraphIndexOverride {
            paragraphIndex = min(max(paragraphIndexOverride, 0), max(content.paragraphs.count - 1, 0))
        } else {
            switch readerMode {
            case .scroll:
                paragraphIndex = min(max(autoScrollTarget, 0), max(content.paragraphs.count - 1, 0))
            case .pageTurn, .cover:
                paragraphIndex = min(max(autoScrollTarget - 1, 0), max(content.paragraphs.count - 1, 0))
            }
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
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            persistReadingPosition(paragraphIndexOverride: paragraphIndex)
            positionPersistTask = nil
        }
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

final class ReaderSpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    @Published var currentParagraphIndex = -1

    private let synthesizer = AVSpeechSynthesizer()
    private var paragraphs: [String] = []
    private var nextIndex = 0
    private var rate: Float = 0.52

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(title: String, paragraphs: [String], rate: Float) {
        stop()
        self.paragraphs = [title] + paragraphs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.nextIndex = 0
        self.rate = rate
        isSpeaking = true
        speakNext()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentParagraphIndex = -1
        paragraphs = []
        nextIndex = 0
    }

    private func speakNext() {
        guard nextIndex < paragraphs.count else {
            stop()
            return
        }
        currentParagraphIndex = nextIndex - 1
        let utterance = AVSpeechUtterance(string: paragraphs[nextIndex])
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = rate
        nextIndex += 1
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard isSpeaking else { return }
        speakNext()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        currentParagraphIndex = -1
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
