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
            if let value = try? container.decode(String.self, forKey: key) {
                raw[key.stringValue] = value
            } else if let value = try? container.decode(Bool.self, forKey: key) {
                raw[key.stringValue] = String(value)
            } else if let value = try? container.decode(Int.self, forKey: key) {
                raw[key.stringValue] = String(value)
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
                    if ["true", "1", "yes", "on"].contains(text) {
                        return true
                    }
                    if ["false", "0", "no", "off"].contains(text) {
                        return false
                    }
                }
            }
            return defaultValue
        }

        func rule(_ key: String) -> SourceRule? {
            if let ruleText = string(key) {
                return SourceRule(raw: ruleText)
            }
            if let nested = try? container.decode(SourceRule.self, forKey: DynamicCodingKey(key)) {
                return nested
            }
            return nil
        }

        let name = string("bookSourceName") ?? string("sourceName") ?? "\u{672a}\u{547d}\u{540d}\u{4e66}\u{6e90}"
        let url = string("bookSourceUrl") ?? string("sourceUrl") ?? UUID().uuidString

        self.init(
            bookSourceName: name,
            bookSourceUrl: url,
            bookSourceGroup: string("bookSourceGroup") ?? string("sourceGroup"),
            bookSourceType: int(["bookSourceType", "sourceType"]),
            enabled: bool(["enabled", "enable"], default: true),
            weight: int(["weight"]),
            searchUrl: string("searchUrl") ?? string("searchURL"),
            exploreUrl: string("exploreUrl") ?? string("exploreURL"),
            ruleSearch: rule("ruleSearch") ?? rule("rulesSearch"),
            ruleBookInfo: rule("ruleBookInfo") ?? rule("rulesBookInfo") ?? rule("ruleBook"),
            ruleToc: rule("ruleToc") ?? rule("rulesToc"),
            ruleContent: rule("ruleContent") ?? rule("ruleBookContent") ?? rule("rulesContent"),
            ruleExplore: rule("ruleExplore") ?? rule("rulesExplore"),
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
            self.init(raw: value)
            return
        }
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var fields: [String: String] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(String.self, forKey: key) {
                fields[key.stringValue] = value
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
