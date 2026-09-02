import SwiftUI

struct RSSSourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let source: RSSSource
    let onSave: (RSSSource) -> Void

    @State private var draft: RSSSource
    @State private var validationMessage: String?

    init(source: RSSSource, onSave: @escaping (RSSSource) -> Void) {
        self.source = source
        self.onSave = onSave
        _draft = State(initialValue: source)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础") {
                    TextField("名称", text: $draft.sourceName)
                    TextField("Feed URL", text: $draft.sourceUrl)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("分组", text: Binding($draft.sourceGroup, replacingNilWith: ""))
                    TextField("备注", text: Binding($draft.sourceComment, replacingNilWith: ""))
                    Toggle("启用", isOn: $draft.enabled)
                    Toggle("使用 Cookie", isOn: $draft.enabledCookieJar)
                }
                Section("列表规则") {
                    ruleField("文章列表", keyPath: \.ruleArticles)
                    ruleField("下一页", keyPath: \.ruleNextPage)
                    ruleField("标题", keyPath: \.ruleTitle)
                    ruleField("发布时间", keyPath: \.rulePubDate)
                    ruleField("描述", keyPath: \.ruleDescription)
                    ruleField("图片", keyPath: \.ruleImage)
                    ruleField("链接", keyPath: \.ruleLink)
                }
                Section("正文") {
                    ruleField("正文内容", keyPath: \.ruleContent)
                    ruleField("排序 URL", keyPath: \.sortUrl)
                    ruleField("CSS 样式", keyPath: \.style, axis: .vertical)
                }
                if let validationMessage {
                    Section { Text(validationMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("编辑 RSS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func ruleField(_ title: String, keyPath: WritableKeyPath<RSSSource, String?>, axis: Axis.Set = .horizontal) -> some View {
        Group {
            if axis == .vertical {
                TextField(title, text: binding(for: keyPath), axis: .vertical)
                    .lineLimit(3...8)
            } else {
                TextField(title, text: binding(for: keyPath))
                    .textInputAutocapitalization(.never)
            }
        }
    }

    private func binding(for keyPath: WritableKeyPath<RSSSource, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        )
    }

    private func save() {
        let name = draft.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlText = draft.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { validationMessage = "名称不能为空"; return }
        guard let url = URL(string: urlText), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            validationMessage = "Feed URL 必须是 http/https"
            return
        }
        guard draft.ruleArticles?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil else {
            validationMessage = "文章列表规则不能为空"
            return
        }
        draft.sourceName = name
        draft.sourceUrl = urlText
        onSave(draft)
        dismiss()
    }
}

private extension Binding where Value == String {
    init(_ optional: Binding<String?>, replacingNilWith fallback: String) {
        self.init(
            get: { optional.wrappedValue ?? fallback },
            set: { optional.wrappedValue = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        )
    }
}
