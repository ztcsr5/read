import Foundation
import XCTest
@testable import SourceReadSwift

/// End-to-end fixtures for the two source patterns that most often break when
/// an Android Legado source is moved to iOS: encrypted response bodies and a
/// bodyJs stage that performs another request before returning readable HTML.
final class SourceEngineCryptoFixtureTests: XCTestCase {
    func testCryptoJSPassphraseDecryptsOpenSSLSaltedEnvelope() throws {
        let result = JSCoreRuntime().evaluate("CryptoJS.AES.decrypt('U2FsdGVkX18xMjM0NTY3OKWM0JxM5A2ppliuYJJMeHs=', 'password').toString(CryptoJS.enc.Utf8)")
        guard case .success(let text) = result else {
            return XCTFail("expected OpenSSL passphrase decrypt: \(result)")
        }
        XCTAssertEqual(text, "hello legado")
    }

    func testContentBodyJsDecryptsCryptoJSAESBase64HTML() async throws {
        let source = BookSource(
            bookSourceName: "CryptoJS body fixture",
            bookSourceUrl: "https://fixture.local/",
            ruleContent: SourceRule(
                fields: [
                    "content": "#content@text",
                    "bodyJs": "var raw = CryptoJS.enc.Base64.parse(result); var key = CryptoJS.enc.Utf8.parse('0123456789abcdef'); var iv = CryptoJS.enc.Utf8.parse('abcdef0123456789'); return CryptoJS.AES.decrypt({ciphertext: raw}, key, {iv: iv, mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7}).toString(CryptoJS.enc.Utf8);"
                ]
            )
        )
        let chapter = BookChapter(
            title: "加密章节",
            url: "https://fixture.local/chapter/1",
            bookUrl: "https://fixture.local/book/1",
            index: 0,
            isVip: false
        )
        let network = MappingSourceNetworkClient(responses: [
            "https://fixture.local/chapter/1": "LCEmLrSirfT+lvtnegMzd63dBv1sLhdok++uPr+GpkYO9RxyGwnHbMbeWkP3V6TyLzTdDgQd8yQ6f8GaPaITYw=="
        ])

        let result = await LegadoSourceEngine(network: network).getContent(source: source, chapter: chapter)

        guard case .success(let content) = result else {
            return XCTFail("expected decrypted content: \(result)")
        }
        XCTAssertEqual(content.paragraphs, ["动态正文"])
        XCTAssertEqual(network.requestedURLs, ["https://fixture.local/chapter/1"])
    }

    func testBodyJsAjaxPersistsNonceCookieAndReturnsFollowUpHTML() async throws {
        let source = BookSource(
            bookSourceName: "bodyJs ajax fixture",
            bookSourceUrl: "https://fixture.local/",
            ruleContent: SourceRule(fields: ["content": "#content@text"]),
            raw: [
                "bodyJs": "var boot = java.ajax('https://fixture.local/bootstrap'); java.put('token', boot.header('X-Nonce')); return java.ajax('https://fixture.local/content?token=' + java.get('token')).body();"
            ]
        )
        let chapter = BookChapter(
            title: "动态章节",
            url: "https://fixture.local/chapter/2",
            bookUrl: "https://fixture.local/book/2",
            index: 0,
            isVip: false
        )
        let network = BodyJSAjaxSourceNetworkClient()

        let result = await LegadoSourceEngine(network: network).getContent(source: source, chapter: chapter)

        guard case .success(let content) = result else {
            return XCTFail("expected ajax bodyJs content: \(result)")
        }
        XCTAssertEqual(content.paragraphs, ["动态请求正文"])
        XCTAssertEqual(network.requestedURLs, [
            "https://fixture.local/chapter/2",
            "https://fixture.local/bootstrap",
            "https://fixture.local/content?token=nonce-bodyjs"
        ])
        XCTAssertEqual(network.invalidRequests, 0)
    }

    func testPaginatedContentCarriesBodyJsTokenIntoNextPage() async throws {
        let source = BookSource(
            bookSourceName: "paged bodyJs fixture",
            bookSourceUrl: "https://fixture.local/",
            ruleContent: SourceRule(fields: [
                "content": "#content@text",
                "nextContentUrl": "a.next@href"
            ]),
            raw: [
                "bodyJs": "if (result.indexOf('PAGE_ONE') >= 0) { var boot = java.ajax('https://fixture.local/bootstrap'); java.put('cursor', boot.header('X-Cursor')); } return result.replace(' PAGE_ONE', '').replace('CURSOR_PLACEHOLDER', java.get('cursor'));"
            ]
        )
        let chapter = BookChapter(
            title: "分页章节",
            url: "https://fixture.local/chapter/paged",
            bookUrl: "https://fixture.local/book/paged",
            index: 0,
            isVip: false
        )
        let network = PaginatedBodyJSSourceNetworkClient()

        let result = await LegadoSourceEngine(network: network).getContent(source: source, chapter: chapter)

        guard case .success(let content) = result else {
            return XCTFail("expected paginated bodyJs content: \(result)")
        }
        XCTAssertEqual(content.paragraphs, ["分页第一页", "分页第二页"])
        XCTAssertEqual(network.requestedURLs, [
            "https://fixture.local/chapter/paged",
            "https://fixture.local/bootstrap",
            "https://fixture.local/chapter/paged-next?cursor=cursor-bodyjs"
        ])
        XCTAssertEqual(network.invalidRequests, 0)
    }
}

