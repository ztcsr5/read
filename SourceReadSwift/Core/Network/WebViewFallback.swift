import Foundation
import WebKit

@MainActor
final class WebViewFallback: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Result<String, SourceEngineError>, Never>?
    private var webView: WKWebView?
    private var delayTask: Task<Void, Never>?
    private var fallbackTimer: Task<Void, Never>?
    private let cookieStore: SourceCookieStore?

    init(cookieStore: SourceCookieStore? = nil) {
        self.cookieStore = cookieStore
    }

    func load(url: URL, delay: TimeInterval = 3) async -> Result<String, SourceEngineError> {
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled {
                    self.finish(.failure(.network("WebView fallback cancelled")))
                    return
                }
                self.navigationDelay = max(0.25, min(delay, 30))
                let configuration = WKWebViewConfiguration()
                let webView = WKWebView(frame: .zero, configuration: configuration)
                webView.navigationDelegate = self
                self.webView = webView
                webView.load(URLRequest(url: url))
                // A navigation delegate is not guaranteed to fire for a
                // malformed challenge page. Keep a bounded fallback timer so
                // diagnostics never hang forever waiting on WebKit.
                self.fallbackTimer = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard let self, !Task.isCancelled else { return }
                    self.finish(.failure(.network("WebView fallback timed out")))
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(.network("WebView fallback cancelled")))
            }
        })
    }

    private var navigationDelay: TimeInterval = 3

    private func syncCookies(from webView: WKWebView) async {
        guard let cookieStore else { return }
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        await cookieStore.storeWebViewCookies(cookies)
    }

    private func finish(_ result: Result<String, SourceEngineError>) {
        delayTask?.cancel()
        delayTask = nil
        fallbackTimer?.cancel()
        fallbackTimer = nil
        webView?.stopLoading()
        continuation?.resume(returning: result)
        continuation = nil
        webView = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        delayTask?.cancel()
        delayTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.navigationDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
            await self.syncCookies(from: webView)
            self.finish(.success(html ?? ""))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(.network(error.localizedDescription)))
    }
}
