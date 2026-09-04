import Foundation
import CoreFoundation
import CryptoSwift
import ZIPFoundation
import CommonCrypto
import Compression

/// Native services required by Legado JavaScript sources.  All filesystem access is
/// constrained to the app container; relative paths live under Documents/LegadoSandbox.
final class LegadoHostServices {
    private let executionContext: RuleExecutionContext
    private let fileManager: FileManager
    let sandboxURL: URL

    init(executionContext: RuleExecutionContext, fileManager: FileManager = .default) {
        self.executionContext = executionContext
        self.fileManager = fileManager
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.sandboxURL = documents.appendingPathComponent("LegadoSandbox", isDirectory: true)
        try? fileManager.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
    }

    // MARK: - Cookie

    func cookie(url rawURL: String, key: String?) -> String {
        guard let url = URL(string: rawURL),
              let cookies = HTTPCookieStorage.shared.cookies(for: url) else {
            return executionContext.string(for: "cookieHeader")
        }
        if let key, !key.isEmpty {
            return cookies.first(where: { $0.name == key })?.value ?? ""
        }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? ""
    }

    @discardableResult
    func setCookie(url rawURL: String, value: String) -> String {
        executionContext.setValue(value, for: "cookieHeader")
        guard let url = URL(string: rawURL), !value.isEmpty else { return value }
        let headerFields = ["Set-Cookie": value]
        HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
            .forEach(HTTPCookieStorage.shared.setCookie)
        return value
    }

    // MARK: - Text/encoding

