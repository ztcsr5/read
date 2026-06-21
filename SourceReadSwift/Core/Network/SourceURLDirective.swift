import Foundation

struct SourceURLDirective: Equatable {
    var urlText: String
    var method: SourceHTTPMethod
    var headers: [String: String]
    var body: Data?

    init(urlText: String, method: SourceHTTPMethod = .get, headers: [String: String] = [:], body: Data? = nil) {
        self.urlText = urlText
        self.method = method
        self.headers = headers
        self.body = body
    }
}

struct SourceURLDirectiveParser {
    func parse(_ text: String) -> SourceURLDirective {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var headers: [String: String] = [:]
        var method: SourceHTTPMethod = .get
        var body: Data?

        let directives = splitURLAndTrailingDirectives(working)
        working = directives.url
        if let headerText = directives.header {
            headers.merge(parseStringMap(headerText), uniquingKeysWith: { _, new in new })
        }
        if let bodyText = directives.body {
            body = Data(bodyText.utf8)
            method = .post
        }

        let split = splitURLAndJSONOptions(working)
        working = split.url
        if let options = split.options {
            for key in ["headers", "header", "bookSourceHeader"] {
                headers.merge(parseHeadersOption(options[key]), uniquingKeysWith: { _, new in new })
            }
            if let methodText = firstString(in: options, keys: ["method", "httpMethod"]),
               methodText.uppercased() == "POST" {
                method = .post
            }
            if let bodyOption = firstValue(in: options, keys: ["body", "requestBody", "postBody"]) {
                body = encodeBodyOption(bodyOption, headers: headers)
                method = .post
            }
        }

        return SourceURLDirective(urlText: working, method: method, headers: headers, body: body)
    }

    private func splitURLAndTrailingDirectives(_ text: String) -> (url: String, header: String?, body: String?) {
        var markers: [(name: String, range: Range<String.Index>)] = []
        let aliases: [(name: String, marker: String)] = [
            ("header", "@Header:"),
            ("header", "@Headers:"),
            ("body", "@Body:"),
            ("body", "@Post:"),
            ("body", "@RequestBody:")
        ]
        for alias in aliases {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(
                    of: alias.marker,
                    options: .caseInsensitive,
                    range: searchStart..<text.endIndex
                  ) {
                markers.append((alias.name, range))
                searchStart = range.upperBound
            }
        }
        markers.sort { $0.range.lowerBound < $1.range.lowerBound }

        guard let first = markers.first else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil, nil)
        }

        var header: String?
        var body: String?
        for index in markers.indices {
            let marker = markers[index]
            let contentStart = marker.range.upperBound
            let nextIndex = markers.index(after: index)
            let contentEnd: String.Index
            if nextIndex < markers.endIndex {
                contentEnd = markers[nextIndex].range.lowerBound
            } else {
                contentEnd = text.endIndex
            }
            let content = String(text[contentStart..<contentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if marker.name == "header" {
                header = content
            } else {
                body = content
            }
        }

        let url = String(text[..<first.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (url, header, body)
    }

    private func splitURLAndJSONOptions(_ text: String) -> (url: String, options: [String: Any]?) {
        guard let comma = text.firstIndex(of: ",") else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        let url = String(text[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
        let optionText = String(text[text.index(after: comma)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard optionText.hasPrefix("{"),
              let data = optionText.data(using: .utf8),
              let options = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        return (url, options)
    }

    private func parseStringMap(_ text: String) -> [String: String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return stringMap(object)
        }
        let pairs = trimmed
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return pairs.reduce(into: [:]) { result, line in
            let separator: Character = line.contains(":") ? ":" : "="
            let parts = line.split(separator: separator, maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            result[key] = value
        }
    }

    private func parseHeadersOption(_ value: Any?) -> [String: String] {
        if let object = value as? [String: Any] {
            return stringMap(object)
        }
        if let text = value as? String {
            return parseStringMap(text)
        }
        return [:]
    }

    private func stringMap(_ object: [String: Any]) -> [String: String] {
        object.reduce(into: [:]) { result, item in
            result[item.key] = String(describing: item.value)
        }
    }

    private func firstString(in options: [String: Any], keys: [String]) -> String? {
        firstValue(in: options, keys: keys) as? String
    }

    private func firstValue(in options: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = options[key] {
                return value
            }
        }
        return nil
    }

    private func encodeBodyOption(_ value: Any, headers: [String: String]) -> Data? {
        if let text = value as? String {
            return Data(text.utf8)
        }
        if let object = value as? [String: Any] {
            let contentType = headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value ?? ""
            if contentType.localizedCaseInsensitiveContains("application/json"),
               let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
                return data
            }
            let form = object
                .sorted { $0.key < $1.key }
                .map { key, value in
                    "\(urlEncode(key))=\(urlEncode(String(describing: value)))"
                }
                .joined(separator: "&")
            return Data(form.utf8)
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            return data
        }
        return Data(String(describing: value).utf8)
    }

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
