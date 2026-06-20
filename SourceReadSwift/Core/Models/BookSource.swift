import Foundation

struct BookSource: Identifiable, Codable, Hashable, Sendable {
    var id: String { bookSourceUrl }

    let bookSourceName: String
    let bookSourceUrl: String
    let bookSourceGroup: String?
    let enabled: Bool
    let searchUrl: String?
    let ruleSearch: SourceRule?
    let ruleBookInfo: SourceRule?
    let ruleToc: SourceRule?
    let ruleContent: SourceRule?
    let header: String?
    let loginUrl: String?
    let loginCheckJs: String?
    let raw: [String: String]

    enum CodingKeys: String, CodingKey {
        case bookSourceName
        case bookSourceUrl
        case bookSourceGroup
        case enabled
        case searchUrl
        case ruleSearch
        case ruleBookInfo
        case ruleToc
        case ruleContent
        case header
        case loginUrl
        case loginCheckJs
    }

    init(
        bookSourceName: String,
        bookSourceUrl: String,
        bookSourceGroup: String? = nil,
        enabled: Bool = true,
        searchUrl: String? = nil,
        ruleSearch: SourceRule? = nil,
        ruleBookInfo: SourceRule? = nil,
        ruleToc: SourceRule? = nil,
        ruleContent: SourceRule? = nil,
        header: String? = nil,
        loginUrl: String? = nil,
        loginCheckJs: String? = nil,
        raw: [String: String] = [:]
    ) {
        self.bookSourceName = bookSourceName
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceGroup = bookSourceGroup
        self.enabled = enabled
        self.searchUrl = searchUrl
        self.ruleSearch = ruleSearch
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
        self.header = header
        self.loginUrl = loginUrl
        self.loginCheckJs = loginCheckJs
        self.raw = raw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var raw: [String: String] = [:]
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
            bookSourceGroup: string("bookSourceGroup"),
            enabled: (try? container.decode(Bool.self, forKey: DynamicCodingKey("enabled"))) ?? true,
            searchUrl: string("searchUrl"),
            ruleSearch: rule("ruleSearch"),
            ruleBookInfo: rule("ruleBookInfo"),
            ruleToc: rule("ruleToc"),
            ruleContent: rule("ruleContent"),
            header: string("header"),
            loginUrl: string("loginUrl"),
            loginCheckJs: string("loginCheckJs"),
            raw: raw
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bookSourceName, forKey: .bookSourceName)
        try container.encode(bookSourceUrl, forKey: .bookSourceUrl)
        try container.encodeIfPresent(bookSourceGroup, forKey: .bookSourceGroup)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(searchUrl, forKey: .searchUrl)
        try container.encodeIfPresent(ruleSearch, forKey: .ruleSearch)
        try container.encodeIfPresent(ruleBookInfo, forKey: .ruleBookInfo)
        try container.encodeIfPresent(ruleToc, forKey: .ruleToc)
        try container.encodeIfPresent(ruleContent, forKey: .ruleContent)
        try container.encodeIfPresent(header, forKey: .header)
        try container.encodeIfPresent(loginUrl, forKey: .loginUrl)
        try container.encodeIfPresent(loginCheckJs, forKey: .loginCheckJs)
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
