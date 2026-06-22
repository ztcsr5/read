import Foundation

enum PickedDocumentAccess {
    static func copiedURL(from url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copiedURL: URL?
        var thrownError: Error?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            do {
                let fileManager = FileManager.default
                let directory = fileManager.temporaryDirectory
                    .appendingPathComponent("PickedDocuments", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

                let safeName = readableURL.lastPathComponent.nilIfEmpty ?? UUID().uuidString
                let destination = directory.appendingPathComponent(safeName)

                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: readableURL, to: destination)
                copiedURL = destination
            } catch {
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let copiedURL else {
            throw CocoaError(.fileReadUnknown)
        }
        return copiedURL
    }

    static func data(from url: URL) throws -> (data: Data, fileName: String, copiedURL: URL) {
        let localURL = try copiedURL(from: url)
        return (try Data(contentsOf: localURL), localURL.lastPathComponent, localURL)
    }
}
