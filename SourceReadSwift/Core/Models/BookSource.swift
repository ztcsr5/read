import Foundation

struct BookSource: Identifiable, Codable, Hashable, Sendable {
    var id: String { bookSourceUrl }

    let bookSourceName: String
    let bookSourceUrl: String
    let bookSourceGroup: String?
    let bookSourceType: Int
    let enabled: Bool
    let weight: Int
    let searchUrl: String?
    let exploreUrl: String?
    let ruleSearch: SourceRule?
    let ruleBookInfo: SourceRule?
    let ruleToc: SourceRule?
    let ruleContent: SourceRule?
    let ruleExplore: SourceRule?
    let header: String?
    let loginUrl: String?
    let loginCheckJs: String?
    let customConfig: String?
    let raw: [String: String]

    enum CodingKeys: String, CodingKey {
        case bookSourceName
        case bookSourceUrl
        case bookSourceGroup
        case bookSourceType
        case enabled
        case weight
        case searchUrl
        case exploreUrl
        case ruleSearch
        case ruleBookInfo
        case ruleToc
        case ruleContent
        case ruleExplore
        case header
        case loginUrl
        case loginCheckJs
        case customConfig
        case raw
    }

    init(
        bookSourceName: String,
        bookSourceUrl: String,
        bookSourceGroup: String? = nil,
        bookSourceType: Int = 0,
        enabled: Bool = true,
        weight: Int = 0,
        searchUrl: String? = nil,
        exploreUrl: String? = nil,
        ruleSearch: SourceRule? = nil,
        ruleBookInfo: SourceRule? = nil,
        ruleToc: SourceRule? = nil,
        ruleContent: SourceRule? = nil,
        ruleExplore: SourceRule? = nil,
        header: String? = nil,
        loginUrl: String? = nil,
        loginCheckJs: String? = nil,
        customConfig: String? = nil,
        raw: [String: String] = [:]
    ) {
        self.bookSourceName = bookSourceName
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceGroup = bookSourceGroup
        self.bookSourceType = bookSourceType
        self.enabled = enabled
        self.weight = weight
        self.searchUrl = searchUrl
        self.exploreUrl = exploreUrl
        self.ruleSearch = ruleSearch
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
        self.ruleExplore = ruleExplore
        self.header = header
        self.loginUrl = loginUrl
        self.loginCheckJs = loginCheckJs
        self.customConfig = customConfig
        self.raw = raw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var raw: [String: String] = [:]
        if let persistedRaw = try? container.decode([String: String].self, forKey: DynamicCodingKey("raw")) {
            raw.merge(persistedRaw, uniquingKeysWith: { _, new in new })
        }
        for key in container.allKeys {
            if let value = try? container.decode(LosslessJSONValue.self, forKey: key) {
                raw[key.stringValue] = value.stringValue
            }
        }

        func string(_ key: String) -> String? {
            raw[key]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        func int(_ keys: [String], default defaultValue: Int = 0) -> Int {
            for key in keys {
                if let value = try? container.decode(Int.self, forKey: DynamicCodingKey(key)) {
                    return value
                }
                if let text = string(key), let value = Int(text) {
                    return value
                }
            }
            return defaultValue
        }

        func bool(_ keys: [String], default defaultValue: Bool) -> Bool {
            for key in keys {
                if let value = try? container.decode(Bool.self, forKey: DynamicCodingKey(key)) {
                    return value
                }
                if let text = string(key)?.lowercased() {
                    if ["true", "1", "yes", "y", "on", "enable", "enabled"].contains(text) {
                        return true
                    }
                    if ["false", "0", "no", "n", "off", "disable", "disabled"].contains(text) {
                        return false
                    }
                }
            }
            return defaultValue
        }

        func rule(_ key: String) -> SourceRule? {
            if let nested = try? container.decode(SourceRule.self, forKey: DynamicCodingKey(key)) {
                return nested
            }
            if let ruleText = string(key) {
                return SourceRule(raw: ruleText)
            }
            return nil
        }

        func legacyRuleMap(_ fields: [String: String]) -> SourceRule? {
            var mapped: [String: String] = [:]
            for item in fields {
                guard let value = legadoLegacyRule(string(item.value)), !value.isEmpty else { continue }
                mapped[item.key] = value
            }
            return mapped.isEmpty ? nil : SourceRule(fields: mapped)
        }

        func legacyContentRuleMap() -> SourceRule? {
            var mapped: [String: String] = [:]
            if var content = legadoLegacyRule(string("ruleBookContent")), !content.isEmpty {
                if content.hasPrefix("$"), !content.hasPrefix("$.") {
                    content.removeFirst()
                }
                mapped["content"] = content
            }
            if let replaceRegex = legadoLegacyRule(string("ruleBookContentReplace")), !replaceRegex.isEmpty {
                mapped["replaceRegex"] = replaceRegex
            }
            if let nextContentUrl = legadoLegacyRule(string("ruleContentUrlNext")), !nextContentUrl.isEmpty {
                mapped["nextContentUrl"] = nextContentUrl
            }
            return mapped.isEmpty ? nil : SourceRule(fields: mapped)
        }

        let name = string("bookSourceName") ?? string("sourceName") ?? string("name") ?? "\u{672a}\u{547d}\u{540d}\u{4e66}\u{6e90}"
        let url = string("bookSourceUrl") ?? string("sourceUrl") ?? string("url") ?? UUID().uuidString
        let ruleBookContent = rule("ruleBookContent")
        let structuredRuleBookContent = ruleBookContent?.fields.isEmpty == false ? ruleBookContent : nil

        self.init(
            bookSourceName: name,
            bookSourceUrl: url,
            bookSourceGroup: string("bookSourceGroup") ?? string("sourceGroup") ?? string("group"),
            bookSourceType: int(["bookSourceType", "sourceType"]),
            enabled: bool(["enabled", "enable"], default: true),
            weight: int(["weight", "serialNumber", "customOrder"]),
            searchUrl: string("searchUrl") ?? string("searchURL") ?? legadoLegacyURL(string("ruleSearchUrl")),
            exploreUrl: string("exploreUrl") ?? string("exploreURL") ?? legadoLegacyURLs(string("ruleFindUrl")),
            ruleSearch: rule("ruleSearch") ?? rule("rulesSearch") ?? legacyRuleMap([
                "bookList": "ruleSearchList",
                "name": "ruleSearchName",
                "author": "ruleSearchAuthor",
                "intro": "ruleSearchIntroduce",
                "kind": "ruleSearchKind",
                "bookUrl": "ruleSearchNoteUrl",
                "coverUrl": "ruleSearchCoverUrl",
                "lastChapter": "ruleSearchLastChapter"
            ]),
            ruleBookInfo: rule("ruleBookInfo") ?? rule("rulesBookInfo") ?? rule("ruleBook") ?? legacyRuleMap([
                "init": "ruleBookInfoInit",
                "name": "ruleBookName",
                "author": "ruleBookAuthor",
                "intro": "ruleIntroduce",
                "kind": "ruleBookKind",
                "coverUrl": "ruleCoverUrl",
                "lastChapter": "ruleBookLastChapter",
                "tocUrl": "ruleChapterUrl"
            ]),
            ruleToc: rule("ruleToc") ?? rule("rulesToc") ?? legacyRuleMap([
                "chapterList": "ruleChapterList",
                "chapterName": "ruleChapterName",
                "chapterUrl": "ruleContentUrl",
                "nextTocUrl": "ruleChapterUrlNext"
            ]),
            ruleContent: rule("ruleContent") ?? rule("rulesContent") ?? structuredRuleBookContent ?? legacyContentRuleMap() ?? ruleBookContent,
            ruleExplore: rule("ruleExplore") ?? rule("rulesExplore") ?? legacyRuleMap([
                "bookList": "ruleFindList",
                "name": "ruleFindName",
                "author": "ruleFindAuthor",
                "intro": "ruleFindIntroduce",
                "kind": "ruleFindKind",
                "bookUrl": "ruleFindNoteUrl",
                "coverUrl": "ruleFindCoverUrl",
                "lastChapter": "ruleFindLastChapter"
            ]),
            header: string("header") ?? string("headers") ?? string("bookSourceHeader"),
            loginUrl: string("loginUrl"),
            loginCheckJs: string("loginCheckJs"),
            customConfig: string("customConfig"),
            raw: raw
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bookSourceName, forKey: .bookSourceName)
        try container.encode(bookSourceUrl, forKey: .bookSourceUrl)
        try container.encodeIfPresent(bookSourceGroup, forKey: .bookSourceGroup)
        try container.encode(bookSourceType, forKey: .bookSourceType)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(weight, forKey: .weight)
        try container.encodeIfPresent(searchUrl, forKey: .searchUrl)
        try container.encodeIfPresent(exploreUrl, forKey: .exploreUrl)
        try container.encodeIfPresent(ruleSearch, forKey: .ruleSearch)
        try container.encodeIfPresent(ruleBookInfo, forKey: .ruleBookInfo)
        try container.encodeIfPresent(ruleToc, forKey: .ruleToc)
        try container.encodeIfPresent(ruleContent, forKey: .ruleContent)
        try container.encodeIfPresent(ruleExplore, forKey: .ruleExplore)
        try container.encodeIfPresent(header, forKey: .header)
        try container.encodeIfPresent(loginUrl, forKey: .loginUrl)
        try container.encodeIfPresent(loginCheckJs, forKey: .loginCheckJs)
        try container.encodeIfPresent(customConfig, forKey: .customConfig)
        if !raw.isEmpty {
            try container.encode(raw, forKey: .raw)
        }
    }

    func updatingEnabled(_ enabled: Bool) -> BookSource {
        BookSource(
            bookSourceName: bookSourceName,
            bookSourceUrl: bookSourceUrl,
            bookSourceGroup: bookSourceGroup,
            bookSourceType: bookSourceType,
            enabled: enabled,
            weight: weight,
            searchUrl: searchUrl,
            exploreUrl: exploreUrl,
            ruleSearch: ruleSearch,
            ruleBookInfo: ruleBookInfo,
            ruleToc: ruleToc,
            ruleContent: ruleContent,
            ruleExplore: ruleExplore,
            header: header,
            loginUrl: loginUrl,
            loginCheckJs: loginCheckJs,
            customConfig: customConfig,
            raw: raw
        )
    }
}

struct SourceRule: Codable, Hashable, Sendable {
    var raw: String?
    var fields: [String: String]

