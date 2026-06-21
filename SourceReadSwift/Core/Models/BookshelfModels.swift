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
    var latestChapterTitle: String?
    var totalChapters: Int
    var currentChapterIndex: Int
    var currentChapterTitle: String?
    var lastReadAt: Date?
    var addedAt: Date

    var readingProgress: Double {
        guard totalChapters > 0 else { return 0 }
        return min(max(Double(currentChapterIndex + 1) / Double(totalChapters), 0), 1)
    }

    var hasUpdates: Bool {
        totalChapters > 0 && currentChapterIndex + 1 < totalChapters
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
        latestChapterTitle: String? = nil,
        totalChapters: Int = 0,
        currentChapterIndex: Int = 0,
        currentChapterTitle: String? = nil,
        lastReadAt: Date? = nil,
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
        self.latestChapterTitle = latestChapterTitle
        self.totalChapters = totalChapters
        self.currentChapterIndex = currentChapterIndex
        self.currentChapterTitle = currentChapterTitle
        self.lastReadAt = lastReadAt
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
            localContent: localTextBook.paragraphs,
            latestChapterTitle: "全文",
            totalChapters: 1,
            currentChapterIndex: 0,
            currentChapterTitle: "全文"
        )
    }
}
