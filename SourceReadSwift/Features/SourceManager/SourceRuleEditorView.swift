import SwiftUI

struct SourceRuleEditorView: View {
    let source: BookSource
    let onSave: (BookSource) -> Void
    let onCancel: () -> Void

    @State private var searchURL: String
    @State private var searchRule: String
    @State private var detailRule: String
    @State private var tocRule: String
    @State private var contentRule: String
    @State private var selectedSection = 0
    @State private var issues: [RuleValidationIssue] = []
    @State private var previewSample = "<html><body><article><h1>示例书名</h1><p class=\"content\">示例正文</p></article></body></html>"
    @State private var previewOutput = ""
    @State private var isPreviewing = false

    init(source: BookSource, onSave: @escaping (BookSource) -> Void, onCancel: @escaping () -> Void) {
        self.source = source
        self.onSave = onSave
        self.onCancel = onCancel
        _searchURL = State(initialValue: source.searchUrl ?? "")
        _searchRule = State(initialValue: Self.text(source.ruleSearch))
        _detailRule = State(initialValue: Self.text(source.ruleBookInfo))
        _tocRule = State(initialValue: Self.text(source.ruleToc))
        _contentRule = State(initialValue: Self.text(source.ruleContent))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("规则阶段", selection: $selectedSection) {
                        Text("搜索").tag(0)
                        Text("详情").tag(1)
                        Text("目录").tag(2)
                        Text("正文").tag(3)
                    }
                    .pickerStyle(.segmented)
                }
                Section("当前阶段说明") {
                    Label(stageHelp.title, systemImage: stageHelp.systemImage)
                        .font(.subheadline.weight(.semibold))
                    Text(stageHelp.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("输入") {
                    if selectedSection == 0 {
                        TextEditor(text: $searchURL)
                            .frame(minHeight: 80)
                            .font(.system(.footnote, design: .monospaced))
                    }
                    TextEditor(text: currentRuleBinding)
                        .frame(minHeight: 180)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    TextEditor(text: $previewSample)
                        .frame(minHeight: 120)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        runLocalPreview()
                    } label: {
                        Label(isPreviewing ? "预览中…" : "用本地样本预览", systemImage: "play.circle")
                    }
                    .disabled(isPreviewing || previewSample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !previewOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("预览结果")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(previewOutput)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                } header: {
                    Text("本地样本预览（不联网）")
                } footer: {
                    Text("输入脱敏 HTML/JSON 样本，单步执行当前规则；预览不会保存书源或 Cookie。")
                }
                if !issues.isEmpty {
                    Section("校验结果") {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.footnote)
                        }
                    }
                }
                Section("说明") {
                    Text("支持 CSS、XPath、JSONPath、@js: 和 <js> 规则。保存前会保留原书源字段，并只覆盖当前规则分组。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("规则编辑 · \(source.bookSourceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("校验并保存") {
                        let drafts = [
                            "searchUrl": searchURL,
                            "ruleSearch": searchRule,
                            "ruleBookInfo": detailRule,
                            "ruleToc": tocRule,
                            "ruleContent": contentRule
                        ]
                        issues = RuleEditorValidator().validate(source: source, drafts: drafts)
                        guard issues.isEmpty else { return }
                        onSave(source.updatingRules(searchURL: searchURL, search: searchRule, detail: detailRule, toc: tocRule, content: contentRule))
                    }
                }
            }
        }
    }

    private var currentRuleBinding: Binding<String> {
        switch selectedSection {
        case 0: return $searchRule
        case 1: return $detailRule
        case 2: return $tocRule
        default: return $contentRule
        }
    }

    private var stageHelp: (title: String, message: String, systemImage: String) {
        switch selectedSection {
        case 0: return ("搜索规则", "从搜索响应中提取书名、作者、封面和详情链接；JSON 书源通常填写 JSONPath，网页书源填写 CSS/XPath。", "magnifyingglass")
        case 1: return ("详情规则", "提取书籍简介、作者、封面、目录地址和最新章节。没有目录地址时会尝试使用详情页中的目录链接。", "book.closed")
        case 2: return ("目录规则", "把章节标题和章节链接解析成目录列表；分页目录可在规则中保留 nextUrl/分页字段。", "list.number")
        default: return ("正文规则", "从章节响应中提取正文文本；建议同时处理广告净化和 HTML 实体，预览结果应接近阅读页正文。", "doc.text")
        }
    }

    private func runLocalPreview() {
        isPreviewing = true
        let sample = previewSample
        let text: String
        switch selectedSection {
        case 0: text = searchRule
        case 1: text = detailRule
        case 2: text = tocRule
        default: text = contentRule
        }
        let stage: RulePreviewEvaluator.Stage
        switch selectedSection {
        case 0: stage = .search
        case 1: stage = .detail
        case 2: stage = .toc
        default: stage = .content
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let output = RulePreviewEvaluator().evaluate(sample: sample, ruleText: text, stage: stage)
            DispatchQueue.main.async {
                previewOutput = output
                isPreviewing = false
            }
        }
    }

    private static func text(_ rule: SourceRule?) -> String {
        guard let rule else { return "" }
        if let raw = rule.raw, rule.fields.isEmpty { return raw }
        guard let data = try? JSONEncoder().encode(rule.fields),
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }
}
