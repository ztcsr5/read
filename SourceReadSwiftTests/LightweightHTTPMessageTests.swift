import XCTest
@testable import SourceReadSwift

final class LightweightHTTPMessageTests: XCTestCase {
    func testParserWaitsForBodyBytesAndPreservesUTF8Body() {
        let header = "POST /api/sources/import?from=pc HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: 16\r\n\r\n"
        let partial = Data((header + "{\"name\":\"书").utf8)
        if case .incomplete = LightweightHTTPParser.parse(partial) {
            // expected: the body is split at a TCP packet boundary
        } else {
            XCTFail("parser should wait for the declared byte count")
        }

        let body = "{\"name\":\"书\"}"
        let request = Data((header.replacingOccurrences(of: "16", with: String(body.utf8.count)) + body).utf8)
        guard case .complete(let parsed) = LightweightHTTPParser.parse(request) else {
            return XCTFail("request should parse")
        }
        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.path, "/api/sources/import")
        XCTAssertEqual(parsed.query, "from=pc")
        XCTAssertEqual(String(data: parsed.body, encoding: .utf8), body)
    }

    func testParserRejectsChunkedAndOversizedRequests() {
        let chunked = Data("POST /import HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        if case .failure(let code, _) = LightweightHTTPParser.parse(chunked) {
            XCTAssertEqual(code, 501)
        } else {
            XCTFail("chunked requests should be explicit and deterministic")
        }

        let oversized = Data("POST /import HTTP/1.1\r\nContent-Length: 999999999\r\n\r\n".utf8)
        if case .failure(let code, _) = LightweightHTTPParser.parse(oversized) {
            XCTAssertEqual(code, 413)
        } else {
            XCTFail("oversized body should be rejected before buffering")
        }
    }

    func testParserAcceptsHeadWithoutBodyAndNormalizesHeaders() {
        let request = Data("HEAD /health HTTP/1.1\r\nhOsT: localhost\r\n\r\n".utf8)
        guard case .complete(let parsed) = LightweightHTTPParser.parse(request) else {
            return XCTFail("HEAD request should parse")
        }
        XCTAssertEqual(parsed.method, "HEAD")
        XCTAssertEqual(parsed.path, "/health")
        XCTAssertEqual(parsed.headers["host"], "localhost")
        XCTAssertTrue(parsed.body.isEmpty)
    }
}