    init(raw: String? = nil, fields: [String: String] = [:]) {
        self.raw = raw
        self.fields = fields
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let value = try? single.decode(String.self) {
            if let data = value.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let fields = object.reduce(into: [String: String]()) { result, item in
                    result[item.key] = String(describing: item.value)
                }
                self.init(fields: fields)
                return
            }
            self.init(raw: value)
            return
        }
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var fields: [String: String] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(LosslessJSONValue.self, forKey: key) {
                fields[key.stringValue] = value.stringValue
            }
        }
        self.init(fields: fields)
    }

    func encode(to encoder: Encoder) throws {
        if let raw, fields.isEmpty {
            var container = encoder.singleValueContainer()
            try container.encode(raw)
            return
        }
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for item in fields.sorted(by: { $0.key < $1.key }) {
            try container.encode(item.value, forKey: DynamicCodingKey(item.key))
        }
    }
}

private func legadoLegacyRule(_ oldRule: String?) -> String? {
    guard var newRule = oldRule?.trimmingCharacters(in: .whitespacesAndNewlines), !newRule.isEmpty else {
        return nil
    }
    var reverse = false
    var allInOne = false
    if newRule.hasPrefix("-") {
        reverse = true
        newRule.removeFirst()
    }
    if newRule.hasPrefix("+") {
        allInOne = true
        newRule.removeFirst()
    }
    let lower = newRule.lowercased()
    let shouldConvertSeparators = !lower.hasPrefix("@css:")
        && !lower.hasPrefix("@xpath:")
        && !newRule.hasPrefix("//")
        && !newRule.hasPrefix("##")
        && !newRule.hasPrefix(":")
        && !newRule.hasPrefix("#")
        && !lower.contains("@js:")
        && !lower.contains("<js>")
    if shouldConvertSeparators {
        if newRule.contains("#"), !newRule.contains("##") {
            newRule = newRule.replacingOccurrences(of: "#", with: "##")
        }
        if newRule.contains("|"), !newRule.contains("||") {
            if newRule.contains("##") {
                var parts = newRule.components(separatedBy: "##")
                if let first = parts.first {
                    parts[0] = first.replacingOccurrences(of: "|", with: "||")
                    newRule = parts.joined(separator: "##")
                }
            } else {
                newRule = newRule.replacingOccurrences(of: "|", with: "||")
            }
        }
        if newRule.contains("&"),
           !newRule.contains("&&"),
           !newRule.contains("http"),
           !newRule.hasPrefix("/") {
            newRule = newRule.replacingOccurrences(of: "&", with: "&&")
        }
    }
    if allInOne {
        newRule = "+\(newRule)"
    }
    if reverse {
        newRule = "-\(newRule)"
    }
    return newRule
}

