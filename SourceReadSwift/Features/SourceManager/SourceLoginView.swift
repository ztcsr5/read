import SwiftUI
import Foundation
import WebKit

/// Native login/verification surface for sources that cannot be exercised by URLSession alone.
/// Cookies are copied into the same actor used by the Legado engine when navigation finishes.
struct SourceLoginView: View {
    @Environment(\.dismiss) private var dismiss
    let source: BookSource
    let cookieStore: SourceCookieStore
    @State private var status = "正在打开登录页…"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open")
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))

                if let url = loginURL {
                    SourceLoginWebView(url: url, cookieStore: cookieStore) { message in
                        status = message
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text("登录地址无效")
                            .font(.headline)
                        Text("请在书源 JSON 中检查 loginUrl。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(source.bookSourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var loginURL: URL? {
        guard let text = source.loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}

private struct SourceLoginWebView: UIViewRepresentable {
    let url: URL
    let cookieStore: SourceCookieStore
    let onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(cookieStore: cookieStore, onStatus: onStatus)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let cookieStore: SourceCookieStore
        let onStatus: (String) -> Void

        init(cookieStore: SourceCookieStore, onStatus: @escaping (String) -> Void) {
            self.cookieStore = cookieStore
            self.onStatus = onStatus
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onStatus("正在加载…")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onStatus("页面已加载，Cookie 已同步")
            Task { @MainActor in
                let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        continuation.resume(returning: cookies)
                    }
                }
                await cookieStore.storeWebViewCookies(cookies)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onStatus("页面加载失败：\(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onStatus("页面加载失败：\(error.localizedDescription)")
        }
    }
}
