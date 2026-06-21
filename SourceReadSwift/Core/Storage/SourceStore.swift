import Foundation

struct SourceImportReport: Equatable, Sendable {
    var addedBookSources = 0
    var updatedBookSources = 0
    var addedRSSSources = 0
    var updatedRSSSources = 0
    var addedCatalogs = 0
    var updatedCatalogs = 0
    var ignored = 0

    var totalAdded: Int {
        addedBookSources + addedRSSSources + addedCatalogs
    }

    var totalUpdated: Int {
        updatedBookSources + updatedRSSSources + updatedCatalogs
    }

    var userMessage: String {
        "导入完成：新增 \(totalAdded)，更新 \(totalUpdated)，忽略 \(ignored)；书源 \(addedBookSources)/\(updatedBookSources)，仓库 \(addedCatalogs)/\(updatedCatalogs)，RSS \(addedRSSSources)/\(updatedRSSSources)"
    }
}

@MainActor
final class SourceStore: ObservableObject {
    @Published private(set) var sources: [BookSource] = []
    @Published private(set) var rssSources: [RSSSource] = []
    @Published private(set) var catalogs: [SourceCatalog] = []
    @Published private(set) var lastError: String?
    private let persistence: SourcePersistence

    init(persistence: SourcePersistence = SourcePersistence()) {
        self.persistence = persistence
        do {
            let snapshot = try persistence.load()
            sources = snapshot.sources
            rssSources = snapshot.rssSources
            catalogs = snapshot.catalogs
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func importJSON(_ text: String) throws -> SourceImportReport {
        try importJSONData(Data(text.utf8))
    }

    @discardableResult
    func importSmartInput(_ input: String) throws -> SourceImportInput {
        let parsed = SourceImportLinkParser.parse(input)
        switch parsed.kind {
        case .empty:
            throw SourceImportError.empty
        case .json:
            _ = try importJSON(parsed.value)
        case .url:
            throw SourceImportError.urlImportRequired(parsed.value)
        case .unsupportedScheme:
            throw SourceImportError.unsupportedScheme
        case .unknown:
            throw SourceImportError.unknownInput
        }
        return parsed
    }

    @discardableResult
    func importJSONData(_ data: Data) throws -> SourceImportReport {
        let normalized = try normalizeImportData(stripUTF8BOM(data))
        let decoder = JSONDecoder()
        if let items = try? decoder.decode([AnySourceImportItem].self, from: normalized) {
            return try importItems(items)
        }
        if let wrapped = try? decoder.decode(WrappedSourceImportItems.self, from: normalized),
           !wrapped.items.isEmpty {
            return try importItems(wrapped.items)
        }
        let item = try decoder.decode(AnySourceImportItem.self, from: normalized)
        return try importItems([item])
    }

    func importSources(_ imported: [BookSource]) throws {
        let valid = imported.filter {
            !$0.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !valid.isEmpty else {
            throw SourceImportError.empty
        }
        sources = merge(existing: sources, incoming: valid)
        try persist()
        lastError = nil
    }

    func upsertBookSourceJSON(_ text: String) throws -> BookSource {
        let decoder = JSONDecoder()
        let source = try decoder.decode(BookSource.self, from: Data(text.utf8))
        try importSources([source])
        return source
    }

    func importRSSSources(_ imported: [RSSSource]) throws {
        let valid = imported.filter {
            !$0.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !valid.isEmpty else {
            throw SourceImportError.empty
        }
        rssSources = mergeRSS(existing: rssSources, incoming: valid)
        try persist()
        lastError = nil
    }

    func importCatalogs(_ imported: [SourceCatalog]) throws {
        let valid = imported.filter {
            !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !valid.isEmpty else {
            throw SourceImportError.empty
        }
        catalogs = mergeCatalogs(existing: catalogs, incoming: valid)
        try persist()
        lastError = nil
    }

    func seedForDevelopment() {
        guard sources.isEmpty else { return }
        sources = [
            BookSource(
                bookSourceName: "Example HTML Source",
                bookSourceUrl: "https://example.com",
                searchUrl: "https://example.com/search?q={{keyword}}",
                ruleSearch: SourceRule(fields: [
                    "bookList": ".book",
                    "name": ".title@text",
                    "author": ".author@text",
                    "bookUrl": "a@href",
                    "coverUrl": "img@src"
                ])
            )
        ]
    }

    func source(for sourceUrl: String) -> BookSource? {
        sources.first { $0.bookSourceUrl == sourceUrl }
    }

    func remove(_ source: BookSource) {
        sources.removeAll { $0.bookSourceUrl == source.bookSourceUrl }
        saveAfterMutation()
    }

    func remove(sourceURLs: Set<String>) {
        sources.removeAll { sourceURLs.contains($0.bookSourceUrl) }
        saveAfterMutation()
    }

    func removeRSS(sourceURLs: Set<String>) {
        rssSources.removeAll { sourceURLs.contains($0.sourceUrl) }
        saveAfterMutation()
    }

    func removeCatalogs(urls: Set<String>) {
        catalogs.removeAll { urls.contains($0.url) }
        saveAfterMutation()
    }

    func setEnabled(_ enabled: Bool, for sourceURLs: Set<String>) {
        sources = sources.map { source in
            sourceURLs.contains(source.bookSourceUrl) ? source.updatingEnabled(enabled) : source
        }
        saveAfterMutation()
    }

    func setRSSEnabled(_ enabled: Bool, for sourceURLs: Set<String>) {
        rssSources = rssSources.map { source in
            guard sourceURLs.contains(source.sourceUrl) else { return source }
            var updated = source
            updated.enabled = enabled
            return updated
        }
        saveAfterMutation()
    }

    func setCatalogsEnabled(_ enabled: Bool, for urls: Set<String>) {
        catalogs = catalogs.map { catalog in
            guard urls.contains(catalog.url) else { return catalog }
            var updated = catalog
            updated.enabled = enabled
            return updated
        }
        saveAfterMutation()
    }

    func recordCatalogImport(url: String, report: SourceImportReport) {
        guard let index = catalogs.firstIndex(where: { $0.url == url }) else { return }
        catalogs[index].importedCount = report.totalAdded + report.totalUpdated
        catalogs[index].lastStatus = report.userMessage
        catalogs[index].lastImportedAt = Date()
        saveAfterMutation()
    }

    private func saveAfterMutation() {
        do {
            try persist()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persist() throws {
        try persistence.save(
            SourceLibrarySnapshot(
                sources: sources,
                rssSources: rssSources,
                catalogs: catalogs
            )
        )
    }

    private func importItems(_ items: [AnySourceImportItem]) throws -> SourceImportReport {
        var bookSources: [BookSource] = []
        var rss: [RSSSource] = []
        var sourceCatalogs: [SourceCatalog] = []
        var ignored = 0
        for item in items {
            switch item.kind {
            case .bookSource:
                if item.bookSource.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ignored += 1
                } else {
                    bookSources.append(item.bookSource)
                }
            case .rss:
                if item.rssSource.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ignored += 1
                } else {
                    rss.append(item.rssSource)
                }
            case .catalog:
                if item.catalog.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ignored += 1
                } else {
                    sourceCatalogs.append(item.catalog)
                }
            case .unknown:
                ignored += 1
            }
        }
        if bookSources.isEmpty && rss.isEmpty && sourceCatalogs.isEmpty {
            throw SourceImportError.empty
        }
        let report = SourceImportReport(
            addedBookSources: addedCount(existing: sources.map(\.bookSourceUrl), incoming: bookSources.map(\.bookSourceUrl)),
            updatedBookSources: updatedCount(existing: sources.map(\.bookSourceUrl), incoming: bookSources.map(\.bookSourceUrl)),
            addedRSSSources: addedCount(existing: rssSources.map(\.sourceUrl), incoming: rss.map(\.sourceUrl)),
            updatedRSSSources: updatedCount(existing: rssSources.map(\.sourceUrl), incoming: rss.map(\.sourceUrl)),
            addedCatalogs: addedCount(existing: catalogs.map(\.url), incoming: sourceCatalogs.map(\.url)),
            updatedCatalogs: updatedCount(existing: catalogs.map(\.url), incoming: sourceCatalogs.map(\.url)),
            ignored: ignored
        )
        if !bookSources.isEmpty {
            sources = merge(existing: sources, incoming: bookSources)
        }
        if !rss.isEmpty {
            rssSources = mergeRSS(existing: rssSources, incoming: rss)
        }
        if !sourceCatalogs.isEmpty {
            catalogs = mergeCatalogs(existing: catalogs, incoming: sourceCatalogs)
        }
        try persist()
        lastError = nil
        return report
    }

    private func addedCount(existing: [String], incoming: [String]) -> Int {
        Set(incoming).subtracting(Set(existing)).count
    }

    private func updatedCount(existing: [String], incoming: [String]) -> Int {
        Set(incoming).intersection(Set(existing)).count
    }

    private func merge(existing: [BookSource], incoming: [BookSource]) -> [BookSource] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.bookSourceUrl, $0) })
        for item in incoming {
            map[item.bookSourceUrl] = item
        }
        return map.values.sorted { $0.bookSourceName < $1.bookSourceName }
    }

