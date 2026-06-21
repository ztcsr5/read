import SwiftUI

enum ReaderMode: String, CaseIterable, Identifiable, Sendable {
    case scroll
    case pageTurn
    case cover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scroll: return "滑动"
        case .pageTurn: return "平移"
        case .cover: return "覆盖"
        }
    }
}

enum ReaderTapAction: String, CaseIterable, Identifiable, Sendable {
    case previousPage
    case nextPage
    case previousChapter
    case nextChapter
    case menu
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previousPage: return "上一页"
        case .nextPage: return "下一页"
        case .previousChapter: return "上一章"
        case .nextChapter: return "下一章"
        case .menu: return "菜单"
        case .disabled: return "无动作"
        }
    }

    var shortTitle: String {
        switch self {
        case .previousPage: return "上页"
        case .nextPage: return "下页"
        case .previousChapter: return "上章"
        case .nextChapter: return "下章"
        case .menu: return "菜单"
        case .disabled: return "关闭"
        }
    }

    var color: Color {
        switch self {
        case .previousPage, .previousChapter: return .blue
        case .nextPage, .nextChapter: return .green
        case .menu: return AppTheme.accent
        case .disabled: return .secondary
        }
    }

    static let defaultActions: [ReaderTapAction] = [
        .previousPage, .previousPage, .nextPage,
        .previousPage, .menu, .nextPage,
        .nextPage, .nextPage, .nextPage
    ]

    static var defaultRawValue: String {
        encode(defaultActions)
    }

    static func encode(_ actions: [ReaderTapAction]) -> String {
        actions.map(\.rawValue).joined(separator: ",")
    }

    static func decode(rawValue: String) -> [ReaderTapAction] {
        let values = rawValue
            .split(separator: ",")
            .map { ReaderTapAction(rawValue: String($0)) ?? .menu }
        guard values.count == 9 else { return defaultActions }
        return values.contains(.menu) ? values : defaultActions
    }
}

enum ReaderPreloadPolicy {
    static let defaultCount = 2
    static let minimumCount = 0
    static let maximumCount = 5

    static func clamp(_ count: Int) -> Int {
        min(max(count, minimumCount), maximumCount)
    }

    static func title(for count: Int) -> String {
        let value = clamp(count)
        return value == 0 ? "关闭" : "\(value) 章"
    }
}
