import Foundation

struct BookshelfPersistence {
    private let fileManager: FileManager
    private let fileName = "bookshelf_books.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [BookshelfBook] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([BookshelfBook].self, from: data)
    }

    func save(_ books: [BookshelfBook]) throws {
        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(books)
        try data.write(to: url, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        if let rootURL {
            return rootURL.appendingPathComponent(fileName)
        }
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("SourceReadSwift", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