    private func mergeRSS(existing: [RSSSource], incoming: [RSSSource]) -> [RSSSource] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.sourceUrl, $0) })
        for item in incoming {
            map[item.sourceUrl] = item
        }
        return map.values.sorted { $0.sourceName < $1.sourceName }
    }

    private func mergeCatalogs(existing: [SourceCatalog], incoming: [SourceCatalog]) -> [SourceCatalog] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.url, $0) })
        for item in incoming {
            map[item.url] = item
        }
        return map.values.sorted { $0.name < $1.name }
    }

    private func stripUTF8BOM(_ data: Data) -> Data {
        let bom = Data([0xEF, 0xBB, 0xBF])
        guard data.starts(with: bom) else { return data }
        return data.dropFirst(3)
    }

    private func normalizeImportData(_ data: Data) throws -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = try? JSONDecoder().decode(String.self, from: Data(text.utf8)) {
            text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("{") || text.hasPrefix("[") {
            return Data(text.utf8)
        }
        if let extracted = extractFirstJSONValue(from: text) {
            return Data(extracted.utf8)
        }
        return data
    }

    private func extractFirstJSONValue(from text: String) -> String? {
        let chars = Array(text)
        for start in chars.indices where chars[start] == "{" || chars[start] == "[" {
            let open = chars[start]
            let close: Character = open == "{" ? "}" : "]"
            var depth = 0
            var inString = false
            var escaped = false
            for index in start..<chars.count {
                let char = chars[index]
                if inString {
                    if escaped {
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == "\"" {
                        inString = false
                    }
                    continue
                }
                if char == "\"" {
                    inString = true
                } else if char == open {
                    depth += 1
                } else if char == close {
                    depth -= 1
                    if depth == 0 {
                        return String(chars[start...index])
                    }
                }
            }
        }
        return nil
    }
}