    func encodeURI(_ value: String, charset: String? = nil) -> String {
        let normalized = charset?.lowercased() ?? "utf-8"
        if normalized.contains("gbk") || normalized.contains("gb2312") || normalized.contains("gb18030") {
            let encoding = Self.gbkEncoding
            guard let data = value.data(using: encoding) else { return value }
            return data.map { byte in
                let scalar = UnicodeScalar(byte)
                if CharacterSet.alphanumerics.contains(scalar) || "-._~".utf8.contains(byte) {
                    return String(UnicodeScalar(byte))
                }
                return String(format: "%%%02X", byte)
            }.joined()
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func utf8ToGbk(_ value: String) -> NSArray {
        guard let data = value.data(using: Self.gbkEncoding) else { return [] }
        return data.map { NSNumber(value: $0) } as NSArray
    }

    func decodeText(_ data: Data, charset: String?) -> String {
        let name = charset?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let encoding: String.Encoding
        if name.contains("gbk") || name.contains("gb2312") || name.contains("gb18030") {
            encoding = Self.gbkEncoding
        } else if name.contains("utf-16") {
            encoding = .utf16
        } else if name.contains("big5") {
            encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        } else {
            encoding = .utf8
        }
        return String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .utf8)
            ?? ""
    }

    func htmlFormat(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    // MARK: - AES

    func aes(
        operation: String,
        input: Any?,
        key: Any?,
        transformation: String,
        iv: Any?
    ) -> Any {
        do {
            let keyBytes = bytes(from: key)
            let ivBytes = bytes(from: iv)
            let mode: BlockMode = transformation.uppercased().contains("ECB")
                ? ECB()
                : CBC(iv: normalizedIV(ivBytes))
            let padding: Padding = transformation.uppercased().contains("NOPADDING") ? .noPadding : .pkcs7
            let cipher = try AES(key: normalizedKey(keyBytes), blockMode: mode, padding: padding)
            let isDecode = operation.localizedCaseInsensitiveContains("decode")
            var payload = bytes(from: input)
            if operation.localizedCaseInsensitiveContains("base64decode"),
               let decoded = Data(base64Encoded: Self.normalizedBase64(RuleExecutionContext.bridgeString(input))) {
                payload = Array(decoded)
            }
            let output = try isDecode ? cipher.decrypt(payload) : cipher.encrypt(payload)
            if operation.localizedCaseInsensitiveContains("base64") && !isDecode {
                let encoded = Data(output).base64EncodedString()
                if operation.localizedCaseInsensitiveContains("bytearray") {
                    return Array(encoded.utf8).map { NSNumber(value: $0) } as NSArray
                }
                return encoded
            }
            if operation.localizedCaseInsensitiveContains("bytearray") {
                return output.map { NSNumber(value: $0) } as NSArray
            }
            return String(data: Data(output), encoding: .utf8) ?? Data(output).base64EncodedString()
        } catch {
            executionContext.log("AES failed: \(error.localizedDescription)")
            return operation.localizedCaseInsensitiveContains("bytearray") ? ([] as NSArray) : ""
        }
    }

    /// Generic raw-byte cipher bridge used by CryptoJS WordArray shims and by
    /// Javax.Cipher-compatible source snippets.  Keeping this separate from
    /// the legacy string helpers preserves their historical return semantics
    /// while allowing binary ciphertext to round-trip without UTF-8 loss.
    func cipher(
        operation: String,
        input: Any?,
        key: Any?,
        transformation: String,
        iv: Any?
    ) -> NSArray {
        let upper = transformation.uppercased()
        let isDecrypt = operation.localizedCaseInsensitiveContains("decrypt") ||
            operation.localizedCaseInsensitiveContains("decode")
        let kind: String = upper.contains("DESEDE") || upper.contains("TRIPLEDES") ? "3DES" :
            (upper.contains("DES") ? "DES" : "AES")
        let mode = upper.contains("/ECB") || upper.contains("ECB/") ? "ECB" : "CBC"
        let padding: String = upper.contains("NOPADDING") ? "NoPadding" :
            (upper.contains("ZEROPADDING") ? "ZeroPadding" : "PKCS7")
        var payload = bytes(from: input)
        var keyBytes = bytes(from: key)
        var ivBytes = bytes(from: iv)
        do {
            let output: [UInt8]
            if kind == "AES" {
                let blockSize = 16
                keyBytes = normalizedKey(keyBytes)
                ivBytes = Array((ivBytes + Array(repeating: 0, count: blockSize)).prefix(blockSize))
                let blockMode: BlockMode = mode == "ECB" ? ECB() : CBC(iv: ivBytes)
                let paddingMode: Padding = padding == "NoPadding" ? .noPadding :
                    (padding == "ZeroPadding" ? .zeroPadding : .pkcs7)
                let aes = try AES(key: keyBytes, blockMode: blockMode, padding: paddingMode)
                output = try isDecrypt ? aes.decrypt(payload) : aes.encrypt(payload)
            } else {
                output = try commonCrypto(
                    payload: payload,
                    key: keyBytes,
                    iv: ivBytes,
                    algorithm: kind == "3DES" ? CCAlgorithm(kCCAlgorithm3DES) : CCAlgorithm(kCCAlgorithmDES),
                    mode: mode,
                    padding: padding,
                    decrypt: isDecrypt
                )
            }
            return output.map { NSNumber(value: $0) } as NSArray
        } catch {
            executionContext.log("\(kind) cipher failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Inflate a zlib-wrapped byte stream for java.util.zip.InflaterInputStream.
    /// Compression is available on every supported iOS release and avoids
    /// pulling a second native zlib package into the app.
    func inflate(_ value: Any?) -> NSArray {
        let input = bytes(from: value)
        guard !input.isEmpty else { return [] }
        // Compression.framework accepts the zlib-wrapped payload used by
        // Legado.  A few sources incorrectly strip or retain the wrapper, so
        // try both representations before reporting a decode miss.
        var candidates = [input]
        if input.count > 6, input[0] == 0x78 {
            candidates.append(Array(input.dropFirst(2).dropLast(4)))
        }
        for candidate in candidates where !candidate.isEmpty {
            // The one-shot API can report 0 for a valid stream when the
            // destination buffer is not large enough.  The streaming API
            // gives us the exact status and lets us grow the destination
            // without guessing the uncompressed size.
            if let output = inflateCandidate(candidate) {
                return output.map { NSNumber(value: $0) } as NSArray
            }
            // Keep a one-shot fallback for older Compression implementations
            // which do not expose a useful stream status for tiny payloads.
            var capacity = max(1024, candidate.count * 4)
            for _ in 0..<8 {
                var output = Array(repeating: UInt8(0), count: capacity)
                let decoded = candidate.withUnsafeBytes { source in
                    output.withUnsafeMutableBytes { destination in
                        compression_decode_buffer(
                            destination.bindMemory(to: UInt8.self).baseAddress!,
                            capacity,
                            source.bindMemory(to: UInt8.self).baseAddress!,
                            candidate.count,
                            nil,
                            COMPRESSION_ZLIB
                        )
                    }
                }
                if decoded > 0 {
                    output.removeLast(output.count - decoded)
                    return output.map { NSNumber(value: $0) } as NSArray
                }
                capacity *= 2
            }
        }
        executionContext.log("InflaterInputStream failed to decode payload")
        return []
    }

    private func inflateCandidate(_ candidate: [UInt8]) -> [UInt8]? {
        guard !candidate.isEmpty else { return nil }
        var stream = compression_stream()
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(&stream) }

        var output: [UInt8] = []
        var destination = Array(repeating: UInt8(0), count: max(4096, candidate.count * 4))
        var source = candidate
        return source.withUnsafeMutableBytes { sourceBuffer in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.src_ptr = sourcePointer
            stream.src_size = source.count
            var iterations = 0
            while iterations < 256 {
                iterations += 1
                let status = destination.withUnsafeMutableBytes { destinationBuffer -> compression_status in
                    stream.dst_ptr = destinationBuffer.bindMemory(to: UInt8.self).baseAddress!
                    stream.dst_size = destinationBuffer.count
                    return compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE))
                }
                let produced = destination.count - stream.dst_size
                if produced > 0 {
                    output.append(contentsOf: destination.prefix(produced))
                }
                if status == COMPRESSION_STATUS_END { return output }
                if status == COMPRESSION_STATUS_ERROR { return nil }
                if stream.src_size == 0 && produced == 0 { return nil }
                if produced == destination.count {
                    let nextCount = min(destination.count * 2, 16 * 1024 * 1024)
                    if nextCount == destination.count { return nil }
                    destination = Array(repeating: UInt8(0), count: nextCount)
                }
            }
            return nil
        }
    }

    // MARK: - Files and ZIP

    func readFile(_ path: String) -> NSArray {
        guard let url = resolvedURL(path), let data = try? Data(contentsOf: url) else { return [] }
        return data.map { NSNumber(value: $0) } as NSArray
    }

    func readText(_ path: String, charset: String? = nil) -> String {
        guard let url = resolvedURL(path), let data = try? Data(contentsOf: url) else { return "" }
        return decodeText(data, charset: charset)
    }

    /// Legado's cacheFile is a small persistent file cache, not just an in-memory
    /// variable. Keep it inside the per-app sandbox so sources can share helper
    /// data without escaping the application container.
    @discardableResult
    func cacheFile(_ path: String, content: String) -> String {
        guard let url = resolvedURL(path, createParent: true) else { return "" }
        do {
            try Data(content.utf8).write(to: url, options: .atomic)
            return content
        } catch {
            executionContext.log("cacheFile failed: \(error.localizedDescription)")
            return ""
        }
    }

    @discardableResult
    func deleteFile(_ path: String) -> Bool {
        guard let url = resolvedURL(path) else { return false }
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return true
        } catch {
            executionContext.log("deleteFile failed: \(error.localizedDescription)")
            return false
        }
    }

    func downloadFile(_ rawURL: String, path: String) -> String {
        guard let sourceURL = URL(string: rawURL), let destination = resolvedURL(path, createParent: true) else { return "" }
        let semaphore = DispatchSemaphore(value: 0)
        var output = ""
        URLSession.shared.dataTask(with: sourceURL) { data, _, error in
            defer { semaphore.signal() }
            guard error == nil, let data else { return }
            do {
                try data.write(to: destination, options: .atomic)
                output = destination.path
            } catch {
                self.executionContext.log("downloadFile failed: \(error.localizedDescription)")
            }
        }.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        return output
    }

    func unzipFile(_ path: String) -> String {
        guard let archiveURL = resolvedURL(path) else { return "" }
        let destination = archiveURL.deletingPathExtension()
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try fileManager.unzipItem(at: archiveURL, to: destination)
            return destination.path
        } catch {
            executionContext.log("unzipFile failed: \(error.localizedDescription)")
            return ""
        }
    }

