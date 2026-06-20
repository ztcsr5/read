import Foundation
import JavaScriptCore

final class JSCoreRuntime {
    private let context: JSContext

    init() {
        self.context = JSContext()!
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

    private func installBaseBridge() {
        context.exceptionHandler = { context, exception in
            context?.exception = exception
        }

        let prelude = """
        var java = java || {};
        java.urlEncode = function(value) { return encodeURIComponent(String(value)); };
        java.base64Decode = function(value) {
          if (typeof atob === 'function') return atob(value);
          return value;
        };
        java.base64Encode = function(value) {
          if (typeof btoa === 'function') return btoa(value);
          return value;
        };
        var Packages = Packages || {};
        Packages.org = Packages.org || {};
        Packages.java = Packages.java || {};
        function importClass(_) { return undefined; }
        """
        context.evaluateScript(prelude)
    }
}

