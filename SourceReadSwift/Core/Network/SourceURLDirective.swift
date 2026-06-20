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

        if let headerRange = working.range(of: "@Header:", options: .caseInsensitive) {
            let prefix = String(working[..<headerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let headerText = String(working[headerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            headers.merge(parseStringMap(headerText), uniquingKeysWith: { _, new in new })
            working = prefix
        }

        if let bodyRange = working.range(of: "@Body:", options: .caseInsensitive) {
            let prefix = String(working[..<bodyRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyText = String(working[bodyRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            body = Data(bodyText.utf8)
            method = .post
            working = prefix
        }

        let split = splitURLAndJSONOptions(working)
        working = split.url
        if let options = split.options {
            if let optionHeaders = options["headers"] as? [String: Any] {
                headers.merge(stringMap(optionHeaders), uniquingKeysWith: { _, new in new })
            }
            if let optionHeaders = options["header"] as? [String: Any] {
                headers.merge(stringMap(optionHeaders), uniquingKeysWith: { _, new in new })
            }
            if let directHeader = options["headers"] as? String {
                headers.merge(parseStringMap(directHeader), uniquingKeysWith: { _, new in new })
            }
            if let methodText = options["method"] as? String, methodText.uppercased() == "POST" {
                method = .post
            }
            if let bodyText = options["body"] as? String {
                body = Data(bodyText.utf8)
                method = .post
            }
        }

        return SourceURLDirective(urlText: working, method: method, headers: headers, body: body)
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
        return [:]
    }

    private func stringMap(_ object: [String: Any]) -> [String: String] {
        object.reduce(into: [:]) { result, item in
            result[item.key] = String(describing: item.value)
        }
    }
}

