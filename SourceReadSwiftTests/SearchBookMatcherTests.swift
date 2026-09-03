import XCTest
@testable import SourceReadSwift

final class SearchBookMatcherTests: XCTestCase {
    func testExactSearchNormalizesBookTitleMarksWidthAndWhitespace() {
        let books = [
            SearchBook(name: "《斗 破苍穹》", author: "天蚕土豆", coverUrl: nil, bookUrl: "/1", sourceName: "A", sourceUrl: "https://a", intro: nil),
            SearchBook(name: "斗破苍穹前传", author: "作者", coverUrl: nil, bookUrl: "/2", sourceName: "B", sourceUrl: "https://b", intro: nil)
        ]
        let result = SearchBookMatcher.filteredAndRanked(books, keyword: "斗破苍穹", exact: true)
        XCTAssertEqual(result.map(\.bookUrl), ["/1"])
    }

    func testFuzzySearchFiltersNoiseAndRanksExactTitleFirst() {
        let books = [
            SearchBook(name: "无关结果", author: "其他", coverUrl: nil, bookUrl: "/noise", sourceName: "A", sourceUrl: "https://a", intro: nil),
            SearchBook(name: "斗破苍穹前传", author: "作者", coverUrl: nil, bookUrl: "/prefix", sourceName: "B", sourceUrl: "https://b", intro: nil),
            SearchBook(name: "斗破苍穹", author: "天蚕土豆", coverUrl: nil, bookUrl: "/exact", sourceName: "C", sourceUrl: "https://c", intro: nil)
        ]
        let result = SearchBookMatcher.filteredAndRanked(books, keyword: "斗破苍穹", exact: false)
        XCTAssertEqual(result.map(\.bookUrl), ["/exact", "/prefix"])
    }

    func testDeduplicatesSameSourceAndBookURL() {
        let item = SearchBook(name: "测试书", author: "作者", coverUrl: nil, bookUrl: "/same", sourceName: "A", sourceUrl: "https://a", intro: nil)
        let result = SearchBookMatcher.filteredAndRanked([item, item], keyword: "测试书", exact: true)
        XCTAssertEqual(result.count, 1)
    }
}
