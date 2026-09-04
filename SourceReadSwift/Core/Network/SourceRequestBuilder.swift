import Foundation

struct SourceRequestBuilder {
    private let directiveParser = SourceURLDirectiveParser()

    func buildPageRequest(
        source: BookSource,
        urlText: String,
        persistentValues: [String: String] = [:]
    ) -> SourceRequest {
        buildRequest(source: source, resolvedText: urlText, persistentValues: persistentValues)
    }

    func buildSearchRequest(
        source: BookSource,
        searchUrl: String,
        keyword: String,
        page: Int,
        persistentValues: [String: String] = [:]
    ) -> SourceRequest {
        let resolved = searchUrl
            .replacingOccurrences(of: "{{key}}", with: keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)
            .replacingOccurrences(of: "{{keyword}}", with: keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)
            .replacingOccurrences(of: "{{page}}", with: String(page))

        return buildRequest(
            source: source,
            resolvedText: resolved,
            keyword: keyword,
            page: page,
            persistentValues: persistentValues
        )
    }

    private func buildRequest(
        source: BookSource,
        resolvedText: String,
        keyword: String? = nil,
        page: Int? = nil,
        persistentValues: [String: String] = [:]
    ) -> SourceRequest {
        let interpolatedText = interpolatePersistentValues(resolvedText, values: persistentValues)
        let directive = directiveParser.parse(interpolatedText)
        let url = resolveURL(directive.urlText, base: source.bookSourceUrl)
        let sourceOptions = requestOptions(
            source,
            keyword: keyword,
            page: page,
            persistentValues: persistentValues
        )
        let charset = directive.expectedCharset ?? sourceCharset(source)

        var headers = sourceHeaders(source, persistentValues: persistentValues)
        mergeHeaders(sourceOptions.headers, into: &headers)
        // A cookie written by a Legado JS stage is dynamic state, not a source
        // default.  Apply it after source/custom headers but before the URL
        // directive so an explicit @Header: Cookie=... still wins.
        if let dynamicCookie = persistentValues["cookieHeader"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dynamicCookie.isEmpty {
            setHeaderCaseInsensitive("Cookie", value: dynamicCookie, in: &headers)
        }
        mergeHeaders(directive.headers, into: &headers)
        headers = headers.mapValues { interpolatePersistentValues($0, values: persistentValues) }
        headers["User-Agent", default: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"]
        headers["Accept", default: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"]
        applyDefaultNavigationHeaders(to: &headers, sourceBase: source.bookSourceUrl)

        let body = directive.body.map { interpolateData($0, values: persistentValues) } ?? sourceOptions.body
        let timeout = resolvedTimeout(
            directive: directive,
            source: source,
            options: sourceOptions.timeout
        )
        let method: SourceHTTPMethod = {
            if directive.method == .post { return .post }
            if directive.method == .head { return .head }
            if sourceOptions.method == .post { return .post }
            if sourceOptions.method == .head { return .head }
            if body != nil { return .post }
            return .get
        }()

        return SourceRequest(
            url: url,
            method: method,
            headers: headers,
            body: body,
            expectedCharset: charset,
            timeout: timeout
        )
    }

    private func parseHeaders(_ text: String?) -> [String: String] {
        guard let text, !text.isEmpty else { return [:] }
        let decoded = decodeEscapes(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = decoded.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return stringMap(object)
        }
        return decoded
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == ";" })
            .reduce(into: [:]) { result, line in
                let value = String(line)
                let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let headerValue = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }
                result[key] = decodeEscapes(headerValue)
            }
    }

    private func stringMap(_ object: [String: Any]) -> [String: String] {
        object.reduce(into: [:]) { result, item in
            result[item.key] = stringify(item.value)
        }
    }

