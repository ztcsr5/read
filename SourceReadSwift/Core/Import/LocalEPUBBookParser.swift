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
        let coverURL = extractCoverURL(
            from: opfXML,
            manifest: manifest,
            basePath: basePath,
            archive: archive,
            bookURL: fileURL
        )
        let orderedIDs = spine.isEmpty
            ? manifest.filter { $0.mediaType.contains("xhtml") || $0.mediaType.contains("html") }.map(\.id)
            : spine
        let chapters = try orderedIDs.enumerated().compactMap { index, id -> LocalTextChapter? in
            guard let item = manifest.first(where: { $0.id == id }) else { return nil }
            let href = item.href
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
        return LocalTextBook(title: metadata.title, author: metadata.author, chapters: chapters, coverURL: coverURL)
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

    private func manifestItems(from opf: String) -> [ManifestItem] {
        do {
            let document = try SwiftSoup.parse(opf)
            return try document.select("manifest item").array().compactMap { item in
                let id = try item.attr("id")
                let href = try item.attr("href")
                guard !id.isEmpty, !href.isEmpty else { return nil }
                return ManifestItem(
                    id: id,
                    href: href,
                    mediaType: try item.attr("media-type").lowercased(),
                    properties: try item.attr("properties")
                )
            }
        } catch {
            return []
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
            let nodes = try document.select("h1, h2, h3, h4, h5, h6, p, li, blockquote, pre").array()
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

    private func extractCoverURL(
        from opf: String,
        manifest: [ManifestItem],
        basePath: String,
        archive: Archive,
        bookURL: URL
    ) -> URL? {
        let coverID: String? = {
            if let raw = try? firstMatch(
                in: opf,
                pattern: #"<meta[^>]+name\s*=\s*["']cover["'][^>]+content\s*=\s*["']([^"']+)["']"#
            ) { return raw }
            return manifest.first(where: { item in
                item.properties.split(separator: " ").contains { $0 == "cover-image" }
            })?.id
        }()
        guard let item = manifest.first(where: { $0.id == coverID })
                ?? manifest.first(where: { $0.mediaType.hasPrefix("image/") }) else {
            return nil
        }
        let path = normalizeEPUBPath(basePath: basePath, href: item.href)
        guard let entry = archive[path] else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry) { data.append($0) }
            guard !data.isEmpty else { return nil }
            let root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("SourceReadSwift/EPUBCovers", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let ext = URL(fileURLWithPath: item.href).pathExtension.nilIfEmpty ?? "img"
            let key = stableFileKey(bookURL.standardizedFileURL.path)
            let destination = root.appendingPathComponent("\(key).\(ext)")
            try data.write(to: destination, options: [.atomic])
            return destination
        } catch {
            return nil
        }
    }

    private func stableFileKey(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func normalizeEPUBPath(basePath: String, href: String) -> String {
        let rawHref = href.components(separatedBy: "#").first ?? href
        let cleanHref = rawHref.removingPercentEncoding ?? rawHref
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
            let pattern = "<\(escaped)(?:\\s[^>]*)?>([\\s\\S]*?)</\(escaped)>"
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

private struct ManifestItem {
    let id: String
    let href: String
    let mediaType: String
    let properties: String
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
