import Foundation

struct PurifyRule: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var pattern: String
    var enabled: Bool

    init(id: String = UUID().uuidString, pattern: String, enabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.enabled = enabled
    }
}

struct PurifyRulePreset: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var detail: String
    var patterns: [String]

    static let builtIn: [PurifyRulePreset] = [
        PurifyRulePreset(
            id: "ads",
            title: "广告与推广",
            detail: "删除常见章节内广告、推广、备用网址提示。",
            patterns: [
                ".*最新地址.*",
                ".*备用网址.*",
                ".*APP内阅读.*",
                ".*下载.*app.*",
                ".*关注.*公众号.*"
            ]
        ),
        PurifyRulePreset(
            id: "site-tail",
            title: "站点尾巴",
            detail: "删除站点在正文首尾追加的收藏、推荐、版权尾巴。",
            patterns: [
                "请收藏本站.*##",
                "喜欢.*请大家收藏.*##",
                "本章未完.*请点击下一页继续阅读.*##",
                "章节错误.*请点击报错.*##"
            ]
        ),
        PurifyRulePreset(
            id: "noise",
            title: "乱码与占位",
            detail: "删除常见空白占位、重复分隔符和正文噪声。",
            patterns: [
                "\\u3000{4,}##\\n",
                "[-—=]{6,}##",
                "\\[.*?最新网址.*?\\]##",
                "『.*?』##"
            ]
        )
    ]
}

@MainActor
final class PurifyRuleStore: ObservableObject {
    @Published private(set) var rules: [PurifyRule] = []
    @Published private(set) var lastError: String?

    private let persistence: PurifyRulePersistence

    init(persistence: PurifyRulePersistence = PurifyRulePersistence()) {
        self.persistence = persistence
        do {
            rules = try persistence.load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    var enabledPatterns: [String] {
        rules
            .filter(\.enabled)
            .map(\.pattern)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func add(_ pattern: String) {
        let clean = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !rules.contains(where: { $0.pattern == clean }) else { return }
        rules.insert(PurifyRule(pattern: clean), at: 0)
        persist()
    }

    func importLines(_ text: String) -> Int {
        let values = text.components(separatedBy: CharacterSet.newlines)
        return importPatterns(values)
    }

    @discardableResult
    func importPatterns(_ patterns: [String]) -> Int {
        var seen = Set(rules.map(\.pattern))
        let values = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
        for value in values.reversed() {
            rules.insert(PurifyRule(pattern: value), at: 0)
        }
        persist()
        return values.count
    }

    func containsPattern(_ pattern: String) -> Bool {
        let clean = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        return rules.contains { $0.pattern == clean }
    }

    func setEnabled(_ enabled: Bool, ruleID: String) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        rules[index].enabled = enabled
        persist()
    }

    func setAllEnabled(_ enabled: Bool) {
        guard rules.contains(where: { $0.enabled != enabled }) else { return }
        rules = rules.map { rule in
            var updated = rule
            updated.enabled = enabled
            return updated
        }
        persist()
    }

    func preview(text: String) -> String {
        PurifyRuleEvaluator.apply(rules: enabledPatterns, to: text)
    }

    func remove(ruleID: String) {
        rules.removeAll { $0.id == ruleID }
        persist()
    }

    private func persist() {
        do {
            try persistence.save(rules)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

struct PurifyRulePersistence {
    private let fileManager: FileManager
    private let fileName = "purify_rules.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [PurifyRule] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([PurifyRule].self, from: data)
    }

    func save(_ rules: [PurifyRule]) throws {
        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(rules)
        try data.write(to: url, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        if let rootURL {
            return rootURL.appendingPathComponent(fileName)
        }
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("SourceReadSwift", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