private final class MappingSourceNetworkClient: SourceNetworkClient, @unchecked Sendable {
    private let responses: [String: String]
    private let lock = NSLock()
    private var urls: [String] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    var requestedURLs: [String] {
        lock.lock(); defer { lock.unlock() }
        return urls
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let url = request.url.absoluteString
        lock.lock(); urls.append(url); lock.unlock()
        let body = responses[url] ?? ""
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: [:], body: body, data: Data(body.utf8)))
    }
}

private final class BodyJSAjaxSourceNetworkClient: SourceNetworkClient, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String] = []
    private var failures = 0

    var requestedURLs: [String] {
        lock.lock(); defer { lock.unlock() }
        return urls
    }

    var invalidRequests: Int {
        lock.lock(); defer { lock.unlock() }
        return failures
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let url = request.url.absoluteString
        lock.lock(); urls.append(url); lock.unlock()
        switch url {
        case "https://fixture.local/chapter/2":
            return .success(SourceResponse(url: request.url, statusCode: 200, headers: [:], body: "placeholder", data: Data("placeholder".utf8)))
        case "https://fixture.local/bootstrap":
            return .success(SourceResponse(
                url: request.url,
                statusCode: 200,
                headers: ["X-Nonce": "nonce-bodyjs", "Set-Cookie": "sid=bodyjs; Path=/"],
                body: "boot",
                data: Data("boot".utf8)
            ))
        case "https://fixture.local/content?token=nonce-bodyjs":
            let token = request.url.query?.split(separator: "=").last.map(String.init)
            let cookie = request.headers.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }?.value
            guard token == "nonce-bodyjs", cookie == "sid=bodyjs" else {
                lock.lock(); failures += 1; lock.unlock()
                return .failure(.network("bodyJs nonce/cookie missing"))
            }
            let body = "<html><body><div id='content'>动态请求正文</div></body></html>"
            return .success(SourceResponse(url: request.url, statusCode: 200, headers: [:], body: body, data: Data(body.utf8)))
        default:
            lock.lock(); failures += 1; lock.unlock()
            return .failure(.network("unexpected fixture URL"))
        }
    }
}

private final class PaginatedBodyJSSourceNetworkClient: SourceNetworkClient, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String] = []
    private var failures = 0

    var requestedURLs: [String] {
        lock.lock(); defer { lock.unlock() }
        return urls
    }

    var invalidRequests: Int {
        lock.lock(); defer { lock.unlock() }
        return failures
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let url = request.url.absoluteString
        lock.lock(); urls.append(url); lock.unlock()
        switch url {
        case "https://fixture.local/chapter/paged":
            let body = "<html><body><div id='content'>分页第一页 PAGE_ONE</div><a class='next' href='/chapter/paged-next?cursor=CURSOR_PLACEHOLDER'>next</a></body></html>"
            return .success(SourceResponse(url: request.url, statusCode: 200, headers: [:], body: body, data: Data(body.utf8)))
        case "https://fixture.local/bootstrap":
            return .success(SourceResponse(
                url: request.url,
                statusCode: 200,
                headers: ["X-Cursor": "cursor-bodyjs", "Set-Cookie": "sid=paged; Path=/"],
                body: "boot",
                data: Data("boot".utf8)
            ))
        case "https://fixture.local/chapter/paged-next?cursor=cursor-bodyjs":
            let cookie = request.headers.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }?.value
            guard cookie == "sid=paged" else {
                lock.lock(); failures += 1; lock.unlock()
                return .failure(.network("pagination cookie missing"))
            }
            let body = "<html><body><div id='content'>分页第二页</div></body></html>"
            return .success(SourceResponse(url: request.url, statusCode: 200, headers: [:], body: body, data: Data(body.utf8)))
        default:
            lock.lock(); failures += 1; lock.unlock()
            return .failure(.network("unexpected pagination fixture URL"))
        }
    }
}
