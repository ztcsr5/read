import XCTest
@testable import SourceReadSwift

/// Stage 9 locks the binary-facing Java/Android and CryptoJS shims against
/// deterministic fixtures.  These tests intentionally stay offline: all
/// crypto and decompression work happens inside the JSCore bridge.
final class LegadoStage9CompatibilityTests: XCTestCase {
    func testJavaEncodingCollectionsAndStreams() throws {
        let result = JSCoreRuntime().evaluate(#"""
        var encoded = Packages.java.net.URLEncoder.encode('a b+c/中文', 'UTF-8');
        var decoded = Packages.java.net.URLDecoder.decode(encoded, 'UTF-8');
        var range = Packages.java.util.Arrays.copyOfRange([1, 2, 3], 1, 5);
        var list = Packages.java.util.Arrays.asList('a', 'b');
        var out = new Packages.java.io.ByteArrayOutputStream();
        out.write([65, 66, 67], 1, 2);
        out.write(68);
        var input = new Packages.java.io.ByteArrayInputStream([1, 2, 3]);
        var read = [input.read(), input.read(), input.available(), input.skip(1), input.read()];
        JSON.stringify({encoded: encoded, decoded: decoded, range: range, list: [list.size(), list.get(1)], output: out.toString(), read: read})
        """#)

        let object = try jsonObject(from: result)
        XCTAssertEqual(object["encoded"] as? String, "a+b%2Bc%2F%E4%B8%AD%E6%96%87")
        XCTAssertEqual(object["decoded"] as? String, "a b+c/中文")
        XCTAssertEqual(object["range"] as? [Int], [2, 3, 0, 0])
        XCTAssertEqual(object["list"] as? [Int], [2, 1])
        XCTAssertEqual(object["output"] as? String, "BCD")
        XCTAssertEqual(object["read"] as? [Int], [1, 2, 1, 1, -1])
    }

    func testInflaterInputStreamSupportsZlibFixture() throws {
        // zlib.compress(b"hello legado")
        let compressed = [120, 156, 203, 72, 205, 201, 201, 87, 200, 73, 77, 79, 76, 201, 7, 0, 30, 22, 4, 161]
        let result = JSCoreRuntime().evaluate("""
        var stream = new Packages.java.util.zip.InflaterInputStream(compressed);
        var bytes = [];
        var value;
        while ((value = stream.read()) >= 0) bytes.push(value);
        bytesToStr(bytes)
        """, variables: ["compressed": compressed])
        guard case .success(let value) = result else {
            return XCTFail("expected inflate success: \(result)")
        }
        XCTAssertEqual(value, "hello legado")
    }

    func testIntegerLongImporterAndDigestApis() throws {
        let result = JSCoreRuntime().evaluate("""
        var imported = JavaImporter();
        imported.importPackage(Packages.java.util);
        imported.importClass(Packages.java.lang.Integer);
        var digest = Packages.java.security.MessageDigest.getInstance('SHA-256').digest('abc'.getBytes());
        var mac = Packages.javax.crypto.Mac.getInstance('HmacSHA256');
        mac.init(new Packages.javax.crypto.spec.SecretKeySpec('key'.getBytes(), 'HmacSHA256'));
        var streaming = Packages.java.security.MessageDigest.getInstance('SHA-224');
        streaming.update('a'.getBytes()); streaming.update('bc'.getBytes());
        var mac224 = Packages.javax.crypto.Mac.getInstance('HmacSHA224');
        mac224.init(new Packages.javax.crypto.spec.SecretKeySpec('key'.getBytes(), 'HmacSHA224'));
        var encodedBytes = Packages.java.util.Base64.getEncoder().encode('abc'.getBytes());
        JSON.stringify({integer: Packages.java.lang.Integer.toString(255, 16), long: Packages.java.lang.Long.parseLong('42'), imported: imported.Arrays.equals([1, 2], [1, 2]), digest: Packages.java.util.Base64.encodeToString(digest), mac: Packages.java.util.Base64.encodeToString(mac.doFinal('abc'.getBytes())), sha224: Packages.java.util.Base64.encodeToString(streaming.digest()), hmac224: Packages.java.util.Base64.encodeToString(mac224.doFinal('abc'.getBytes())), encodedBytes: Packages.java.util.Base64.getDecoder().decode(encodedBytes)})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["integer"] as? String, "ff")
        XCTAssertEqual(object["long"] as? Int, 42)
        XCTAssertEqual(object["imported"] as? Bool, true)
        XCTAssertEqual(object["digest"] as? String, "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=")
        XCTAssertEqual(object["mac"] as? String, "nBluMtwBdfhvSxy4konWYZ3mvuaZ5MN45oMJ7Zehpqs=")
        XCTAssertEqual(object["sha224"] as? String, "Iwl9IjQF2CKGQqR3vaJVsyqtvOS9oLP342ydpw==")
        XCTAssertEqual(object["hmac224"] as? String, "9SRnC3408xRn3gqpZZOGHPZRF9QU+y2GFY12Dg==")
        XCTAssertEqual(object["encodedBytes"] as? [Int], [97, 98, 99])
    }

