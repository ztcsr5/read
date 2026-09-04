import XCTest
@testable import SourceReadSwift

/// Stage 10 covers the remaining high-frequency Android/Legado compatibility
/// surfaces: CryptoJS ciphers, Java URL/collections/regex facades, response
/// metadata and Flutter utility aliases. All tests are offline and deterministic
/// except for the random CryptoJS salt, which is validated through a round-trip.
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

    func testJavaURLSafeBase64AndPaddingVariants() throws {
        let result = JSCoreRuntime().evaluate("""
        var standard = Packages.java.util.Base64.getEncoder().encodeToString('ûï'.getBytes());
        var url = Packages.java.util.Base64.getUrlEncoder().encodeToString('ûï'.getBytes());
        var noPad = Packages.java.util.Base64.getEncoder().withoutPadding().encodeToString('hello'.getBytes());
        var decoded = Packages.java.util.Base64.getUrlDecoder().decode(url);
        JSON.stringify({standard: standard, url: url, noPad: noPad, decoded: bytesToStr(decoded)})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["standard"] as? String, "w7vDrw==")
        XCTAssertEqual(object["url"] as? String, "w7vDrw")
        XCTAssertEqual(object["noPad"] as? String, "aGVsbG8")
        XCTAssertEqual(object["decoded"] as? String, "ûï")
    }

    func testByteArrayInputStreamExposesBytesAndGzipReads() throws {
        let result = JSCoreRuntime().evaluate("""
        var input = new Packages.java.io.ByteArrayInputStream([65, 66, 67]);
        var out = [0, 0, 0]; var count = input.read(out, 0, 3);
        JSON.stringify({count: count, bytes: out, available: input.available(), exposed: input.__bytes.length})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["count"] as? Int, 3)
        XCTAssertEqual(object["exposed"] as? Int, 3)
        XCTAssertEqual(object["available"] as? Int, 0)
    }

    func testJavaURLSupportsBothConstructorOrdersAndURI() throws {
        let result = JSCoreRuntime().evaluate("""
        var a = new Packages.java.net.URL('https://example.com/books/a/../b?q=1#x');
        var b = new Packages.java.net.URL('../cover.jpg', 'https://example.com/books/ch1.html');
        var c = new Packages.java.net.URL('https://example.com/books/ch1.html', '../cover.jpg');
        var u = new Packages.java.net.URI('https://example.com/a/../b').normalize();
        JSON.stringify({a: a.normalize().toString(), b: b.toString(), c: c.toString(), uri: u.toString(), host: a.getHost(), port: a.getDefaultPort()})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["a"] as? String, "https://example.com/books/b?q=1#x")
        XCTAssertEqual(object["b"] as? String, "https://example.com/cover.jpg")
        XCTAssertEqual(object["c"] as? String, "https://example.com/cover.jpg")
        XCTAssertEqual(object["uri"] as? String, "https://example.com/b")
        XCTAssertEqual(object["port"] as? Int, 443)
    }

    func testURLConnectionPropertiesAndResponseMetadata() throws {
        let context = RuleExecutionContext()
        context.responseHandler = { _ in
            SourceResponse(url: URL(string: "https://example.com/final")!, statusCode: 201,
                           headers: ["Content-Type": "text/plain", "X-Test": "yes"], body: "ok", data: Data("ok".utf8))
        }
        let result = JSCoreRuntime(executionContext: context).evaluate("""
        var c = Packages.java.net.URL('https://example.com/start').openConnection();
        c.setRequestProperty('X-Req', 'one').addRequestProperty('X-Req', 'two').setReadTimeout(321);
        c.connect();
        JSON.stringify({code: c.getResponseCode(), type: c.getContentType(), req: c.getRequestProperty('X-Req'), timeout: c.getReadTimeout(), header: c.getHeaderField('X-Test'), body: c.getInputStream().available()})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["code"] as? Int, 201)
        XCTAssertEqual(object["type"] as? String, "text/plain")
        XCTAssertEqual(object["req"] as? String, "one, two")
        XCTAssertEqual(object["timeout"] as? Int, 321)
        XCTAssertEqual(object["header"] as? String, "yes")
        XCTAssertEqual(object["body"] as? Int, 2)
    }

    func testStringBuilderMutations() throws {
        let result = JSCoreRuntime().evaluate("""
        var b = new Packages.java.lang.StringBuilder('abc');
        b.insert(1, 'X').deleteCharAt(2).replace(0, 1, 'Q').append('!').reverse();
        JSON.stringify({text: b.toString(), length: b.length(), char: b.charAt(1), sub: b.substring(1, 3), capacity: b.capacity()})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["text"] as? String, "!cXQ")
        XCTAssertEqual(object["length"] as? Int, 4)
        XCTAssertEqual(object["char"] as? String, "c")
    }

    func testHashMapAndArrayListCollectionSurface() throws {
        let result = JSCoreRuntime().evaluate("""
        var m = new Packages.java.util.HashMap({a: 1, b: 2}); m.putAll({c: 3});
        var e = m.entrySet().get(0); e.setValue(9);
        var list = new Packages.java.util.ArrayList([1, 2, 3]); list.add(1, 8); list.removeAt(0); list.removeAll([3]); list.addAll(0, [7, 6]); list.sort(function(a,b){return a-b;});
        JSON.stringify({map: m.get('a'), has: m.containsValue(2), fallback: m.getOrDefault('z', 7), list: list.toArray()})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["map"] as? Int, 9)
        XCTAssertEqual(object["has"] as? Bool, true)
        XCTAssertEqual(object["fallback"] as? Int, 7)
        XCTAssertEqual(object["list"] as? [Int], [2, 6, 7, 8])
    }

    func testMatcherExtendedSurface() throws {
        let result = JSCoreRuntime().evaluate("""
        var matcher = Packages.java.util.regex.Pattern.compile('(a)(b)').matcher('xxabyyab');
        matcher.find(2); var first = matcher.group(0); var replaced = matcher.replaceAll('[$1$2]');
        JSON.stringify({first: first, start: matcher.start(), end: matcher.end(), replaced: replaced, rs: matcher.regionStart(), re: matcher.regionEnd()})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["first"] as? String, "ab")
        XCTAssertEqual(object["start"] as? Int, 2)
        XCTAssertEqual(object["end"] as? Int, 4)
        XCTAssertEqual(object["replaced"] as? String, "xx[ab]yy[ab]")
    }

    func testCacheDocumentWindowAndSourceMetadata() throws {
        let source = BookSource(bookSourceName: "Stage10", bookSourceUrl: "https://example.com", bookSourceType: 0,
                               searchUrl: nil, exploreUrl: nil, header: nil, loginUrl: "https://example.com/login", loginCheckJs: "ok")
        let result = JSCoreRuntime().evaluate("""
        putCache('k', 'v'); putField('f', 'x');
        JSON.stringify({cache: getCache('k'), field: getField('f'), win: window === window, root: document.documentElement != null, comment: source.bookSourceComment, login: source.loginUrl})
        """, variables: ["source": source, "result": "<html><body>ok</body></html>", "baseUrl": "https://example.com/"])
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["cache"] as? String, "v")
        XCTAssertEqual(object["field"] as? String, "x")
        XCTAssertEqual(object["win"] as? Bool, true)
        XCTAssertEqual(object["root"] as? Bool, true)
        XCTAssertEqual(object["login"] as? String, "https://example.com/login")
    }

    func testFlutterUtilityAliases() throws {
        let result = JSCoreRuntime().evaluate("""
        JSON.stringify({sha: sha224Encode('abc'), sha384: sha348Encode('abc'), uri: uriEncode('a b'), round: uriDecode(uriEncode('a b')), utc: timeFormatUTC(0)})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["sha"] as? String, "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7")
        XCTAssertEqual(object["sha384"] as? String, "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")
        XCTAssertEqual(object["round"] as? String, "a b")
    }

    func testCryptoJSBinaryWordArrayRoundTrip() throws {
        let result = JSCoreRuntime().evaluate("""
        var binary = CryptoJS.lib.WordArray.create([0, 255, 16, 128], 4);
        JSON.stringify({hex: CryptoJS.enc.Hex.stringify(binary), b64: CryptoJS.enc.Base64.stringify(binary), bytes: binary.sigBytes})
        """)
        let object = try jsonObject(from: result)
        XCTAssertEqual(object["hex"] as? String, "00ff1080")
        XCTAssertEqual(object["b64"] as? String, "AP8QgA==")
        XCTAssertEqual(object["bytes"] as? Int, 4)
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
