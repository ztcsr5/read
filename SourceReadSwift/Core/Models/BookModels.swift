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
    let sourceName: String
    let sourceUrl: String
    let intro: String?
    let latestChapter: String?
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