    func testCryptoJSWordArraysAndAESCipherFixtures() throws {
        let result = JSCoreRuntime().evaluate("""
        var key = CryptoJS.enc.Utf8.parse('0123456789abcdef');
        var iv = CryptoJS.enc.Utf8.parse('abcdef0123456789');
        var plain = CryptoJS.enc.Utf8.parse('hello legado');
        var encrypted = CryptoJS.AES.encrypt(plain, key, {iv: iv, mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7});
        var decrypted = CryptoJS.AES.decrypt(encrypted, key, {iv: iv, mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7});
        JSON.stringify({hex: CryptoJS.enc.Hex.stringify(plain), base64: encrypted.toString(), text: CryptoJS.enc.Utf8.stringify(decrypted), latin: CryptoJS.enc.Latin1.stringify(CryptoJS.enc.Latin1.parse('ABC'))})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["hex"] as? String, "68656c6c6f206c656761646f")
        XCTAssertEqual(object["base64"] as? String, "vJ5ACeBMmCz2biliGgiqvw==")
        XCTAssertEqual(object["text"] as? String, "hello legado")
        XCTAssertEqual(object["latin"] as? String, "ABC")
    }

    func testCryptoJSDESAndJavaCipherFixtures() throws {
        let result = JSCoreRuntime().evaluate("""
        var desKey = CryptoJS.enc.Utf8.parse('12345678');
        var desIV = CryptoJS.enc.Utf8.parse('abcdefgh');
        var des = CryptoJS.DES.encrypt(CryptoJS.enc.Utf8.parse('hello legado'), desKey, {iv: desIV, mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7});
        var keySpec = new Packages.javax.crypto.spec.SecretKeySpec('0123456789abcdef'.getBytes(), 'AES');
        var ivSpec = new Packages.javax.crypto.spec.IvParameterSpec('abcdef0123456789'.getBytes());
        var cipher = Packages.javax.crypto.Cipher.getInstance('AES/CBC/PKCS5Padding');
        cipher.init(Packages.javax.crypto.Cipher.ENCRYPT_MODE, keySpec, ivSpec);
        var javaCiphertext = cipher.doFinal('hello legado'.getBytes());
        JSON.stringify({des: des.toString(), java: Packages.java.util.Base64.encodeToString(javaCiphertext)})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["des"] as? String, "LQXnK155iVg3Ejw4EwgNgQ==")
        XCTAssertEqual(object["java"] as? String, "vJ5ACeBMmCz2biliGgiqvw==")
    }

    func testLegacyJavaCipherHelpersNormalizeArgumentOrder() throws {
        let result = JSCoreRuntime().evaluate("""
        var aes = java.aesEncodeToBase64String('hello legado', '0123456789abcdef', 'abcdef0123456789', 'AES/CBC/PKCS5Padding');
        var aesLegacy = java.aesEncodeToBase64String('hello legado', '0123456789abcdef', 'AES/CBC/PKCS5Padding', 'abcdef0123456789');
        var aesPlain = java.aesBase64DecodeToString(aes, '0123456789abcdef', 'abcdef0123456789', 'AES/CBC/PKCS5Padding');
        var des = java.desEncodeToBase64String('hello legado', '12345678', 'abcdefgh', 'DES/CBC/PKCS5Padding');
        var desPlain = java.desBase64DecodeToString(des, '12345678', 'abcdefgh', 'DES/CBC/PKCS5Padding');
        JSON.stringify({aes: aes, aesLegacy: aesLegacy, aesPlain: aesPlain, des: des, desPlain: desPlain})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["aes"] as? String, "vJ5ACeBMmCz2biliGgiqvw==")
        XCTAssertEqual(object["aesLegacy"] as? String, "vJ5ACeBMmCz2biliGgiqvw==")
        XCTAssertEqual(object["aesPlain"] as? String, "hello legado")
        XCTAssertEqual(object["des"] as? String, "LQXnK155iVg3Ejw4EwgNgQ==")
        XCTAssertEqual(object["desPlain"] as? String, "hello legado")
    }

    private func jsonObject(from result: Result<String, SourceEngineError>, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("expected JSON result: \(result)", file: file, line: line)
            throw NSError(domain: "LegadoStage9Tests", code: 1)
        }
        return object
    }
}
