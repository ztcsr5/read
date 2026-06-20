import Foundation
import WebKit

actor SourceCookieStore {
    private var cookiesByHost: [String: [HTTPCookie]] = [:]

    func cookies(for url: URL) -> [HTTPCookie] {
        guard let host = url.host else { return [] }
        return cookiesByHost[host] ?? []
    }

    func cookieHeader(for url: URL) -> String? {
        let cookies = cookies(for: url)
        guard !cookies.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    func store(_ cookies: [HTTPCookie], for url: URL) {
        guard let host = url.host else { return }
        var current = cookiesByHost[host] ?? []
        for cookie in cookies {
            current.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            current.append(cookie)
        }
        cookiesByHost[host] = current
    }

    func syncFromWebView(_ webView: WKWebView) async {
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        for cookie in cookies {
            let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            cookiesByHost[host, default: []].append(cookie)
        }
    }
}