private func legadoLegacyURLs(_ oldURLs: String?) -> String? {
    guard let text = oldURLs?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
        return nil
    }
    if text.hasPrefix("@js:") || text.hasPrefix("<js>") {
        return text
    }
    if !text.contains("\n"), !text.contains("&&") {
        return legadoLegacyURL(text)
    }
    let parts = text
        .components(separatedBy: CharacterSet.newlines)
        .flatMap { $0.components(separatedBy: "&&") }
        .compactMap { legadoLegacyURL($0)?.replacingOccurrences(of: #"\n\s*"#, with: "", options: .regularExpression) }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: "\n")
}

private func legadoLegacyURL(_ oldURL: String?) -> String? {
    guard var url = oldURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
        return nil
    }
    if url.lowercased().hasPrefix("<js>") {
        return url
            .replacingOccurrences(of: "=searchKey", with: "={{key}}")
            .replacingOccurrences(of: "=searchPage", with: "={{page}}")
    }

    var options: [String: Any] = [:]
    if let range = url.range(of: #"@Header:\{.+?\}"#, options: [.regularExpression, .caseInsensitive]) {
        let headerDirective = String(url[range])
        url.removeSubrange(range)
        options["headers"] = String(headerDirective.dropFirst(8))
    }

    if let pipe = url.firstIndex(of: "|") {
        let charsetAndTail = String(url[url.index(after: pipe)...])
        url = String(url[..<pipe])
        let tailParts = charsetAndTail.components(separatedBy: "@")
        let charsetText = tailParts.first ?? ""
        if let separator = charsetText.firstIndex(of: "="),
           separator < charsetText.index(before: charsetText.endIndex) {
            options["charset"] = String(charsetText[charsetText.index(after: separator)...])
        } else if !charsetText.isEmpty {
            options["charset"] = charsetText
        }
        if tailParts.count > 1 {
            options["method"] = "POST"
            options["body"] = legadoLegacyTemplatePlaceholders(tailParts.dropFirst().joined(separator: "@"))
        }
    }

    var scripts: [String] = []
    url = replaceMatches(in: url, pattern: #"\{\{.+?\}\}"#) { match in
        scripts.append(match)
        return "$\(scripts.count - 1)"
    }
    url = url
        .replacingOccurrences(of: "{", with: "<")
        .replacingOccurrences(of: "}", with: ">")
        .replacingOccurrences(of: "searchKey", with: "{{key}}")
    url = replaceMatches(in: url, pattern: #"<searchPage([-+]\d+)>"#) { match in
        let delta = match
            .replacingOccurrences(of: "<searchPage", with: "")
            .replacingOccurrences(of: ">", with: "")
        return "{{page\(delta)}}"
    }
    url = replaceMatches(in: url, pattern: #"searchPage([-+]\d+)"#) { match in
        let delta = match.replacingOccurrences(of: "searchPage", with: "")
        return "{{page\(delta)}}"
    }
    url = url.replacingOccurrences(of: "searchPage", with: "{{page}}")
    for index in scripts.indices {
        let script = scripts[index]
            .replacingOccurrences(of: "searchKey", with: "key")
            .replacingOccurrences(of: "searchPage", with: "page")
        url = url.replacingOccurrences(of: "$\(index)", with: script)
    }

    let bodyParts = url.components(separatedBy: "@")
    url = bodyParts.first ?? url
    if bodyParts.count > 1, options["body"] == nil {
        options["method"] = "POST"
        options["body"] = legadoLegacyTemplatePlaceholders(bodyParts.dropFirst().joined(separator: "@"))
    }

    guard !options.isEmpty,
          JSONSerialization.isValidJSONObject(options),
          let data = try? JSONSerialization.data(withJSONObject: options, options: [.sortedKeys]),
          let json = String(data: data, encoding: .utf8) else {
        return url
    }
    return "\(url),\(json)"
}

