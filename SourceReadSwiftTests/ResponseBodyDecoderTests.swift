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

    func testDecodeResultExposesTransportMetadata() {
        let decoder = ResponseBodyDecoder()
        let result = decoder.decodeResult(data: Data(gzip), headers: ["Content-Encoding": "gzip"])

        XCTAssertEqual(result.data, Data("hello legado".utf8))
        XCTAssertEqual(result.encodings, ["gzip"])
        XCTAssertTrue(result.wasDecoded)
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
        XCTAssertEqual(normalized.encodedByteCount, gzip.count)
        XCTAssertEqual(normalized.contentEncodings, ["gzip"])
        XCTAssertTrue(normalized.bodyWasDecoded)
    }

    func testNormalizeRetainsUnsupportedTransportMetadataWithoutPartialDecode() {
        let payload = Data("already decoded".utf8)
        let response = SourceResponse(
            url: URL(string: "https://fixture.example/unsupported")!,
            statusCode: 200,
            headers: ["Content-Encoding": "br"],
            body: "already decoded",
            data: payload
        )

        let normalized = ResponseBodyDecoder().normalize(response)
        XCTAssertEqual(normalized.body, response.body)
        XCTAssertEqual(normalized.data, payload)
        XCTAssertEqual(normalized.encodedByteCount, payload.count)
        XCTAssertEqual(normalized.contentEncodings, ["br"])
        XCTAssertFalse(normalized.bodyWasDecoded)
    }

    func testDecodesStackedContentCodingsInReverseOrder() {
        let decoder = ResponseBodyDecoder()
        let stacked = [
            120, 156, 147, 239, 230, 96, 0, 1, 166, 255, 218, 122, 158, 62, 231, 252,
            124, 3, 79, 120, 250, 250, 251, 156, 100, 103, 168, 231, 243, 250, 199,
            199, 192, 192, 0, 0, 150, 92, 9, 8
        ].map(UInt8.init)

        XCTAssertEqual(
            decoder.decode(data: Data(stacked), headers: ["Content-Encoding": "gzip, deflate"]),
            Data("stacked legado".utf8)
        )
        XCTAssertEqual(
            decoder.decode(data: Data(gzip), headers: ["Content-Encoding": "x-gzip"]),
            Data("hello legado".utf8)
        )
    }
}
