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

    var paragraphs: [String] {
        chapters.flatMap(\.paragraphs)
    }
}

struct LocalTextChapter: Identifiable, Codable, Hashable, Sendable, Equatable {
    var id: Int { index }
    let title: String
    let paragraphs: [String]
    let index: Int
}
