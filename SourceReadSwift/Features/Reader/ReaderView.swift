import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var appState: AppState
    let bookID: String
    let content: ChapterContent
    let chapterIndex: Int
    let totalChapters: Int?
    var chapters: [BookChapter] = []
    var onSelectChapter: ((BookChapter) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showOverlay = false
    @State private var showSettings = false
    @State private var showChapterList = false
    @State private var showBookmarks = false
    @AppStorage("reader.fontSize") private var fontSize: Double = 20
    @AppStorage("reader.lineSpacing") private var lineSpacing: Double = 8
    @AppStorage("reader.pagePadding") private var pagePadding: Double = 24
    @AppStorage("reader.background") private var backgroundRawValue: String = ReaderBackground.paper.rawValue

    private var background: ReaderBackground {
        ReaderBackground(rawValue: backgroundRawValue) ?? .paper
    }

    private var bookmarks: [ReaderBookmark] {
        appState.bookshelfStore.book(id: bookID)?.bookmarks ?? []
    }

    private var isCurrentChapterBookmarked: Bool {
        appState.bookshelfStore.isBookmarked(bookID: bookID, chapterIndex: chapterIndex)
    }

    var body: some View {
        ZStack {
            background.color.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(content.title)
                        .font(.system(size: fontSize + 8, weight: .bold, design: .serif))
                        .foregroundStyle(background.textColor)
                        .padding(.bottom, 12)

                    ForEach(Array(content.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.system(size: fontSize, weight: .regular, design: .serif))
                            .foregroundStyle(background.textColor)
                            .lineSpacing(lineSpacing)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(CGFloat(pagePadding))
                .padding(.bottom, 120)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) {
                    showOverlay.toggle()
                    if !showOverlay {
                        showSettings = false
                    }
                }
            }

            if showOverlay {
                readerOverlay
                    .transition(.opacity)
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
            appState.bookshelfStore.updateReadingProgress(
                bookID: bookID,
                chapterIndex: chapterIndex,
                chapterTitle: content.title,
                totalChapters: totalChapters ?? 0
            )
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
                Text("当前章节")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    toolButton(icon: "list.bullet", title: "目录") {
                        showChapterList = true
                        showSettings = false
                    }
                    toolButton(icon: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark", title: "书签") {
                        toggleCurrentBookmark()
                        showSettings = false
                    }
                    toolButton(icon: "speaker.wave.2", title: "朗读") {
                        showSettings = false
                    }
                    toolButton(icon: "play", title: "自动") {
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

                Picker("设置", selection: .constant(0)) {
                    Text("外观").tag(0)
                    Text("排版").tag(1)
                    Text("高级").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 14) {
                    Text("字号大小")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Slider(value: $fontSize, in: 14...32, step: 1)

                    Text("行高")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Slider(value: $lineSpacing, in: 2...18, step: 1)

                    Text("左右间距")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Slider(value: $pagePadding, in: 14...40, step: 1)

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
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 390)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: -5)
        }
        .ignoresSafeArea(edges: .bottom)
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
                        isCurrentChapterBookmarked ? "取消当前章节书签" : "加入当前章节书签",
                        systemImage: isCurrentChapterBookmarked ? "bookmark.slash" : "bookmark"
                    )
                }

                if bookmarks.isEmpty {
                    Text("暂无书签")
                        .foregroundStyle(.secondary)
                } else {
                    Section("我的书签") {
                        ForEach(bookmarks) { bookmark in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(bookmark.chapterTitle)
                                    .font(.headline)
                                Text(bookmark.snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
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

    private func toggleCurrentBookmark() {
        appState.bookshelfStore.toggleBookmark(
            bookID: bookID,
            chapterIndex: chapterIndex,
            chapterTitle: content.title,
            snippet: content.paragraphs.first ?? content.title
        )
        showBookmarks = true
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
