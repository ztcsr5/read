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

    private func add(_ path: String, text: String, to archive: Archive) throws {
        let data = Data(text.utf8)
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
            let start = Int(position)
            let end = start + Int(size)
            return data.subdata(in: start..<end)
        }
    }
}
