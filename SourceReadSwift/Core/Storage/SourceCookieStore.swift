import Foundation

actor SourceCookieStore {
    private var cookiesByHost: [String: [HTTPCookie]] = [:]

    func cookies(for url: URL) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        return cookiesByHost[host] ?? []
    }

    func cookieHeader(for url: URL) -> String? {
        let cookies = cookies(for: url)
        guard !cookies.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    func store(_ cookies: [HTTPCookie], for url: URL) {
        guard let host = url.host?.lowercased() else { return }
        store(cookies, host: host)
    }

    func storeWebViewCookies(_ cookies: [HTTPCookie]) {
        for cookie in cookies {
            let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            guard !host.isEmpty else { continue }
            store([cookie], host: host)
        }
    }

    /// Store one or more raw Set-Cookie header values.  URLSession may expose
    /// a combined field with an Expires comma; split it conservatively before
    /// handing each cookie to Foundation's RFC parser.
    func storeSetCookieHeaders(_ headers: [String: String], for url: URL) {
        let values = CookieHeaderParser.setCookieValues(from: headers)
        guard !values.isEmpty else { return }
        var parsed: [HTTPCookie] = []
        for value in values {
            parsed.append(contentsOf: HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: url))
        }
        store(parsed, for: url)
    }

    private func store(_ cookies: [HTTPCookie], host: String) {
        var current = cookiesByHost[host] ?? []
        for cookie in cookies {
            current.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            current.append(cookie)
        }
        cookiesByHost[host.lowercased()] = current
    }
}