private enum SourceImportItemKind {
    case bookSource
    case rss
    case catalog
    case unknown
}

private struct AnySourceImportItem: Decodable {
    let kind: SourceImportItemKind
    let bookSource: BookSource
    let rssSource: RSSSource
    let catalog: SourceCatalog

    init(bookSource: BookSource) {
        self.kind = .bookSource
        self.bookSource = bookSource
        self.rssSource = RSSSource(sourceName: "", sourceUrl: "")
        self.catalog = SourceCatalog(name: "", url: "")
    }

    init(rssSource: RSSSource) {
        self.kind = .rss
        self.bookSource = BookSource(bookSourceName: "", bookSourceUrl: UUID().uuidString)
        self.rssSource = rssSource
        self.catalog = SourceCatalog(name: "", url: "")
    }

    init(catalog: SourceCatalog) {
        self.kind = .catalog
        self.bookSource = BookSource(bookSourceName: "", bookSourceUrl: UUID().uuidString)
        self.rssSource = RSSSource(sourceName: "", sourceUrl: "")
        self.catalog = catalog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let keys = Set(container.allKeys.map(\.stringValue))
        let sourceUrl = (try? container.decode(String.self, forKey: DynamicCodingKey("sourceUrl"))) ?? ""
        let url = (try? container.decode(String.self, forKey: DynamicCodingKey("url"))) ?? ""
        let group = (try? container.decode(String.self, forKey: DynamicCodingKey("sourceGroup"))) ?? ""
        let comment = (try? container.decode(String.self, forKey: DynamicCodingKey("sourceComment"))) ?? ""
        let combined = [sourceUrl, url, group, comment].joined(separator: " ").lowercased()

        if keys.contains("bookSourceName")
            || keys.contains("bookSourceUrl")
            || keys.contains("searchUrl")
            || keys.contains("ruleSearch")
            || keys.contains("rulesSearch")
            || keys.contains("ruleToc")
            || keys.contains("rulesToc")
            || keys.contains("ruleBookContent") {
            kind = .bookSource
        } else if keys.contains("ruleArticles")
            || keys.contains("ruleTitle")
            || keys.contains("sortUrl")
            || combined.contains("rss")
            || combined.contains("feed")
            || combined.contains("atom") {
            kind = .rss
        } else if keys.contains("importUrl")
            || keys.contains("singleUrl")
            || combined.contains("shuyuan")
            || combined.contains("书源")
            || sourceUrl.lowercased().hasSuffix(".json")
            || url.lowercased().hasSuffix(".json") {
            kind = .catalog
        } else if keys.contains("sourceName") || keys.contains("name") {
            kind = .catalog
        } else {
            kind = .unknown
        }

        bookSource = (try? BookSource(from: decoder)) ?? BookSource(
            bookSourceName: "",
            bookSourceUrl: UUID().uuidString
        )
        rssSource = (try? RSSSource(from: decoder)) ?? RSSSource(sourceName: "", sourceUrl: "")
        catalog = (try? SourceCatalog(from: decoder)) ?? SourceCatalog(name: "", url: "")
    }
}

