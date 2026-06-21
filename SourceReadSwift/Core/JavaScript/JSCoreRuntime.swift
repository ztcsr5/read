import Foundation
import JavaScriptCore
import SwiftSoup

final class JSCoreRuntime {
    private let context: JSContext
    private let ajaxHandler: ((String) -> String)?

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
            value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        }
        let base64Encode: @convention(block) (String) -> String = { value in
            Data(value.utf8).base64EncodedString()
        }
        let base64Decode: @convention(block) (String) -> String = { value in
            guard let data = Data(base64Encoded: value) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
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
                return try Self.extractString(from: document, rule: rule)
            } catch {
                return ""
            }
        }
        let getStringList: @convention(block) (String, String, String) -> NSArray = { html, rule, baseUrl in
            do {
                let document = try SwiftSoup.parse(html, baseUrl)
                let values = try Self.extractStringList(from: document, rule: rule)
                return values as NSArray
            } catch {
                return [] as NSArray
            }
        }
        let ajaxHandler = self.ajaxHandler
        let ajax: @convention(block) (String) -> String = { url in
            ajaxHandler?(url) ?? ""
        }
        let post: @convention(block) (String, String) -> String = { url, body in
            let separator = url.contains("@Body:") ? "" : "@Body:"
            return ajaxHandler?("\(url)\(separator)\(body)") ?? ""
        }

        context.setObject(urlEncode, forKeyedSubscript: "__native_urlEncode" as NSString)
        context.setObject(base64Encode, forKeyedSubscript: "__native_base64Encode" as NSString)
        context.setObject(base64Decode, forKeyedSubscript: "__native_base64Decode" as NSString)
        context.setObject(timeFormat, forKeyedSubscript: "__native_timeFormat" as NSString)
        context.setObject(getString, forKeyedSubscript: "__native_getString" as NSString)
        context.setObject(getStringList, forKeyedSubscript: "__native_getStringList" as NSString)
        context.setObject(ajax, forKeyedSubscript: "__native_ajax" as NSString)
        context.setObject(post, forKeyedSubscript: "__native_post" as NSString)
    }

    private func installBaseBridge() {
        context.exceptionHandler = { context, exception in
            context?.exception = exception
        }

        let prelude = """
        var java = java || {};
        java.urlEncode = function(value) { return __native_urlEncode(String(value)); };
        java.base64Encode = function(value) { return __native_base64Encode(String(value)); };
        java.base64Decode = function(value) { return __native_base64Decode(String(value)); };
        java.timeFormat = function(timestamp, format) { return __native_timeFormat(Number(timestamp), String(format)); };
        java.getTime = function() { return Date.now(); };
        java.getString = function(html, rule) { return __native_getString(String(html), String(rule), String(typeof baseUrl === 'undefined' ? '' : baseUrl)); };
        java.getStringList = function(html, rule) {
          var list = __native_getStringList(String(html), String(rule), String(typeof baseUrl === 'undefined' ? '' : baseUrl));
          var out = [];
          for (var i = 0; i < list.length; i++) out.push(String(list[i]));
          return out;
        };
        java.ajax = function(url) { return __native_ajax(String(url)); };
        java.get = function(url) { return __native_ajax(String(url)); };
        java.post = function(url, body) { return __native_post(String(url), String(body || '')); };
        java.log = function(value) { return String(value); };
        var Packages = Packages || {};
        Packages.org = Packages.org || {};
        Packages.java = Packages.java || {};
        function importClass(_) { return undefined; }
        """
        context.evaluateScript(prelude)
    }

    private static func extractString(from document: Document, rule: String) throws -> String {
        let parts = rule.components(separatedBy: "@")
        let selector = normalizeSelector(parts.first ?? "")
        let attr = parts.dropFirst().first ?? "text"
        let element = selector.isEmpty ? document : try document.select(selector).first() ?? document
        return try extractValue(from: element, attr: attr)
    }

    private static func extractStringList(from document: Document, rule: String) throws -> [String] {
        let parts = rule.components(separatedBy: "@")
        let selector = normalizeSelector(parts.first ?? "")
        let attr = parts.dropFirst().first ?? "text"
        let elements: [Element] = selector.isEmpty ? [document] : try document.select(selector).array()
        return try elements.map { try extractValue(from: $0, attr: attr) }.filter { !$0.isEmpty }
    }

    private static func extractValue(from element: Element, attr: String) throws -> String {
        if attr == "text" {
            return try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if attr == "html" {
            return try element.html().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return try element.attr(attr).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeSelector(_ selector: String) -> String {
        selector
            .replacingOccurrences(of: "&&", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
