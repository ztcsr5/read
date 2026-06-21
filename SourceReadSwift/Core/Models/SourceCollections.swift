import Foundation

struct RSSSource: Identifiable, Codable, Hashable, Sendable {
    var id: String { sourceUrl }
    var sourceName: String
    var sourceUrl: String
    var sourceIcon: String?
    var sourceGroup: String?
    var sourceComment: String?
    var enabled: Bool
    var enabledCookieJar: Bool
    var sortUrl: String?
    var ruleArticles: String?
    var ruleNextPage: String?
    var ruleTitle: String?
    var rulePubDate: String?
    var ruleDescription: String?
    var ruleImage: String?
    var ruleLink: String?
    var ruleContent: String?
    var style: String?
    var customConfig: String?

    enum CodingKeys: String, CodingKey {
        case sourceName
        case sourceUrl
        case sourceIcon
        case sourceGroup
        case sourceComment
        case enabled
        case enabledCookieJar
        case sortUrl
        case ruleArticles
        case ruleNextPage
        case ruleTitle
        case rulePubDate
        case ruleDescription
        case ruleImage
        case ruleLink
        case ruleContent
        case style
        case customConfig
    }

    init(
        sourceName: String,
        sourceUrl: String,
        sourceIcon: String? = nil,
        sourceGroup: String? = nil,
        sourceComment: String? = nil,
        enabled: Bool = true,
        enabledCookieJar: Bool = false,
        sortUrl: String? = nil,
        ruleArticles: String? = nil,
        ruleNextPage: String? = nil,
        ruleTitle: String? = nil,
        rulePubDate: String? = nil,
        ruleDescription: String? = nil,
        ruleImage: String? = nil,
        ruleLink: String? = nil,
        ruleContent: String? = nil,
        style: String? = nil,
        customConfig: String? = nil
    ) {
        self.sourceName = sourceName
        self.sourceUrl = sourceUrl
        self.sourceIcon = sourceIcon
        self.sourceGroup = sourceGroup
        self.sourceComment = sourceComment
        self.enabled = enabled
        self.enabledCookieJar = enabledCookieJar
        self.sortUrl = sortUrl
        self.ruleArticles = ruleArticles
        self.ruleNextPage = ruleNextPage
        self.ruleTitle = ruleTitle
        self.rulePubDate = rulePubDate
        self.ruleDescription = ruleDescription
        self.ruleImage = ruleImage
        self.ruleLink = ruleLink
        self.ruleContent = ruleContent
        self.style = style
        self.customConfig = customConfig
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        func string(_ key: String) -> String? {
            (try? container.decode(String.self, forKey: DynamicCodingKey(key)))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }
        func bool(_ key: String, default defaultValue: Bool) -> Bool {
            (try? container.decode(Bool.self, forKey: DynamicCodingKey(key))) ?? defaultValue
        }
        self.init(
            sourceName: string("sourceName") ?? string("name") ?? "Unknown RSS",
            sourceUrl: string("sourceUrl") ?? string("url") ?? "",
            sourceIcon: string("sourceIcon") ?? string("icon"),
            sourceGroup: string("sourceGroup") ?? string("group"),
            sourceComment: string("sourceComment") ?? string("comment"),
            enabled: bool("enabled", default: true),
            enabledCookieJar: bool("enabledCookieJar", default: false),
            sortUrl: string("sortUrl"),
            ruleArticles: string("ruleArticles"),
            ruleNextPage: string("ruleNextPage"),
            ruleTitle: string("ruleTitle"),
            rulePubDate: string("rulePubDate"),
            ruleDescription: string("ruleDescription"),
            ruleImage: string("ruleImage"),
            ruleLink: string("ruleLink"),
            ruleContent: string("ruleContent"),
            style: string("style"),
            customConfig: string("customConfig")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(sourceUrl, forKey: .sourceUrl)
        try container.encodeIfPresent(sourceIcon, forKey: .sourceIcon)
        try container.encodeIfPresent(sourceGroup, forKey: .sourceGroup)
        try container.encodeIfPresent(sourceComment, forKey: .sourceComment)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(enabledCookieJar, forKey: .enabledCookieJar)
        try container.encodeIfPresent(sortUrl, forKey: .sortUrl)
        try container.encodeIfPresent(ruleArticles, forKey: .ruleArticles)
        try container.encodeIfPresent(ruleNextPage, forKey: .ruleNextPage)
        try container.encodeIfPresent(ruleTitle, forKey: .ruleTitle)
        try container.encodeIfPresent(rulePubDate, forKey: .rulePubDate)
        try container.encodeIfPresent(ruleDescription, forKey: .ruleDescription)
        try container.encodeIfPresent(ruleImage, forKey: .ruleImage)
        try container.encodeIfPresent(ruleLink, forKey: .ruleLink)
        try container.encodeIfPresent(ruleContent, forKey: .ruleContent)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(customConfig, forKey: .customConfig)
    }
}

struct SourceCatalog: Identifiable, Codable, Hashable, Sendable {
    var id: String { url }
    var name: String
    var url: String
    var importUrl: String?
    var icon: String?
    var group: String?
    var comment: String?
    var enabled: Bool
    var importedCount: Int
    var lastStatus: String?
    var lastImportedAt: Date?

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case importUrl
        case icon
        case group
        case comment
        case enabled
        case importedCount
        case lastStatus
        case lastImportedAt
    }

    init(
        name: String,
        url: String,
        importUrl: String? = nil,
        icon: String? = nil,
        group: String? = nil,
        comment: String? = nil,
        enabled: Bool = true,
        importedCount: Int = 0,
        lastStatus: String? = nil,
        lastImportedAt: Date? = nil
    ) {
        self.name = name
        self.url = url
        self.importUrl = importUrl
        self.icon = icon
        self.group = group
        self.comment = comment
        self.enabled = enabled
        self.importedCount = importedCount
        self.lastStatus = lastStatus
        self.lastImportedAt = lastImportedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        func string(_ key: String) -> String? {
            (try? container.decode(String.self, forKey: DynamicCodingKey(key)))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }
        self.init(
            name: string("sourceName") ?? string("name") ?? "Unknown Catalog",
            url: string("sourceUrl") ?? string("url") ?? "",
            importUrl: string("importUrl") ?? string("singleUrl"),
            icon: string("sourceIcon") ?? string("icon"),
            group: string("sourceGroup") ?? string("group"),
            comment: string("sourceComment") ?? string("comment"),
            enabled: (try? container.decode(Bool.self, forKey: DynamicCodingKey("enabled"))) ?? true,
            importedCount: (try? container.decode(Int.self, forKey: DynamicCodingKey("importedCount"))) ?? 0,
            lastStatus: string("lastStatus"),
            lastImportedAt: nil
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(importUrl, forKey: .importUrl)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(group, forKey: .group)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(importedCount, forKey: .importedCount)
        try container.encodeIfPresent(lastStatus, forKey: .lastStatus)
        try container.encodeIfPresent(lastImportedAt, forKey: .lastImportedAt)
    }
}

struct SourceLibrarySnapshot: Codable, Sendable {
    var sources: [BookSource]
    var rssSources: [RSSSource]
    var catalogs: [SourceCatalog]

    init(
        sources: [BookSource] = [],
        rssSources: [RSSSource] = [],
        catalogs: [SourceCatalog] = []
    ) {
        self.sources = sources
        self.rssSources = rssSources
        self.catalogs = catalogs
    }
}
