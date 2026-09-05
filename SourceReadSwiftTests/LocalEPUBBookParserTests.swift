import XCTest
import ZIPFoundation
@testable import SourceReadSwift

final class LocalEPUBBookParserTests: XCTestCase {
    func testParsesMinimalEPUB() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let epubURL = root.appendingPathComponent("sample.epub")
        guard let archive = Archive(url: epubURL, accessMode: .create) else {
            return XCTFail("failed to create epub archive")
        }

        try add("mimetype", text: "application/epub+zip", to: archive)
        try add(
            "META-INF/container.xml",
            text: #"""
            <?xml version="1.0"?>
            <container version="1.0">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """#,
            to: archive
        )
        try add(
            "OEBPS/content.opf",
            text: #"""
            <package>
              <metadata>
                <dc:title>Sample Book</dc:title>
                <dc:creator>Author</dc:creator>
              </metadata>
              <manifest>
                <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="c1"/>
              </spine>
            </package>
            """#,
            to: archive
        )
        try add(
            "OEBPS/chapter1.xhtml",
            text: #"""
            <html><head><title>Chapter One</title></head><body><h1>Chapter One</h1><p>Hello</p><p>World</p></body></html>
            """#,
            to: archive
        )

        let book = try LocalEPUBBookParser().parse(fileURL: epubURL)

        XCTAssertEqual(book.title, "Sample Book")
        XCTAssertEqual(book.author, "Author")
        XCTAssertEqual(book.chapters.count, 1)
        XCTAssertEqual(book.chapters.first?.title, "Chapter One")
        XCTAssertEqual(book.chapters.first?.paragraphs, ["Chapter One", "Hello", "World"])
        try? FileManager.default.removeItem(at: root)
    }

    func testParsesPercentEncodedSpinePathAndBrFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let epubURL = root.appendingPathComponent("encoded.epub")
        guard let archive = Archive(url: epubURL, accessMode: .create) else { return XCTFail("failed to create epub archive") }
        try add("META-INF/container.xml", text: #"<container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>"#, to: archive)
        try add("OEBPS/book.opf", text: #"<package><metadata><dc:title>Encoded</dc:title></metadata><manifest><item id="c" href="chap%20one.xhtml"/></manifest><spine><itemref idref="c"/></spine></package>"#, to: archive)
        try add("OEBPS/chap one.xhtml", text: #"<html><body><h1>One</h1>Line A<br/>Line B</body></html>"#, to: archive)

        let book = try LocalEPUBBookParser().parse(fileURL: epubURL)
        XCTAssertEqual(book.title, "Encoded")
        XCTAssertEqual(book.chapters.first?.title, "One")
        XCTAssertTrue(book.chapters.first?.paragraphs.contains("Line A Line B") == true)
        try? FileManager.default.removeItem(at: root)
    }

    func testUsesHTMLManifestOrderWhenSpineIsMissing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let epubURL = root.appendingPathComponent("no-spine.epub")
        guard let archive = Archive(url: epubURL, accessMode: .create) else { return XCTFail("failed to create epub archive") }
        try add("META-INF/container.xml", text: #"<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>"#, to: archive)
        try add("book.opf", text: #"<package><metadata><dc:title>No Spine</dc:title></metadata><manifest><item id="cover" href="cover.jpg" media-type="image/jpeg"/><item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest></package>"#, to: archive)
        try add("chapter.xhtml", text: #"<html><body><h1>Chapter</h1><p>Body</p></body></html>"#, to: archive)

        let book = try LocalEPUBBookParser().parse(fileURL: epubURL)
        XCTAssertEqual(book.chapters.map(\.title), ["Chapter"])
        XCTAssertEqual(book.chapters.first?.paragraphs, ["Chapter", "Body"])
        try? FileManager.default.removeItem(at: root)
    }

    func testExtractsCoverImageFromManifest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let epubURL = root.appendingPathComponent("cover.epub")
        guard let archive = Archive(url: epubURL, accessMode: .create) else { return XCTFail("failed to create epub archive") }
        try add("META-INF/container.xml", text: #"<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>"#, to: archive)
        try add("book.opf", text: #"<package><metadata><dc:title>Cover Book</dc:title><meta name="cover" content="cover"/></metadata><manifest><item id="cover" href="images/cover.jpg" media-type="image/jpeg"/><item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>"#, to: archive)
        try add("chapter.xhtml", text: #"<html><body><h1>Chapter</h1><p>Body</p></body></html>"#, to: archive)
        try add("images/cover.jpg", data: Data([0xFF, 0xD8, 0xFF, 0xD9]), to: archive)

        let book = try LocalEPUBBookParser().parse(fileURL: epubURL)
        XCTAssertEqual(book.title, "Cover Book")
        XCTAssertTrue(book.coverURL?.isFileURL == true)
        XCTAssertTrue(book.coverURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        try? FileManager.default.removeItem(at: root)
    }

    func testUsesEPUB3NavigationLabelsForChapterTitles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let epubURL = root.appendingPathComponent("nav.epub")
        guard let archive = Archive(url: epubURL, accessMode: .create) else { return XCTFail("failed to create epub archive") }
        try add("META-INF/container.xml", text: #"<container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>"#, to: archive)
        try add("OEBPS/book.opf", text: #"<package><metadata><dc:title>Nav Book</dc:title></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>"#, to: archive)
        try add("OEBPS/nav.xhtml", text: #"<html><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml#start">目录标题</a></li></ol></nav></body></html>"#, to: archive)
        try add("OEBPS/chapter.xhtml", text: #"<html><body><h1>页面标题</h1><p>正文</p></body></html>"#, to: archive)

        let book = try LocalEPUBBookParser().parse(fileURL: epubURL)
        XCTAssertEqual(book.chapters.first?.title, "目录标题")
        try? FileManager.default.removeItem(at: root)
    }

    func testSkipsNonLinearSpineAndPreservesMetadataAndNavigationFragment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let epubURL = root.appendingPathComponent("linear.epub")
        guard let archive = Archive(url: epubURL, accessMode: .create) else { return XCTFail("failed to create epub archive") }
        try add("META-INF/container.xml", text: #"<container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>"#, to: archive)
        try add("OEBPS/book.opf", text: #"<package><metadata><dc:title>Linear</dc:title><dc:creator>A</dc:creator><dc:language>zh-CN</dc:language><dc:publisher>Pub</dc:publisher></metadata><manifest><item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/><item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest><spine><itemref idref="cover" linear="no"/><itemref idref="c1"/></spine></package>"#, to: archive)
        try add("OEBPS/nav.xhtml", text: #"<nav><a href="chapter.xhtml#anchor">第一章</a></nav>"#, to: archive)
        try add("OEBPS/cover.xhtml", text: #"<html><body><p>Cover only</p></body></html>"#, to: archive)
        try add("OEBPS/chapter.xhtml", text: #"<html><body><h1>Chapter</h1><p id="anchor">Body</p></body></html>"#, to: archive)

        let book = try LocalEPUBBookParser().parse(fileURL: epubURL)
        XCTAssertEqual(book.language, "zh-CN")
        XCTAssertEqual(book.publisher, "Pub")
        XCTAssertEqual(book.chapters.map(\.title), ["第一章"])
        XCTAssertEqual(book.chapters.first?.navigationFragment, "anchor")
        XCTAssertEqual(book.chapters.first?.sourcePath, "OEBPS/chapter.xhtml")
        try? FileManager.default.removeItem(at: root)
    }

    func testPreservesMultipleEPUB3FragmentNavigationEntriesInOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let epubURL = root.appendingPathComponent("fragment-navigation.epub")
        guard let archive = Archive(url: epubURL, accessMode: .create) else { return XCTFail("failed to create epub archive") }
        try add("META-INF/container.xml", text: #"<container><rootfiles><rootfile full-path="OPS/package.opf"/></rootfiles></container>"#, to: archive)
        try add("OPS/package.opf", text: #"<package><metadata><dc:title>Anchors</dc:title></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="chapter" href="text/chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>"#, to: archive)
        try add("OPS/nav.xhtml", text: #"<html><body><nav epub:type="toc"><ol><li><a href="text/chapter.xhtml#one">第一节</a></li><li><a href="text/chapter.xhtml#two">第二节</a></li></ol></nav></body></html>"#, to: archive)
        try add("OPS/text/chapter.xhtml", text: #"<html><body><h1 id="one">One</h1><p>A</p><h2 id="two">Two</h2><p>B</p></body></html>"#, to: archive)

        let book = try LocalEPUBBookParser().parse(fileURL: epubURL)

        XCTAssertEqual(book.chapters.count, 1)
        XCTAssertEqual(book.navigationEntries.map(\.title), ["第一节", "第二节"])
        XCTAssertEqual(book.navigationEntries.map(\.sourcePath), ["OPS/text/chapter.xhtml", "OPS/text/chapter.xhtml"])
        XCTAssertEqual(book.navigationEntries.map(\.fragment), ["one", "two"])
        XCTAssertEqual(book.navigationEntries.compactMap(\.chapterIndex), [0, 0])
        XCTAssertEqual(book.navigationEntries.compactMap(\.paragraphIndex), [0, 2])
        try? FileManager.default.removeItem(at: root)
    }

    func testMapsNestedAnchorFragmentToContainingParagraph() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let epubURL = root.appendingPathComponent("nested-anchor.epub")
        guard let archive = Archive(url: epubURL, accessMode: .create) else { return XCTFail("failed to create epub archive") }
        try add("META-INF/container.xml", text: #"<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>"#, to: archive)
        try add("book.opf", text: #"<package><metadata><dc:title>Nested</dc:title></metadata><manifest><item id="nav" href="nav.xhtml" properties="nav"/><item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>"#, to: archive)
        try add("nav.xhtml", text: #"<nav><a href="chapter.xhtml#anchor">正文入口</a></nav>"#, to: archive)
        try add("chapter.xhtml", text: #"<html><body><h1>Chapter</h1><p><a id="anchor"></a>Body text</p></body></html>"#, to: archive)

        let book = try LocalEPUBBookParser().parse(fileURL: epubURL)

        XCTAssertEqual(book.navigationEntries.first?.title, "正文入口")
        XCTAssertEqual(book.navigationEntries.first?.paragraphIndex, 1)
        try? FileManager.default.removeItem(at: root)
    }

    func testNormalizesEncodedPackagePathAndHrefQueryBeforeArchiveLookup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let epubURL = root.appendingPathComponent("encoded-package.epub")
        guard let archive = Archive(url: epubURL, accessMode: .create) else { return XCTFail("failed to create epub archive") }
        try add("META-INF/container.xml", text: #"<container><rootfiles><rootfile full-path="OPS%20Files/package.opf"/></rootfiles></container>"#, to: archive)
        try add("OPS Files/package.opf", text: #"<package><metadata><dc:title>Encoded package</dc:title></metadata><manifest><item id="c1" href="text/chapter%20one.xhtml?cache=1" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>"#, to: archive)
        try add("OPS Files/text/chapter one.xhtml", text: #"<html><body><h1>Chapter</h1><p>Body</p></body></html>"#, to: archive)

        let book = try LocalEPUBBookParser().parse(fileURL: epubURL)
        XCTAssertEqual(book.chapters.first?.sourcePath, "OPS Files/text/chapter one.xhtml")
        XCTAssertEqual(book.chapters.first?.paragraphs, ["Chapter", "Body"])
        try? FileManager.default.removeItem(at: root)
    }

    func testPrefersTypedTOCNavOverLandmarksNav() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let epubURL = root.appendingPathComponent("typed-nav.epub")
        guard let archive = Archive(url: epubURL, accessMode: .create) else { return XCTFail("failed to create epub archive") }
        try add("META-INF/container.xml", text: #"<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>"#, to: archive)
        try add("book.opf", text: #"<package><metadata><dc:title>Typed nav</dc:title></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>"#, to: archive)
        try add("nav.xhtml", text: #"<html><body><nav epub:type="landmarks"><a href="cover.xhtml">封面</a></nav><nav epub:type="toc"><a href="chapter.xhtml">正文</a></nav></body></html>"#, to: archive)
        try add("chapter.xhtml", text: #"<html><body><h1>Chapter</h1><p>Body</p></body></html>"#, to: archive)

        let book = try LocalEPUBBookParser().parse(fileURL: epubURL)
        XCTAssertEqual(book.navigationEntries.map(\.title), ["正文"])
        try? FileManager.default.removeItem(at: root)
    }

    private func add(_ path: String, text: String, to archive: Archive) throws {
        try add(path, data: Data(text.utf8), to: archive)
    }

    private func add(_ path: String, data: Data, to archive: Archive) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
            let start = Int(position)
            let end = start + Int(size)
            return data.subdata(in: start..<end)
        }
    }
}
