import Foundation

struct LocalTextBookParser {
    func parse(data: Data, fileName: String) -> LocalTextBook {
        let text = ResponseTextDecoder().decode(data: data, headers: [:])
        let title = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent.nilIfEmpty ?? "Local Book"
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let chapters = splitChapters(lines: lines, fallbackText: text)
        return LocalTextBook(
            title: title,
            author: "Local",
            chapters: chapters
        )
    }

    private func splitChapters(lines: [String], fallbackText: String) -> [LocalTextChapter] {
        guard !lines.isEmpty else {
            return [LocalTextChapter(title: "全文", paragraphs: [fallbackText], index: 0)]
        }

        var chapters: [(title: String, paragraphs: [String])] = []
        var currentTitle = "全文"
        var currentParagraphs: [String] = []
        var hasDetectedHeading = false

        for line in lines {
            if isChapterHeading(line) {
                if !currentParagraphs.isEmpty {
                    chapters.append((currentTitle, currentParagraphs))
                    currentParagraphs = []
                }
                currentTitle = line
                hasDetectedHeading = true
            } else {
                currentParagraphs.append(line)
            }
        }

        if !currentParagraphs.isEmpty {
            chapters.append((currentTitle, currentParagraphs))
        }

        if !hasDetectedHeading || chapters.isEmpty {
            return [LocalTextChapter(title: "全文", paragraphs: lines, index: 0)]
        }

        return chapters.enumerated().map { index, item in
            LocalTextChapter(title: item.title, paragraphs: item.paragraphs, index: index)
        }
    }

    private func isChapterHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 48 else { return false }
        let patterns = [
            #"^第[0-9零〇一二三四五六七八九十百千万两]+[章节卷回部集].*"#,
            #"^[Cc]hapter\s+[0-9IVXLC]+.*"#,
            #"^[0-9]{1,4}[、.．]\s*\S.*"#
        ]
        return patterns.contains { pattern in
            trimmed.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

struct LocalTextBook: Equatable {
    let title: String
    let author: String
    let chapters: [LocalTextChapter]
    let coverURL: URL?
    let language: String?
    let publisher: String?
    /// EPUB navigation entries in document order. Plain-text imports leave this empty.
    /// Keeping the entries separate from chapters preserves multiple anchors that
    /// point into one XHTML document and makes EPUB3 fragment navigation portable.
    let navigationEntries: [LocalTextNavigationEntry]

    init(
        title: String,
        author: String,
        chapters: [LocalTextChapter],
        coverURL: URL? = nil,
        language: String? = nil,
        publisher: String? = nil,
        navigationEntries: [LocalTextNavigationEntry] = []
    ) {
        self.title = title
        self.author = author
        self.chapters = chapters
        self.coverURL = coverURL
        self.language = language
        self.publisher = publisher
        self.navigationEntries = navigationEntries
    }

    var paragraphs: [String] {
        chapters.flatMap(\.paragraphs)
    }
}

struct LocalTextNavigationEntry: Codable, Hashable, Sendable, Equatable {
    let title: String
    let sourcePath: String
    let fragment: String?
    let chapterIndex: Int?
    /// Best-effort paragraph offset for fragment links inside an XHTML file.
    /// Nil means the target could not be mapped without changing the source text.
    let paragraphIndex: Int?

    init(title: String, sourcePath: String, fragment: String? = nil, chapterIndex: Int? = nil, paragraphIndex: Int? = nil) {
        self.title = title
        self.sourcePath = sourcePath
        self.fragment = fragment
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
    }
}

struct LocalTextChapter: Identifiable, Codable, Hashable, Sendable, Equatable {
    var id: Int { index }
    let title: String
    let paragraphs: [String]
    let index: Int
    /// EPUB package-relative document path. Nil for imported plain text.
    let sourcePath: String?
    /// First navigation anchor targeting this document, when present.
    let navigationFragment: String?

    init(
        title: String,
        paragraphs: [String],
        index: Int,
        sourcePath: String? = nil,
        navigationFragment: String? = nil
    ) {
        self.title = title
        self.paragraphs = paragraphs
        self.index = index
        self.sourcePath = sourcePath
        self.navigationFragment = navigationFragment
    }

    private enum CodingKeys: String, CodingKey {
        case title, paragraphs, index, sourcePath, navigationFragment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        paragraphs = try container.decode([String].self, forKey: .paragraphs)
        index = try container.decode(Int.self, forKey: .index)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        navigationFragment = try container.decodeIfPresent(String.self, forKey: .navigationFragment)
    }
}