    func textFiles(in path: String) -> NSArray {
        guard let folder = resolvedURL(path),
              let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        let values = enumerator.compactMap { item -> String? in
            guard let url = item as? URL,
                  ["txt", "text", "html", "htm"].contains(url.pathExtension.lowercased()) else { return nil }
            return url.path
        }.sorted()
        return values as NSArray
    }

    func zipData(zipPath: String, entryName: String) -> Data? {
        guard let url = resolvedURL(zipPath), let archive = Archive(url: url, accessMode: .read),
              let entry = archive[entryName] else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry) { data.append($0) }
            return data
        } catch {
            executionContext.log("ZIP read failed: \(error.localizedDescription)")
            return nil
        }
    }

    func zipString(zipPath: String, entryName: String, charset: String?) -> String {
        guard let data = zipData(zipPath: zipPath, entryName: entryName) else { return "" }
        return decodeText(data, charset: charset)
    }

    private func resolvedURL(_ path: String, createParent: Bool = false) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate: URL
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            candidate = url
        } else if (trimmed as NSString).isAbsolutePath {
            candidate = URL(fileURLWithPath: trimmed)
        } else {
            candidate = sandboxURL.appendingPathComponent(trimmed)
        }
        let standardized = candidate.standardizedFileURL
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        guard standardized.path == home || standardized.path.hasPrefix(home + "/") else { return nil }
        if createParent {
            try? fileManager.createDirectory(at: standardized.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return standardized
    }

    private func bytes(from value: Any?) -> [UInt8] {
        if let data = value as? Data { return Array(data) }
        if let values = value as? [UInt8] { return values }
        if let values = value as? [Int] { return values.map { UInt8(clamping: $0) } }
        if let values = value as? [NSNumber] { return values.map(\.uint8Value) }
        if let values = value as? [Any] {
            return values.compactMap {
                if let number = $0 as? NSNumber { return number.uint8Value }
                if let number = $0 as? Int { return UInt8(clamping: number) }
                if let number = $0 as? UInt8 { return number }
                return nil
            }
        }
        if let values = value as? NSArray { return values.compactMap { ($0 as? NSNumber)?.uint8Value } }
        return Array(RuleExecutionContext.bridgeString(value).utf8)
    }

    private func commonCrypto(
        payload: [UInt8],
        key: [UInt8],
        iv: [UInt8],
        algorithm: CCAlgorithm,
        mode: String,
        padding: String,
        decrypt: Bool
    ) throws -> [UInt8] {
        let blockSize = algorithm == CCAlgorithm(kCCAlgorithm3DES) ? kCCBlockSize3DES : kCCBlockSizeDES
        let keyLength = algorithm == CCAlgorithm(kCCAlgorithm3DES) ? kCCKeySize3DES : kCCKeySizeDES
        var normalizedKeyBytes = Array((key + Array(repeating: 0, count: keyLength)).prefix(keyLength))
        if algorithm == CCAlgorithm(kCCAlgorithm3DES), key.count == 16 {
            normalizedKeyBytes = key + Array(key.prefix(8))
        }
        var input = payload
        if !decrypt && padding == "ZeroPadding" {
            let count = (blockSize - (input.count % blockSize)) % blockSize
            if count > 0 { input += Array(repeating: 0, count: count) }
        }
        var options: CCOptions = 0
        if mode == "ECB" { options |= CCOptions(kCCOptionECBMode) }
        if padding == "PKCS7" { options |= CCOptions(kCCOptionPKCS7Padding) }
        let keyData = Data(normalizedKeyBytes)
        let inputData = Data(input)
        let ivData = Data((iv + Array(repeating: 0, count: blockSize)).prefix(blockSize))
        var output = Array(repeating: UInt8(0), count: input.count + blockSize)
        var moved = 0
        let status: CCCryptorStatus = keyData.withUnsafeBytes { keyBuffer in
            inputData.withUnsafeBytes { inputBuffer in
                ivData.withUnsafeBytes { ivBuffer in
                    output.withUnsafeMutableBytes { outputBuffer in
                        CCCrypt(
                            decrypt ? CCOperation(kCCDecrypt) : CCOperation(kCCEncrypt),
                            algorithm,
                            options,
                            keyBuffer.baseAddress,
                            keyData.count,
                            mode == "ECB" ? nil : ivBuffer.baseAddress,
                            inputBuffer.baseAddress,
                            inputData.count,
                            outputBuffer.baseAddress,
                            outputBuffer.count,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw NSError(domain: "CommonCrypto", code: Int(status)) }
        output.removeLast(output.count - moved)
        if decrypt && padding == "ZeroPadding" {
            while output.last == 0 { output.removeLast() }
        }
        return output
    }

    private func normalizedKey(_ value: [UInt8]) -> [UInt8] {
        let size = value.count <= 16 ? 16 : (value.count <= 24 ? 24 : 32)
        return Array((value + Array(repeating: 0, count: size)).prefix(size))
    }

    private func normalizedIV(_ value: [UInt8]) -> [UInt8] {
        Array((value + Array(repeating: 0, count: 16)).prefix(16))
    }

    private static func normalizedBase64(_ value: String) -> String {
        var text = value
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = text.count % 4
        if remainder != 0 { text += String(repeating: "=", count: 4 - remainder) }
        return text
    }

    private static let gbkEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    )
}
