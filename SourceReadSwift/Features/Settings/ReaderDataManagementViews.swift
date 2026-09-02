import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BookshelfBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var snapshot: BookshelfBackupSnapshot

    init(snapshot: BookshelfBackupSnapshot) {
        self.snapshot = snapshot
    }

    init(configuration: ReadConfiguration) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshot = try decoder.decode(BookshelfBackupSnapshot.self, from: configuration.file.regularFileContents ?? Data())
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(snapshot))
    }
}

struct ReaderBookmarksView: View {
    @EnvironmentObject private var appState: AppState

    private var sections: [BookmarkSection] {
        appState.bookshelfStore.books.compactMap { book in
            let bookmarks = (book.bookmarks ?? []).sorted { $0.createdAt > $1.createdAt }
            return bookmarks.isEmpty ? nil : BookmarkSection(book: book, bookmarks: bookmarks)
        }
    }

    var body: some View {
        List {
            if sections.isEmpty {
                emptyState(title: "暂无书签", systemImage: "bookmark", message: "阅读时在工具栏加入书签，它们会集中显示在这里。")
            } else {
                ForEach(sections) { section in
                    Section(section.book.title) {
                        ForEach(section.bookmarks) { bookmark in
                            NavigationLink {
                                BookshelfReaderGatewayView(book: section.book, initialBookmark: bookmark)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(bookmark.chapterTitle)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(locationText(bookmark))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                    Text(bookmark.snippet.isEmpty ? "无摘录" : bookmark.snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    appState.bookshelfStore.removeBookmark(bookID: section.book.id, bookmarkID: bookmark.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("书签")
        .listStyle(.insetGrouped)
    }

    private struct BookmarkSection: Identifiable {
        let book: BookshelfBook
        let bookmarks: [ReaderBookmark]
        var id: String { book.id }
    }

    private func locationText(_ bookmark: ReaderBookmark) -> String {
        if let paragraph = bookmark.paragraphIndex {
            return "第 \(bookmark.chapterIndex + 1) 章 · 第 \(paragraph + 1) 段 · \(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "第 \(bookmark.chapterIndex + 1) 章 · \(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func emptyState(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .listRowBackground(Color.clear)
    }
}

struct OfflineChapterCacheView: View {
    @EnvironmentObject private var appState: AppState

    private var grouped: [CacheSection] {
        let map = Dictionary(grouping: appState.chapterContentCacheStore.entries, by: \.bookURL)
        return map.keys.sorted().map { CacheSection(bookURL: $0, entries: map[$0]!.sorted { $0.cachedAt > $1.cachedAt }) }
    }

    var body: some View {
        List {
            if grouped.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("暂无离线章节").font(.headline)
                    Text("在阅读器目录中缓存章节后，可在无网络时继续阅读。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .listRowBackground(Color.clear)
            } else {
                ForEach(grouped) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            let cachedBook = appState.bookshelfStore.books.first(where: {
                                $0.bookURL == entry.bookURL && $0.sourceURL == entry.sourceURL
                            })
                            Group {
                                if let cachedBook {
                                    NavigationLink {
                                        BookshelfReaderGatewayView(
                                            book: cachedBook,
                                            initialChapterIndex: entry.chapterIndex
                                                ?? Int(entry.chapterURL.split(separator: "#").last ?? "")
                                                ?? 0
                                        )
                                    } label: {
                                        cacheRow(entry)
                                    }
                                } else {
                                    cacheRow(entry)
                                }
                            }
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    appState.chapterContentCacheStore.remove(key: entry.key)
                                }
                            }
                        }
                    } header: {
                        Text(bookTitle(for: section.bookURL))
                    } footer: {
                        Text("\(section.entries.count) 章 · \(byteText(section.entries.reduce(0) { $0 + $1.estimatedByteCount }))")
                    }
                }
            }
        }
        .navigationTitle("离线章节")
        .listStyle(.insetGrouped)
    }

    private struct CacheSection: Identifiable {
        let bookURL: String
        let entries: [ChapterContentCacheEntry]
        var id: String { bookURL }
    }

    private func bookTitle(for bookURL: String) -> String {
        appState.bookshelfStore.books.first(where: { $0.bookURL == bookURL })?.title ?? bookURL
    }

    private func byteText(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    private func cacheRow(_ entry: ChapterContentCacheEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(1)
            Text("\(entry.paragraphs.count) 段 · \(entry.cachedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if appState.bookshelfStore.books.contains(where: {
                $0.bookURL == entry.bookURL && $0.sourceURL == entry.sourceURL
            }) {
                Text("点击继续阅读")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }
}