private struct WrappedSourceImportItems: Decodable {
    let items: [AnySourceImportItem]

    enum CodingKeys: String, CodingKey {
        case sources
        case bookSources
        case bookSource
        case data
        case list
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let values = try? container.decode([AnySourceImportItem].self, forKey: .sources) {
            items = values
        } else if let values = try? container.decode([AnySourceImportItem].self, forKey: .bookSources) {
            items = values
        } else if let values = try? container.decode([AnySourceImportItem].self, forKey: .bookSource) {
            items = values
        } else if let values = try? container.decode([AnySourceImportItem].self, forKey: .data) {
            items = values
        } else if let values = try? container.decode([AnySourceImportItem].self, forKey: .list) {
            items = values
        } else if let values = try? container.decode([AnySourceImportItem].self, forKey: .items) {
            items = values
        } else if let value = try? container.decode(AnySourceImportItem.self, forKey: .bookSource) {
            items = [value]
        } else if let value = try? container.decode(AnySourceImportItem.self, forKey: .data) {
            items = [value]
        } else if let value = try? container.decode(AnySourceImportItem.self, forKey: .sources) {
            items = [value]
        } else if let value = try? container.decode(AnySourceImportItem.self, forKey: .bookSources) {
            items = [value]
        } else {
            items = []
        }
    }
}

enum SourceImportError: LocalizedError {
    case empty
    case urlImportRequired(String)
    case unsupportedScheme
    case unknownInput
    case challengePage

    var errorDescription: String? {
        switch self {
        case .empty:
            return "No valid book source was found."
        case .urlImportRequired(let url):
            return "URL import requires downloading first: \(url)"
        case .unsupportedScheme:
            return "Import link was recognized, but no src/url parameter was found."
        case .unknownInput:
            return "Input is not recognized as JSON, an HTTP URL, or a reader import link."
        case .challengePage:
            return "The downloaded content is a Cloudflare or JavaScript challenge page, not source JSON."
        }
    }
}
