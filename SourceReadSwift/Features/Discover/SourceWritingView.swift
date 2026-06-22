import SwiftUI
import Network
import Foundation
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
                            get: { server.isRunning },
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
                        Text("http://\(server.localIP):\(server.port)")
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(AppTheme.accent)
                            .padding(.vertical, 8)
                            .textSelection(.enabled)
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
            // Auto start server
            server.start()
        }
    }
}

// MARK: - HTTP Server Implementation

final class LightweightHTTPServer: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 8080
    @Published var localIP: String = "127.0.0.1"
    @Published var logMessages: [String] = []
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let lockQueue = DispatchQueue(label: "com.sourceread.server.lock")
    var onJSONReceived: ((String) -> Result<String, Error>)?
    
    init() {
        self.localIP = getLocalIPAddress() ?? "127.0.0.1"
    }
    
    func start() {
        guard !isRunning else { return }
        do {
            let parameters = NWParameters.tcp
            let listenerPort = NWEndpoint.Port(rawValue: port) ?? 8080
            listener = try NWListener(using: parameters, on: listenerPort)
            
            listener?.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.log("服务器启动成功，正在监听端口 \(self.port)...")
                    case .failed(let error):
                        self.log("服务器启动失败: \(error)")
                        self.stop()
                    case .cancelled:
                        self.isRunning = false
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
        } catch {
            log("无法创建 Listener: \(error)")
        }
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
        receiveRequest(on: connection)
    }
    
    private func receiveRequest(on connection: NWConnection) {
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
                    self.receiveRequest(on: connection)
                }
                return
            }
            
            self.handleHttpRequest(data: data, connection: connection)
        }
    }
    
    private func handleHttpRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "text/plain", body: "Invalid UTF-8 sequence")
            return
        }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "text/plain", body: "Empty Request")
            return
        }
        
        let requestLineParts = lines[0].components(separatedBy: " ")
        guard requestLineParts.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "text/plain", body: "Invalid request line")
            return
        }
        
        let method = requestLineParts[0]
        let path = requestLineParts[1]
        
        if method == "GET" && path == "/" {
            let html = getWebPageHtml()
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "text/html; charset=utf-8", body: html)
        } else if method == "POST" && path == "/import" {
            let parts = requestString.components(separatedBy: "\r\n\r\n")
            let body = parts.dropFirst().joined(separator: "\r\n\r\n")
            let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let onJSONReceived = onJSONReceived {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let result = onJSONReceived(cleanBody)
                    switch result {
                    case .success(let msg):
                        self.log("导入成功：\(msg)")
                        self.sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "text/plain; charset=utf-8", body: msg)
                    case .failure(let err):
                        self.log("导入失败：\(err.localizedDescription)")
                        self.sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "text/plain; charset=utf-8", body: err.localizedDescription)
                    }
                }
            } else {
                sendResponse(connection: connection, statusCode: 500, statusText: "Internal Error", contentType: "text/plain; charset=utf-8", body: "No import handler registered")
            }
        } else {
            sendResponse(connection: connection, statusCode: 404, statusText: "Not Found", contentType: "text/plain; charset=utf-8", body: "Not Found")
        }
    }
    
    private func sendResponse(connection: NWConnection, statusCode: Int, statusText: String, contentType: String, body: String) {
        let responseBodyData = body.data(using: .utf8) ?? Data()
        let responseHeader = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(responseBodyData.count)\r
        Connection: close\r
        \r
        """
        
        var responseData = responseHeader.data(using: .utf8) ?? Data()
        responseData.append(responseBodyData)
        
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
        }
    }
    
    private func getWebPageHtml() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Web 书源导入助手</title>
            <style>
                :root {
                    --primary: #5c50ec;
                    --primary-hover: #4b3fd3;
                    --bg: #f6f6f9;
                    --card: #ffffff;
                    --text: #333333;
                    --text-secondary: #666666;
                    --border: #e2e8f0;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: var(--bg);
                    color: var(--text);
                    margin: 0;
                    padding: 20px;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    min-height: 90vh;
                }
                .container {
                    background: var(--card);
                    padding: 35px;
                    border-radius: 24px;
                    box-shadow: 0 20px 40px rgba(0,0,0,0.06);
                    max-width: 650px;
                    width: 100%;
                    box-sizing: border-box;
                    transition: transform 0.3s;
                }
                h1 {
                    font-size: 26px;
                    color: var(--primary);
                    margin-top: 0;
                    text-align: center;
                    font-weight: 800;
                    letter-spacing: -0.5px;
                }
                p {
                    font-size: 14px;
                    color: var(--text-secondary);
                    line-height: 1.6;
                    margin-bottom: 20px;
                    text-align: center;
                }
                textarea {
                    width: 100%;
                    height: 300px;
                    padding: 18px;
                    border: 2px solid var(--border);
                    border-radius: 16px;
                    font-family: Menlo, Monaco, Consolas, "Courier New", monospace;
                    font-size: 13px;
                    box-sizing: border-box;
                    resize: vertical;
                    background: #fafafa;
                    transition: all 0.3s;
                }
                textarea:focus {
                    outline: none;
                    border-color: var(--primary);
                    background: #ffffff;
                    box-shadow: 0 0 0 4px rgba(92, 80, 236, 0.12);
                }
                button {
                    background-color: var(--primary);
                    color: white;
                    border: none;
                    padding: 16px 20px;
                    font-size: 16px;
                    font-weight: bold;
                    border-radius: 16px;
                    width: 100%;
                    cursor: pointer;
                    margin-top: 20px;
                    transition: all 0.2s;
                    box-shadow: 0 4px 12px rgba(92, 80, 236, 0.2);
                }
                button:hover {
                    background-color: var(--primary-hover);
                    transform: translateY(-2px);
                    box-shadow: 0 6px 20px rgba(92, 80, 236, 0.3);
                }
                button:active {
                    transform: translateY(0);
                }
                .footer {
                    margin-top: 25px;
                    font-size: 12px;
                    color: #999;
                    text-align: center;
                }
                .toast {
                    position: fixed;
                    top: -100px;
                    left: 50%;
                    transform: translateX(-50%);
                    padding: 16px 24px;
                    border-radius: 16px;
                    color: white;
                    font-weight: 600;
                    box-shadow: 0 10px 30px rgba(0,0,0,0.15);
                    transition: all 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
                    z-index: 1000;
                    text-align: center;
                    min-width: 300px;
                }
                .toast.success {
                    background-color: #10b981;
                }
                .toast.error {
                    background-color: #ef4444;
                }
                .toast.show {
                    top: 24px;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Web 书源导入助手</h1>
                <p>粘贴您的 JSON 书源规则或规则数组，点击下方按钮立即同步到手机中。</p>
                <textarea id="json-input" placeholder='请在此处输入 JSON 书源，支持单个书源或书源数组，例如：&#10;[&#10;  {&#10;    "bookSourceName": "我的精选书源",&#10;    "bookSourceUrl": "http://example.com"&#10;  }&#10;]'></textarea>
                <button id="import-btn" onclick="performImport()">立即导入到手机</button>
            </div>
            <div class="footer">SourceReadSwift Web Sync Center</div>
            
            <div id="toast" class="toast"></div>

            <script>
                function showToast(message, isSuccess) {
                    const toast = document.getElementById('toast');
                    toast.textContent = message;
                    toast.className = 'toast ' + (isSuccess ? 'success' : 'error') + ' show';
                    setTimeout(() => {
                        toast.classList.remove('show');
                    }, 4000);
                }

                function performImport() {
                    const text = document.getElementById('json-input').value.trim();
                    if (!text) {
                        showToast('请输入 JSON 书源内容', false);
                        return;
                    }
                    
                    const btn = document.getElementById('import-btn');
                    btn.disabled = true;
                    btn.textContent = '正在导入...';
                    
                    fetch('/import', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json'
                        },
                        body: text
                    })
                    .then(async res => {
                        const responseText = await res.text();
                        if (res.ok) {
                            showToast(responseText, true);
                            document.getElementById('json-input').value = '';
                        } else {
                            showToast('导入失败: ' + responseText, false);
                        }
                    })
                    .catch(err => {
                        showToast('网络连接失败: ' + err, false);
                    })
                    .finally(() => {
                        btn.disabled = false;
                        btn.textContent = '立即导入到手机';
                    });
                }
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - IP Address Helper

private func getLocalIPAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return nil }
    guard let firstAddr = ifaddr else { return nil }
    
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
                address = ip
                if name == "en0" { // Wi-Fi is preferred
                    freeifaddrs(ifaddr)
                    return ip
                }
            }
        }
    }
    freeifaddrs(ifaddr)
    return address
}
