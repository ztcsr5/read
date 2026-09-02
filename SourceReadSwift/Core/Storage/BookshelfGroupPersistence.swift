import Foundation

struct BookshelfGroupPersistence {
    private let fileManager: FileManager
    private let fileName = "bookshelf_groups.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [BookshelfGroup] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([BookshelfGroup].self, from: Data(contentsOf: url))
    }

    func save(_ groups: [BookshelfGroup]) throws {
        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(groups).write(to: url, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        if let rootURL { return rootURL.appendingPathComponent(fileName) }
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("SourceReadSwift", isDirectory: true).appendingPathComponent(fileName)
    }
}