private func legadoLegacyTemplatePlaceholders(_ text: String) -> String {
    var output = text
    var scripts: [String] = []
    output = replaceMatches(in: output, pattern: #"\{\{.+?\}\}"#) { match in
        scripts.append(match)
        return "$\(scripts.count - 1)"
    }
    output = output
        .replacingOccurrences(of: "{searchKey}", with: "{{key}}")
        .replacingOccurrences(of: "searchKey", with: "{{key}}")
    output = replaceMatches(in: output, pattern: #"\{searchPage([-+]\d+)\}"#) { match in
        let delta = match
            .replacingOccurrences(of: "{searchPage", with: "")
            .replacingOccurrences(of: "}", with: "")
        return "{{page\(delta)}}"
    }
    output = replaceMatches(in: output, pattern: #"searchPage([-+]\d+)"#) { match in
        let delta = match.replacingOccurrences(of: "searchPage", with: "")
        return "{{page\(delta)}}"
    }
    output = output
        .replacingOccurrences(of: "{searchPage}", with: "{{page}}")
        .replacingOccurrences(of: "searchPage", with: "{{page}}")
    for index in scripts.indices {
        output = output.replacingOccurrences(of: "$\(index)", with: scripts[index])
    }
    return output
}

private func replaceMatches(in text: String, pattern: String, transform: (String) -> String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    var output = text
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
    for match in matches.reversed() {
        guard let range = Range(match.range(at: 0), in: output) else { continue }
        output.replaceSubrange(range, with: transform(String(output[range])))
    }
    return output
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private indirect enum LosslessJSONValue: Decodable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case object([String: LosslessJSONValue])
    case array([LosslessJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Int.self) {
            self = .int(value)
        } else if let value = try? single.decode(Double.self) {
            self = .double(value)
        } else if let value = try? single.decode([String: LosslessJSONValue].self) {
            self = .object(value)
        } else if let value = try? single.decode([LosslessJSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .bool(let value):
            return value ? "true" : "false"
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .object, .array:
            return jsonCompatibleString
        case .null:
            return ""
        }
    }

    private var jsonCompatibleString: String {
        let value = jsonCompatibleValue
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    private var jsonCompatibleValue: Any {
        switch self {
        case .string(let value):
            return value
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .object(let value):
            return value.mapValues(\.jsonCompatibleValue)
        case .array(let value):
            return value.map(\.jsonCompatibleValue)
        case .null:
            return NSNull()
        }
    }
}
