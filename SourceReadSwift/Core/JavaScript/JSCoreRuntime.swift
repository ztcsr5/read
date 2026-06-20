import Foundation
import JavaScriptCore

final class JSCoreRuntime {
    private let context: JSContext

    init() {
        self.context = JSContext()!
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

        context.setObject(urlEncode, forKeyedSubscript: "__native_urlEncode" as NSString)
        context.setObject(base64Encode, forKeyedSubscript: "__native_base64Encode" as NSString)
        context.setObject(base64Decode, forKeyedSubscript: "__native_base64Decode" as NSString)
        context.setObject(timeFormat, forKeyedSubscript: "__native_timeFormat" as NSString)
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
        java.log = function(value) { return String(value); };
        var Packages = Packages || {};
        Packages.org = Packages.org || {};
        Packages.java = Packages.java || {};
        function importClass(_) { return undefined; }
        """
        context.evaluateScript(prelude)
    }
}
