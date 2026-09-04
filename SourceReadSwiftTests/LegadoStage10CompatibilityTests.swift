import XCTest
@testable import SourceReadSwift

/// Stage 10 covers the remaining high-frequency CryptoJS cipher shapes used
/// by Android/Legado sources: passphrase envelopes, ECB/zero/no padding and
/// two-key TripleDES.  The tests are offline and deterministic except for the
/// salt, which is validated through a decrypt round-trip.
final class LegadoStage10CompatibilityTests: XCTestCase {
    func testCryptoJSPassphraseEncryptRoundTripsOpenSSLEnvelope() throws {
        let result = JSCoreRuntime().evaluate("""
        var encrypted = CryptoJS.AES.encrypt('hello stage10', 'password');
        var encoded = encrypted.toString();
        var decrypted = CryptoJS.AES.decrypt(encrypted, 'password').toString(CryptoJS.enc.Utf8);
        JSON.stringify({prefix: encoded.substring(0, 8), decrypted: decrypted, stable: encoded === encrypted.toString()})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["prefix"] as? String, "U2FsdGVk")
        XCTAssertEqual(object["decrypted"] as? String, "hello stage10")
        XCTAssertEqual(object["stable"] as? Bool, true)
    }

    func testCryptoJSAESExplicitECBAndPaddingModes() throws {
        let result = JSCoreRuntime().evaluate("""
        var key = CryptoJS.enc.Hex.parse('00112233445566778899aabbccddeeff');
        var block = CryptoJS.enc.Hex.parse('00112233445566778899aabbccddeeff');
        var ecb = CryptoJS.AES.encrypt(block, key, {mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.NoPadding});
        var plain = CryptoJS.AES.decrypt(ecb, key, {mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.NoPadding});
        var zero = CryptoJS.AES.encrypt(CryptoJS.enc.Utf8.parse('zero'), key, {mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.ZeroPadding});
        var zeroPlain = CryptoJS.AES.decrypt(zero, key, {mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.ZeroPadding});
        JSON.stringify({ecb: ecb.toString(), block: CryptoJS.enc.Hex.stringify(plain), zero: CryptoJS.enc.Utf8.stringify(zeroPlain)})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["ecb"] as? String, "YvZ5vivw2TFkHgOco0Absg==")
        XCTAssertEqual(object["block"] as? String, "00112233445566778899aabbccddeeff")
        XCTAssertEqual(object["zero"] as? String, "zero")
    }

    func testCryptoJSTwoKeyTripleDESRoundTrips() throws {
        let result = JSCoreRuntime().evaluate("""
        var key = CryptoJS.enc.Utf8.parse('0123456789abcdef');
        var iv = CryptoJS.enc.Utf8.parse('12345678');
        var encrypted = CryptoJS.TripleDES.encrypt(CryptoJS.enc.Utf8.parse('hello 3des'), key, {iv: iv, mode: 'CBC', padding: CryptoJS.pad.Pkcs7});
        var decrypted = CryptoJS.TripleDES.decrypt(encrypted, key, {iv: iv, mode: 'CBC', padding: CryptoJS.pad.Pkcs7});
        JSON.stringify({cipher: encrypted.toString(), text: CryptoJS.enc.Utf8.stringify(decrypted)})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["text"] as? String, "hello 3des")
        XCTAssertEqual((object["cipher"] as? String)?.isEmpty, false)
    }

    private func jsonObject(from result: Result<String, SourceEngineError>, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("expected JSON result: \(result)", file: file, line: line)
            throw NSError(domain: "LegadoStage10Tests", code: 1)
        }
        return object
    }
}
