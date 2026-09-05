import Foundation
import XCTest
@testable import SourceReadSwift

/// End-to-end transport fixtures for hosts that return compressed HTML while
/// keeping the same Legado rule surface.  The injected client deliberately
/// returns an empty text body and only bytes, proving the production engine
/// normalizes custom network adapters before parsing.
final class SourceEngineCompressedFixtureTests: XCTestCase {
    func testPipelineDecodesGzipAndDeflateAcrossAllStages() async throws {
        let source = BookSource(
            bookSourceName: "Compressed fixture",
            bookSourceUrl: "https://fixture.example/compressed",
            searchUrl: "https://fixture.example/compressed/search?q={{key}}",
            ruleSearch: SourceRule(fields: [
                "bookList": ".book", "name": "h2@text", "bookUrl": "a@href"
            ]),
            ruleBookInfo: SourceRule(fields: ["name": "h1@text", "tocUrl": "a.toc@href"]),
            ruleToc: SourceRule(fields: [
                "chapterList": ".chapter", "chapterName": "a@text", "chapterUrl": "a@href"
            ]),
            ruleContent: SourceRule(fields: ["content": "#content@text"])
        )
        let searchURL = "https://fixture.example/compressed/search?q=book"
        let bookURL = "https://fixture.example/compressed/book/1"
        let tocURL = "https://fixture.example/compressed/toc/1"
        let chapterURL = "https://fixture.example/compressed/chapter/1"
        let network = CompressedFixtureNetwork(responses: [
            searchURL: .gzip([
                31, 139, 8, 0, 0, 0, 0, 0, 2, 255, 179, 73, 201, 44, 83, 72, 206, 73,
                44, 46, 182, 85, 74, 202, 207, 207, 86, 178, 179, 201, 48, 178, 115,
                206, 207, 45, 40, 74, 45, 46, 78, 77, 81, 112, 2, 10, 218, 232, 3,
                197, 108, 18, 21, 50, 138, 82, 211, 108, 149, 244, 147, 225, 178, 250,
                32, 45, 250, 134, 74, 118, 142, 165, 37, 25, 249, 69, 54, 250, 137,
                118, 54, 250, 64, 19, 237, 0, 149, 182, 162, 12, 87, 0, 0, 0
            ]),
            bookURL: .gzip([
                31, 139, 8, 0, 0, 0, 0, 0, 2, 255, 179, 201, 48, 180, 115, 206, 207,
                45, 40, 74, 45, 46, 78, 77, 81, 112, 202, 207, 207, 182, 209, 7,
                138, 217, 36, 42, 36, 231, 36, 22, 23, 219, 42, 149, 228, 39, 43,
                41, 100, 20, 165, 166, 217, 42, 233, 39, 195, 85, 234, 3, 133,
                245, 13, 149, 236, 66, 252, 157, 109, 244, 19, 237, 0, 151, 191,
                71, 227, 71, 0, 0, 0
            ]),
            tocURL: .deflate([
                120, 156, 179, 73, 201, 44, 83, 72, 206, 73, 44, 46, 182, 85, 74, 206,
                72, 44, 40, 73, 45, 82, 178, 179, 73, 84, 200, 40, 74, 77, 179, 85,
                210, 79, 206, 207, 45, 40, 74, 45, 46, 78, 77, 209, 135, 202, 234,
                27, 42, 217, 57, 67, 152, 10, 134, 54, 250, 137, 118, 54, 250, 41,
                153, 101, 118, 0, 142, 162, 24, 101
            ]),
            chapterURL: .deflate([
                120, 156, 179, 73, 201, 44, 83, 200, 76, 177, 85, 74, 206, 207, 43,
                73, 205, 43, 81, 178, 115, 206, 207, 45, 40, 74, 45, 46, 78, 77, 81,
                128, 138, 217, 232, 167, 100, 150, 217, 1, 0, 66, 220, 15, 67
            ])
        ])
        let engine = LegadoSourceEngine(network: network)

        let execution = await engine.runPipelineReport(source: source, keyword: "book", timeout: 1)
        XCTAssertNil(execution.error)
        XCTAssertEqual(execution.result.steps.map(\.stage), [.search, .detail, .toc, .content])
        XCTAssertEqual(execution.result.searchBooks.first?.name, "Compressed Book")
        XCTAssertEqual(execution.result.chapters.first?.title, "Chapter 1")
        XCTAssertEqual(execution.result.content?.paragraphs, ["Compressed content"])

        let searchEvidence = try XCTUnwrap(engine.diagnosticEvidence(sourceURL: source.bookSourceUrl, stage: .search))
        XCTAssertEqual(searchEvidence.responseContentEncodings, ["gzip"])
        XCTAssertTrue(searchEvidence.responseWasDecoded)
        XCTAssertEqual(searchEvidence.responseEncodedByteCount, 94)
        XCTAssertEqual(searchEvidence.responseDecodedByteCount, 87)

        let tocEvidence = try XCTUnwrap(engine.diagnosticEvidence(sourceURL: source.bookSourceUrl, stage: .toc))
        XCTAssertEqual(tocEvidence.responseContentEncodings, ["deflate"])
        XCTAssertTrue(tocEvidence.responseWasDecoded)
    }
}

private final class CompressedFixtureNetwork: SourceNetworkClient, @unchecked Sendable {
    struct Payload: Sendable {
        let data: Data
        let encoding: String

        static func gzip(_ bytes: [UInt8]) -> Payload {
            Payload(data: Data(bytes), encoding: "gzip")
        }

        static func deflate(_ bytes: [UInt8]) -> Payload {
            Payload(data: Data(bytes), encoding: "deflate")
        }
    }

    private let responses: [String: Payload]

    init(responses: [String: Payload]) { self.responses = responses }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        guard let payload = responses[request.url.absoluteString] else {
            return .failure(.network("compressed fixture missing: \(request.url.absoluteString)"))
        }
        return .success(SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: ["Content-Type": "text/html", "Content-Encoding": payload.encoding],
            body: "",
            data: payload.data
        ))
    }
}
