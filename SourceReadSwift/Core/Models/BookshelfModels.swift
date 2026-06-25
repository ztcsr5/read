import Foundation

struct BookshelfBook: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var author: String
    var coverURL: String?
    var sourceName: String
    var sourceURL: String
    var bookURL: String
    var intro: String?
    var localContent: [String]?
    var localChapters: [LocalTextChapter]?
    var latestChapterTitle: String?
    var totalChapters: Int
    var seenTotalChapters: Int?
    var currentChapterIndex: Int
    var currentChapterTitle: String?
    var currentParagraphIndex: Int?
    var bookmarks: [ReaderBookmark]?
    var lastReadAt: Date?
    var lastOpenedAt: Date?
    var readingSessionCount: Int?
    var totalReadingSeconds: TimeInterval?
    var addedAt: Date

    var readingProgress: Double {
        guard totalChapters > 0 else { return 0 }
        return min(max(Double(currentChapterIndex + 1) / Double(totalChapters), 0), 1)
    }

    var hasUpdates: Bool {
        totalChapters > max(seenTotalChapters ?? totalChapters, 0)
    }

    init(
        id: String,
        title: String,
        author: String,
        coverURL: String?,
        sourceName: String,
        sourceURL: String,
        bookURL: String,
        intro: String?,
        localContent: [String]? = nil,
        localChapters: [LocalTextChapter]? = nil,
        latestChapterTitle: String? = nil,
        totalChapters: Int = 0,
        seenTotalChapters: Int? = nil,
        currentChapterIndex: Int = 0,
        currentChapterTitle: String? = nil,
        currentParagraphIndex: Int? = nil,
        bookmarks: [ReaderBookmark]? = nil,
        lastReadAt: Date? = nil,
        lastOpenedAt: Date? = nil,
        readingSessionCount: Int? = nil,
        totalReadingSeconds: TimeInterval? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.bookURL = bookURL
        self.intro = intro
        self.localContent = localContent
        self.localChapters = localChapters
        self.latestChapterTitle = latestChapterTitle
        self.totalChapters = totalChapters
        self.seenTotalChapters = seenTotalChapters
        self.currentChapterIndex = currentChapterIndex
        self.currentChapterTitle = currentChapterTitle
        self.currentParagraphIndex = currentParagraphIndex
        self.bookmarks = bookmarks
        self.lastReadAt = lastReadAt
        self.lastOpenedAt = lastOpenedAt
        self.readingSessionCount = readingSessionCount
        self.totalReadingSeconds = totalReadingSeconds
        self.addedAt = addedAt
    }

    init(searchBook: SearchBook) {
        self.init(
            id: searchBook.id,
            title: searchBook.name,
            author: searchBook.author ?? "作者未知",
            coverURL: searchBook.coverUrl,
            sourceName: searchBook.sourceName,
            sourceURL: searchBook.sourceUrl,
            bookURL: searchBook.bookUrl,
            intro: searchBook.intro
        )
    }

    init(localTextBook: LocalTextBook) {
        let id = "local|\(UUID().uuidString)"
        self.init(
            id: id,
            title: localTextBook.title,
            author: localTextBook.author,
            coverURL: nil,
            sourceName: "Local",
            sourceURL: "local://text",
            bookURL: id,
            intro: nil,
            localContent: nil,
            localChapters: localTextBook.chapters,
            latestChapterTitle: localTextBook.chapters.last?.title ?? "全文",
            totalChapters: max(localTextBook.chapters.count, 1),
            seenTotalChapters: max(localTextBook.chapters.count, 1),
            currentChapterIndex: 0,
            currentChapterTitle: localTextBook.chapters.first?.title ?? "全文"
        )
    }
}
