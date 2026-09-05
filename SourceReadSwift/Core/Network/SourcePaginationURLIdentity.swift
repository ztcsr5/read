import Foundation

/// Stable identity used for source pagination de-duplication.
///
/// Source rules frequently emit the same page using a different spelling:
/// host/scheme case, a default port, a fragment, dot segments, or a different
/// percent-encoding case. Comparing `URL.absoluteString` directly lets those
/// aliases bypass the pagination guard and can cause a source to loop.
struct SourcePaginationURLIdentity: Sendable, Hashable {
    /// Query ordering is enabled by default because pagination parameters are
    /// commonly emitted by dictionary-backed JavaScript objects. Callers can
    /// disable it for sources where query order is semantically significant.
    let sortQueryItems: Bool

    init(sortQueryItems: Bool = true) {
        self.sortQueryItems = sortQueryItems
    }

    func canonical(_ url: URL) -> String {
        Self.canonical(url, sortQueryItems: sortQueryItems)
    }

    func canonical(_ urlText: String) -> String? {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return canonical(url)
    }

    static func canonical(_ url: URL, sortQueryItems: Bool = true) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return normalizePercentEncoding(url.absoluteString, decodeUnreserved: true)
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? url.absoluteString
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        if let scheme = components.scheme?.lowercased(),
           let port = components.port,
           (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
            components.port = nil
        }

        let encodedPath = components.percentEncodedPath.isEmpty
            ? (components.host == nil ? components.path : "/")
            : components.percentEncodedPath
        components.percentEncodedPath = normalizePath(encodedPath)
        components.percentEncodedQuery = normalizeQuery(components.percentEncodedQuery, sortItems: sortQueryItems)
        // Fragments never identify a server-side page and should not prevent
        // an emitted next URL from matching a previously loaded URL.
        components.fragment = nil

        if let value = components.string {
            return value
        }

        return normalizePercentEncoding(url.absoluteString, decodeUnreserved: true)
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? url.absoluteString
    }

    private static func normalizePath(_ value: String) -> String {
        let normalized = normalizePercentEncoding(value, decodeUnreserved: true)
        let hasLeadingSlash = normalized.hasPrefix("/")
        let hasTrailingSlash = normalized.count > 1 && normalized.hasSuffix("/")
        var stack: [Substring] = []

        for segment in normalized.split(separator: "/", omittingEmptySubsequences: false) {
            switch segment {
            case ".":
                continue
            case "..":
                if let last = stack.last, last != "" && last != ".." {
                    stack.removeLast()
                } else if !hasLeadingSlash {
                    stack.append(segment)
                }
            default:
                stack.append(segment)
            }
        }

        var result = stack.map(String.init).joined(separator: "/")
        if hasLeadingSlash && !result.hasPrefix("/") {
            result = "/" + result
        }
        if result.isEmpty && hasLeadingSlash {
            result = "/"
        }
        if hasTrailingSlash && result != "/" && !result.hasSuffix("/") {
            result += "/"
        }
        return result
    }

    private static func normalizeQuery(_ value: String?, sortItems: Bool) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let normalized = value
            .split(separator: "&", omittingEmptySubsequences: false)
            .map { normalizePercentEncoding(String($0), decodeUnreserved: true) }
        let output = sortItems ? normalized.sorted() : normalized
        return output.joined(separator: "&")
    }

    /// Upper-case percent hex digits and decode only RFC 3986 unreserved
    /// bytes. Reserved bytes such as `%2F` remain escaped so path boundaries
    /// and query semantics are not changed while equivalent spellings match.
    private static func normalizePercentEncoding(_ value: String, decodeUnreserved: Bool) -> String {
        let bytes = Array(value.utf8)
        var output = ""
        output.reserveCapacity(value.utf8.count)
        let hex = Array("0123456789ABCDEF".utf8)
        let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
        var index = 0

        while index < bytes.count {
            if bytes[index] == 37, index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) {
                let decoded = high * 16 + low
                if decodeUnreserved, unreserved.contains(decoded) {
                    output.append(String(decoding: [decoded], as: UTF8.self))
                } else {
                    output.append("%")
                    output.append(String(decoding: [hex[Int(high)]], as: UTF8.self))
                    output.append(String(decoding: [hex[Int(low)]], as: UTF8.self))
                }
                index += 3
            } else {
                if bytes[index] < 128 {
                    output.append(String(decoding: [bytes[index]], as: UTF8.self))
                } else {
                    output.append("%")
                    output.append(String(decoding: [hex[Int(bytes[index] >> 4)]], as: UTF8.self))
                    output.append(String(decoding: [hex[Int(bytes[index] & 0x0F)]], as: UTF8.self))
                }
                index += 1
            }
        }
        return output
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }
}
