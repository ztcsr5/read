import Foundation

struct SearchBook: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(sourceUrl)|\(bookUrl)" }
    let name: String
    let author: String?
    let coverUrl: String?
    let bookUrl: String
    let sourceName: String
    let sourceUrl: String
    let intro: String?
}

struct BookDetail: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(sourceUrl)|\(bookUrl)" }
    let name: String
    let author: String?
    let coverUrl: String?
    let bookUrl: String
    let tocUrl: String?
    let sourceName: String
    let sourceUrl: String
    let intro: String?
    let latestChapter: String?

    init(
        name: String,
        author: String?,
        coverUrl: String?,
        bookUrl: String,
        tocUrl: String? = nil,
        sourceName: String,
        sourceUrl: String,
        intro: String?,
        latestChapter: String?
    ) {
        self.name = name
        self.author = author
        self.coverUrl = coverUrl
        self.bookUrl = bookUrl
        self.tocUrl = tocUrl
        self.sourceName = sourceName
        self.sourceUrl = sourceUrl
        self.intro = intro
        self.latestChapter = latestChapter
    }
}

struct BookChapter: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(bookUrl)|\(url)|\(title)" }
    let title: String
    let url: String
    let bookUrl: String
    let index: Int
    let isVip: Bool
}

struct ChapterContent: Codable, Hashable, Sendable {
    let chapter: BookChapter
    let title: String
    let paragraphs: [String]
    let nextContentUrl: String?
}

struct ReaderBookmark: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let chapterIndex: Int
    let chapterTitle: String
    let paragraphIndex: Int?
    let snippet: String
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        chapterIndex: Int,
        chapterTitle: String,
        paragraphIndex: Int? = nil,
        snippet: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.paragraphIndex = paragraphIndex
        self.snippet = snippet
        self.createdAt = createdAt
    }
}
