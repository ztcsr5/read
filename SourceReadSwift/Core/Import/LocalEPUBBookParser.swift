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
            pattern: #"full-path\s*=\s*["']([^"']+)["']"#
        ) else {
            throw LocalEPUBImportError.missingPackageDocument
        }
        let opfXML = try stringEntry(opfPath, in: archive)
        let basePath = URL(fileURLWithPath: opfPath).deletingLastPathComponent().relativePath
        let metadata = metadata(from: opfXML, fallbackTitle: fileURL.deletingPathExtension().lastPathComponent)
        let manifest = manifestItems(from: opfXML)
        let spine = spineItems(from: opfXML)
        let tocEntries = tableOfContentsEntries(from: opfXML, manifest: manifest, basePath: basePath, archive: archive)
        let coverURL = extractCoverURL(
            from: opfXML,
            manifest: manifest,
            basePath: basePath,
            archive: archive,
            bookURL: fileURL
        )
        let linearSpine = spine.filter(\.isLinear).map(\.id)
        let orderedIDs = spine.isEmpty
            ? manifest.filter { $0.mediaType.contains("xhtml") || $0.mediaType.contains("html") }.map(\.id)
            : (linearSpine.isEmpty ? spine.map(\.id) : linearSpine)
        let chapters = try orderedIDs.enumerated().compactMap { index, id -> LocalTextChapter? in
            guard let item = manifest.first(where: { $0.id == id }) else { return nil }
            let href = item.href
            let path = normalizeEPUBPath(basePath: basePath, href: href)
            guard let html = try? stringEntry(path, in: archive) else { return nil }
            let paragraphs = paragraphs(from: html)
            guard !paragraphs.isEmpty else { return nil }
            let tocEntry = tocEntries[path]
            return LocalTextChapter(
                title: tocEntry?.title ?? chapterTitle(from: html) ?? "Chapter \(index + 1)",
                paragraphs: paragraphs,
                index: index,
                sourcePath: path,
                navigationFragment: tocEntry?.fragment
            )
        }
        guard !chapters.isEmpty else {
            throw LocalEPUBImportError.emptyContent
        }
        return LocalTextBook(
            title: metadata.title,
            author: metadata.author,
            chapters: chapters,
            coverURL: coverURL,
            language: metadata.language,
            publisher: metadata.publisher
        )
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

    private func metadata(from opf: String, fallbackTitle: String) -> (title: String, author: String, language: String?, publisher: String?) {
        let title = firstTagText(in: opf, names: ["dc:title", "title"]) ?? fallbackTitle
        let author = firstTagText(in: opf, names: ["dc:creator", "creator"]) ?? "Local"
        let language = firstTagText(in: opf, names: ["dc:language", "language"])
        let publisher = firstTagText(in: opf, names: ["dc:publisher", "publisher"])
        return (title, author, language, publisher)
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

    private func spineItems(from opf: String) -> [SpineItem] {
        do {
            let document = try SwiftSoup.parse(opf)
            return try document.select("spine itemref").array().compactMap {
                let id = try $0.attr("idref")
                guard !id.isEmpty else { return nil }
                return SpineItem(
                    id: id,
                    isLinear: try $0.attr("linear").lowercased() != "no"
                )
            }
        } catch {
            return []
        }
    }

    private func tableOfContentsEntries(
        from opf: String,
        manifest: [ManifestItem],
        basePath: String,
        archive: Archive
    ) -> [String: NavigationEntry] {
        let tocID: String? = {
            do {
                let document = try SwiftSoup.parse(opf)
                guard let element = try document.select("spine").first() else { return nil }
                let value = try element.attr("toc")
                return value.isEmpty ? nil : value
            } catch { return nil }
        }()
        let candidates = manifest.filter { item in
            item.properties.split(separator: " ").contains { $0.lowercased() == "nav" }
                || item.id == tocID
                || item.mediaType == "application/x-dtbncx+xml"
        }
        var result: [String: NavigationEntry] = [:]
        for item in candidates {
            let path = normalizeEPUBPath(basePath: basePath, href: item.href)
            let navigationBasePath = URL(fileURLWithPath: path).deletingLastPathComponent().relativePath
            guard let raw = try? stringEntry(path, in: archive) else { continue }
            if item.mediaType == "application/x-dtbncx+xml" || raw.range(of: "<navMap", options: .caseInsensitive) != nil {
                result.merge(ncxEntries(from: raw, basePath: navigationBasePath), uniquingKeysWith: { current, _ in current })
            } else {
                result.merge(navEntries(from: raw, basePath: navigationBasePath), uniquingKeysWith: { current, _ in current })
            }
        }
        return result
    }

    private func navEntries(from html: String, basePath: String) -> [String: NavigationEntry] {
        guard let document = try? SwiftSoup.parse(html),
              let links = try? document.select("nav a").array() else { return [:] }
        var result: [String: NavigationEntry] = [:]
        for link in links {
            do {
                let href = try link.attr("href")
                let label = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !href.isEmpty, !label.isEmpty else { continue }
                let path = normalizeEPUBPath(basePath: basePath, href: href)
                if result[path] == nil {
                    result[path] = NavigationEntry(title: label, fragment: fragment(from: href))
                }
            } catch { continue }
        }
        return result
    }

    private func ncxEntries(from xml: String, basePath: String) -> [String: NavigationEntry] {
        guard let document = try? SwiftSoup.parse(xml),
              let points = try? document.select("navPoint").array() else { return [:] }
        var result: [String: NavigationEntry] = [:]
        for point in points {
            do {
                guard let content = try point.select("content").first(),
                      let text = try point.select("navLabel text").first() else { continue }
                let src = try content.attr("src")
                let label = try text.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !src.isEmpty, !label.isEmpty else { continue }
                let path = normalizeEPUBPath(basePath: basePath, href: src)
                if result[path] == nil {
                    result[path] = NavigationEntry(title: label, fragment: fragment(from: src))
                }
            } catch { continue }
        }
        return result
    }

    private func paragraphs(from html: String) -> [String] {
        do {
            let document = try SwiftSoup.parse(html)
            let nodes = try document.select("h1, h2, h3, h4, h5, h6, p, li, blockquote, pre").array()
            let values = try nodes.map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !values.isEmpty {
                if values.count == 1,
                   let body = try document.body()?.text().trimmingCharacters(in: .whitespacesAndNewlines),
                   body.count > values[0].count,
                   body.hasPrefix(values[0]) {
                    let directText = String(body.dropFirst(values[0].count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !directText.isEmpty { return values + [directText] }
                }
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

    private func fragment(from href: String) -> String? {
        guard let hashIndex = href.firstIndex(of: "#") else { return nil }
        let value = String(href[href.index(after: hashIndex)...])
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.nilIfEmpty
    }

    private func firstMatch(in text: String, pattern: String) throws -> String? {
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
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

private struct SpineItem {
    let id: String
    let isLinear: Bool
}

private struct NavigationEntry {
    let title: String
    let fragment: String?
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
