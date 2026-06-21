import Foundation

struct LocalTextBookParser {
    func parse(data: Data, fileName: String) -> LocalTextBook {
        let text = ResponseTextDecoder().decode(data: data, headers: [:])
        let title = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent.nilIfEmpty ?? "Local Book"
        let paragraphs = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return LocalTextBook(
            title: title,
            author: "Local",
            paragraphs: paragraphs.isEmpty ? [text] : paragraphs
        )
    }
}

struct LocalTextBook: Equatable {
    let title: String
    let author: String
    let paragraphs: [String]
}
