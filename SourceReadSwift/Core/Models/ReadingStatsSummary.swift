import Foundation

struct ReadingStatsSummary: Equatable, Sendable {
    let totalBooks: Int
    let localBooks: Int
    let remoteBooks: Int
    let readBooks: Int
    let bookmarkedBooks: Int
    let totalBookmarks: Int
    let totalSessions: Int
    let totalReadingSeconds: TimeInterval
    let averageProgress: Double
    let mostReadBook: BookshelfBook?
    let recentBooks: [BookshelfBook]

    init(books: [BookshelfBook]) {
        totalBooks = books.count
        localBooks = books.filter { $0.sourceURL.hasPrefix("local://") }.count
        remoteBooks = totalBooks - localBooks
        readBooks = books.filter { $0.lastReadAt != nil }.count
        bookmarkedBooks = books.filter { !($0.bookmarks ?? []).isEmpty }.count
        totalBookmarks = books.reduce(0) { $0 + ($1.bookmarks?.count ?? 0) }
        totalSessions = books.reduce(0) { $0 + ($1.readingSessionCount ?? 0) }
        totalReadingSeconds = books.reduce(0) { $0 + ($1.totalReadingSeconds ?? 0) }
        averageProgress = books.isEmpty
            ? 0
            : books.reduce(0) { $0 + $1.readingProgress } / Double(books.count)
        mostReadBook = books
            .filter { ($0.totalReadingSeconds ?? 0) > 0 }
            .max { ($0.totalReadingSeconds ?? 0) < ($1.totalReadingSeconds ?? 0) }
        recentBooks = Array(
            books
                .filter { $0.lastReadAt != nil }
                .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
                .prefix(5)
        )
    }
}
