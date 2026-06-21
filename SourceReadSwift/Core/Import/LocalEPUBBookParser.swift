import Foundation
import SwiftSoup
import ZIPFoundation

struct LocalEPUBBookParser {
    func parse(fileURL: URL) throws -> LocalTextBook {
        guard let archive = Archive(url: fileURL, accessMode: .read) else {
            throw LocalEPUBImportError.invalidArchive
        }
        let containerXML = try stringEntry("META-INF/container.xml", in: archive)
        guard let opfPath = try firstMatch(
            in: containerXML,
            pattern: #"full-path\s*=\s*"([^"]+)""#
        ) else {
            throw LocalEPUBImportError.missingPackageDocument
        }
        let opfXML = try stringEntry(opfPath, in: archive)
        let basePath = URL(fileURLWithPath: opfPath).deletingLastPathComponent().relativePath
        let metadata = metadata(from: opfXML, fallbackTitle: fileURL.deletingPathExtension().lastPathComponent)
        let manifest = manifestItems(from: opfXML)
        let spine = spineIDs(from: opfXML)
        let chapters = try spine.enumerated().compactMap { index, id -> LocalTextChapter? in
            guard let href = manifest[id] else { return nil }
            let path = normalizeEPUBPath(basePath: basePath, href: href)
            guard let html = try? stringEntry(path, in: archive) else { return nil }
            let paragraphs = paragraphs(from: html)
            guard !paragraphs.isEmpty else { return nil }
            return LocalTextChapter(
                title: chapterTitle(from: html) ?? "Chapter \(index + 1)",
                paragraphs: paragraphs,
                index: index
            )
        }
        guard !chapters.isEmpty else {
            throw LocalEPUBImportError.emptyContent
        }
        return LocalTextBook(title: metadata.title, author: metadata.author, chapters: chapters)
    }

    private func stringEntry(_ path: String, in archive: Archive) throws -> String {
        guard let entry = archive[path] else {
            throw LocalEPUBImportError.missingEntry(path)
        }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return ResponseTextDecoder().decode(data: data, headers: [:])
    }

    private func metadata(from opf: String, fallbackTitle: String) -> (title: String, author: String) {
        let title = firstTagText(in: opf, names: ["dc:title", "title"]) ?? fallbackTitle
        let author = firstTagText(in: opf, names: ["dc:creator", "creator"]) ?? "Local"
        return (title, author)
    }

    private func manifestItems(from opf: String) -> [String: String] {
        do {
            let document = try SwiftSoup.parse(opf)
            return try document.select("manifest item").array().reduce(into: [:]) { result, item in
                let id = try item.attr("id")
                let href = try item.attr("href")
                guard !id.isEmpty, !href.isEmpty else { return }
                result[id] = href
            }
        } catch {
            return [:]
        }
    }

    private func spineIDs(from opf: String) -> [String] {
        do {
            let document = try SwiftSoup.parse(opf)
            return try document.select("spine itemref").array().compactMap {
                let id = try $0.attr("idref")
                return id.isEmpty ? nil : id
            }
        } catch {
            return []
        }
    }

    private func paragraphs(from html: String) -> [String] {
        do {
            let document = try SwiftSoup.parse(html)
            let nodes = try document.select("p, h1, h2, h3, h4, div").array()
            let values = try nodes.map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !values.isEmpty {
                return values
            }
            let body = try document.body()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            return body?.nilIfEmpty.map { [$0] } ?? []
        } catch {
            return []
        }
    }

    private func chapterTitle(from html: String) -> String? {
        do {
            let document = try SwiftSoup.parse(html)
            return try document.select("h1, h2, h3, title").first()?.text().nilIfEmpty
        } catch {
            return nil
        }
    }

    private func normalizeEPUBPath(basePath: String, href: String) -> String {
        let cleanHref = href.components(separatedBy: "#").first ?? href
        if basePath == "." || basePath == "/" || basePath.isEmpty {
            return cleanHref
        }
        return ([basePath, cleanHref].joined(separator: "/") as NSString)
            .standardizingPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func firstMatch(in text: String, pattern: String) throws -> String? {
        let regex = try NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private func firstTagText(in text: String, names: [String]) -> String? {
        for name in names {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let pattern = #"<\#(escaped)(?:\s[^>]*)?>([\s\S]*?)</\#(escaped)>"#
            if let raw = try? firstMatch(in: text, pattern: pattern) {
                let cleaned = raw
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return nil
    }
}

enum LocalEPUBImportError: LocalizedError {
    case invalidArchive
    case missingPackageDocument
    case missingEntry(String)
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "EPUB 文件不是有效的 ZIP 包。"
        case .missingPackageDocument:
            return "EPUB 缺少 OPF 包描述文件。"
        case .missingEntry(let path):
            return "EPUB 缺少文件：\(path)"
        case .emptyContent:
            return "EPUB 没有解析到可阅读正文。"
        }
    }
}
