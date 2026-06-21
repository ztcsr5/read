import Foundation
import CoreFoundation

struct ResponseTextDecoder {
    func decode(data: Data, headers: [String: String]) -> String {
        if let charset = charset(from: headers),
           let text = decode(data: data, charset: charset) {
            return text
        }
        if let charset = sniffCharset(from: data),
           let text = decode(data: data, charset: charset) {
            return text
        }
        return String(data: data, encoding: .utf8)
            ?? decode(data: data, charset: "gb18030")
            ?? decode(data: data, charset: "gbk")
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private func charset(from headers: [String: String]) -> String? {
        let contentType = headers.first { key, _ in
            key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value
        guard let contentType else { return nil }
        let parts = contentType.components(separatedBy: ";")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("charset=") {
                return String(trimmed.dropFirst("charset=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
        }
        return nil
    }

    private func sniffCharset(from data: Data) -> String? {
        let prefix = data.prefix(4096)
        let ascii = String(data: prefix, encoding: .ascii)
            ?? String(data: prefix, encoding: .isoLatin1)
            ?? ""
        let lower = ascii.lowercased()
        guard let range = lower.range(of: "charset") else { return nil }
        let tail = lower[range.upperBound...].prefix(80)
        guard let separator = tail.firstIndex(where: { $0 == "=" || $0 == ":" }) else { return nil }
        let value = tail[tail.index(after: separator)...]
            .drop(while: { $0 == "\"" || $0 == "'" || $0.isWhitespace })
            .prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        return value.isEmpty ? nil : String(value)
    }

    private func decode(data: Data, charset: String) -> String? {
        let normalized = charset.lowercased().replacingOccurrences(of: "-", with: "")
        switch normalized {
        case "utf8":
            return String(data: data, encoding: .utf8)
        case "gb18030", "gbk", "gb2312":
            let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
        case "iso88591", "latin1":
            return String(data: data, encoding: .isoLatin1)
        default:
            return nil
        }
    }
}
