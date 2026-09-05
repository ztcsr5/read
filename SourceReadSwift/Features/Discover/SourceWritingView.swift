import SwiftUI
import Network
import Foundation
import UIKit
#if canImport(Darwin)
import Darwin
#endif

struct SourceWritingView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var server: LightweightHTTPServer
    @State private var importStatus: String?
    @State private var importError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "globe")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(server.isRunning ? .green : .secondary)
                        
                        Text("Web 写源服务")
                            .font(.title2.bold())
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { server.isRunning || server.isStarting },
                            set: { newValue in
                                if newValue {
                                    server.start()
                                } else {
                                    server.stop()
                                }
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                        .labelsHidden()
                    }
                    
                    Text(server.isRunning ? "服务已启动，请在电脑浏览器中访问下方地址进行书源录入：" : "服务已停止。开启服务后，可在局域网内的电脑上直接编辑并推送书源规则。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if server.isRunning {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(server.localURLs, id: \.self) { url in
                                Text(url)
                                    .font(.system(.callout, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppTheme.accent)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 8)

                        Button {
                            UIPasteboard.general.string = server.localURLs.joined(separator: "\n")
                        } label: {
                            Label("Copy server address", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            UIPasteboard.general.string = server.healthURLs.joined(separator: "\n")
                        } label: {
                            Label("复制健康检查地址", systemImage: "stethoscope")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Text("PC 无法打开时，先访问任一 /health 地址；返回 SOURCE_READ_SWIFT_WEB_OK 即表示局域网连通。请确认手机允许‘本地网络’权限，且路由器未开启 AP 隔离。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let lastError = server.lastError {
                        Text(lastError)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                
                // Status notifications
                if let importStatus {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(importStatus)
                            .font(.subheadline)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                if let importError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(importError)
                            .font(.subheadline)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Log Messages
                VStack(alignment: .leading, spacing: 14) {
                    Text("运行日志")
                        .font(.headline)
                    
                    if server.logMessages.isEmpty {
                        Text("暂无日志")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                            .background(Color(.secondarySystemBackground).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(server.logMessages, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            UIPasteboard.general.string = server.logMessages.joined(separator: "\n")
                        } label: {
                            Label("Copy logs", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // Instructions
                VStack(alignment: .leading, spacing: 14) {
                    Text("使用说明")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Label("确保手机和电脑连接在同一个 Wi-Fi 网络（局域网）下。", systemImage: "wifi")
                        Label("打开电脑浏览器，在地址栏输入上方显示的 IP 地址和端口号。", systemImage: "macbook.and.iphone")
                        Label("在网页中粘贴您的 JSON 规则，然后点击“立即导入到手机”即可自动同步并保存。", systemImage: "square.and.arrow.down")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(AppTheme.pagePadding)
        }
        .pageBackground()
        .navigationTitle("Web 写源")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            server.onJSONReceived = { jsonText in
                do {
                    let report = try appState.sourceStore.importJSON(jsonText)
                    let msg = "成功导入书源：\(report.userMessage)"
                    DispatchQueue.main.async {
                        self.importStatus = msg
                        self.importError = nil
                        // auto clear after 5s
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            if self.importStatus == msg {
                                self.importStatus = nil
                            }
                        }
                    }
                    return .success(msg)
                } catch {
                    let errMsg = error.localizedDescription
                    DispatchQueue.main.async {
                        self.importError = "导入失败：\(errMsg)"
                        self.importStatus = nil
                    }
                    return .failure(error)
                }
            }
            // Keep the web API backed by the same in-memory source store.
            server.sourceStore = appState.sourceStore
            // Auto start server
            server.start()
        }
    }
}

// MARK: - HTTP Server Implementation

final class LightweightHTTPServer: ObservableObject {
    @Published var isRunning = false
    @Published var isStarting = false
    @Published var port: UInt16 = 8080
    @Published var localIP: String = "127.0.0.1"
    @Published var localURLs: [String] = []
    var healthURLs: [String] {
        localURLs.map { $0 + "/health" }
    }
    @Published var lastError: String?
    @Published var logMessages: [String] = []

    /// Main-actor store reference used by the LAN editor API.
    var sourceStore: SourceStore?

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let lockQueue = DispatchQueue(label: "com.sourceread.server.lock")
    var onJSONReceived: ((String) -> Result<String, Error>)?
    
    init(sourceStore: SourceStore? = nil) {
        self.sourceStore = sourceStore
        self.localIP = getLocalIPAddresses().first ?? "127.0.0.1"
    }
    
    func start() {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        lastError = nil
        localIP = getLocalIPAddresses().first ?? "127.0.0.1"
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        let candidates = [port] + (1122...1132).map(UInt16.init).filter { $0 != port }
        var lastStartError: Error?
        for candidate in candidates {
            do {
                listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: candidate) ?? 8080)
                port = candidate
                lastStartError = nil
                break
            } catch {
                lastStartError = error
                listener = nil
            }
        }

        guard listener != nil else {
            isStarting = false
            lastError = "无法创建 Listener：\(lastStartError?.localizedDescription ?? "端口不可用")"
            log(lastError ?? "无法创建 Listener")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.isStarting = false
                    self.isRunning = true
                    self.localIP = getLocalIPAddresses().first ?? self.localIP
                    self.localURLs = self.webURLs()
                    self.log("服务器启动成功，正在监听端口 \(self.port)...")
                case .failed(let error):
                    self.isStarting = false
                    self.lastError = "服务器启动失败：\(error.localizedDescription)"
                    self.log(self.lastError ?? "服务器启动失败")
                    self.stop()
                case .cancelled:
                    self.isStarting = false
                    self.isRunning = false
                    self.localURLs = []
                    self.log("服务器已停止")
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: DispatchQueue.global(qos: .userInitiated))
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        lockQueue.async { [weak self] in
            guard let self = self else { return }
            for connection in self.connections {
                connection.cancel()
            }
            self.connections.removeAll()
        }
        isRunning = false
        isStarting = false
        localURLs = []
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        lockQueue.async { [weak self] in
            self?.connections.append(connection)
        }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.lockQueue.async {
                    if let index = self?.connections.firstIndex(where: { $0 === connection }) {
                        self?.connections.remove(at: index)
                    }
                }
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .default))
        receiveRequest(on: connection, accumulated: Data())
    }
    
    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                self.log("连接接收错误: \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                } else {
                    self.receiveRequest(on: connection, accumulated: accumulated)
                }
                return
            }

            var buffer = accumulated
            buffer.append(data)
            if buffer.count > LightweightHTTPParser.maximumHeaderBytes + LightweightHTTPParser.maximumBodyBytes {
                self.sendResponse(connection: connection, statusCode: 413, statusText: "Payload Too Large", contentType: "text/plain; charset=utf-8", body: "Payload too large")
                return
            }
            switch LightweightHTTPParser.parse(buffer) {
            case .incomplete:
                self.receiveRequest(on: connection, accumulated: buffer)
            case .complete(let request):
                self.handleHttpRequest(request, connection: connection)
            case .failure(let statusCode, let message):
                self.sendResponse(connection: connection, statusCode: statusCode, statusText: Self.statusText(for: statusCode), contentType: "text/plain; charset=utf-8", body: message)
            }
        }
    }

    private static func statusText(for statusCode: Int) -> String {
        switch statusCode {
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 413: return "Payload Too Large"
        case 431: return "Request Header Fields Too Large"
        case 501: return "Not Implemented"
        default: return "Error"
        }
    }
    
    private func handleHttpRequest(_ request: LightweightHTTPRequest, connection: NWConnection) {
        let method = request.method
        // Browsers append cache-busting query items and routinely probe for
        // `/favicon.ico`. Route on the URL path only so `/api/status?ts=...`
        // remains compatible with the same lightweight server.
        let path = request.path
        
        if method == "OPTIONS" {
            sendResponse(connection: connection, statusCode: 204, statusText: "No Content", contentType: "text/plain; charset=utf-8", body: "")
        } else if method == "GET" && (path == "/" || path == "/index.html") {
            let html = getWebPageHtml()
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "text/html; charset=utf-8", body: html)
        } else if (method == "GET" || method == "HEAD") && path == "/health" {
            let healthBody = "SOURCE_READ_SWIFT_WEB_OK\nREAD_SOURCE_WEB_OK port=\(port)"
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "text/plain; charset=utf-8", body: healthBody, includeBody: method != "HEAD")
        } else if (method == "GET" || method == "HEAD") && path == "/favicon.ico" {
            sendResponse(connection: connection, statusCode: 204, statusText: "No Content", contentType: "image/x-icon", body: "", includeBody: false)
        } else if method == "GET" && path == "/api/status" {
            respondWithSourceStore(connection: connection) { store in
                let body = #"{"ok":true,"service":"source-writing","port":\#(self.port),"sourceCount":\#(store?.sources.count ?? 0),"enabledSourceCount":\#(store?.sources.filter(\.enabled).count ?? 0)}"#
                self.sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json; charset=utf-8", body: body)
            }
        } else if method == "GET" && path == "/api/sources" {
            respondWithSourceStore(connection: connection) { store in
                let sources = store?.sources ?? []
                self.sendJSON(connection: connection, value: WebSourceListResponse(
                    ok: true,
                    total: sources.count,
                    enabledCount: sources.filter(\.enabled).count,
                    data: sources
                ))
            }
        } else if method == "GET" && path == "/api/sources/export" {
            respondWithSourceStore(connection: connection) { store in
                let snapshot = store?.backupSnapshot() ?? SourceLibrarySnapshot()
                self.sendJSON(connection: connection, value: snapshot)
            }
        } else if method == "POST" && (path == "/api/sources/import" || path == "/import") {
            guard let body = String(data: request.body, encoding: .utf8) else {
                sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json; charset=utf-8", body: #"{"ok":false,"error":"Request body must be UTF-8 JSON"}"#)
                return
            }
            importSourceJSON(body.trimmingCharacters(in: .whitespacesAndNewlines), connection: connection)
        } else {
            sendResponse(connection: connection, statusCode: 404, statusText: "Not Found", contentType: "text/plain; charset=utf-8", body: "Not Found")
        }
    }
    
    private func importSourceJSON(_ text: String, connection: NWConnection? = nil) {
        guard let onJSONReceived else {
            if let connection { sendResponse(connection: connection, statusCode: 500, statusText: "Internal Error", contentType: "text/plain; charset=utf-8", body: "No import handler registered") }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let result = onJSONReceived(text)
            guard let connection else { return }
            switch result {
            case .success(let message):
                self.log("导入成功：\(message)")
                self.sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json; charset=utf-8", body: #"{"ok":true,"message":"\#(self.jsonEscape(message))"}"#)
            case .failure(let error):
                self.log("导入失败：\(error.localizedDescription)")
                self.sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json; charset=utf-8", body: #"{"ok":false,"error":"\#(self.jsonEscape(error.localizedDescription))"}"#)
            }
        }
    }

    private func respondWithSourceStore(connection: NWConnection, _ body: @escaping @MainActor (SourceStore?) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            body(self.sourceStore)
        }
    }

    private func sendJSON<T: Encodable>(connection: NWConnection, value: T) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json; charset=utf-8", body: String(decoding: data, as: UTF8.self))
        } catch {
            sendResponse(connection: connection, statusCode: 500, statusText: "Internal Error", contentType: "application/json; charset=utf-8", body: #"{"ok":false,"error":"encoding failed"}"#)
        }
    }

    private func jsonEscape(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode(text),
              let encoded = String(data: data, encoding: .utf8) else { return "" }
        return String(encoded.dropFirst().dropLast())
    }

    private func sendResponse(
        connection: NWConnection,
        statusCode: Int,
        statusText: String,
        contentType: String,
        body: String,
        includeBody: Bool = true
    ) {
        let responseBodyData = body.data(using: .utf8) ?? Data()
        let responseHeader = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(responseBodyData.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, HEAD, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Access-Control-Max-Age: 600\r
        Connection: close\r
        \r
        """
        
        var responseData = responseHeader.data(using: .utf8) ?? Data()
        if includeBody {
            responseData.append(responseBodyData)
        }
        
        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.log("发送响应错误: \(error)")
            }
            connection.cancel()
        })
    }
    
    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: Date())
        DispatchQueue.main.async {
            self.logMessages.insert("[\(timeStr)] \(message)", at: 0)
            if self.logMessages.count > 80 {
                self.logMessages.removeLast(self.logMessages.count - 80)
            }
        }
    }

    private func webURLs() -> [String] {
        var seen = Set<String>()
        var urls: [String] = []
        for ip in getLocalIPAddresses() + [localIP, "127.0.0.1"] {
            guard !ip.isEmpty, seen.insert(ip).inserted else { continue }
            urls.append("http://\(ip):\(port)")
        }
        return urls
    }

    private func getWebPageHtml() -> String {
        return stableWebPageHtml()
    }

    private func stableWebPageHtml() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>SourceRead Web Source Import</title>
            <style>
                :root {
                    --primary: #5c50ec;
                    --bg: #f5f5f8;
                    --card: rgba(255,255,255,.84);
                    --text: #16161d;
                    --muted: #6f6f7a;
                    --border: rgba(92,80,236,.18);
                }
                body {
                    min-height: 100vh;
                    margin: 0;
                    padding: 24px;
                    box-sizing: border-box;
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
                    background:
                        radial-gradient(circle at top left, rgba(92,80,236,.20), transparent 32rem),
                        radial-gradient(circle at bottom right, rgba(88,186,255,.18), transparent 30rem),
                        var(--bg);
                    color: var(--text);
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                .container {
                    max-width: 720px;
                    width: 100%;
                    padding: 28px;
                    box-sizing: border-box;
                    border-radius: 28px;
                    background: var(--card);
                    border: 1px solid rgba(255,255,255,.62);
                    box-shadow: 0 28px 80px rgba(20,20,40,.12);
                    backdrop-filter: blur(28px) saturate(1.45);
                    -webkit-backdrop-filter: blur(28px) saturate(1.45);
                }
                h1 {
                    margin: 0 0 8px;
                    font-size: 28px;
                    line-height: 1.15;
                    letter-spacing: -.6px;
                }
                .subtitle {
                    margin: 0 0 22px;
                    color: var(--muted);
                    font-size: 14px;
                    line-height: 1.65;
                }
                .pill {
                    display: inline-flex;
                    margin-bottom: 14px;
                    padding: 7px 11px;
                    border-radius: 999px;
                    background: rgba(92,80,236,.10);
                    color: var(--primary);
                    font-size: 12px;
                    font-weight: 700;
                }
                .actions {
                    display: grid;
                    grid-template-columns: 1fr 1fr;
                    gap: 10px;
                    margin-top: 12px;
                }
                .actions button {
                    margin-top: 0;
                    padding: 12px 14px;
                    font-size: 13px;
                    background: rgba(92,80,236,.10);
                    color: var(--primary);
                    box-shadow: none;
                }
                .status {
                    margin: 14px 0 0;
                    padding: 11px 13px;
                    border-radius: 14px;
                    background: rgba(92,80,236,.07);
                    color: var(--muted);
                    font-size: 12px;
                    line-height: 1.5;
                    white-space: pre-wrap;
                }
                textarea {
                    width: 100%;
                    min-height: 330px;
                    padding: 18px;
                    border: 1px solid var(--border);
                    border-radius: 20px;
                    font-family: Menlo, Monaco, Consolas, "Courier New", monospace;
                    font-size: 13px;
                    line-height: 1.55;
                    box-sizing: border-box;
                    resize: vertical;
                    background: rgba(255,255,255,.74);
                    color: var(--text);
                }
                textarea:focus {
                    outline: none;
                    border-color: var(--primary);
                    box-shadow: 0 0 0 4px rgba(92,80,236,.12);
                }
                button {
                    width: 100%;
                    margin-top: 18px;
                    padding: 16px 18px;
                    border: 0;
                    border-radius: 18px;
                    background-color: var(--primary);
                    color: white;
                    font-size: 15px;
                    font-weight: 800;
                    cursor: pointer;
                    box-shadow: 0 14px 30px rgba(92,80,236,.24);
                    transition: transform .16s ease, opacity .16s ease;
                }
                button:active { transform: scale(.985); }
                button:disabled { opacity: .55; cursor: wait; }
                .toast {
                    position: fixed;
                    top: -100px;
                    left: 50%;
                    transform: translateX(-50%);
                    padding: 16px 24px;
                    border-radius: 16px;
                    color: white;
                    font-weight: 700;
                    box-shadow: 0 10px 30px rgba(0,0,0,.15);
                    transition: all .35s cubic-bezier(.2,.8,.2,1);
                    z-index: 1000;
                    text-align: center;
                    min-width: 300px;
                }
                .toast.success { background-color: #10b981; }
                .toast.error { background-color: #ef4444; }
                .toast.show { top: 24px; }
                .footer { margin-top: 16px; color: var(--muted); font-size: 12px; text-align: center; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="pill">LAN source writer</div>
                <h1>Web Source Import</h1>
                <p class="subtitle">Paste Legado 3.0 JSON, iOS-compatible JSON, or a JSON source array. The content will be imported into the iPhone app.</p>
                <textarea id="json-input" placeholder='Paste JSON book source here, for example:
        [
          {
            "bookSourceName": "Example",
            "bookSourceUrl": "https://example.invalid",
            "searchUrl": "https://example.invalid/search?q={{key}}"
          }
        ]'></textarea>
                <button id="import-btn" onclick="performImport()">Import to iPhone</button>
                <div class="actions">
                    <button onclick="refreshStatus()">Refresh status</button>
                    <button onclick="exportSources()">Export sources</button>
                </div>
                <div id="status" class="status">Status not loaded yet.</div>
                <div class="footer">Keep this page and the iPhone on the same Wi-Fi. API: <code>/api/status</code> · <code>/api/sources</code> · <code>/api/sources/export</code></div>
            </div>
            <div id="toast" class="toast"></div>
            <script>
                function showToast(message, isSuccess) {
                    const toast = document.getElementById('toast');
                    toast.textContent = message;
                    toast.className = 'toast ' + (isSuccess ? 'success' : 'error') + ' show';
                    setTimeout(() => toast.classList.remove('show'), 4000);
                }

                function setStatus(message) {
                    document.getElementById('status').textContent = message;
                }

                async function refreshStatus() {
                    setStatus('Loading source status...');
                    try {
                        const response = await fetch('/api/status', { cache: 'no-store' });
                        const payload = await response.json();
                        if (!response.ok || !payload.ok) throw new Error(payload.error || ('HTTP ' + response.status));
                        setStatus('Online · port ' + payload.port + '\\nSources: ' + payload.sourceCount + ' total · ' + payload.enabledSourceCount + ' enabled');
                    } catch (error) {
                        setStatus('Status unavailable: ' + error);
                    }
                }

                async function exportSources() {
                    try {
                        const response = await fetch('/api/sources/export', { cache: 'no-store' });
                        if (!response.ok) throw new Error('HTTP ' + response.status);
                        const blob = await response.blob();
                        const anchor = document.createElement('a');
                        anchor.href = URL.createObjectURL(blob);
                        anchor.download = 'sourceread-sources-' + new Date().toISOString().slice(0, 10) + '.json';
                        anchor.click();
                        URL.revokeObjectURL(anchor.href);
                        showToast('Sources exported.', true);
                    } catch (error) {
                        showToast('Export failed: ' + error, false);
                    }
                }

                function performImport() {
                    const text = document.getElementById('json-input').value.trim();
                    if (!text) {
                        showToast('Please paste JSON source content.', false);
                        return;
                    }
                    const btn = document.getElementById('import-btn');
                    btn.disabled = true;
                    btn.textContent = 'Importing...';
                    fetch('/api/sources/import', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: text
                    })
                    .then(async res => {
                        const responseText = await res.text();
                        let payload;
                        try { payload = JSON.parse(responseText); } catch (_) { payload = null; }
                        if (res.ok && (!payload || payload.ok !== false)) {
                            showToast(payload && payload.message ? payload.message : responseText, true);
                            document.getElementById('json-input').value = '';
                        } else {
                            showToast('Import failed: ' + (payload && payload.error ? payload.error : responseText), false);
                        }
                    })
                    .catch(err => showToast('Network error: ' + err, false))
                    .finally(() => {
                        btn.disabled = false;
                        btn.textContent = 'Import to iPhone';
                        refreshStatus();
                    });
                }

                refreshStatus();
            </script>
        </body>
        </html>
        """
    }

}

// MARK: - IP Address Helper

private struct WebSourceListResponse: Encodable {
    let ok: Bool
    let total: Int
    let enabledCount: Int
    let data: [BookSource]
}

private func getLocalIPAddresses() -> [String] {
    var wifi: [String] = []
    var others: [String] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return [] }
    guard let firstAddr = ifaddr else { return [] }
    
    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ptr.pointee
        guard let addr = interface.ifa_addr else { continue }
        
        let addrFamily = addr.pointee.sa_family
        if addrFamily == UInt8(AF_INET) {
            let name = String(cString: interface.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, socklen_t(0), NI_NUMERICHOST)
            let ip = String(cString: hostname)
            if ip != "127.0.0.1" {
                if name == "en0" || name.hasPrefix("en") {
                    wifi.append(ip)
                } else {
                    others.append(ip)
                }
            }
        }
    }
    freeifaddrs(ifaddr)
    var seen = Set<String>()
    return (wifi + others).filter { seen.insert($0).inserted }
}
