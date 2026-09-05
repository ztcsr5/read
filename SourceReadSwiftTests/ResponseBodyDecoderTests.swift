import XCTest
@testable import SourceReadSwift

final class ResponseBodyDecoderTests: XCTestCase {
    private let zlib = [120, 156, 203, 72, 205, 201, 201, 87, 200, 73, 77, 79, 76, 201, 7, 0, 30, 22, 4, 161].map(UInt8.init)
    private let gzip = [31, 139, 8, 0, 0, 0, 0, 0, 2, 255, 203, 72, 205, 201, 201, 87, 200, 73, 77, 79, 76, 201, 7, 0, 253, 112, 110, 222, 12, 0, 0, 0].map(UInt8.init)

    func testDecodesGzipAndDeflateContentEncoding() {
        let decoder = ResponseBodyDecoder()
        let expected = Data("hello legado".utf8)

        XCTAssertEqual(decoder.decode(data: Data(zlib), headers: ["Content-Encoding": "deflate"]), expected)
        XCTAssertEqual(decoder.decode(data: Data(gzip), headers: ["content-encoding": "gzip"]), expected)
    }

    func testPreservesUnsupportedOrAlreadyDecodedPayload() {
        let decoder = ResponseBodyDecoder()
        let plain = Data("already decoded".utf8)
        XCTAssertEqual(decoder.decode(data: plain, headers: ["Content-Encoding": "gzip"]), plain)
        XCTAssertEqual(decoder.decode(data: plain, headers: ["Content-Encoding": "br"]), plain)
        XCTAssertEqual(decoder.decode(data: plain, headers: [:]), plain)
    }

    func testNormalizesSourceResponseForInjectedClients() {
        let response = SourceResponse(
            url: URL(string: "https://fixture.example/compressed")!,
            statusCode: 200,
            headers: ["Content-Encoding": "gzip", "Content-Type": "text/plain; charset=utf-8"],
            body: "",
            data: Data(gzip)
        )

        let normalized = ResponseBodyDecoder().normalize(response)
        XCTAssertEqual(normalized.body, "hello legado")
        XCTAssertEqual(normalized.data, Data("hello legado".utf8))
        XCTAssertEqual(normalized.headers["Content-Encoding"], "gzip")
    }
}
