import Foundation

@MainActor
final class BookshelfStore: ObservableObject {
    @Published private(set) var books: [BookshelfBook] = []
    @Published private(set) var lastError: String?

    private let persistence: BookshelfPersistence

    init(persistence: BookshelfPersistence = BookshelfPersistence()) {
        self.persistence = persistence
        do {
            books = try persistence.load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func contains(_ searchBook: SearchBook) -> Bool {
        books.contains { $0.id == searchBook.id }
    }

    func addOrUpdate(_ searchBook: SearchBook) {
        if let index = books.firstIndex(where: { $0.id == searchBook.id }) {
            var item = books[index]
            item.title = searchBook.name
            item.author = searchBook.author ?? item.author
            item.coverURL = searchBook.coverUrl
            item.sourceName = searchBook.sourceName
            item.sourceURL = searchBook.sourceUrl
            item.bookURL = searchBook.bookUrl
            item.intro = searchBook.intro
            books[index] = item
        } else {
            books.insert(BookshelfBook(searchBook: searchBook), at: 0)
        }
        persist()
    }

    func addLocalTextBook(_ localTextBook: LocalTextBook) {
        books.insert(BookshelfBook(localTextBook: localTextBook), at: 0)
        persist()
    }

    func updateDetails(
        bookID: String,
        latestChapterTitle: String?,
        intro: String?,
        totalChapters: Int
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].latestChapterTitle = latestChapterTitle
        books[index].intro = intro ?? books[index].intro
        books[index].totalChapters = max(totalChapters, books[index].totalChapters)
        persist()
    }

    func updateReadingProgress(
        bookID: String,
        chapterIndex: Int,
        chapterTitle: String?,
        totalChapters: Int
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].currentChapterIndex = max(0, chapterIndex)
        books[index].currentChapterTitle = chapterTitle
        books[index].totalChapters = max(totalChapters, books[index].totalChapters)
        books[index].lastReadAt = Date()
        moveToFront(index: index)
        persist()
    }

    func remove(bookID: String) {
        books.removeAll { $0.id == bookID }
        persist()
    }

    var recentBooks: [BookshelfBook] {
        books
            .filter { $0.lastReadAt != nil }
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
    }

    var updatedBooks: [BookshelfBook] {
        books.filter(\.hasUpdates)
    }

    private func moveToFront(index: Int) {
        guard books.indices.contains(index), index != 0 else { return }
        let item = books.remove(at: index)
        books.insert(item, at: 0)
    }

    private func persist() {
        do {
            try persistence.save(books)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
