import Foundation

protocol SourceEngine: Sendable {
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError>
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError>
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError>
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError>
}

final class LegadoSourceEngine: SourceEngine {
    private let network: SourceNetworkClient
    private let diagnostics: DiagnosticSink

    init(
        network: SourceNetworkClient = URLSessionSourceNetworkClient(),
        diagnostics: DiagnosticSink = .noop
    ) {
        self.network = network
        self.diagnostics = diagnostics
    }

    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        guard let searchUrl = source.searchUrl, !searchUrl.isEmpty else {
            return .failure(.invalidSource("searchUrl 为空"))
        }

        await diagnostics.emit(.init(
            level: .info,
            stage: "search.prepare",
            sourceName: source.bookSourceName,
            message: "准备搜索",
            details: ["keyword": keyword, "page": String(page)]
        ))

        let requestBuilder = SourceRequestBuilder()
        let request = requestBuilder.buildSearchRequest(source: source, searchUrl: searchUrl, keyword: keyword, page: page)

        switch await network.load(request) {
        case .success(let response):
            guard !response.body.isEmpty else {
                return .failure(.empty("搜索响应为空"))
            }
            let parser = SearchResultParser()
            return parser.parse(source: source, response: response)
        case .failure(let error):
            return .failure(error)
        }
    }

    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        .failure(.unsupported("Book detail parser not implemented yet"))
    }

    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        .failure(.unsupported("Chapter parser not implemented yet"))
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        .failure(.unsupported("Content parser not implemented yet"))
    }
}

