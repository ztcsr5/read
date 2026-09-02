import XCTest
@testable import SourceReadSwift

final class SearchResultFilterTests: XCTestCase {
    private let books = [
        SearchBook(name: "星河旅人", author: "甲作者", coverUrl: nil, bookUrl: "https://a.example/book/1", sourceName: "甲源", sourceUrl: "https://a.example", intro: nil),
        SearchBook(name: "山海经", author: "乙作者", coverUrl: nil, bookUrl: "https://b.example/book/2", sourceName: "乙源", sourceUrl: "https://b.example", intro: nil)
    ]

    func testFilterByAuthorAndSource() {
        XCTAssertEqual(SearchResultFilter.apply(books, query: "乙作", scope: .author).map(\.name), ["山海经"])
        XCTAssertEqual(SearchResultFilter.apply(books, query: "a.example", scope: .source).map(\.name), ["星河旅人"])
    }

    func testAllScopeMatchesAddressAndEmptyQueryPreservesResults() {
        XCTAssertEqual(SearchResultFilter.apply(books, query: "book/2", scope: .all).map(\.name), ["山海经"])
        XCTAssertEqual(SearchResultFilter.apply(books, query: "", scope: .title).count, books.count)
    }
}
