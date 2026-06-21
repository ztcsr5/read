import Foundation
import JavaScriptCore
import SwiftSoup
import CryptoKit

final class JSCoreRuntime {
    private let context: JSContext
    private let ajaxHandler: ((String) -> String)?
    private var bridgeStore: [String: String] = [:]

    init(ajaxHandler: ((String) -> String)? = nil) {
        self.context = JSContext()!
        self.ajaxHandler = ajaxHandler
        installNativeClosures()
        installBaseBridge()
    }

    func evaluate(_ script: String, variables: [String: Any] = [:]) -> Result<String, SourceEngineError> {
        for (key, value) in variables {
            context.setObject(value, forKeyedSubscript: key as NSString)
        }
        guard let result = context.evaluateScript(script) else {
            if let exception = context.exception {
                return .failure(.javascript(exception.toString()))
            }
            return .success("")
        }
        if let exception = context.exception {
            context.exception = nil
            return .failure(.javascript(exception.toString()))
        }
        return .success(result.toString())
    }

    private func installNativeClosures() {
        let urlEncode: @convention(block) (String) -> String = { value in
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._*")
            return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }
        let urlDecode: @convention(block) (String) -> String = { value in
            value.removingPercentEncoding ?? value
        }
        let base64Encode: @convention(block) (String) -> String = { value in
            Data(value.utf8).base64EncodedString()
        }
        let base64Decode: @convention(block) (String) -> String = { value in
            guard let data = Data(base64Encoded: value) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        let md5: @convention(block) (String) -> String = { value in
            let digest = Insecure.MD5.hash(data: Data(value.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        let sha1: @convention(block) (String) -> String = { value in
            let digest = Insecure.SHA1.hash(data: Data(value.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        let sha256: @convention(block) (String) -> String = { value in
            let digest = SHA256.hash(data: Data(value.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        let hmacSHA256: @convention(block) (String, String) -> String = { value, key in
            let secret = SymmetricKey(data: Data(key.utf8))
            let digest = HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: secret)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        let hexEncode: @convention(block) (String) -> String = { value in
            Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        }
        let hexDecode: @convention(block) (String) -> String = { value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count.isMultiple(of: 2) else { return "" }
            var bytes: [UInt8] = []
            var index = cleaned.startIndex
            while index < cleaned.endIndex {
                let next = cleaned.index(index, offsetBy: 2)
                guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return "" }
                bytes.append(byte)
                index = next
            }
            return String(data: Data(bytes), encoding: .utf8) ?? ""
        }
        let timeFormat: @convention(block) (Double, String) -> String = { timestamp, format in
            let date = Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = format
                .replacingOccurrences(of: "yyyy", with: "yyyy")
                .replacingOccurrences(of: "MM", with: "MM")
                .replacingOccurrences(of: "dd", with: "dd")
                .replacingOccurrences(of: "HH", with: "HH")
                .replacingOccurrences(of: "mm", with: "mm")
                .replacingOccurrences(of: "ss", with: "ss")
            return formatter.string(from: date)
        }
        let getString: @convention(block) (String, String, String) -> String = { html, rule, baseUrl in
            do {
                let document = try SwiftSoup.parse(html, baseUrl)
                return try Self.extractString(from: document, rule: rule, baseUrl: URL(string: baseUrl))
            } catch {
                return ""
            }
        }
        let getStringList: @convention(block) (String, String, String) -> NSArray = { html, rule, baseUrl in
            do {
                let document = try SwiftSoup.parse(html, baseUrl)
                let values = try Self.extractStringList(from: document, rule: rule, baseUrl: URL(string: baseUrl))
                return values as NSArray
            } catch {
                return [] as NSArray
            }
        }
        let ajaxHandler = self.ajaxHandler
        weak var weakSelf = self
        let ajax: @convention(block) (String, String) -> String = { url, headers in
            let requestText = weakSelf?.requestText(url: url, body: nil, headers: headers, includeStoredBody: false) ?? url
            return ajaxHandler?(requestText) ?? ""
        }
        let post: @convention(block) (String, String, String) -> String = { url, body, headers in
            let requestText = weakSelf?.requestText(url: url, body: body, headers: headers, includeStoredBody: true) ?? "\(url)@Body:\(body)"
            return ajaxHandler?(requestText) ?? ""
        }
        let put: @convention(block) (String, String) -> String = { key, value in
            weakSelf?.bridgeStore[key] = value
            return value
        }
        let getStore: @convention(block) (String) -> String = { key in
            weakSelf?.bridgeStore[key] ?? ""
        }

        context.setObject(urlEncode, forKeyedSubscript: "__native_urlEncode" as NSString)
        context.setObject(urlDecode, forKeyedSubscript: "__native_urlDecode" as NSString)
        context.setObject(base64Encode, forKeyedSubscript: "__native_base64Encode" as NSString)
        context.setObject(base64Decode, forKeyedSubscript: "__native_base64Decode" as NSString)
        context.setObject(md5, forKeyedSubscript: "__native_md5" as NSString)
        context.setObject(sha1, forKeyedSubscript: "__native_sha1" as NSString)
        context.setObject(sha256, forKeyedSubscript: "__native_sha256" as NSString)
        context.setObject(hmacSHA256, forKeyedSubscript: "__native_hmacSHA256" as NSString)
        context.setObject(hexEncode, forKeyedSubscript: "__native_hexEncode" as NSString)
        context.setObject(hexDecode, forKeyedSubscript: "__native_hexDecode" as NSString)
        context.setObject(timeFormat, forKeyedSubscript: "__native_timeFormat" as NSString)
        context.setObject(getString, forKeyedSubscript: "__native_getString" as NSString)
        context.setObject(getStringList, forKeyedSubscript: "__native_getStringList" as NSString)
        context.setObject(ajax, forKeyedSubscript: "__native_ajax" as NSString)
        context.setObject(post, forKeyedSubscript: "__native_post" as NSString)
        context.setObject(put, forKeyedSubscript: "__native_put" as NSString)
        context.setObject(getStore, forKeyedSubscript: "__native_getStore" as NSString)
    }

    private func installBaseBridge() {
        context.exceptionHandler = { context, exception in
            context?.exception = exception
        }

        let prelude = """
        var java = java || {};
        java.urlEncode = function(value) { return __native_urlEncode(String(value)); };
        java.encodeURI = java.urlEncode;
        java.encodeURIComponent = java.urlEncode;
        java.decodeURI = function(value) { return __native_urlDecode(String(value)); };
        java.decodeURIComponent = java.decodeURI;
        java.base64Encode = function(value) { return __native_base64Encode(String(value)); };
        java.base64Decode = function(value) { return __native_base64Decode(String(value)); };
        java.base64DecodeToString = java.base64Decode;
        java.base64Decoder = java.base64Decode;
        java.base64 = java.base64Encode;
        java.unbase64 = java.base64Decode;
        java.decodeBase64 = java.base64Decode;
        java.md5 = function(value) { return __native_md5(String(value)); };
        java.md5Encode = java.md5;
        java.hexMd5 = java.md5;
        java.MD5 = java.md5;
        java.sha1 = function(value) { return __native_sha1(String(value)); };
        java.SHA1 = java.sha1;
        java.sha256 = function(value) { return __native_sha256(String(value)); };
        java.SHA256 = java.sha256;
        java.timeFormat = function(timestamp, format) { return __native_timeFormat(Number(timestamp), String(format)); };
        java.getTime = function() { return Date.now(); };
        java.getString = function(html, rule) { return __native_getString(String(html), String(rule), String(typeof baseUrl === 'undefined' ? '' : baseUrl)); };
        java.getStringList = function(html, rule) {
          var list = __native_getStringList(String(html), String(rule), String(typeof baseUrl === 'undefined' ? '' : baseUrl));
          var out = [];
          for (var i = 0; i < list.length; i++) out.push(String(list[i]));
          return out;
        };
        function __bridgeString(value) {
          if (value === undefined || value === null) return '';
          if (typeof value === 'string') return value;
          return JSON.stringify(value);
        }
        function __bridgeStored(name) {
          return __native_getStore(String(name));
        }
        function __bridgeResponse(text) {
          var value = String(text || '');
          return {
            body: function() { return value; },
            text: function() { return value; },
            toString: function() { return value; },
            valueOf: function() { return value; }
          };
        }
        java.put = function(key, value) { return __native_put(String(key), __bridgeString(value)); };
        java.getVar = function(key) { return __bridgeStored(key); };
        java.ajax = function(url, headers) { return __bridgeResponse(__native_ajax(String(url), __bridgeString(headers || ''))); };
        java.get = function(url, headers) {
          var key = String(url);
          var value = __bridgeStored(key);
          if (value && key.indexOf('://') < 0 && key.charAt(0) !== '/') return value;
          return __bridgeResponse(__native_ajax(key, __bridgeString(headers || '')));
        };
        java.post = function(url, body, headers) { return __bridgeResponse(__native_post(String(url), __bridgeString(body || ''), __bridgeString(headers || ''))); };
        java.log = function(value) { return String(value); };
        function base64Encode(value) { return java.base64Encode(value); }
        function base64Decode(value) { return java.base64Decode(value); }
        function unbase64(value) { return java.base64Decode(value); }
        function md5(value) { return java.md5(value); }
        function hexMd5(value) { return java.md5(value); }
        function sha1(value) { return java.sha1(value); }
        function atob(value) { return java.base64Decode(value); }
        function btoa(value) { return java.base64Encode(value); }
        var CryptoJS = CryptoJS || {};
        function __cryptoText(value) {
          if (value && value.__text !== undefined) return String(value.__text);
          return String(value);
        }
        function __cryptoWordArray(text, defaultEncoding) {
          var value = String(text || '');
          var defaultEnc = defaultEncoding || 'utf8';
          return {
            __text: value,
            toString: function(encoder) {
              var enc = encoder && encoder.__encoding ? String(encoder.__encoding) : defaultEnc;
              if (enc === 'hex') return __native_hexEncode(value);
              if (enc === 'base64') return __native_base64Encode(value);
              return value;
            },
            valueOf: function() { return value; }
          };
        }
        function __cryptoDigest(hex) {
          var value = String(hex || '');
          return {
            __hex: value,
            toString: function(encoder) {
              var enc = encoder && encoder.__encoding ? String(encoder.__encoding) : 'hex';
              if (enc === 'utf8') return __native_hexDecode(value);
              if (enc === 'base64') return __native_base64Encode(__native_hexDecode(value));
              return value;
            },
            valueOf: function() { return value; }
          };
        }
        CryptoJS.MD5 = function(value) {
          return __cryptoDigest(__native_md5(__cryptoText(value)));
        };
        CryptoJS.SHA1 = function(value) {
          return __cryptoDigest(__native_sha1(__cryptoText(value)));
        };
        CryptoJS.SHA256 = function(value) {
          return __cryptoDigest(__native_sha256(__cryptoText(value)));
        };
        CryptoJS.HmacSHA256 = function(value, key) {
          return __cryptoDigest(__native_hmacSHA256(__cryptoText(value), __cryptoText(key)));
        };
        CryptoJS.enc = CryptoJS.enc || {};
        CryptoJS.enc.Utf8 = {
          __encoding: 'utf8',
          parse: function(value) { return __cryptoWordArray(String(value), 'utf8'); },
          stringify: function(value) { return __cryptoText(value); }
        };
        CryptoJS.enc.Hex = {
          __encoding: 'hex',
          parse: function(value) { return __cryptoWordArray(__native_hexDecode(String(value)), 'hex'); },
          stringify: function(value) { return value && value.__hex ? String(value.__hex) : __native_hexEncode(__cryptoText(value)); }
        };
        CryptoJS.enc.Base64 = {
          __encoding: 'base64',
          parse: function(value) { return __cryptoWordArray(__native_base64Decode(String(value)), 'base64'); },
          stringify: function(value) { return __native_base64Encode(__cryptoText(value)); }
        };
        var Packages = Packages || {};
        Packages.org = Packages.org || {};
        Packages.org.jsoup = Packages.org.jsoup || {};
        Packages.java = Packages.java || {};
        var org = Packages.org;
        function __makeJsoupSelection(html, selector, baseUrlValue) {
          return {
            select: function(nextSelector) {
              var joined = selector ? selector + ' ' + String(nextSelector) : String(nextSelector);
              return __makeJsoupSelection(html, joined, baseUrlValue);
            },
            first: function() { return this; },
            get: function(_) { return this; },
            text: function() { return __native_getString(String(html), String(selector) + '@text', String(baseUrlValue || '')); },
            html: function() { return __native_getString(String(html), String(selector) + '@html', String(baseUrlValue || '')); },
            attr: function(name) { return __native_getString(String(html), String(selector) + '@' + String(name), String(baseUrlValue || '')); },
            eachText: function() {
              var list = __native_getStringList(String(html), String(selector) + '@text', String(baseUrlValue || ''));
              var out = [];
              for (var i = 0; i < list.length; i++) out.push(String(list[i]));
              return out;
            }
          };
        }
        Packages.org.jsoup.Jsoup = {
          parse: function(html, baseUrlValue) {
            return __makeJsoupSelection(String(html), '', String(baseUrlValue || (typeof baseUrl === 'undefined' ? '' : baseUrl)));
          }
        };
        function importClass(_) { return undefined; }
        """
        context.evaluateScript(prelude)
    }

    private func requestText(url: String, body: String?, headers explicitHeaders: String, includeStoredBody: Bool) -> String {
        var output = url
        let headers = mergedHeaders(explicitHeaders)
        if !headers.isEmpty, !output.localizedCaseInsensitiveContains("@Header:") {
            output += "@Header:\(jsonString(headers))"
        }

        let bodyText = requestBody(explicitBody: body, includeStoredBody: includeStoredBody)
        if let bodyText, !bodyText.isEmpty, !output.localizedCaseInsensitiveContains("@Body:") {
            output += "@Body:\(bodyText)"
        }
        return output
    }

    private func mergedHeaders(_ explicitHeaders: String) -> [String: String] {
        var headers: [String: String] = [:]
        for key in ["headers", "header", "bookSourceHeader"] {
            headers.merge(parseStringMap(bridgeStore[key] ?? ""), uniquingKeysWith: { _, new in new })
        }
        headers.merge(parseStringMap(explicitHeaders), uniquingKeysWith: { _, new in new })
        return headers
    }

    private func requestBody(explicitBody: String?, includeStoredBody: Bool) -> String? {
        if let explicitBody, !explicitBody.isEmpty {
            return normalizedBody(explicitBody)
        }
        guard includeStoredBody else { return nil }
        for key in ["body", "requestBody", "postBody", "params"] {
            if let value = bridgeStore[key], !value.isEmpty {
                return normalizedBody(value)
            }
        }
        return nil
    }

    private func normalizedBody(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return value
        }
        return object
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(String(describing: value)))"
            }
            .joined(separator: "&")
    }

    private func parseStringMap(_ text: String) -> [String: String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object.reduce(into: [:]) { result, item in
                result[item.key] = String(describing: item.value)
            }
        }
        return trimmed
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == ";" })
            .reduce(into: [:]) { result, line in
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                let separator: Character = text.contains(":") ? ":" : "="
                let parts = text.split(separator: separator, maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }
                result[key] = value
            }
    }

    private func jsonString(_ object: [String: String]) -> String {
        let sorted = object.sorted { $0.key < $1.key }.reduce(into: [String: String]()) { result, item in
            result[item.key] = item.value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: sorted, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func extractString(from document: Document, rule: String, baseUrl: URL?) throws -> String {
        try HtmlRuleExtractor().value(from: document, rule: rule, baseUrl: baseUrl)
    }

    private static func extractStringList(from document: Document, rule: String, baseUrl: URL?) throws -> [String] {
        let split = splitSelectorAndAttribute(rule)
        let html = try document.outerHtml()
        let elements = try HtmlRuleExtractor().select(
            html,
            baseUrl: baseUrl ?? URL(fileURLWithPath: "/"),
            listRule: split.selector
        )
        return try elements.map {
            try HtmlRuleExtractor().value(from: $0, rule: "@\(split.attribute)", baseUrl: baseUrl)
        }.filter { !$0.isEmpty }
    }

    private static func splitSelectorAndAttribute(_ rule: String) -> (selector: String, attribute: String) {
        let parts = rule.components(separatedBy: "@")
        guard parts.count > 1 else {
            return (rule, "text")
        }
        return (parts.dropLast().joined(separator: "@"), parts.last ?? "text")
    }
}
