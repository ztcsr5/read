import Foundation
import WebKit

@MainActor
final class WebViewFallback: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Result<String, SourceEngineError>, Never>?
    private var webView: WKWebView?
    private let cookieStore: SourceCookieStore?

    init(cookieStore: SourceCookieStore? = nil) {
        self.cookieStore = cookieStore
    }

    func load(url: URL, delay: TimeInterval = 3) async -> Result<String, SourceEngineError> {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let configuration = WKWebViewConfiguration()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            self.webView = webView
            webView.load(URLRequest(url: url))

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
                await self.syncCookies(from: webView)
                self.finish(.success(html ?? ""))
            }
        }
    }

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
        continuation?.resume(returning: result)
        continuation = nil
        webView = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(.network(error.localizedDescription)))
    }
}
