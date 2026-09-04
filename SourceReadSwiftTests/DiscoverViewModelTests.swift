import XCTest
@testable import SourceReadSwift

@MainActor
final class DiscoverViewModelTests: XCTestCase {
    func testClearSearchCancelsAndResetsAllVisibleState() {
        let viewModel = DiscoverViewModel()
        viewModel.keyword = "三体"
        viewModel.results = [
            SearchBook(
                name: "三体",
                author: "刘慈欣",
                coverUrl: nil,
                bookUrl: "https://fixture.invalid/book/1",
                sourceName: "Fixture",
                sourceUrl: "https://fixture.invalid",
                intro: nil
            )
        ]
        viewModel.errorMessage = "fixture error"
        viewModel.checkedSourceCount = 3
        viewModel.hitSourceCount = 1
        viewModel.totalResultCount = 1
        viewModel.resultFilter = "Fixture"

        viewModel.clearSearch()

        XCTAssertEqual(viewModel.keyword, "")
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertFalse(viewModel.hasSearchState)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.checkedSourceCount, 0)
        XCTAssertEqual(viewModel.hitSourceCount, 0)
        XCTAssertEqual(viewModel.totalResultCount, 0)
        XCTAssertEqual(viewModel.resultFilter, "")
    }

    func testClearSearchIsSafeWhenNoSearchHasStarted() {
        let viewModel = DiscoverViewModel()

        viewModel.clearSearch()

        XCTAssertEqual(viewModel.keyword, "")
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertFalse(viewModel.isSearching)
        XCTAssertFalse(viewModel.hasSearchState)
    }
}