    private func resolveURL(_ text: String, base: String) -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        if let baseURL = URL(string: base),
           let relative = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL {
            return relative
        }
        return URL(string: base) ?? URL(string: "https://invalid.local")!
    }

    private func sourceHeaders(_ source: BookSource, persistentValues: [String: String] = [:]) -> [String: String] {
        var headers = parseHeaders(source.header)
        for key in ["headers", "bookSourceHeader"] {
            mergeHeaders(parseHeaders(source.raw[key]), into: &headers)
        }
        if let customConfig = source.customConfig,
           let data = customConfig.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let nested = object["headers"] as? [String: Any] {
                mergeHeaders(stringMap(nested), into: &headers)
            }
            if let nested = object["header"] as? [String: Any] {
                mergeHeaders(stringMap(nested), into: &headers)
            }
            if let text = object["header"] as? String {
                mergeHeaders(parseHeaders(text), into: &headers)
            }
            if let cookie = object["cookie"] as? String, !cookie.isEmpty {
                setHeaderCaseInsensitive("Cookie", value: cookie, in: &headers)
            }
            applyUserAgentAlias(from: object, to: &headers)
        }
        if let cookie = source.raw["cookie"], !cookie.isEmpty {
            setHeaderCaseInsensitive("Cookie", value: cookie, in: &headers)
        }
        applyUserAgentAlias(from: source.raw.reduce(into: [String: Any]()) { result, item in
            result[item.key] = item.value
        }, to: &headers)
        return headers.mapValues { interpolatePersistentValues($0, values: persistentValues) }
    }

    private func applyUserAgentAlias(from object: [String: Any], to headers: inout [String: String]) {
        guard !containsHeader(headers, "User-Agent") else { return }
        for key in ["userAgent", "ua", "httpUserAgent"] {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    headers["User-Agent"] = trimmed
                    return
                }
            }
        }
    }

    private func requestOptions(
        _ source: BookSource,
        keyword: String?,
        page: Int?,
        persistentValues: [String: String] = [:]
    ) -> (method: SourceHTTPMethod?, body: Data?, headers: [String: String], timeout: TimeInterval?) {
        var method: SourceHTTPMethod?
        var body: Data?
        var headers: [String: String] = [:]
        var timeout: TimeInterval?

        func apply(_ object: [String: Any]) {
            for key in ["method", "httpMethod", "type"] {
                guard let methodText = object[key] as? String else { continue }
                switch methodText.uppercased() {
                case "POST": method = .post
                case "HEAD": method = .head
                default: break
                }
            }
            if let nested = object["headers"] as? [String: Any] {
                mergeHeaders(stringMap(nested), into: &headers)
            }
            if let nested = object["header"] as? [String: Any] {
                mergeHeaders(stringMap(nested), into: &headers)
            }
            if let nested = object["bookSourceHeader"] as? [String: Any] {
                mergeHeaders(stringMap(nested), into: &headers)
            }
            if let text = object["headers"] as? String {
                mergeHeaders(parseHeaders(text), into: &headers)
            }
            if let text = object["header"] as? String {
                mergeHeaders(parseHeaders(text), into: &headers)
            }
            if let text = object["bookSourceHeader"] as? String {
                mergeHeaders(parseHeaders(text), into: &headers)
            }
            if let bodyOption = firstValue(in: object, keys: ["body", "requestBody", "postBody", "data"]),
               let encoded = encodeBodyOption(
                   bodyOption,
                   headers: headers,
                   keyword: keyword,
                   page: page,
                   persistentValues: persistentValues
               ) {
                body = encoded
                method = .post
            }
            if timeout == nil,
               let rawTimeout = firstValue(in: object, keys: ["timeout", "timeoutMs", "connectTimeout"]),
               let parsed = timeoutSeconds(rawTimeout) {
                timeout = parsed
            }
        }

        if let customConfig = source.customConfig,
           let data = customConfig.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            apply(object)
        }

        apply(source.raw.reduce(into: [String: Any]()) { result, item in
            result[item.key] = item.value
        })
        return (method, body, headers.mapValues { interpolatePersistentValues($0, values: persistentValues) }, timeout)
    }

    private func resolvedTimeout(
        directive: SourceURLDirective,
        source: BookSource,
        options: TimeInterval?
    ) -> TimeInterval {
        let raw = directive.timeout
            ?? options
            ?? timeoutValue(source.customConfig)
            ?? timeoutValue(source.raw)
            ?? 12
        return min(max(raw, 1), 120)
    }

    private func timeoutValue(_ raw: [String: String]) -> TimeInterval? {
        for key in ["timeout", "timeoutMs", "connectTimeout"] {
            if let value = raw[key], let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), number > 0 {
                return number >= 100 ? number / 1_000 : number
            }
        }
        return nil
    }

    private func timeoutValue(_ text: String?) -> TimeInterval? {
        guard let text,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["timeout", "timeoutMs", "connectTimeout"] {
            if let value = object[key], let number = timeoutSeconds(value) { return number }
        }
        return nil
    }

    private func timeoutSeconds(_ value: Any) -> TimeInterval? {
        let number: Double?
        if let value = value as? NSNumber {
            number = value.doubleValue
        } else {
            number = Double(String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let number, number > 0 else { return nil }
        return number >= 100 ? number / 1_000 : number
    }

    private func applyDefaultNavigationHeaders(to headers: inout [String: String], sourceBase: String) {
        guard let baseURL = URL(string: sourceBase), let host = baseURL.host else { return }
        let scheme = baseURL.scheme ?? "https"
        let origin = "\(scheme)://\(host)"
        if !containsHeader(headers, "Referer") {
            headers["Referer"] = "\(origin)/"
        }
        if !containsHeader(headers, "Origin") {
            headers["Origin"] = origin
        }
    }

    private func containsHeader(_ headers: [String: String], _ name: String) -> Bool {
        headers.keys.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// HTTP field names are case-insensitive.  Dictionary.merge is not, so a
    /// source containing `cookie`, `Cookie`, or `COOKIE` could otherwise emit
    /// duplicate fields and make URLRequest choose the wrong value.
    private func mergeHeaders(_ newHeaders: [String: String], into headers: inout [String: String]) {
        for (key, value) in newHeaders {
            setHeaderCaseInsensitive(key, value: value, in: &headers)
        }
    }

    private func setHeaderCaseInsensitive(_ key: String, value: String, in headers: inout [String: String]) {
        if let existingKey = headers.keys.first(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) {
            headers.removeValue(forKey: existingKey)
        }
        headers[key] = value
    }

    private func sourceCharset(_ source: BookSource) -> String? {
        if let charset = source.raw["charset"]?.trimmingCharacters(in: .whitespacesAndNewlines), !charset.isEmpty {
            return charset
        }
        if let customConfig = source.customConfig,
           let data = customConfig.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["charset", "encoding", "encode"] {
                if let value = object[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }
        return nil
    }

    private func interpolate(_ text: String, keyword: String?, page: Int?) -> String {
        var output = text
        if let keyword {
            let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
            output = output
                .replacingOccurrences(of: "{{key}}", with: encoded)
                .replacingOccurrences(of: "{{keyword}}", with: encoded)
        }
        if let page {
            output = output.replacingOccurrences(of: "{{page}}", with: String(page))
        }
        return output
    }

    private func firstValue(in options: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = options[key] {
                return value
            }
        }
        return nil
    }

    private func encodeBodyOption(
        _ value: Any,
        headers: [String: String],
        keyword: String?,
        page: Int?,
        persistentValues: [String: String] = [:]
    ) -> Data? {
        if let text = value as? String {
            return Data(interpolatePersistentValues(interpolate(text, keyword: keyword, page: page), values: persistentValues).utf8)
        }
        if let object = value as? [String: Any] {
            let interpolated = object.reduce(into: [String: String]()) { result, item in
                result[item.key] = interpolatePersistentValues(
                    interpolate(stringify(item.value), keyword: keyword, page: page),
                    values: persistentValues
                )
            }
            let contentType = headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value ?? ""
            if contentType.localizedCaseInsensitiveContains("application/json") {
                let jsonObject = object.reduce(into: [String: Any]()) { result, item in
                    if let stringValue = item.value as? String {
                        result[item.key] = interpolatePersistentValues(
                            interpolate(stringValue, keyword: keyword, page: page),
                            values: persistentValues
                        )
                    } else {
                        result[item.key] = item.value
                    }
                }
                if let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys]) {
                    return data
                }
            }
            let form = interpolated
                .sorted { $0.key < $1.key }
                .map { key, value in
                    "\(urlEncode(key))=\(urlEncode(value))"
                }
                .joined(separator: "&")
            return Data(form.utf8)
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            return data
        }
        return Data(interpolatePersistentValues(String(describing: value), values: persistentValues).utf8)
    }

    /// Legado JS sources commonly persist a nonce, token or cursor in one
    /// stage and reference it from a later URL/header/body as `{{token}}` or
    /// `{token}`.  Android's runtime expands those values at request time;
    /// keeping the expansion in the request builder makes all four pipeline
    /// stages (including synchronous JS ajax calls) behave the same way.
    private func interpolatePersistentValues(_ text: String, values: [String: String]) -> String {
        guard !values.isEmpty else { return text }
        return values.reduce(text) { output, item in
            guard !item.key.isEmpty else { return output }
            return output
                .replacingOccurrences(of: "{{\(item.key)}}", with: item.value)
                .replacingOccurrences(of: "{\(item.key)}", with: item.value)
        }
    }

    private func interpolateData(_ data: Data, values: [String: String]) -> Data {
        guard !values.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return data }
        return Data(interpolatePersistentValues(text, values: values).utf8)
    }

    private func stringify(_ value: Any) -> String {
        if let value = value as? String { return decodeEscapes(value) }
        if let value = value as? NSNumber { return value.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    private func decodeEscapes(_ value: String) -> String {
        guard value.contains("\\") else { return value }
        return value
            .replacingOccurrences(of: "\\r\\n", with: "\r\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
