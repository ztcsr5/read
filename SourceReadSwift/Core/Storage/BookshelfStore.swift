import Foundation

@MainActor
final class BookshelfStore: ObservableObject {
    @Published private(set) var books: [BookshelfBook] = []
    @Published private(set) var groups: [BookshelfGroup] = []
    @Published private(set) var lastError: String?

    private let persistence: BookshelfPersistence
    private let groupPersistence: BookshelfGroupPersistence

    init(persistence: BookshelfPersistence = BookshelfPersistence(), groupPersistence: BookshelfGroupPersistence = BookshelfGroupPersistence()) {
        self.persistence = persistence
        self.groupPersistence = groupPersistence
        do {
            books = try persistence.load()
            groups = try groupPersistence.load().sorted { $0.sortOrder < $1.sortOrder }
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

    func book(id: String) -> BookshelfBook? {
        books.first { $0.id == id }
    }

    func updateDetails(
        bookID: String,
        latestChapterTitle: String?,
        intro: String?,
        totalChapters: Int
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        let previousTotalChapters = books[index].totalChapters
        if books[index].seenTotalChapters == nil {
            books[index].seenTotalChapters = previousTotalChapters > 0
                ? previousTotalChapters
                : totalChapters
        }
        books[index].latestChapterTitle = latestChapterTitle
        books[index].intro = intro ?? books[index].intro
        books[index].totalChapters = max(totalChapters, books[index].totalChapters)
        persist()
    }

    func markUpdatesSeen(bookID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].seenTotalChapters = books[index].totalChapters
        persist()
    }

    func switchSource(
        bookID: String,
        to searchBook: SearchBook,
        latestChapterTitle: String?,
        intro: String?,
        totalChapters: Int
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].title = searchBook.name
        books[index].author = searchBook.author ?? books[index].author
        books[index].coverURL = searchBook.coverUrl ?? books[index].coverURL
        books[index].sourceName = searchBook.sourceName
        books[index].sourceURL = searchBook.sourceUrl
        books[index].bookURL = searchBook.bookUrl
        books[index].intro = intro ?? searchBook.intro ?? books[index].intro
        books[index].latestChapterTitle = latestChapterTitle
        books[index].totalChapters = max(totalChapters, 0)
        books[index].seenTotalChapters = max(totalChapters, 0)
        books[index].currentChapterIndex = 0
        books[index].currentChapterTitle = nil
        books[index].currentParagraphIndex = nil
        books[index].bookmarks = nil
        books[index].lastReadAt = Date()
        moveToFront(index: index)
        persist()
    }

    func markRefreshFailure(bookID: String, message: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].intro = books[index].intro ?? message
        persist()
    }

    func updateReadingProgress(
        bookID: String,
        chapterIndex: Int,
        chapterTitle: String?,
        totalChapters: Int,
        paragraphIndex: Int? = nil
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].currentChapterIndex = max(0, chapterIndex)
        books[index].currentChapterTitle = chapterTitle
        books[index].currentParagraphIndex = paragraphIndex.map { max(0, $0) }
        books[index].totalChapters = max(totalChapters, books[index].totalChapters)
        books[index].seenTotalChapters = max(
            books[index].seenTotalChapters ?? 0,
            books[index].currentChapterIndex + 1
        )
        books[index].lastReadAt = Date()
        moveToFront(index: index)
        persist()
    }

    func markReaderOpened(bookID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].lastOpenedAt = Date()
        books[index].lastReadAt = Date()
        moveToFront(index: index)
        persist()
    }

    func recordReadingSession(bookID: String, duration: TimeInterval) {
        guard duration > 1,
              let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].readingSessionCount = (books[index].readingSessionCount ?? 0) + 1
        books[index].totalReadingSeconds = (books[index].totalReadingSeconds ?? 0) + duration
        books[index].lastReadAt = Date()
        moveToFront(index: index)
        persist()
    }

    func remove(bookID: String) {
        books.removeAll { $0.id == bookID }
        persist()
    }

    func removeBooks(bookIDs: Set<String>) {
        guard !bookIDs.isEmpty else { return }
        books.removeAll { bookIDs.contains($0.id) }
        persist()
    }

    func createGroup(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !groups.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        groups.append(BookshelfGroup(name: trimmed, sortOrder: groups.count))
        persistGroups()
    }

    func deleteGroup(id: String) {
        guard let deletedName = groups.first(where: { $0.id == id })?.name else { return }
        groups.removeAll { $0.id == id }
        for index in books.indices where books[index].groupName == deletedName {
            books[index].groupName = nil
        }
        normalizeGroupOrder()
        persistGroups()
        persist()
    }

    func moveBooks(bookIDs: Set<String>, toGroupName: String?) {
        let normalized = toGroupName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        for index in books.indices where bookIDs.contains(books[index].id) {
            books[index].groupName = normalized
        }
        persist()
    }

    func isBookmarked(bookID: String, chapterIndex: Int, paragraphIndex: Int? = nil) -> Bool {
        book(id: bookID)?.bookmarks?.contains {
            $0.chapterIndex == chapterIndex && $0.paragraphIndex == paragraphIndex
        } ?? false
    }

    func toggleBookmark(
        bookID: String,
        chapterIndex: Int,
        chapterTitle: String,
        paragraphIndex: Int? = nil,
        snippet: String
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        var bookmarks = books[index].bookmarks ?? []
        if let existingIndex = bookmarks.firstIndex(where: {
            $0.chapterIndex == chapterIndex && $0.paragraphIndex == paragraphIndex
        }) {
            bookmarks.remove(at: existingIndex)
        } else {
            bookmarks.insert(
                ReaderBookmark(
                    chapterIndex: chapterIndex,
                    chapterTitle: chapterTitle,
                    paragraphIndex: paragraphIndex,
                    snippet: snippet
                ),
                at: 0
            )
        }
        books[index].bookmarks = bookmarks
        persist()
    }

    func removeBookmark(bookID: String, bookmarkID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].bookmarks?.removeAll { $0.id == bookmarkID }
        persist()
    }

    /// Returns a portable snapshot. Cookies, login state and source credentials
    /// live in separate stores and are deliberately excluded.
    func backupSnapshot() -> BookshelfBackupSnapshot {
        BookshelfBackupSnapshot(books: books, groups: groups)
    }

    /// Restores a snapshot atomically. Existing records are replaced so a
    /// restore behaves predictably on a new device; malformed/empty backups are
    /// rejected by the caller before this method is reached.
    @discardableResult
    func restore(_ snapshot: BookshelfBackupSnapshot) -> Bool {
        guard snapshot.schemaVersion == 1 else { return false }
        let normalizedGroups = snapshot.groups
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { offset, group in
                var updated = group
                updated.sortOrder = offset
                return updated
            }
        let validGroupNames = Set(normalizedGroups.map(\.name))
        let normalizedBooks = snapshot.books.map { book in
            var updated = book
            if let groupName = updated.groupName, !validGroupNames.contains(groupName) {
                updated.groupName = nil
            }
            return updated
        }
        books = normalizedBooks
        groups = normalizedGroups
        persistGroups()
        persist()
        return lastError == nil
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

    private func persistGroups() {
        do { try groupPersistence.save(groups) } catch { lastError = error.localizedDescription }
    }

    private func normalizeGroupOrder() {
        groups = groups.enumerated().map { offset, group in
            var updated = group
            updated.sortOrder = offset
            return updated
        }
    }
}
