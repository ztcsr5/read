import Foundation
import JavaScriptCore

/// JavaScript-facing model objects used by Android Legado sources. They intentionally
/// expose the same camelCase names as the Android data classes while retaining the
/// native Swift models as the source of truth.
@objc protocol LegadoSearchBookExport: JSExport {
    var bookUrl: String { get set }
    var tocUrl: String { get set }
    var origin: String { get set }
    var originName: String { get set }
    var name: String { get set }
    var author: String { get set }
    var kind: String { get set }
    var coverUrl: String { get set }
    var intro: String { get set }
    var latestChapterTitle: String { get set }
    var wordCount: String { get set }
    var variable: String { get set }
    func putVariable(_ key: String, _ value: String)
}

final class LegadoSearchBookBridge: NSObject, LegadoSearchBookExport {
    var bookUrl = ""; var tocUrl = ""; var origin = ""; var originName = ""
    var name = ""; var author = ""; var kind = ""; var coverUrl = ""; var intro = ""
    var latestChapterTitle = ""; var wordCount = ""; var variable = ""
    private var variables: [String: String] = [:]
    func putVariable(_ key: String, _ value: String) { variables[key] = value; variable = value }
    init(book: SearchBook) {
        bookUrl = book.bookUrl; origin = book.sourceUrl; originName = book.sourceName
        name = book.name; author = book.author ?? ""; coverUrl = book.coverUrl ?? ""; intro = book.intro ?? ""
        super.init()
    }
}

@objc protocol LegadoBookChapterExport: JSExport {
    var url: String { get set }; var title: String { get set }; var bookUrl: String { get set }
    var index: Int { get set }; var resourceUrl: String { get set }; var tag: String { get set }; var variable: String { get set }
    func putVariable(_ key: String, _ value: String)
    func isVip() -> Bool
}

final class LegadoBookChapterBridge: NSObject, LegadoBookChapterExport {
    var url = ""; var title = ""; var bookUrl = ""; var index = 0; var resourceUrl = ""; var tag = ""; var variable = ""
    private var variables: [String: String] = [:]
    func putVariable(_ key: String, _ value: String) { variables[key] = value; variable = value }
    func isVip() -> Bool { let text = title.lowercased(); return text.contains("vip") || text.contains("订阅") || text.contains("付费") }
    init(chapter: BookChapter) { url = chapter.url; title = chapter.title; bookUrl = chapter.bookUrl; index = chapter.index; super.init() }
}

@objc protocol LegadoResponseExport: JSExport {
    var body: String { get }; var url: String { get }; var statusCode: Int { get }
    func text() -> String
    func header(_ name: String) -> String
}

final class LegadoResponseBridge: NSObject, LegadoResponseExport {
    let body: String; let url: String; let statusCode: Int; private let headers: [String: String]
    init(response: SourceResponse) { body = response.body; url = response.url.absoluteString; statusCode = response.statusCode; headers = response.headers; super.init() }
    init(body: String, url: String, statusCode: Int = 200, headers: [String: String] = [:]) { self.body = body; self.url = url; self.statusCode = statusCode; self.headers = headers; super.init() }
    func text() -> String { body }
    func header(_ name: String) -> String { headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value ?? "" }
}
