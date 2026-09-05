import SwiftUI
import WebKit

struct SmartWebReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var address = "https://"
    @State private var loadedURL: URL?
    @State private var article: SmartWebArticle?
    @State private var isExtracting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let article {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(article.title).font(.title.bold())
                            Text(article.text)
                                .font(.system(size: 18, weight: .regular))
                                .lineSpacing(8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.pagePadding)
                        .padding(.bottom, 90)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button { self.article = nil } label: {
                            Label("返回网页", systemImage: "safari")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 8)
                    }
                } else {
                    VStack(spacing: 14) {
                        HStack(spacing: 8) {
                            TextField("粘贴小说网页地址", text: $address)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .textFieldStyle(.roundedBorder)
                            Button("打开") { loadPage() }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal, AppTheme.pagePadding)

                        if let loadedURL {
                            SmartWebView(url: loadedURL)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(alignment: .bottom) {
                                    Button {
                                        extractPage()
                                    } label: {
                                        Label(isExtracting ? "提取中…" : "提取正文并阅读", systemImage: "doc.text.magnifyingglass")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isExtracting)
                                    .padding(12)
                                }
                        } else {
                            ContentUnavailableView("网页阅读模式", systemImage: "safari", description: Text("粘贴网页地址后打开。提取正文会移除导航、广告和脚本，只保留可阅读内容。"))
                        }
                        if let errorMessage {
                            Text(errorMessage).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .pageBackground()
            .navigationTitle("智能网页阅读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func loadPage() {
        errorMessage = nil
        article = nil
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            errorMessage = "请输入有效的 http/https 地址"
            return
        }
        loadedURL = url
    }

    private func extractPage() {
        guard let loadedURL else { return }
        isExtracting = true
        errorMessage = nil
        SmartWebView.extract(url: loadedURL) { result in
            isExtracting = false
            switch result {
            case .success(let html):
                let extracted = SmartWebArticleExtractor.extract(html: html, fallbackTitle: loadedURL.host ?? "网页文章")
                guard !extracted.paragraphs.isEmpty else {
                    errorMessage = "未识别到正文，请换一个文章页或稍后重试"
                    return
                }
                article = extracted
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SmartWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView { WKWebView(frame: .zero) }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard view.url != url else { return }
        view.load(URLRequest(url: url))
    }

    static func extract(url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let webView = WKWebView(frame: .zero)
        let delegate = ExtractionDelegate(completion: completion)
        delegate.webView = webView
        objc_setAssociatedObject(webView, "smart-web-delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        webView.navigationDelegate = delegate
        webView.load(URLRequest(url: url))
    }
}

private final class ExtractionDelegate: NSObject, WKNavigationDelegate {
    let completion: (Result<String, Error>) -> Void
    var webView: WKWebView?
    init(completion: @escaping (Result<String, Error>) -> Void) { self.completion = completion }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { value, error in
            if let error { self.completion(.failure(error)) }
            else { self.completion(.success(value as? String ?? "")) }
            self.webView = nil
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completion(.failure(error))
        self.webView = nil
    }
}
