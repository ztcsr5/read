import Foundation
import SwiftUI
import UIKit

enum ReaderBackground: String, CaseIterable, Identifiable, Sendable {
    case paper
    case green
    case gray
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return "纸张"
        case .green: return "护眼"
        case .gray: return "浅灰"
        case .dark: return "深色"
        }
    }

    var color: Color {
        switch self {
        case .paper: return Color(red: 0.96, green: 0.93, blue: 0.86)
        case .green: return Color(red: 0.88, green: 0.94, blue: 0.86)
        case .gray: return Color(.systemGray6)
        case .dark: return Color(red: 0.12, green: 0.12, blue: 0.13)
        }
    }

    var textColor: Color {
        self == .dark ? .white.opacity(0.9) : .primary
    }

    var uiTextColor: UIColor {
        self == .dark ? UIColor.white.withAlphaComponent(0.92) : UIColor.label
    }
}

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

/// Normalizes values entered beside reader sliders.  Keeping parsing and
/// clamping outside the view makes malformed persisted/input values harmless
/// and gives the XCTest target a deterministic contract for every setting.
enum ReaderValueNormalizer {
    static func clampedValue(
        from rawValue: String,
        range: ClosedRange<Double>
    ) -> Double? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        // A trailing decimal separator is a valid *draft* while the user is
        // typing, but it is not a committed value.  Treat it as invalid here
        // so blur/submit restores the last known-good value instead of
        // silently accepting a partial edit.
        guard !normalized.isEmpty,
              !normalized.hasSuffix("."),
              normalized != "+",
              normalized != "-",
              let parsed = Double(normalized),
              parsed.isFinite else {
            return nil
        }
        return min(max(parsed, range.lowerBound), range.upperBound)
    }

    static func formatted(_ value: Double, step: Double) -> String {
        guard value.isFinite else { return "0" }
        if step < 1 {
            return String(format: "%.2f", value)
                .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        }
        return String(format: "%.0f", value)
    }
}

/// A compact numeric editor used next to every reader slider.  The draft text
/// is allowed to be temporarily incomplete (for example `1.` while typing),
/// then committed and clamped when editing ends or the keyboard submits.
struct ReaderNumberInput: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    @State private var draft: String
    @FocusState private var focused: Bool

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        _draft = State(initialValue: ReaderValueNormalizer.formatted(value.wrappedValue, step: step))
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $draft, onEditingChanged: { isEditing in
                if !isEditing { commit() }
            }, onCommit: commit)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: 76)
            .focused($focused)
            .accessibilityLabel("输入\(title)")

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: value) { updated in
            let formatted = ReaderValueNormalizer.formatted(updated, step: step)
            if draft != formatted, !focused {
                draft = formatted
            }
        }
    }

    private func commit() {
        guard let parsed = ReaderValueNormalizer.clampedValue(from: draft, range: range) else {
            draft = ReaderValueNormalizer.formatted(value, step: step)
            return
        }
        value = parsed
        draft = ReaderValueNormalizer.formatted(parsed, step: step)
    }
}
