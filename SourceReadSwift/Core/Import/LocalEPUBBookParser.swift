import Foundation
import SwiftSoup
import ZIPFoundation

struct LocalEPUBBookParser {
    func parse(fileURL: URL) throws -> LocalTextBook {
        let signpost = PerformanceSignpost.begin("epub.parse")
        defer { PerformanceSignpost.end("epub.parse", id: signpost) }
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
        let navigation = allNavigationEntries(from: opfXML, manifest: manifest, basePath: basePath, archive: archive)
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
        var chapterHTMLByPath: [String: String] = [:]
        let parsedChapters = try orderedIDs.enumerated().compactMap { index, id -> LocalTextChapter? in
            guard let item = manifest.first(where: { $0.id == id }) else { return nil }
            let href = item.href
            let path = normalizeEPUBPath(basePath: basePath, href: href)
            guard let html = try? stringEntry(path, in: archive) else { return nil }
            chapterHTMLByPath[path] = html
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
        // A malformed/empty spine item can be skipped above. Reindex the
        // surviving chapters so persisted progress and array navigation keep
        // the same contiguous coordinate system.
        let chapters = parsedChapters.enumerated().map { index, chapter in
            LocalTextChapter(
                title: chapter.title,
                paragraphs: chapter.paragraphs,
                index: index,
                sourcePath: chapter.sourcePath,
                navigationFragment: chapter.navigationFragment
            )
        }
        guard !chapters.isEmpty else {
            throw LocalEPUBImportError.emptyContent
        }
        let chapterIndexesByPath = chapters.reduce(into: [String: Int]()) { result, chapter in
            if let path = chapter.sourcePath, result[path] == nil { result[path] = chapter.index }
        }
        var paragraphIndexesByNavigationID: [String: Int] = [:]
        for entry in navigation {
            guard let fragment = entry.fragment else { continue }
            let identity = entry.sourcePath + "#" + fragment
            guard paragraphIndexesByNavigationID[identity] == nil,
                  let html = chapterHTMLByPath[entry.sourcePath],
                  let paragraphIndex = paragraphIndex(for: fragment, in: html) else { continue }
            paragraphIndexesByNavigationID[identity] = paragraphIndex
        }
        var seenNavigation = Set<String>()
        let navigationEntries: [LocalTextNavigationEntry] = navigation.compactMap { entry -> LocalTextNavigationEntry? in
            let identity = entry.sourcePath + "#" + (entry.fragment ?? "")
            guard seenNavigation.insert(identity).inserted else { return nil }
            return LocalTextNavigationEntry(
                title: entry.title,
                sourcePath: entry.sourcePath,
                fragment: entry.fragment,
                chapterIndex: chapterIndexesByPath[entry.sourcePath],
                paragraphIndex: entry.fragment.flatMap { paragraphIndexesByNavigationID[entry.sourcePath + "#" + $0] }
            )
        }
        let book = LocalTextBook(
            title: metadata.title,
            author: metadata.author,
            chapters: chapters,
            coverURL: coverURL,
            language: metadata.language,
            publisher: metadata.publisher,
            navigationEntries: navigationEntries
        )
        PerformanceSignpost.event("epub.parse.summary", "chapters=\(book.chapters.count), navigation=\(book.navigationEntries.count)")
        return book
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

    /// Returns every EPUB2/EPUB3 navigation link, including multiple fragment
    /// links into the same XHTML document. The chapter map above intentionally
    /// keeps only the first label for backwards-compatible chapter titles.
    private func allNavigationEntries(
        from opf: String,
        manifest: [ManifestItem],
        basePath: String,
        archive: Archive
    ) -> [NavigationEntry] {
        let tocID: String? = {
            do {
                let document = try SwiftSoup.parse(opf)
                guard let element = try document.select("spine").first() else { return nil }
                return try element.attr("toc").nilIfEmpty
            } catch { return nil }
        }()
        let candidates = manifest.filter { item in
            item.properties.split(separator: " ").contains { $0.lowercased() == "nav" }
                || item.id == tocID
                || item.mediaType == "application/x-dtbncx+xml"
        }
        var result: [NavigationEntry] = []
        for item in candidates {
            let path = normalizeEPUBPath(basePath: basePath, href: item.href)
            let navigationBasePath = URL(fileURLWithPath: path).deletingLastPathComponent().relativePath
            guard let raw = try? stringEntry(path, in: archive) else { continue }
            if item.mediaType == "application/x-dtbncx+xml" || raw.range(of: "<navMap", options: .caseInsensitive) != nil {
                result.append(contentsOf: ncxEntriesList(from: raw, basePath: navigationBasePath))
            } else {
                result.append(contentsOf: navEntriesList(from: raw, basePath: navigationBasePath))
            }
        }
        return result
    }

    private func navEntries(from html: String, basePath: String) -> [String: NavigationEntry] {
        var result: [String: NavigationEntry] = [:]
        for entry in navEntriesList(from: html, basePath: basePath) where result[entry.sourcePath] == nil {
            result[entry.sourcePath] = entry
        }
        return result
    }

    private func navEntriesList(from html: String, basePath: String) -> [NavigationEntry] {
        guard let document = try? SwiftSoup.parse(html),
              let links = try? document.select("nav a").array() else { return [] }
        var result: [NavigationEntry] = []
        for link in links {
            do {
                let href = try link.attr("href")
                let label = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !href.isEmpty, !label.isEmpty else { continue }
                let path = normalizeEPUBPath(basePath: basePath, href: href)
                result.append(NavigationEntry(sourcePath: path, title: label, fragment: fragment(from: href)))
            } catch { continue }
        }
        return result
    }

    private func ncxEntries(from xml: String, basePath: String) -> [String: NavigationEntry] {
        var result: [String: NavigationEntry] = [:]
        for entry in ncxEntriesList(from: xml, basePath: basePath) where result[entry.sourcePath] == nil {
            result[entry.sourcePath] = entry
        }
        return result
    }

    private func ncxEntriesList(from xml: String, basePath: String) -> [NavigationEntry] {
        guard let document = try? SwiftSoup.parse(xml),
              let points = try? document.select("navPoint").array() else { return [] }
        var result: [NavigationEntry] = []
        for point in points {
            do {
                guard let content = try point.select("content").first(),
                      let text = try point.select("navLabel text").first() else { continue }
                let src = try content.attr("src")
                let label = try text.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !src.isEmpty, !label.isEmpty else { continue }
                let path = normalizeEPUBPath(basePath: basePath, href: src)
                result.append(NavigationEntry(sourcePath: path, title: label, fragment: fragment(from: src)))
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

    /// Maps an EPUB fragment id/name to the paragraph index used by the
    /// normalized chapter model. This is best effort: malformed XHTML or an
    /// anchor outside a text block simply leaves the index nil.
    private func paragraphIndex(for fragment: String, in html: String) -> Int? {
        do {
            let document = try SwiftSoup.parse(html)
            let nodes = try document.select("h1, h2, h3, h4, h5, h6, p, li, blockquote, pre").array()
            var paragraphIndex = 0
            for node in nodes {
                let text = try node.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let nodeID = try node.attr("id")
                let nodeName = try node.attr("name")
                if nodeID == fragment || nodeName == fragment {
                    return paragraphIndex
                }
                // A number of EPUB generators put the anchor on an empty
                // inline element inside the paragraph instead of on the
                // block itself. Treat that anchor as the same paragraph
                // target so fragment jumps do not silently land at the top.
                let nestedAnchors = try node.select("[id], [name]").array()
                if try nestedAnchors.contains(where: { anchor in
                    try anchor.attr("id") == fragment || anchor.attr("name") == fragment
                }) {
                    return paragraphIndex
                }
                paragraphIndex += 1
            }
        } catch {
            return nil
        }
        return nil
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
    let sourcePath: String
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
