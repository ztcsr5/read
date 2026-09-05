import Foundation
import JavaScriptCore
import SwiftSoup
import CryptoKit
import CommonCrypto

final class JSCoreRuntime {
    private let context: JSContext
    private let ajaxHandler: ((String) -> String)?
    private let executionContext: RuleExecutionContext
    private let javaHostBridge: LegadoJavaHostBridge
    private let ruleHostBridge: LegadoRuleHostBridge
    private let jsoupBridge: LegadoJsoupBridge
    private let jxNodeFactory: LegadoJXNodeFactoryBridge
    private var baseBridgeError: String? = nil

    init(
        ajaxHandler: ((String) -> String)? = nil,
        executionContext: RuleExecutionContext = RuleExecutionContext()
    ) {
        self.context = JSContext()!
        self.ajaxHandler = ajaxHandler
        self.executionContext = executionContext
        self.javaHostBridge = LegadoJavaHostBridge(executionContext: executionContext)
        self.ruleHostBridge = LegadoRuleHostBridge(executionContext: executionContext)
        self.jsoupBridge = LegadoJsoupBridge(executionContext: executionContext)
        self.jxNodeFactory = LegadoJXNodeFactoryBridge(executionContext: executionContext)
        if executionContext.networkHandler == nil {
            executionContext.networkHandler = ajaxHandler
        }
        context.setObject(javaHostBridge, forKeyedSubscript: "__nativeLegado" as NSString)
        context.setObject(ruleHostBridge, forKeyedSubscript: "__nativeRule" as NSString)
        context.setObject(jsoupBridge, forKeyedSubscript: "__nativeJsoup" as NSString)
        context.setObject(jxNodeFactory, forKeyedSubscript: "__nativeJXNode" as NSString)
        installNativeClosures()
        // Declare the compatibility roots in a tiny standalone script first.
        // JavaScriptCore can reject a first-read of an undeclared global inside
        // the large prelude; predeclaring them keeps the later `var x = x ||`
        // aliases source-compatible without relying on browser semantics.
        context.evaluateScript("var java = {}; var cookie = {}; var CryptoJS = {}; var Packages = {}; var JXNode = function(value) { return __nativeJXNode.create(value); };")
        installBaseBridge()
    }

    func evaluate(_ script: String, variables: [String: Any] = [:]) -> Result<String, SourceEngineError> {
        if let baseBridgeError {
            return .failure(.javascript("Legado bridge prelude failed: \(baseBridgeError)"))
        }
        executionContext.bind(variables)
        let normalization = LegadoJavaScriptCompatibility.normalize(script)
        let executableScript = normalization.normalizedScript
        context.exception = nil
        for (key, value) in variables {
            var jsCompatibleValue = value
            if let source = value as? BookSource {
                var map = source.raw
                map["bookSourceName"] = source.bookSourceName
                map["sourceName"] = source.bookSourceName
                map["bookSourceUrl"] = source.bookSourceUrl
                map["sourceUrl"] = source.bookSourceUrl
                map["bookSourceGroup"] = source.bookSourceGroup ?? ""
                map["sourceGroup"] = source.bookSourceGroup ?? ""
                map["bookSourceType"] = String(source.bookSourceType)
                map["weight"] = String(source.weight)
                map["searchUrl"] = source.searchUrl ?? ""
                map["exploreUrl"] = source.exploreUrl ?? ""
                map["header"] = source.header ?? ""
                map["customConfig"] = source.customConfig ?? ""
                // Android Legado exposes these metadata fields directly on `source`.
                // Keep them in the JS object even when Swift stores them in raw.
                map["bookSourceComment"] = source.raw["bookSourceComment"] ?? source.raw["comment"] ?? ""
                map["bookSourceUrlName"] = source.raw["bookSourceUrlName"] ?? source.raw["urlName"] ?? ""
                map["loginUrl"] = source.loginUrl ?? source.raw["loginUrl"] ?? ""
                map["loginCheckJs"] = source.loginCheckJs ?? source.raw["loginCheckJs"] ?? ""
                jsCompatibleValue = map
            } else if let chapter = value as? BookChapter {
                jsCompatibleValue = LegadoBookChapterBridge(chapter: chapter)
            } else if let book = value as? SearchBook {
                jsCompatibleValue = LegadoSearchBookBridge(book: book)
            } else if let book = value as? BookDetail {
                let bridge = LegadoSearchBookBridge(book: SearchBook(
                    name: book.name, author: book.author, coverUrl: book.coverUrl,
                    bookUrl: book.bookUrl, sourceName: book.sourceName, sourceUrl: book.sourceUrl, intro: book.intro
                ))
                bridge.tocUrl = book.tocUrl ?? ""
                bridge.latestChapterTitle = book.latestChapter ?? ""
                jsCompatibleValue = bridge
            }
            context.setObject(jsCompatibleValue, forKeyedSubscript: key as NSString)
            
            if key == "chapter" {
                let injectScript = """
                if (typeof chapter !== 'undefined' && chapter !== null) {
                    chapter.name = chapter.name || chapter.title || '';
                    chapter.title = chapter.title || chapter.name || '';
                    chapter.chapterUrl = chapter.chapterUrl || chapter.url || '';
                    chapter.url = chapter.url || chapter.chapterUrl || '';
                    chapter.chapterIndex = chapter.chapterIndex == null ? (chapter.index || 0) : chapter.chapterIndex;
                    chapter.index = chapter.index == null ? chapter.chapterIndex : chapter.index;
                    chapter.getName = function() { return chapter.name || chapter.title || ''; };
                    chapter.getTitle = chapter.getName;
                    chapter.getUrl = function() { return chapter.url || chapter.chapterUrl || ''; };
                    chapter.getChapterUrl = chapter.getUrl;
                    chapter.getIndex = function() { return chapter.index || chapter.chapterIndex || 0; };
                    chapter.getChapterIndex = chapter.getIndex;
                    chapter.isVip = function() {
                        var title = String(chapter.title || chapter.name || '').toLowerCase();
                        return title.indexOf('vip') >= 0 || title.indexOf('订阅') >= 0 || title.indexOf('付费') >= 0;
                    };
                }
                """
                context.evaluateScript(injectScript)
            } else if key == "source" {
                let injectScript = """
                if (typeof source !== 'undefined' && source !== null) {
                    source.getKey = function() { return source.key || source.bookSourceUrl || source.sourceUrl || ''; };
                    source.sourceUrl = source.sourceUrl || source.bookSourceUrl || source.key || '';
                    source.sourceName = source.sourceName || source.bookSourceName || '';
                    source.bookSourceComment = source.bookSourceComment || source.comment || '';
                    source.bookSourceUrlName = source.bookSourceUrlName || source.urlName || source.sourceName || '';
                    source.loginUrl = source.loginUrl || '';
                    source.loginCheckJs = source.loginCheckJs || '';
                    source.getName = function() { return source.bookSourceName || source.sourceName || ''; };
                    source.getUrl = function() { return source.bookSourceUrl || source.sourceUrl || source.key || ''; };
                    source.getSourceUrl = source.getUrl;
                    source.getVariable = function(key) {
                        if (arguments.length > 0 && key != null && String(key) !== '') return java.getVar('source.variable.' + String(key));
                        return source.variable || java.getVar('source.variable') || '';
                    };
                    source.setVariable = function(key, value) {
                        if (arguments.length > 1) return java.put('source.variable.' + String(key), value == null ? '' : String(value));
                        source.variable = key == null ? '' : String(key);
                        return java.put('source.variable', source.variable);
                    };
                    source.getVariableMap = function() {
                        var parsed = {};
                        try { parsed = JSON.parse(source.getVariable() || '{}'); } catch (_) {}
                        return {
                          get: function(k) { var value = parsed[String(k)]; return value == null ? '' : value; },
                          put: function(k, v) { parsed[String(k)] = v; source.setVariable(JSON.stringify(parsed)); return v; },
                          remove: function(k) { var old = parsed[String(k)]; delete parsed[String(k)]; source.setVariable(JSON.stringify(parsed)); return old == null ? null : old; },
                          containsKey: function(k) { return Object.prototype.hasOwnProperty.call(parsed, String(k)); },
                          isEmpty: function() { return Object.keys(parsed).length === 0; }
                        };
                    };
                    source.getLoginInfoMap = function() { return { get: function(k) { return java.getVar('source.login.' + String(k || '')); } }; };
                    source.putLoginHeader = function(k, v) { return java.put('source.loginHeader.' + String(k || ''), v == null ? '' : String(v)); };
                    source.getLoginHeader = function(k) { return java.getVar('source.loginHeader.' + String(k || '')); };
                    source.putVariable = source.setVariable;
                }
                """
                context.evaluateScript(injectScript)
            } else if key == "book" {
                let injectScript = """
                if (typeof book !== 'undefined' && book !== null) {
                    book.getVariable = function(key) {
                        if (arguments.length > 0 && key != null && String(key) !== '') return java.getVar('book.variable.' + String(key));
                        return book.variable || java.getVar('book.variable') || '';
                    };
                    book.name = book.name || book.title || '';
                    book.title = book.title || book.name || '';
                    book.bookUrl = book.bookUrl || book.url || '';
                    book.url = book.url || book.bookUrl || '';
                    book.tocUrl = book.tocUrl || book.bookUrl || book.url || '';
                    book.getName = function() { return book.name || book.title || ''; };
                    book.getTitle = book.getName;
                    book.getAuthor = function() { return book.author || ''; };
                    book.getBookUrl = function() { return book.bookUrl || book.url || ''; };
                    book.getUrl = book.getBookUrl;
                    book.getTocUrl = function() { return book.tocUrl || book.bookUrl || book.url || ''; };
                    book.getOrigin = function() { return book.origin || book.bookSourceUrl || ''; };
                    book.setVariable = function(key, value) {
                        if (arguments.length > 1) return java.put('book.variable.' + String(key), value == null ? '' : String(value));
                        book.variable = key == null ? '' : String(key);
                        return java.put('book.variable', book.variable);
                    };
                    book.putVariable = book.setVariable;
                }
                """
                context.evaluateScript(injectScript)
            }
        }
        guard let result = context.evaluateScript(executableScript) else {
            if let exception = context.exception {
                let message = exception.toString() ?? "JavaScript exception"
                executionContext.recordJavaScript(SourceJavaScriptEvidence(
                    originalScript: normalization.originalScript,
                    normalizedScript: executableScript,
                    features: normalization.features,
                    exception: message,
                    succeeded: false
                ))
                return .failure(.javascript(message))
            }
            executionContext.recordJavaScript(SourceJavaScriptEvidence(
                originalScript: normalization.originalScript,
                normalizedScript: executableScript,
                features: normalization.features,
                succeeded: true
            ))
            return .success("")
        }
        if let exception = context.exception {
            let message = exception.toString() ?? "JavaScript exception"
            context.exception = nil
            executionContext.recordJavaScript(SourceJavaScriptEvidence(
                originalScript: normalization.originalScript,
                normalizedScript: executableScript,
                features: normalization.features,
                exception: message,
                succeeded: false
            ))
            return .failure(.javascript(message))
        }
        executionContext.recordJavaScript(SourceJavaScriptEvidence(
            originalScript: normalization.originalScript,
            normalizedScript: executableScript,
            features: normalization.features,
            succeeded: true
        ))
        synchronizeExecutionContextFromJavaScript()
        return .success(result.toString())
    }

    private func synchronizeExecutionContextFromJavaScript() {
        for key in ["result", "baseUrl", "nextChapterUrl", "cookieHeader"] {
            guard let value = context.objectForKeyedSubscript(key),
                  !value.isUndefined,
                  !value.isNull else { continue }
            executionContext.setValue(value.toObject(), for: key)
        }
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
        let base64EncodeBytes: @convention(block) (NSArray) -> String = { values in
            let bytes = values.compactMap(Self.byteValue)
            return Data(bytes).base64EncodedString()
        }
        let base64Decode: @convention(block) (String) -> String = { value in
            let normalized = Self.normalizedBase64(value)
            guard let data = Data(base64Encoded: normalized) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        let base64DecodeBytes: @convention(block) (String) -> NSArray = { value in
            let normalized = Self.normalizedBase64(value)
            guard let data = Data(base64Encoded: normalized) else { return [] }
            return data.map { NSNumber(value: $0) } as NSArray
        }
        let stringToBytes: @convention(block) (String) -> NSArray = { value in
            Data(value.utf8).map { NSNumber(value: $0) } as NSArray
        }
        let stringToBytesCharset: @convention(block) (String, String) -> NSArray = { value, charset in
            Self.data(for: value, charset: charset).map { NSNumber(value: $0) } as NSArray
        }
        let bytesToString: @convention(block) (JSValue) -> String = { value in
            let bytes = Self.byteValues(from: value)
            return String(data: Data(bytes), encoding: .utf8) ?? ""
        }
        let bytesToStringCharset: @convention(block) (JSValue, String) -> String = { value, charset in
            let bytes = Self.byteValues(from: value)
            return Self.string(from: Data(bytes), charset: charset)
        }
        let digestBytes: @convention(block) (NSArray, String) -> NSArray = { values, algorithm in
            let bytes = values.compactMap(Self.byteValue)
            let data = Data(bytes)
            let normalized = algorithm.lowercased().replacingOccurrences(of: "-", with: "")
            let digest: [UInt8]
            switch normalized {
            case "md5": digest = Array(Insecure.MD5.hash(data: data))
            case "sha1": digest = Array(Insecure.SHA1.hash(data: data))
            case "sha224":
                var output = Array(repeating: UInt8(0), count: Int(CC_SHA224_DIGEST_LENGTH))
                data.withUnsafeBytes { buffer in
                    output.withUnsafeMutableBytes { destination in
                        _ = CC_SHA224(buffer.baseAddress, CC_LONG(data.count), destination.bindMemory(to: UInt8.self).baseAddress)
                    }
                }
                digest = output
            case "sha384": digest = Array(SHA384.hash(data: data))
            case "sha512": digest = Array(SHA512.hash(data: data))
            case "ripemd160": digest = Self.ripemd160(data)
            default: digest = Array(SHA256.hash(data: data))
            }
            return digest.map { NSNumber(value: $0) } as NSArray
        }
        let hmacBytes: @convention(block) (NSArray, String, NSArray) -> NSArray = { values, algorithm, keyValues in
            let message = Data(values.compactMap(Self.byteValue))
            let key = SymmetricKey(data: Data(keyValues.compactMap(Self.byteValue)))
            let normalized = algorithm.lowercased().replacingOccurrences(of: "hmac", with: "").replacingOccurrences(of: "-", with: "")
            let bytes: [UInt8]
            switch normalized {
            case "md5":
                var output = Array(repeating: UInt8(0), count: Int(CC_MD5_DIGEST_LENGTH))
                message.withUnsafeBytes { messageBuffer in
                    key.withUnsafeBytes { keyBuffer in
                        output.withUnsafeMutableBytes { destination in
                            CCHmac(CCHmacAlgorithm(kCCHmacAlgMD5), keyBuffer.baseAddress, key.bitCount / 8,
                                   messageBuffer.baseAddress, message.count, destination.bindMemory(to: UInt8.self).baseAddress)
                        }
                    }
                }
                bytes = output
            case "sha1": bytes = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
            case "sha224":
                var output = Array(repeating: UInt8(0), count: Int(CC_SHA224_DIGEST_LENGTH))
                message.withUnsafeBytes { messageBuffer in
                    key.withUnsafeBytes { keyBuffer in
                        output.withUnsafeMutableBytes { destination in
                            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA224), keyBuffer.baseAddress, key.bitCount / 8,
                                   messageBuffer.baseAddress, message.count, destination.bindMemory(to: UInt8.self).baseAddress)
                        }
                    }
                }
                bytes = output
            case "sha384": bytes = Array(HMAC<SHA384>.authenticationCode(for: message, using: key))
            case "sha512": bytes = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
            default: bytes = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
            }
            return bytes.map { NSNumber(value: $0) } as NSArray
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
        let digestHex: @convention(block) (String, String) -> String = { value, algorithm in
            Self.digestHex(value: value, algorithm: algorithm)
        }
        let hmacHex: @convention(block) (String, String, String) -> String = { value, algorithm, key in
            Self.hmacHex(value: value, algorithm: algorithm, key: key)
        }
        let hmacBase64: @convention(block) (String, String, String) -> String = { value, algorithm, key in
            Self.hmacBase64(value: value, algorithm: algorithm, key: key)
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
                let safeBaseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "http://localhost/" : baseUrl
                let document = try SwiftSoup.parse(html, safeBaseUrl)
                return try Self.extractString(from: document, rule: rule, baseUrl: URL(string: safeBaseUrl))
            } catch {
                return ""
            }
        }
        let getStringList: @convention(block) (String, String, String) -> NSArray = { html, rule, baseUrl in
            do {
                let safeBaseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "http://localhost/" : baseUrl
                let document = try SwiftSoup.parse(html, safeBaseUrl)
                let values = try Self.extractStringList(from: document, rule: rule, baseUrl: URL(string: safeBaseUrl))
                return values as NSArray
            } catch {
                return [] as NSArray
            }
        }
        let countElements: @convention(block) (String, String, String) -> Int = { html, selector, baseUrl in
            do {
                let safeBaseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "http://localhost/" : baseUrl
                let document = try SwiftSoup.parse(html, safeBaseUrl)
                return try Self.countElements(in: document, selector: selector, baseUrl: URL(string: safeBaseUrl))
            } catch {
                return 0
            }
        }
        let ajaxHandler = self.ajaxHandler
        weak var weakSelf = self
        let ajaxResponse: @convention(block) (String, String) -> NSDictionary = { url, headers in
            guard let runtime = weakSelf else { return [:] }
            let requestText = runtime.requestText(url: url, body: nil, headers: headers, includeStoredBody: false)
            if let response = runtime.executionContext.responseHandler?(requestText) {
                runtime.executionContext.ingestResponse(response)
                return [
                    "body": response.body,
                    "url": response.url.absoluteString,
                    "statusCode": response.statusCode,
                    "headers": response.headers
                ] as NSDictionary
            }
            let body = runtime.executionContext.networkHandler?(requestText) ?? ajaxHandler?(requestText) ?? ""
            return ["body": body, "url": url, "statusCode": 200, "headers": [:]] as NSDictionary
        }
        let ajaxBytes: @convention(block) (String, String) -> NSArray = { url, headers in
            guard let runtime = weakSelf else { return [] }
            let requestText = runtime.requestText(url: url, body: nil, headers: headers, includeStoredBody: false)
            if let response = runtime.executionContext.responseHandler?(requestText) {
                runtime.executionContext.ingestResponse(response)
                return response.data.map { NSNumber(value: $0) } as NSArray
            }
            let body = runtime.executionContext.networkHandler?(requestText) ?? ajaxHandler?(requestText) ?? ""
            return Array(body.utf8).map { NSNumber(value: $0) } as NSArray
        }
        let ajax: @convention(block) (String, String) -> String = { url, headers in
            let requestText = weakSelf?.requestText(url: url, body: nil, headers: headers, includeStoredBody: false) ?? url
            return ajaxHandler?(requestText) ?? ""
        }
        let post: @convention(block) (String, String, String) -> String = { url, body, headers in
            let requestText = weakSelf?.requestText(url: url, body: body, headers: headers, includeStoredBody: true) ?? "\(url)@Body:\(body)"
            if let response = weakSelf?.executionContext.responseHandler?(requestText) {
                weakSelf?.executionContext.ingestResponse(response)
                return response.body
            }
            return weakSelf?.executionContext.networkHandler?(requestText) ?? ajaxHandler?(requestText) ?? ""
        }
        let postResponse: @convention(block) (String, String, String) -> NSDictionary = { url, body, headers in
            guard let runtime = weakSelf else { return [:] }
            let requestText = runtime.requestText(url: url, body: body, headers: headers, includeStoredBody: true)
            if let response = runtime.executionContext.responseHandler?(requestText) {
                runtime.executionContext.ingestResponse(response)
                return [
                    "body": response.body,
                    "url": response.url.absoluteString,
                    "statusCode": response.statusCode,
                    "headers": response.headers
                ] as NSDictionary
            }
            let value = runtime.executionContext.networkHandler?(requestText) ?? ajaxHandler?(requestText) ?? ""
            return ["body": value, "url": url, "statusCode": 200, "headers": [:]] as NSDictionary
        }
        let put: @convention(block) (String, String) -> String = { key, value in
            weakSelf?.executionContext.put(value, for: key) ?? value
        }
        let getStore: @convention(block) (String) -> String = { key in
            weakSelf?.executionContext.get(key) ?? ""
        }
        let removeElements: @convention(block) (String, String) -> String = { html, selector in
            do {
                let defaultBaseUrl = URL(string: "http://localhost/")!
                let doc = try SwiftSoup.parse(html, defaultBaseUrl.absoluteString)
                let extractor = HtmlRuleExtractor()
                let elements = try extractor.select(from: doc, rule: selector, baseUrl: defaultBaseUrl)
                for el in elements {
                    try el.remove()
                }
                return try doc.outerHtml()
            } catch {
                return html
            }
        }
        let getParents: @convention(block) (String, String, String) -> NSArray = { html, selector, baseUrl in
            do {
                let safeBaseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "http://localhost/" : baseUrl
                let doc = try SwiftSoup.parse(html, safeBaseUrl)
                let extractor = HtmlRuleExtractor()
                let elements = try extractor.select(from: doc, rule: selector, baseUrl: URL(string: safeBaseUrl))
                var parentsHtml: [String] = []
                for el in elements {
                    var curr = el.parent()
                    while let p = curr {
                        // SwiftSoup exposes the synthetic Document (`#root`) as
                        // an Element parent. Jsoup/SourceRead's JS bridge stops
                        // at <html>, so do not leak that implementation detail.
                        if p.nodeName() != "#root" && p.nodeName() != "#document" {
                            parentsHtml.append(try p.outerHtml())
                        }
                        curr = p.parent()
                    }
                }
                return parentsHtml as NSArray
            } catch {
                return [] as NSArray
            }
        }

        context.setObject(urlEncode, forKeyedSubscript: "__native_urlEncode" as NSString)
        context.setObject(urlDecode, forKeyedSubscript: "__native_urlDecode" as NSString)
        context.setObject(base64Encode, forKeyedSubscript: "__native_base64Encode" as NSString)
        context.setObject(base64EncodeBytes, forKeyedSubscript: "__native_base64EncodeBytes" as NSString)
        context.setObject(base64Decode, forKeyedSubscript: "__native_base64Decode" as NSString)
        context.setObject(base64DecodeBytes, forKeyedSubscript: "__native_base64DecodeBytes" as NSString)
        context.setObject(stringToBytes, forKeyedSubscript: "__native_stringToBytes" as NSString)
        context.setObject(stringToBytesCharset, forKeyedSubscript: "__native_stringToBytesCharset" as NSString)
        context.setObject(bytesToString, forKeyedSubscript: "__native_bytesToString" as NSString)
        context.setObject(bytesToStringCharset, forKeyedSubscript: "__native_bytesToStringCharset" as NSString)
        context.setObject(digestBytes, forKeyedSubscript: "__native_digestBytes" as NSString)
        context.setObject(hmacBytes, forKeyedSubscript: "__native_hmacBytes" as NSString)
        context.setObject(md5, forKeyedSubscript: "__native_md5" as NSString)
        context.setObject(sha1, forKeyedSubscript: "__native_sha1" as NSString)
        context.setObject(sha256, forKeyedSubscript: "__native_sha256" as NSString)
        context.setObject(hmacSHA256, forKeyedSubscript: "__native_hmacSHA256" as NSString)
        context.setObject(digestHex, forKeyedSubscript: "__native_digestHex" as NSString)
        context.setObject(hmacHex, forKeyedSubscript: "__native_hmacHex" as NSString)
        context.setObject(hmacBase64, forKeyedSubscript: "__native_hmacBase64" as NSString)
        context.setObject(hexEncode, forKeyedSubscript: "__native_hexEncode" as NSString)
        context.setObject(hexDecode, forKeyedSubscript: "__native_hexDecode" as NSString)
        context.setObject(timeFormat, forKeyedSubscript: "__native_timeFormat" as NSString)
        context.setObject(getString, forKeyedSubscript: "__native_getString" as NSString)
        context.setObject(getStringList, forKeyedSubscript: "__native_getStringList" as NSString)
        context.setObject(countElements, forKeyedSubscript: "__native_countElements" as NSString)
        context.setObject(ajax, forKeyedSubscript: "__native_ajax" as NSString)
        context.setObject(ajaxResponse, forKeyedSubscript: "__native_ajaxResponse" as NSString)
        context.setObject(ajaxBytes, forKeyedSubscript: "__native_ajaxBytes" as NSString)
        context.setObject(post, forKeyedSubscript: "__native_post" as NSString)
        context.setObject(postResponse, forKeyedSubscript: "__native_postResponse" as NSString)
        context.setObject(put, forKeyedSubscript: "__native_put" as NSString)
        context.setObject(getStore, forKeyedSubscript: "__native_getStore" as NSString)
        context.setObject(removeElements, forKeyedSubscript: "__native_removeElements" as NSString)
        context.setObject(getParents, forKeyedSubscript: "__native_getParents" as NSString)
    }

    private func installBaseBridge() {
        context.exceptionHandler = { context, exception in
            context?.exception = exception
        }

        let prelude = """
        // JavaScriptCore throws when an undeclared identifier is read on the
        // right-hand side of `var java = java || {}`.  Android/Legado scripts
        // expect these namespaces to be created on a fresh context, so guard
        // every root namespace with `typeof` before reusing an existing value.
        if (typeof java === 'undefined' || java === null) java = {};
        // Legado scripts use browser globals even in a bare JavaScriptCore context.
        // JavaScriptCore on older iOS versions has no globalThis; use the
        // current global object while keeping `window` as a writable facade.
        if (typeof globalThis === 'undefined' || globalThis === null) {
          globalThis = this;
        }
        if (typeof window === 'undefined' || window === null) window = globalThis;
        if (typeof document === 'undefined' || document === null) document = {};
        var __cache_store = (typeof __cache_store !== 'undefined' && __cache_store) || {};
        var __field_store = (typeof __field_store !== 'undefined' && __field_store) || {};
        var cache = {
          get: function(key) { var value = __cache_store[String(key)]; return value == null ? '' : value; },
          put: function(key, value) { __cache_store[String(key)] = value; return value; },
          getFromCache: function(key) { return this.get(key); },
          putInCache: function(key, value, time) { return this.put(key, value); }
        };
        // SourceRead's JSON/HTML hybrid helper.  Keep both constructor and
        // factory spellings used by Android Legado sources.
        if (typeof JXNode === 'undefined' || JXNode === null) JXNode = function(value) { return __nativeJXNode.create(value); };
        JXNode.create = function(value) { return __nativeJXNode.create(value); };
        var jxNode = function(value) { return __nativeJXNode.create(value); };
        java.urlEncode = function(value) { return __native_urlEncode(String(value)); };
        java.encodeURI = function(value, charset) {
          return String(__nativeLegado.invoke({ method: 'encodeURI', args: [String(value), charset == null ? '' : String(charset)] }) || '');
        };
        java.encodeURIComponent = java.urlEncode;
        java.decodeURI = function(value) { return __native_urlDecode(String(value)); };
        java.decodeURIComponent = java.decodeURI;
        java.base64Encode = function(value) {
          if (value && typeof value !== 'string' && value.length != null) return __native_base64EncodeBytes(value);
          return __native_base64Encode(String(value));
        };
        java.base64Decode = function(value) { return __native_base64Decode(String(value)); };
        java.base64DecodeToByteArray = function(value) {
          var encoded = value && value.length != null && typeof value !== 'string'
            ? String(__native_bytesToString(__javaBytes(value)) || '')
            : String(value == null ? '' : value);
          return __asJavaList(__native_base64DecodeBytes(encoded));
        };
        java.base64DecodeToString = java.base64Decode;
        java.base64Decoder = java.base64Decode;
        java.base64 = java.base64Encode;
        java.unbase64 = java.base64Decode;
        java.decodeBase64 = java.base64Decode;
        java.base64UrlEncode = function(value, withoutPadding) {
          var encoded = java.base64Encode(value).replace(/\\+/g, '-').replace(/\\//g, '_');
          return withoutPadding === false ? encoded : encoded.replace(/=+$/g, '');
        };
        java.base64UrlDecode = function(value) {
          return java.base64Decode(String(value == null ? '' : value).replace(/-/g, '+').replace(/_/g, '/'));
        };
        java.inflate = function(value) {
          // Return a scalar across JSExport. Older JavaScriptCore releases can
          // expose an NSArray result as a host object with no indexed members;
          // hex lets us rebuild a real JavaScript Array without that loss.
          return __hexToJavaBytes(__nativeLegado.invoke({ method: 'inflateHex', args: [value] }));
        };
        java.gunzip = function(value) {
          return __hexToJavaBytes(__nativeLegado.invoke({ method: 'gunzipHex', args: [value] }));
        };
        java.copyOfRange = function(value, start, end) {
          var source = __javaBytes(value);
          var from = Math.max(0, Number(start || 0)), to = Math.max(from, Number(end || 0));
          var out = source.slice(from, to);
          while (out.length < to - from) out.push(0);
          return __asJavaList(out);
        };
        java.asList = function() {
          if (arguments.length === 1 && arguments[0] && typeof arguments[0] !== 'string') return __asJavaList(__javaArray(arguments[0]));
          return __asJavaList(Array.prototype.slice.call(arguments));
        };
        java.strToBytes = function(value) { return __asJavaList(__native_stringToBytes(String(value || ''))); };
        java.bytesToStr = function(value) {
          var list = __javaArray(value), out = '', i = 0;
          while (i < list.length) {
            var first = Number(list[i++] == null ? 0 : list[i - 1]) & 255;
            if (first < 0x80) { out += String.fromCharCode(first); continue; }
            var code = 0, needed = 0;
            if ((first & 0xe0) === 0xc0) { code = first & 0x1f; needed = 1; }
            else if ((first & 0xf0) === 0xe0) { code = first & 0x0f; needed = 2; }
            else if ((first & 0xf8) === 0xf0) { code = first & 0x07; needed = 3; }
            else { out += '\\ufffd'; continue; }
            var valid = true;
            for (var j = 0; j < needed; j++) {
              if (i >= list.length) { valid = false; break; }
              var continuation = Number(list[i++] == null ? 0 : list[i - 1]) & 255;
              if ((continuation & 0xc0) !== 0x80) { valid = false; break; }
              code = (code << 6) | (continuation & 0x3f);
            }
            if (!valid || (needed === 1 && code < 0x80) || (needed === 2 && code < 0x800) || (needed === 3 && code < 0x10000) || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) {
              out += '\\ufffd';
              continue;
            }
            if (code <= 0xffff) out += String.fromCharCode(code);
            else { code -= 0x10000; out += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff)); }
          }
          return out;
        };
        java.hexEncodeToString = function(value) {
          var list = value && value.length != null ? value : __native_stringToBytes(String(value || ''));
          var out = '';
          for (var i = 0; i < list.length; i++) { var h = Number(list[i]).toString(16); out += h.length < 2 ? '0' + h : h; }
          return out;
        };
        java.hexDecodeToString = function(value) {
          var text = String(value || '').replace(/\\s+/g, '');
          if (text.length % 2) return '';
          var bytes = [];
          for (var i = 0; i < text.length; i += 2) {
            var n = parseInt(text.substring(i, i + 2), 16);
            if (isNaN(n)) return '';
            bytes.push(n);
          }
          return String(__native_bytesToString(bytes) || '');
        };
        java.getStr = function(key, fallback) {
          var value = java.get(key);
          if (value === '' && arguments.length > 1) return String(fallback == null ? '' : fallback);
          return value == null ? '' : String(value);
        };
        java.getJson = function(value, fallback) {
          if (value !== null && typeof value === 'object') return value;
          try { return JSON.parse(String(value == null ? '' : value)); }
          catch (_) {
            if (arguments.length > 1 && fallback !== undefined) {
              if (fallback !== null && typeof fallback === 'object') return fallback;
              try { return JSON.parse(String(fallback)); } catch (_) {}
            }
            return {};
          }
        };
        java.putJson = function(key, value) { return java.put(String(key || ''), JSON.stringify(value == null ? {} : value)); };
        java.postForm = function(url, body, headers) {
          var merged = {};
          if (headers && typeof headers === 'object') for (var k in headers) merged[k] = headers[k];
          if (!merged['Content-Type'] && !merged['content-type']) merged['Content-Type'] = 'application/x-www-form-urlencoded';
          // Preserve Legado's query-style separators but make the common
          // encoded space readable in the native request envelope.
          var formBody = String(body == null ? '' : body).replace(/%20/gi, ' ');
          return java.post(url, formBody, merged);
        };
        java.md5 = function(value) { return __native_md5(String(value)); };
        java.md5Encode = java.md5;
        java.md5Encode16 = function(value) { return java.md5(value).substring(8, 24); };
        java.hexMd5 = java.md5;
        java.MD5 = java.md5;
        java.sha1 = function(value) { return __native_sha1(String(value)); };
        java.SHA1 = java.sha1;
        java.sha256 = function(value) { return __native_sha256(String(value)); };
        java.SHA256 = java.sha256;
        java.digestHex = function(value, algorithm) { return __native_digestHex(String(value || ''), String(algorithm || 'sha256')); };
        java.sha256Encode = function(value) { return java.digestHex(value, 'sha256'); };
        java.sha1Encode = function(value) { return java.digestHex(value, 'sha1'); };
        java.sha512Encode = function(value) { return java.digestHex(value, 'sha512'); };
        java.sha224Encode = function(value) { return java.digestHex(value, 'sha224'); };
        java.sha384Encode = function(value) { return java.digestHex(value, 'sha384'); };
        java.sha348Encode = java.sha384Encode;
        java.ripemd160Encode = function(value) { return java.digestHex(value, 'ripemd160'); };
        java.rsaEncrypt = function(value, key) { return String(__nativeLegado.invoke({ method: 'rsaEncrypt', args: [String(value || ''), String(key || '')] }) || ''); };
        java.rsaDecrypt = function(value, key) { return String(__nativeLegado.invoke({ method: 'rsaDecrypt', args: [String(value || ''), String(key || '')] }) || ''); };
        java.RSA_encrypt = function(value, key) { return java.rsaEncrypt(value, key); };
        java.RSA_decrypt = function(value, key) { return java.rsaDecrypt(value, key); };
        java.RSA_encryptWithPrivate = function(value, key) { return String(__nativeLegado.invoke({ method: 'RSA_encryptWithPrivate', args: [String(value || ''), String(key || '')] }) || ''); };
        java.RSA_decryptWithPublic = function(value, key) { return String(__nativeLegado.invoke({ method: 'RSA_decryptWithPublic', args: [String(value || ''), String(key || '')] }) || ''); };
        java.digestBase64Str = function(value, algorithm) { return java.base64Encode(__hexToJavaBytes(java.digestHex(value, algorithm || 'sha256'))); };
        java.uriEncode = function(value) { return java.encodeURI(value); };
        java.uriDecode = function(value) { return java.decodeURI(value); };
        java.t2s = function(value) { return String(value == null ? '' : value); };
        java.s2t = java.t2s;
        java.toNumChapter = java.t2s;
        java.timeFormatUTC = function(timestamp) { return new Date(timestamp == null ? Date.now() : Number(timestamp)).toISOString().replace('T', ' ').substring(0, 19); };
        java.putCache = function(key, value) { return cache.put(key, value); };
        java.getCache = function(key) { return cache.get(key); };
        java.putField = function(key, value) { __field_store[String(key)] = value; return value; };
        java.getField = function(key) { var value = __field_store[String(key)]; return value == null ? '' : value; };
        java.getFromCache = java.getCache;
        java.putInCache = java.putCache;
        java.HMacHex = function(value, algorithm, key) { return __native_hmacHex(String(value || ''), String(algorithm || 'HmacSHA1'), String(key || '')); };
        java.hmacSHA256 = function(value, key) { return java.HMacHex(value, 'HmacSHA256', key); };
        java.HMacBase64 = function(value, algorithm, key) { return __native_hmacBase64(String(value || ''), String(algorithm || 'HmacSHA1'), String(key || '')); };
        java.timeFormat = function(timestamp, format) {
          return __native_timeFormat(Number(timestamp), String(format || 'yyyy-MM-dd HH:mm:ss'));
        };
        java.getTime = function() { return Date.now(); };
        java.currentTimeMillis = java.getTime;
        java.now = java.getTime;
        java.randomUUID = function() {
          return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0;
            var v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
          });
        };
        java.uuid = java.randomUUID;
        java.androidId = function() { return 'sourcereadswift-ios'; };
        function __defaultHtml() {
          if (typeof result !== 'undefined') return String(result);
          if (typeof html !== 'undefined') return String(html);
          return '';
        }
        function __defaultBaseUrl() {
          return String(typeof baseUrl === 'undefined' ? '' : baseUrl);
        }
        try {
          Object.defineProperty(document, 'documentElement', { configurable: true, get: function() {
            try { return Packages.org.jsoup.Jsoup.parse(__defaultHtml(), __defaultBaseUrl()); } catch (_) { return null; }
          }});
          Object.defineProperty(document, 'cookie', { configurable: true,
            get: function() { return java.getCookie(__defaultBaseUrl()); },
            set: function(value) { return cookie.setCookie(__defaultBaseUrl(), String(value || '')); }
          });
        } catch (_) {}
        window.document = document;
        window.java = java;
        if (!String.prototype.contains) {
          String.prototype.contains = function(value) { return this.indexOf(String(value)) >= 0; };
        }
        if (!String.prototype.startsWith) {
          String.prototype.startsWith = function(value) { return this.indexOf(String(value)) === 0; };
        }
        if (!String.prototype.endsWith) {
          String.prototype.endsWith = function(value) {
            value = String(value);
            return this.substring(this.length - value.length) === value;
          };
        }
        if (!String.prototype.equals) {
          String.prototype.equals = function(value) { return String(this) === String(value); };
        }
        if (!String.prototype.equalsIgnoreCase) {
          String.prototype.equalsIgnoreCase = function(value) {
            return String(this).toLowerCase() === String(value).toLowerCase();
          };
        }
        if (!String.prototype.replaceAll) {
          String.prototype.replaceAll = function(search, replacement) {
            return String(this).split(String(search)).join(String(replacement));
          };
        }
        if (!String.prototype.getBytes) {
          String.prototype.getBytes = function(charset) {
            var name = charset == null ? '' : String(charset);
            return __asJavaList(name ? __native_stringToBytesCharset(String(this), name) : __native_stringToBytes(String(this)));
          };
        }
        function __asJavaList(list) {
          // Never mutate an NSArray/host object returned by JavaScriptCore.  A
          // native NSArray can expose no writable indexed properties, causing
          // `slice.call(...)` and JSON.stringify to silently produce `[]`.
          // Always copy into a real JS Array before adding Java-style aliases.
          if (!Array.isArray(list)) list = __javaArray(list);
          list.get = function(index) { return list[Number(index)]; };
          list.first = function() { return list.length ? list[0] : null; };
          list.last = function() { return list.length ? list[list.length - 1] : null; };
          list.size = function() { return list.length; };
          list.isEmpty = function() { return list.length === 0; };
          list.toArray = function() { return Array.prototype.slice.call(list); };
          list.contains = function(value) { return list.indexOf(value) >= 0; };
          return list;
        }
        function __javaArray(value) {
          if (value == null) return [];
          if (typeof value === 'string') return Array.prototype.slice.call(__native_stringToBytes(value));
          if (typeof value.toArray === 'function') {
            try { return __javaArray(value.toArray()); } catch (_) {}
          }
          var length = value.length;
          if (length == null && value.count != null) {
            try { length = typeof value.count === 'function' ? value.count() : value.count; } catch (_) {}
          }
          if (length == null || isNaN(Number(length))) return [];
          length = Math.max(0, Number(length));
          var out = [];
          for (var i = 0; i < length; i++) {
            var item;
            try { item = value[i]; } catch (_) { item = null; }
            if (item == null && typeof value.objectAtIndex === 'function') {
              try { item = value.objectAtIndex(i); } catch (_) {}
            }
            out.push(item);
          }
          return out;
        }
        function __javaBytes(value) {
          return __javaArray(value).map(function(item) { return Number(item == null ? 0 : item) & 255; });
        }
        function __hexToJavaBytes(value) {
          var text = String(value == null ? '' : value).replace(/\\s+/g, '').toLowerCase();
          if ((text.length & 1) !== 0) return __asJavaList([]);
          var out = [];
          for (var i = 0; i < text.length; i += 2) {
            var byte = parseInt(text.substring(i, i + 2), 16);
            if (isNaN(byte)) return __asJavaList([]);
            out.push(byte & 255);
          }
          return __asJavaList(out);
        }
        function __jsonPathTokens(path) {
          var text = String(path || '');
          if (text.indexOf('$..') === 0) text = '**.' + text.substring(3);
          else if (text.indexOf('$.') === 0) text = text.substring(2);
          else if (text.charAt(0) === '$') text = text.substring(1);
          var tokens = [];
          var buffer = '';
          function flush() {
            var value = buffer.trim();
            if (value) tokens.push(value);
            buffer = '';
          }
          for (var i = 0; i < text.length;) {
            var ch = text.charAt(i);
            if (ch === '[') {
              flush();
              var depth = 1;
              var quote = '';
              var escaped = false;
              var cursor = i + 1;
              var token = '';
              for (; cursor < text.length && depth > 0; cursor++) {
                var c = text.charAt(cursor);
                if (quote) {
                  token += c;
                  if (escaped) escaped = false;
                  else if (c === '\\\\') escaped = true;
                  else if (c === quote) quote = '';
                } else if (c === '"' || c === "'") { quote = c; token += c; }
                else if (c === '[') { depth++; token += c; }
                else if (c === ']') { depth--; if (depth > 0) token += c; }
                else token += c;
              }
              token = token.trim().replace(/^['"]|['"]$/g, '');
              if (token) tokens.push(token);
              i = cursor;
              continue;
            }
            if (ch === '.') {
              flush();
              if (text.charAt(i + 1) === '.') { tokens.push('**'); i += 2; }
              else i++;
              continue;
            }
            if (ch === '/') { flush(); i++; continue; }
            buffer += ch;
            i++;
          }
          flush();
          return tokens;
        }
        function __jsonChildren(value) {
          var children = [];
          if (value && typeof value === 'object' && typeof value !== 'string') {
            if (typeof value.length === 'number') for (var i = 0; i < value.length; i++) children.push(value[i]);
            else for (var key in value) children.push(value[key]);
          }
          return children;
        }
        function __jsonArray(value) {
          if (value && typeof value !== 'string' && typeof value.length === 'number') {
            var array = [];
            for (var i = 0; i < value.length; i++) array.push(value[i]);
            return array;
          }
          return null;
        }
        function __jsonFlatten(value, output) {
          if (value && typeof value.length === 'number' && typeof value !== 'string') {
            for (var i = 0; i < value.length; i++) __jsonFlatten(value[i], output);
          } else output.push(value);
        }
        function __jsonTruthy(value) {
          if (value === null || value === undefined || value === false) return false;
          if (typeof value === 'number') return value !== 0;
          if (typeof value === 'string') return value !== '' && value.toLowerCase() !== 'false';
          return true;
        }
        function __jsonLookup(value, path) {
          var key = String(path || '').replace(/^@\\.?/, '');
          if (!key || key === '@') return value;
          var current = value;
          var parts = key.split('.').filter(function(part) { return part !== ''; });
          for (var i = 0; i < parts.length; i++) {
            if (current == null || current[parts[i]] === undefined) return undefined;
            current = current[parts[i]];
          }
          return current;
        }
        function __jsonFilterMatch(value, expression) {
          var text = String(expression || '').trim();
          var operators = ['!=', '==', '>=', '<=', '>', '<', '='];
          var op = null;
          var position = -1;
          for (var i = 0; i < operators.length; i++) {
            position = text.indexOf(operators[i]);
            if (position >= 0) { op = operators[i]; break; }
          }
          var actual;
          if (op) {
            actual = __jsonLookup(value, text.substring(0, position).trim());
            var expected = text.substring(position + op.length).trim().replace(/^['"]|['"]$/g, '');
            if (actual === undefined || actual === null) return false;
            var lhs = String(typeof actual === 'object' ? JSON.stringify(actual) : actual);
            var leftNumber = Number(lhs), rightNumber = Number(expected);
            if (lhs !== '' && isFinite(leftNumber) && isFinite(rightNumber)) {
              if (op === '==' || op === '=') return leftNumber === rightNumber;
              if (op === '!=') return leftNumber !== rightNumber;
              if (op === '>') return leftNumber > rightNumber;
              if (op === '<') return leftNumber < rightNumber;
              if (op === '>=') return leftNumber >= rightNumber;
              if (op === '<=') return leftNumber <= rightNumber;
            }
            if (op === '==' || op === '=') return lhs === expected;
            if (op === '!=') return lhs !== expected;
            return false;
          }
          return __jsonTruthy(__jsonLookup(value, text));
        }
        function __jsonWalk(current, tokens, index) {
          if (index >= tokens.length) return current;
          var token = tokens[index];
          if (token === '**') {
            var recursive = [];
            var direct = __jsonWalk(current, tokens, index + 1);
            if (direct !== undefined && direct !== null) __jsonFlatten(direct, recursive);
            var children = __jsonChildren(current);
            for (var i = 0; i < children.length; i++) {
              var nested = __jsonWalk(children[i], tokens, index);
              if (nested !== undefined && nested !== null) __jsonFlatten(nested, recursive);
            }
            return recursive;
          }
          var array = __jsonArray(current);
          if (token.indexOf('?(') === 0 && token.charAt(token.length - 1) === ')' && array) {
            var expression = token.substring(2, token.length - 1);
            var filtered = array.filter(function(item) { return __jsonFilterMatch(item, expression); });
            return __jsonWalk(filtered, tokens, index + 1);
          }
          if (array) {
            if (token === '*') return __jsonWalk(array, tokens, index + 1);
            if (/^-?\\d+$/.test(token)) {
              var numeric = Number(token); if (numeric < 0) numeric = array.length + numeric;
              return numeric >= 0 && numeric < array.length ? __jsonWalk(array[numeric], tokens, index + 1) : undefined;
            }
            var mapped = [];
            for (var j = 0; j < array.length; j++) {
              var itemResult = __jsonWalk(array[j], tokens, index);
              if (itemResult !== undefined && itemResult !== null) __jsonFlatten(itemResult, mapped);
            }
            return mapped;
          }
          if (current && typeof current === 'object') {
            if (token === '*') {
              var values = __jsonChildren(current);
              return __jsonWalk(values, tokens, index + 1);
            }
            if (current[token] !== undefined) return __jsonWalk(current[token], tokens, index + 1);
          }
          return undefined;
        }
        function __jsonRuleValues(documentText, rule) {
          var root;
          try { root = typeof documentText === 'object' ? documentText : JSON.parse(String(documentText || '')); } catch (_) { return []; }
          var tokens = __jsonPathTokens(rule);
          if (!tokens.length) return [root];
          var result = __jsonWalk(root, tokens, 0);
          var values = [];
          if (result !== undefined && result !== null) __jsonFlatten(result, values);
          return values;
        }
        function __jsonRuleString(documentText, rule) {
          return __jsonRuleValues(documentText, rule).map(function(value) {
            return value == null ? '' : (typeof value === 'object' ? JSON.stringify(value) : String(value));
          }).join('\\n');
        }
        function __jsonRuleList(documentText, rule) {
          return __asJavaList(__jsonRuleValues(documentText, rule).map(function(value) {
            return value == null ? '' : (typeof value === 'object' ? JSON.stringify(value) : String(value));
          }));
        }
        if (!Array.prototype.get) {
          Array.prototype.get = function(index) { return this[Number(index)]; };
        }
        if (!Array.prototype.size) {
          Array.prototype.size = function() { return this.length; };
        }
        if (!Array.prototype.isEmpty) {
          Array.prototype.isEmpty = function() { return this.length === 0; };
        }
        // Android's java.util.List proxies are frequently consumed through
        // JavaScript's Array prototype (not only as an own property). Keep
        // both spellings so `ajaxAll(...).first()` works across JSCore builds.
        if (!Array.prototype.first) {
          Array.prototype.first = function() { return this.length ? this[0] : null; };
        }
        if (!Array.prototype.last) {
          Array.prototype.last = function() { return this.length ? this[this.length - 1] : null; };
        }
        // Legado exposes these helpers in both forms:
        //   java.getString(rule) and java.getString(html, rule)
        // The boolean second argument is an isUrl flag, not HTML.
        java.getString = function(input, rule) {
          if (arguments.length <= 1 || typeof rule === 'boolean') {
            return __native_getString(__defaultHtml(), String(input), __defaultBaseUrl());
          }
          // Flutter/Legado also uses getString(key, default). Only treat the
          // two-argument form as a parser overload when the first value is
          // clearly HTML/JSON or the second value clearly looks like a rule.
          var first = String(input == null ? '' : input);
          var second = String(rule == null ? '' : rule);
          var firstTrimmed = first.trim ? first.trim() : first;
          var looksLikeDocument = firstTrimmed.charAt(0) === '<' || firstTrimmed.charAt(0) === '[' || firstTrimmed.charAt(0) === '{';
          var looksLikeRule = second.indexOf('.') >= 0 || second.indexOf('#') >= 0 || second.indexOf('@') >= 0 || second.indexOf('>') >= 0 || second.indexOf('$') === 0 || second.indexOf('[') >= 0 || second.indexOf(':') >= 0;
          if (!looksLikeDocument && !looksLikeRule) {
            var stored = java.get(first);
            return stored === '' ? second : String(stored);
          }
          if ((input && typeof input === 'object') || ((firstTrimmed.charAt(0) === '[' || firstTrimmed.charAt(0) === '{') && second.charAt(0) === '$')) {
            if (second.charAt(0) === '$') return __jsonRuleString(input, second);
          }
          return __native_getString(String(input), String(rule), __defaultBaseUrl());
        };
        java.getStringWithDefault = function(input, rule, fallback) {
          var value = java.getString(input, rule);
          return value === '' && fallback != null ? String(fallback) : value;
        };
        java.getStringList = function(input, rule) {
          var useDefaultHtml = arguments.length <= 1 || typeof rule === 'boolean';
          var pageHtml = useDefaultHtml ? __defaultHtml() : String(input);
          var actualRule = useDefaultHtml ? String(input) : String(rule);
          if (!useDefaultHtml && ((input && typeof input === 'object') || (/^\\s*[\\[{]/.test(pageHtml) && /^\\$/.test(actualRule)))) {
            if (/^\\$/.test(actualRule)) return __jsonRuleList(input, actualRule);
          }
          var list = __native_getStringList(pageHtml, actualRule, __defaultBaseUrl());
          var out = [];
          for (var i = 0; i < list.length; i++) out.push(String(list[i]));
          return __asJavaList(out);
        };
        java.getElements = function(input, rule) {
          var useDefaultHtml = arguments.length <= 1 || typeof rule === 'boolean';
          var pageHtml = useDefaultHtml ? __defaultHtml() : String(input);
          var actualRule = useDefaultHtml ? String(input) : String(rule);
          if (useDefaultHtml) {
            __nativeRule.setContent(pageHtml);
            return __nativeRule.getElements(actualRule);
          }
          // The native bridge is document-scoped; return a Jsoup-like selection
          // proxy for the explicit HTML overload so callers can still chain text,
          // attr, first/get/eachText and remove operations.
          return __makeJsoupSelection({ html: pageHtml }, actualRule, __defaultBaseUrl());
        };
        java.removeElements = function(input, selector) {
          var pageHtml = arguments.length > 1 ? String(input) : __defaultHtml();
          var actualSelector = arguments.length > 1 ? String(selector) : String(input);
          return __native_removeElements(pageHtml, actualSelector);
        };
        java.getParents = function(input, selector, baseUrlValue) {
          var pageHtml = arguments.length > 1 ? String(input) : __defaultHtml();
          var actualSelector = arguments.length > 1 ? String(selector) : String(input);
          var actualBase = arguments.length > 2 ? String(baseUrlValue || '') : __defaultBaseUrl();
          return __asJavaList(__native_getParents(pageHtml, actualSelector, actualBase));
        };
        java.getInt = function(input, fallback) {
          var stored = java.getVar(input);
          var value = stored !== '' ? stored : java.getString(input);
          var parsed = parseInt(String(value), 10);
          return isNaN(parsed) ? Number(fallback || 0) : parsed;
        };
        java.getLong = java.getInt;
        java.getDouble = function(input, fallback) {
          var stored = java.getVar(input);
          var value = stored !== '' ? stored : java.getString(input);
          var parsed = parseFloat(String(value));
          return isNaN(parsed) ? Number(fallback || 0) : parsed;
        };
        java.getElement = function(rule) {
          __nativeRule.setContent(__defaultHtml());
          return __nativeRule.getElement(String(rule || ''));
        };
        function __bridgeString(value) {
          if (value === undefined || value === null) return '';
          if (typeof value === 'string') return value;
          return JSON.stringify(value);
        }
        function __bridgeStored(name) {
          return __native_getStore(String(name));
        }
        // Response/body compatibility: Android Legado sources use both the
        // legacy `response.statusCode` property and the newer callable
        // `response.statusCode()`/`response.code` forms.  A callable Number
        // object keeps both spellings coercible in concatenation/JSON while
        // still allowing invocation.
        function __bridgeBody(value) {
          var body = new String(value == null ? '' : String(value));
          body.string = function() { return String(body); };
          body.text = body.string;
          body.bytes = function() { return __asJavaList(__native_stringToBytes(String(body))); };
          body.byteArray = body.bytes;
          body.length = String(body).length;
          body.json = function() {
            try { return JSON.parse(String(body)); } catch (_) { return {}; }
          };
          return body;
        }
        function __bridgeHeaders(value) {
          var source = value || {};
          var map = {};
          for (var key in source) if (Object.prototype.hasOwnProperty.call(source, key)) map[String(key)] = String(source[key] == null ? '' : source[key]);
          function find(name) {
            var wanted = String(name || '').toLowerCase();
            for (var key in map) if (String(key).toLowerCase() === wanted) return map[key];
            return '';
          }
          function contains(name) {
            var wanted = String(name || '').toLowerCase();
            for (var key in map) if (String(key).toLowerCase() === wanted) return true;
            return false;
          }
          map.get = function(name) { return find(name); };
          map.getIgnoreCase = map.get;
          map.has = contains;
          map.containsKey = map.has;
          map.keys = function() { var out = []; for (var key in map) if (typeof map[key] === 'string') out.push(key); return __asJavaList(out); };
          map.values = function() { var out = []; for (var key in map) if (typeof map[key] === 'string') out.push(map[key]); return __asJavaList(out); };
          map.entries = function() { var out = []; for (var key in map) if (typeof map[key] === 'string') out.push([key, map[key]]); return __asJavaList(out); };
          map.toJSON = function() { var out = {}; for (var key in map) if (typeof map[key] === 'string') out[key] = map[key]; return out; };
          map.toString = function() { return JSON.stringify(map.toJSON()); };
          return map;
        }
        function __bridgeCookies(headers) {
          var raw = '';
          for (var key in (headers || {})) if (String(key).toLowerCase() === 'set-cookie') raw = String(headers[key] || '');
          // A Set-Cookie header may contain commas in Expires=...; only split
          // when the comma is followed by a new cookie-pair (not an attribute).
          var values = raw.split(/,\\s*(?=[^;=,]+=[^;=,]+)/).filter(function(item) { return item.trim() !== ''; });
          var cookies = {};
          for (var i = 0; i < values.length; i++) {
            var pair = values[i].split(';')[0];
            var pos = pair.indexOf('=');
            if (pos > 0) cookies[pair.substring(0, pos).trim()] = pair.substring(pos + 1).trim();
          }
          cookies.get = function(name) { return cookies[String(name || '')] || ''; };
          cookies.containsKey = function(name) { return Object.prototype.hasOwnProperty.call(cookies, String(name || '')); };
          cookies.toJSON = function() { var out = {}; for (var key in cookies) if (typeof cookies[key] === 'string') out[key] = cookies[key]; return out; };
          return cookies;
        }
        function __bridgeStatusCode(value) {
          var number = Number(value == null || value === '' ? 200 : value);
          if (!isFinite(number)) number = 200;
          var callable = function() { return number; };
          callable.valueOf = function() { return number; };
          callable.toString = function() { return String(number); };
          return callable;
        }
        function __bridgeResponse(text, responseUrl, responseMeta) {
          var meta = responseMeta || {};
          var value = meta.body !== undefined ? String(meta.body || '') : String(text || '');
          var finalUrl = meta.url !== undefined ? String(meta.url || responseUrl || '') : String(responseUrl || '');
          var code = meta.statusCode !== undefined ? Number(meta.statusCode) : 200;
          var responseHeaders = meta.headers || {};
          var bodyValue = __bridgeBody(value);
          var statusValue = __bridgeStatusCode(code);
          var headerMap = __bridgeHeaders(responseHeaders);
          var response = {
            statusCode: statusValue,
            // `code` and `status` are numeric aliases in Fetch-like sources;
            // `statusCode` remains the callable/legacy-compatible member.
            code: code,
            status: code,
            ok: code >= 200 && code < 300,
            body: function() { return bodyValue; },
            text: function() { return bodyValue; },
            json: function() { return bodyValue.json(); },
            url: function() { return finalUrl; },
            finalUrl: function() { return finalUrl; },
            header: function(name) { return headerMap.get(name); },
            headers: function() { return headerMap; },
            cookies: function() { return __bridgeCookies(responseHeaders); },
            cookie: function() { return this.header('set-cookie') || this.header('cookie'); },
            // A number of Android/Flutter sources call `fetch(...).match(...)`
            // directly. Delegate common String operations to the response
            // body while retaining the modern response API (`json`, `text`).
            match: function(pattern, flags) { return String(value).match(pattern, flags); },
            replace: function(search, replacement) { return String(value).replace(search, replacement); },
            replaceAll: function(search, replacement) { return String(value).split(String(search)).join(String(replacement)); },
            split: function(separator, limit) { return String(value).split(separator, limit); },
            trim: function() { return String(value).trim(); },
            indexOf: function(search, position) { return String(value).indexOf(String(search), position); },
            includes: function(search, position) { return String(value).indexOf(String(search), position) >= 0; },
            substring: function(start, end) { return String(value).substring(start, end); },
            substr: function(start, length) { return String(value).substr(start, length); },
            charAt: function(index) { return String(value).charAt(index); },
            length: value.length,
            toString: function() { return value; },
            valueOf: function() { return value; }
          };
          // The native bridge is synchronous, but many Android sources use
          // Promise-style response handling. A response is thenable and the
          // callback is invoked immediately with the same materialized value.
          response.then = function(onFulfilled, onRejected) {
            try {
              var next = typeof onFulfilled === 'function' ? onFulfilled(response) : response;
              return __syncPromise(next);
            } catch (error) {
              return __syncPromiseRejected(error);
            }
          };
          response.catch = function(onRejected) { return __syncPromise(response).catch(onRejected); };
          response.finally = function(onFinally) { return __syncPromise(response).finally(onFinally); };
          return response;
        }
        // Minimal synchronous Promise facade. It deliberately does not queue
        // work: JavaScriptCore callbacks must return before Swift can continue.
        function __syncPromise(value, rejected) {
          if (!rejected && value && value.__state && typeof value.then === 'function') return value;
          var state = rejected ? 'rejected' : 'fulfilled';
          var promise = {
            __value: value,
            __state: state,
            then: function(onFulfilled, onRejected) {
              try {
                if (promise.__state === 'fulfilled') {
                  return __syncPromise(typeof onFulfilled === 'function' ? onFulfilled(promise.__value) : promise.__value);
                }
                if (typeof onRejected === 'function') return __syncPromise(onRejected(promise.__value));
                return __syncPromiseRejected(promise.__value);
              } catch (error) { return __syncPromiseRejected(error); }
            },
            catch: function(onRejected) { return promise.then(null, onRejected); },
            finally: function(onFinally) {
              try {
                var next = typeof onFinally === 'function' ? onFinally() : null;
                if (next && typeof next.then === 'function') {
                  return next.then(function() { return promise; });
                }
                return promise;
              } catch (error) { return __syncPromiseRejected(error); }
            },
            valueOf: function() { return promise.__value; },
            toString: function() { return String(promise.__value == null ? '' : promise.__value); }
          };
          return promise;
        }
        function __syncPromiseRejected(error) { return __syncPromise(error, true); }
        // Always prefer the synchronous constructor when the host exposes a
        // native Promise. Native `then` callbacks are queued on a microtask,
        // which means a Legado rule would otherwise return a pending Promise
        // to Swift before its callback has produced the value.
        function __syncPromiseConstructor(executor) {
          var settled = false, value, rejected = false;
          function resolve(next) { if (!settled) { settled = true; value = next; } }
          function reject(error) { if (!settled) { settled = true; value = error; rejected = true; } }
          try { if (typeof executor === 'function') executor(resolve, reject); }
          catch (error) { reject(error); }
          return __syncPromise(value, rejected);
        }
        try { Promise = __syncPromiseConstructor; } catch (_) {
          if (typeof Promise === 'undefined' || Promise === null) Promise = __syncPromiseConstructor;
        }
        if (typeof Promise !== 'undefined' && Promise !== null) {
          Promise.resolve = function(value) { return __syncPromise(value); };
          Promise.reject = function(error) { return __syncPromiseRejected(error); };
          Promise.all = function(values) {
            var list = values && typeof values.length === 'number' ? values : [], out = [];
            for (var i = 0; i < list.length; i++) {
              var item = list[i];
              if (item && item.__state) {
                if (item.__state === 'rejected') return __syncPromiseRejected(item.__value);
                item = item.__value;
              }
              out.push(item);
            }
            return __syncPromise(out);
          };
          Promise.race = function(values) {
            var list = values && typeof values.length === 'number' ? values : [];
            return list.length ? __syncPromise(list[0] && list[0].__state ? list[0].__value : list[0]) : __syncPromise([]);
          };
        }
        if (typeof queueMicrotask === 'undefined') queueMicrotask = function(callback) {
          if (typeof callback === 'function') callback();
        };
        if (typeof setTimeout === 'undefined') setTimeout = function(callback, _) {
          if (typeof callback === 'function') callback();
          return 0;
        };
        if (typeof clearTimeout === 'undefined') clearTimeout = function(_) {};
        if (typeof URLSearchParams === 'undefined') {
          URLSearchParams = function(init) {
            var pairs = [];
            var input = init || '';
            if (typeof input === 'object' && typeof input !== 'string') {
              for (var key in input) if (Object.prototype.hasOwnProperty.call(input, key)) pairs.push([String(key), String(input[key])]);
            } else {
              String(input).replace(/^\\?/, '').split('&').forEach(function(part) {
                if (!part) return;
                var pieces = part.split('='), key = pieces.shift() || '', val = pieces.join('=');
                try { key = decodeURIComponent(key.replace(/\\+/g, ' ')); } catch (_) {}
                try { val = decodeURIComponent(val.replace(/\\+/g, ' ')); } catch (_) {}
                pairs.push([key, val]);
              });
            }
            this.append = function(key, value) { pairs.push([String(key), String(value)]); };
            this.set = function(key, value) { this.delete(key); this.append(key, value); };
            this.get = function(key) { key = String(key); for (var i = 0; i < pairs.length; i++) if (pairs[i][0] === key) return pairs[i][1]; return null; };
            this.getAll = function(key) { key = String(key); return pairs.filter(function(pair) { return pair[0] === key; }).map(function(pair) { return pair[1]; }); };
            this.has = function(key) { return this.get(key) !== null; };
            this.delete = function(key) { key = String(key); pairs = pairs.filter(function(pair) { return pair[0] !== key; }); };
            this.toString = function() { return pairs.map(function(pair) { return encodeURIComponent(pair[0]) + '=' + encodeURIComponent(pair[1]); }).join('&'); };
            this.forEach = function(callback) { pairs.forEach(function(pair) { callback(pair[1], pair[0], this); }, this); };
          };
        }
        if (typeof Headers === 'undefined') {
          Headers = function(init) {
            var map = {};
            if (init && typeof init === 'object') for (var key in init) map[String(key).toLowerCase()] = String(init[key]);
            this.get = function(key) { return map[String(key).toLowerCase()] || null; };
            this.has = function(key) { return Object.prototype.hasOwnProperty.call(map, String(key).toLowerCase()); };
            this.set = function(key, value) { map[String(key).toLowerCase()] = String(value); };
            this.append = this.set;
            this.delete = function(key) { delete map[String(key).toLowerCase()]; };
            this.toJSON = function() { return map; };
          };
        }
        if (typeof Response === 'undefined') {
          Response = function(body, init) {
            var text = String(body == null ? '' : body), options = init || {};
            this.status = Number(options.status || 200); this.ok = this.status >= 200 && this.status < 300;
            this.url = String(options.url || ''); this.headers = new Headers(options.headers || {});
            this.text = function() { return __syncPromise(text); };
            this.json = function() { try { return __syncPromise(JSON.parse(text)); } catch (error) { return __syncPromiseRejected(error); } };
            this.body = function() { return __syncPromise(text); };
          };
        }
        java.put = function(key, value) {
          return __nativeLegado.invoke({ method: 'put', args: [String(key), value] });
        };
        java.putVar = java.put;
        java.getVar = function(key) {
          return String(__nativeLegado.invoke({ method: 'get', args: [String(key)] }) || '');
        };
        java.getValue = java.getVar;
        java.removeVar = function(key) {
          return !!__nativeLegado.invoke({ method: 'remove', args: [String(key)] });
        };
        java.remove = java.removeVar;
        java.ajax = function(url, headers) {
          var target = String(url);
          return __bridgeResponse('', target, __native_ajaxResponse(target, __bridgeString(headers || '')));
        };
        java.get = function(url, headers) {
          var key = String(url);
          var value = __bridgeStored(key);
          if (value && key.indexOf('://') < 0 && key.charAt(0) !== '/') return value;
          if (key.indexOf('://') < 0 && key.charAt(0) !== '/') return '';
          return __bridgeResponse('', key, __native_ajaxResponse(key, __bridgeString(headers || '')));
        };
        java.fetch = function(url, options) {
          options = options || {};
          var method = String(options.method || 'GET').toUpperCase();
          if (method === 'POST' || options.body != null) {
            // Preserve Fetch/Legado request options in the directive text so the
            // native request parser and diagnostics can observe method/body/headers.
            var requestOptions = { method: method, body: options.body == null ? '' : options.body, headers: options.headers || {} };
            var target = String(url || '') + ',' + JSON.stringify(requestOptions) + '@Body:' + String(requestOptions.body || '');
            return __bridgeResponse('', String(url || ''), __native_ajaxResponse(target, ''));
          }
          var target = String(url);
          return __bridgeResponse('', target, __native_ajaxResponse(target, __bridgeString(options.headers || options)));
        };
        java.post = function(url, body, headers) {
          var target = String(url);
          return __bridgeResponse('', target, __native_postResponse(target, __bridgeString(body || ''), __bridgeString(headers || '')));
        };
        java.ajaxBytes = function(url, headers) {
          return __asJavaList(__native_ajaxBytes(String(url || ''), __bridgeString(headers || '')));
        };
        java.head = function(url, headers) {
          var target = String(url || '') + ',{"method":"HEAD","headers":' + __bridgeString(headers || {}) + '}';
          return __bridgeResponse('', String(url || ''), __native_ajaxResponse(target, ''));
        };
        java.getStrResponse = function(url, rule) {
          var response = java.ajax(url);
          var body = response && response.body ? String(response.body()) : String(response || '');
          if (rule == null || String(rule || '') === '') return body;
          return __native_getString(body, String(rule), String(typeof baseUrl === 'undefined' ? url : baseUrl));
        };
        java.getResponseCode = function(url, headers) {
          return Number(java.ajax(url, headers).statusCode || 0);
        };
        java.cacheFile = function(path, content) {
          return __nativeLegado.invoke({ method: 'cacheFile', args: [String(path || ''), content == null ? '' : String(content)] });
        };
        java.deleteFile = function(path) {
          return !!__nativeLegado.invoke({ method: 'deleteFile', args: [String(path || '')] });
        };
        java.importScript = function(scriptOrUrl) {
          var value = String(scriptOrUrl || '');
          if (/^data:/i.test(value)) {
            var comma = value.indexOf(',');
            if (comma >= 0) value = value.substring(comma + 1);
            try { value = decodeURIComponent(value); } catch (_) {}
          } else if (/^https?:/i.test(value)) {
            value = String(java.ajax(value).body() || '');
          }
          if (!value.trim()) return '';
          (0, eval)(value);
          return value;
        };
        java.ajaxAll = function(urls, headers) {
          var values = [];
          if (urls && typeof urls.length === 'number') {
            for (var i = 0; i < urls.length; i++) values.push(String(urls[i]));
          } else if (urls != null) {
            values.push(String(urls));
          }
          var out = [];
          // Keep status/headers/final URL for each response.  A number of
          // Android sources inspect Set-Cookie or Content-Type from ajaxAll;
          // routing through the metadata bridge avoids losing that information.
          var headerText = __bridgeString(headers || '');
            for (var j = 0; j < values.length; j++) {
            var target = values[j] || '';
            out.push(__bridgeResponse('', target, __native_ajaxResponse(target, headerText)));
          }
          return __asJavaList(out);
        };
        function __makeConnect(url) {
          var target = String(url || '');
          var config = { headers: {}, body: '', method: 'GET', doOutput: false, connectTimeout: 0, readTimeout: 0, response: null, output: null };
          function response() {
            if (config.response) return config.response;
            var headerText = __bridgeString(config.headers);
            var outgoingBody = config.body || '';
            if (!outgoingBody && config.output && typeof config.output.toByteArray === 'function') outgoingBody = String(__native_bytesToString(__javaBytes(config.output.toByteArray())) || '');
            if (config.method === 'POST' || config.method === 'PUT' || config.method === 'PATCH' || config.doOutput || outgoingBody) {
              config.response = __bridgeResponse('', target, __native_postResponse(target, outgoingBody, headerText));
            } else {
              config.response = __bridgeResponse('', target, __native_ajaxResponse(target, headerText));
            }
            return config.response;
          }
          var api = {
            setRequestProperty: function(key, value) { config.headers[String(key)] = String(value); config.response = null; return api; },
            addRequestProperty: function(key, value) { var name = String(key), next = String(value); config.headers[name] = config.headers[name] ? config.headers[name] + ', ' + next : next; config.response = null; return api; },
            getRequestProperty: function(key) { return config.headers[String(key)] == null ? null : config.headers[String(key)]; },
            header: function(key, value) {
              config.headers[String(key)] = String(value);
              config.response = null;
              return api;
            },
            headers: function(value) {
              if (value) {
                var parsed = value;
                if (typeof parsed === 'string') {
                  try { parsed = JSON.parse(parsed); } catch (_) { parsed = {}; }
                }
                for (var key in parsed) config.headers[String(key)] = String(parsed[key]);
                config.response = null;
              }
              return api;
            },
            cookie: function(value) {
              if (value != null) config.headers['Cookie'] = String(value);
              return api;
            },
            cookies: function(value) {
              if (value != null) config.headers['Cookie'] = String(value);
              return api;
            },
            data: function(key, value) {
              if (arguments.length === 1) {
                config.body = __bridgeString(key);
              } else {
                var part = encodeURIComponent(String(key)) + '=' + encodeURIComponent(String(value));
                config.body = config.body ? config.body + '&' + part : part;
              }
              config.method = 'POST'; config.response = null;
              return api;
            },
            requestBody: function(value) {
              config.body = String(value || '');
              config.method = 'POST'; config.response = null;
              return api;
            },
            timeout: function(value) { config.connectTimeout = config.readTimeout = Number(value || 0); return api; },
            setConnectTimeout: function(value) { config.connectTimeout = Number(value || 0); return api; },
            setReadTimeout: function(value) { config.readTimeout = Number(value || 0); return api; },
            getConnectTimeout: function() { return config.connectTimeout; },
            getReadTimeout: function() { return config.readTimeout; },
            setDoOutput: function(value) { config.doOutput = !!value; if (config.doOutput) config.method = 'POST'; config.response = null; return api; },
            getDoOutput: function() { return config.doOutput; },
            setRequestMethod: function(value) { config.method = String(value || 'GET').toUpperCase(); config.response = null; return api; },
            getRequestMethod: function() { return config.method; },
            ignoreContentType: function(_) { return api; },
            ignoreHttpErrors: function(_) { return api; },
            followRedirects: function(_) { return api; },
            raw: function() { return api; },
            request: function(method) { if (method) config.method = String(method).toUpperCase(); config.response = null; return api; },
            userAgent: function(value) {
              config.headers['User-Agent'] = String(value);
              return api;
            },
            get: function() {
              config.method = 'GET'; return response();
            },
            post: function(body) {
              if (arguments.length > 0) config.body = __bridgeString(body);
              config.method = 'POST'; return response();
            },
            body: function() {
              return response().body();
            },
            execute: function() {
              return response();
            },
            connect: function() { response(); return api; },
            getResponseCode: function() { return Number(response().code || response().statusCode || 0); },
            getContentType: function() { return response().header('content-type') || ''; },
            getHeaderField: function(nameOrIndex) {
              var headers = response().headers();
              if (typeof nameOrIndex === 'number' || /^\\d+$/.test(String(nameOrIndex))) {
                var keys = headers.keys(); return headers.get(keys[Number(nameOrIndex)]);
              }
              return headers.get(String(nameOrIndex || '')) || null;
            },
            getHeaderFields: function() { return response().headers(); },
            getInputStream: function() { return new Packages.java.io.ByteArrayInputStream(response().body().bytes()); },
            getOutputStream: function() { if (!config.output) config.output = new Packages.java.io.ByteArrayOutputStream(); return config.output; },
            url: function() { return target; },
            toString: function() { return target; }
          };
          return api;
        }
        java.connect = __makeConnect;
        java.log = function(value) {
          return String(__nativeLegado.invoke({ method: 'log', args: [__bridgeString(value)] }) || '');
        };
        java.toast = function(_) { return ''; };
        java.longToast = function(_) { return ''; };
        java.getCookie = function(url, key) {
          var nativeCookie = __nativeLegado.invoke({ method: 'getCookie', args: [String(url || __defaultBaseUrl()), key == null ? '' : String(key)] });
          if (nativeCookie != null && String(nativeCookie) !== '') return String(nativeCookie);
          return String(typeof cookieHeader === 'undefined' ? '' : cookieHeader);
        };
        java.getWebViewUA = function() { return 'Mozilla/5.0 SourceReadSwift iOS'; };
        java.startBrowser = function() { return ''; };
        java.startBrowserAwait = function() { return ''; };
        java.webView = function() { return ''; };
        java.openUrl = java.startBrowser;
        if (typeof cookie === 'undefined' || cookie === null) cookie = {};
        cookie.getCookie = java.getCookie;
        cookie.getKey = function(url, key) {
          var name = String(key || '');
          var header = java.getCookie(url);
          var parts = header.split(';');
          for (var i = 0; i < parts.length; i++) {
            var item = parts[i].trim();
            var pos = item.indexOf('=');
            if (pos > 0 && item.substring(0, pos).trim() === name) return item.substring(pos + 1).trim();
          }
          return '';
        };
        cookie.setCookie = function(url, value) {
          if (arguments.length < 2) { value = url; url = __defaultBaseUrl(); }
          cookieHeader = String(value || '');
          return String(__nativeLegado.invoke({ method: 'setCookie', args: [String(url || __defaultBaseUrl()), cookieHeader] }) || '');
        };
        cookie.removeCookie = function() {
          cookieHeader = '';
          __nativeLegado.invoke({ method: 'setCookie', args: [''] });
          return true;
        };
        java.setCookie = cookie.setCookie;
        java.utf8ToGbk = function(value) { return __nativeLegado.invoke({ method: 'utf8ToGbk', args: [String(value || '')] }); };
        java.htmlFormat = function(value) {
          var input = String(value == null ? '' : value);
          // Legado's clean/htmlFormat keeps readable line breaks while
          // dropping script/style and markup noise.
          return input
            .replace(/<script[\\s\\S]*?<\\/script>/gi, '')
            .replace(/<style[\\s\\S]*?<\\/style>/gi, '')
            .replace(/<\\/?(?:br|p|div|section|article|li|tr|h[1-6])[^>]*>/gi, '\\n')
            .replace(/<[^>]+>/g, '')
            .replace(/&nbsp;/gi, ' ')
            .replace(/&amp;/gi, '&')
            .replace(/&lt;/gi, '<')
            .replace(/&gt;/gi, '>')
            .replace(/&quot;/gi, '"')
            .replace(/&#39;/gi, "'")
            .replace(/\\r/g, '')
            .replace(/\\n{3,}/g, '\\n\\n')
            .split('\\n').map(function(line) { return line.trim(); }).filter(Boolean).join('\\n');
        };
        java.readFile = function(path) { return __nativeLegado.invoke({ method: 'readFile', args: [String(path || '')] }); };
        java.readTxtFile = function(path, charset) { return String(__nativeLegado.invoke({ method: 'readTxtFile', args: [String(path || ''), String(charset || 'utf-8')] }) || ''); };
        java.downloadFile = function(url, path) { return String(__nativeLegado.invoke({ method: 'downloadFile', args: [String(url || ''), String(path || '')] }) || ''); };
        java.unzipFile = function(path) { return String(__nativeLegado.invoke({ method: 'unzipFile', args: [String(path || '')] }) || ''); };
        java.getTxtInFolder = function(path) { return __nativeLegado.invoke({ method: 'getTxtInFolder', args: [String(path || '')] }); };
        java.getZipStringContent = function(path, entry, charset) { return String(__nativeLegado.invoke({ method: 'getZipStringContent', args: [String(path || ''), String(entry || ''), String(charset || 'utf-8')] }) || ''); };
        java.getZipByteArrayContent = function(path, entry) { return __nativeLegado.invoke({ method: 'getZipByteArrayContent', args: [String(path || ''), String(entry || '')] }); };
        java.getSandboxPath = function() { return String(__nativeLegado.invoke({ method: 'sandboxPath', args: [] }) || ''); };
        java.fetchCloudTTS = function(_) { return ''; };
        function __cipherArgs(third, fourth, fallback) {
          var thirdText = String(third == null ? '' : third);
          var looksLikeTransformation = thirdText.indexOf('/') >= 0 || /^(AES|DES|DESEDE|TRIPLEDES)/i.test(thirdText);
          return {
            iv: looksLikeTransformation ? fourth : third,
            transformation: String((looksLikeTransformation ? third : fourth) || fallback)
          };
        }
        function __aes(method, input, key, third, fourth) {
          var normalized = __cipherArgs(third, fourth, 'AES/CBC/PKCS7Padding');
          return __nativeLegado.invoke({ method: method, args: [input, key, normalized.transformation, normalized.iv] });
        }
        java.aesDecodeToByteArray = function(a,b,c,d) { return __aes('aesDecodeToByteArray',a,b,c,d); };
        java.aesDecodeToString = function(a,b,c,d) { return __aes('aesDecodeToString',a,b,c,d); };
        java.aesBase64DecodeToByteArray = function(a,b,c,d) { return __aes('aesBase64DecodeToByteArray',a,b,c,d); };
        java.aesBase64DecodeToString = function(a,b,c,d) { return __aes('aesBase64DecodeToString',a,b,c,d); };
        java.aesEncodeToByteArray = function(a,b,c,d) { return __aes('aesEncodeToByteArray',a,b,c,d); };
        java.aesEncodeToString = function(a,b,c,d) { return __aes('aesEncodeToString',a,b,c,d); };
        java.aesEncodeToBase64ByteArray = function(a,b,c,d) { return __aes('aesEncodeToBase64ByteArray',a,b,c,d); };
        java.aesEncodeToBase64String = function(a,b,c,d) { return __aes('aesEncodeToBase64String',a,b,c,d); };
        function __cipherBase64Encode(value, key, third, fourth, fallback) {
          var normalized = __cipherArgs(third, fourth, fallback);
          var plain = value && value.length != null && typeof value !== 'string' ? value : __native_stringToBytes(String(value == null ? '' : value));
          var encrypted = __nativeLegado.invoke({ method: 'cipherEncryptBytes', args: [plain, key, normalized.transformation, normalized.iv] });
          return __native_base64EncodeBytes(encrypted && encrypted.length != null ? encrypted : []);
        }
        function __cipherBase64Decode(value, key, third, fourth, fallback) {
          var normalized = __cipherArgs(third, fourth, fallback);
          var decoded = __native_base64DecodeBytes(String(value == null ? '' : value));
          var plain = __nativeLegado.invoke({ method: 'cipherDecryptBytes', args: [decoded, key, normalized.transformation, normalized.iv] });
          return __native_bytesToString(plain && plain.length != null ? plain : []);
        }
        java.desEncodeToBase64String = function(value, key, iv, transformation) {
          return __cipherBase64Encode(value, key, iv, transformation, 'DES/CBC/PKCS5Padding');
        };
        java.tripleDESEncodeBase64Str = function(value, key, mode, padding, iv) {
          var transformation = 'DESede/' + String(mode || 'CBC') + '/' + String(padding || 'PKCS5Padding');
          return __cipherBase64Encode(value, key, transformation, iv, transformation);
        };
        java.cipherEncodeToBase64String = function(value, key, iv, transformation) {
          return __cipherBase64Encode(value, key, iv, transformation, 'AES/CBC/PKCS5Padding');
        };
        java.desBase64DecodeToString = function(value, key, iv, transformation) {
          return __cipherBase64Decode(value, key, iv, transformation, 'DES/CBC/PKCS5Padding');
        };
        java.cipherBase64DecodeToString = function(value, key, iv, transformation) {
          return __cipherBase64Decode(value, key, iv, transformation, 'AES/CBC/PKCS5Padding');
        };
        java.setContent = function(value) {
          result = String(value == null ? '' : value);
          return String(__nativeRule.setContent(result));
        };
        function __installSourceAndBook() {
          if (typeof source === 'undefined' || source === null) source = {};
          source.getKey = function() { return source.key || source.bookSourceUrl || source.sourceUrl || ''; };
          source.sourceUrl = source.sourceUrl || source.bookSourceUrl || source.key || '';
          source.sourceName = source.sourceName || source.bookSourceName || '';
          source.bookSourceComment = source.bookSourceComment || source.comment || '';
          source.bookSourceUrlName = source.bookSourceUrlName || source.urlName || source.sourceName || '';
          source.loginUrl = source.loginUrl || '';
          source.loginCheckJs = source.loginCheckJs || '';
          source.getName = function() { return source.bookSourceName || source.sourceName || ''; };
          source.getUrl = function() { return source.bookSourceUrl || source.sourceUrl || source.key || ''; };
          source.getSourceUrl = source.getUrl;
          source.getVariable = function(key) {
            if (arguments.length > 0 && key != null && String(key) !== '') return java.getVar('source.variable.' + String(key));
            return source.variable || java.getVar('source.variable') || '';
          };
          source.setVariable = function(key, value) {
            if (arguments.length > 1) return java.put('source.variable.' + String(key), value == null ? '' : String(value));
            source.variable = key == null ? '' : String(key);
            return java.put('source.variable', source.variable);
          };
          source.getVariableMap = function() {
            var parsed = {};
            try { parsed = JSON.parse(source.getVariable() || '{}'); } catch (_) {}
            return {
              get: function(k) { var value = parsed[String(k)]; return value == null ? '' : value; },
              put: function(k, v) { parsed[String(k)] = v; source.setVariable(JSON.stringify(parsed)); return v; },
              remove: function(k) { var old = parsed[String(k)]; delete parsed[String(k)]; source.setVariable(JSON.stringify(parsed)); return old == null ? null : old; },
              containsKey: function(k) { return Object.prototype.hasOwnProperty.call(parsed, String(k)); },
              isEmpty: function() { return Object.keys(parsed).length === 0; }
            };
          };
          source.getLoginInfoMap = function() { return {
            get: function(k) { return java.getVar('source.login.' + String(k || '')); },
            put: function(k, v) { return java.put('source.login.' + String(k || ''), v == null ? '' : String(v)); },
            remove: function(k) { return java.removeVar('source.login.' + String(k || '')); }
          }; };
          source.putLoginHeader = function(k, v) { return java.put('source.loginHeader.' + String(k || ''), v == null ? '' : String(v)); };
          source.getLoginHeader = function(k) { return java.getVar('source.loginHeader.' + String(k || '')); };
          source.putVariable = source.setVariable;
          if (typeof book === 'undefined' || book === null) book = {};
          book.name = book.name || book.title || '';
          book.title = book.title || book.name || '';
          book.bookUrl = book.bookUrl || book.url || '';
          book.url = book.url || book.bookUrl || '';
          book.tocUrl = book.tocUrl || book.bookUrl || book.url || '';
          book.getName = function() { return book.name || book.title || ''; };
          book.getTitle = book.getName;
          book.getAuthor = function() { return book.author || ''; };
          book.getBookUrl = function() { return book.bookUrl || book.url || ''; };
          book.getUrl = book.getBookUrl;
          book.getTocUrl = function() { return book.tocUrl || book.bookUrl || book.url || ''; };
          book.getOrigin = function() { return book.origin || book.bookSourceUrl || ''; };
          book.getVariable = function(key) {
            if (arguments.length > 0 && key != null && String(key) !== '') return java.getVar('book.variable.' + String(key));
            return book.variable || java.getVar('book.variable') || '';
          };
                    book.setVariable = function(key, value) {
            if (arguments.length > 1) return java.put('book.variable.' + String(key), value == null ? '' : String(value));
            book.variable = key == null ? '' : String(key);
            return java.put('book.variable', book.variable);
          };
          book.putVariable = function(key, value) { return book.setVariable(key, value); };
          book.variableMap = book.variableMap || {
            get: function(k) { return book.getVariable(k); },
            put: function(k,v) { return book.setVariable(k,v); },
            remove: function(k) { return java.removeVar('book.variable.' + String(k || '')); },
            containsKey: function(k) { return book.getVariable(k) !== ''; }
          };
          if (typeof chapter === 'undefined' || chapter === null) chapter = {};
          chapter.name = chapter.name || chapter.title || '';
          chapter.title = chapter.title || chapter.name || '';
          chapter.chapterUrl = chapter.chapterUrl || chapter.url || '';
          chapter.url = chapter.url || chapter.chapterUrl || '';
          chapter.chapterIndex = chapter.chapterIndex == null ? (chapter.index || 0) : chapter.chapterIndex;
          chapter.index = chapter.index == null ? chapter.chapterIndex : chapter.index;
          chapter.getName = function() { return chapter.name || chapter.title || ''; };
          chapter.getTitle = chapter.getName;
          chapter.getUrl = function() { return chapter.url || chapter.chapterUrl || ''; };
          chapter.getChapterUrl = chapter.getUrl;
          chapter.getIndex = function() { return chapter.index || chapter.chapterIndex || 0; };
          chapter.getChapterIndex = chapter.getIndex;
          chapter.getVariable = function(key) {
            if (arguments.length > 0 && key != null && String(key) !== '') return java.getVar('chapter.variable.' + String(key));
            return chapter.variable || java.getVar('chapter.variable') || '';
          };
          chapter.setVariable = function(key, value) {
            if (arguments.length > 1) return java.put('chapter.variable.' + String(key), value == null ? '' : String(value));
            chapter.variable = key == null ? '' : String(key);
            return java.put('chapter.variable', chapter.variable);
          };
          chapter.putVariable = function(key, value) { return chapter.setVariable(key, value); };
          chapter.variableMap = chapter.variableMap || {
            get: function(k) { return chapter.getVariable(k); },
            put: function(k,v) { return chapter.setVariable(k,v); },
            remove: function(k) { return java.removeVar('chapter.variable.' + String(k || '')); },
            containsKey: function(k) { return chapter.getVariable(k) !== ''; }
          };
          chapter.isVip = function() {
            var title = String(chapter.title || chapter.name || '').toLowerCase();
            return title.indexOf('vip') >= 0 || title.indexOf('订阅') >= 0 || title.indexOf('付费') >= 0;
          };
        }
        __installSourceAndBook();
        function base64Encode(value) { return java.base64Encode(value); }
        function base64Decode(value) { return java.base64Decode(value); }
        function unbase64(value) { return java.base64Decode(value); }
        function md5(value) { return java.md5(value); }
        function hexMd5(value) { return java.md5(value); }
        function sha1(value) { return java.sha1(value); }
        function atob(value) { return java.base64Decode(value); }
        function btoa(value) { return java.base64Encode(value); }
        function getStr(key, fallback) { return java.getStr(key, fallback); }
        function getJson(value, fallback) { return java.getJson(value, fallback); }
        function putJson(key, value) { return java.putJson(key, value); }
        function strToBytes(value) { return java.strToBytes(value); }
        function bytesToStr(value) { return java.bytesToStr(value); }
        function hexEncodeToString(value) { return java.hexEncodeToString(value); }
        function hexDecodeToString(value) { return java.hexDecodeToString(value); }
        function getString(input, rule) { return java.getString(input, rule); }
        function getStringList(input, rule) { return java.getStringList(input, rule); }
        function getElements(input, rule) { return java.getElements(input, rule); }
        function getElement(rule) { return java.getElement(rule); }
        function setContent(value) { return java.setContent(value); }
        function put(key, value) { return java.put(key, value); }
        function get(key, fallback) { return java.getStr(key, fallback); }
        if (typeof CryptoJS === 'undefined' || CryptoJS === null) CryptoJS = {};
        function __cryptoBytes(value, encoding) {
          if (value == null) return [];
          if (value.__hex !== undefined) return __cryptoBytes(value.__hex, 'hex');
          if (value.__bytes && value.__bytes.length != null) {
            var rawBytes = Array.prototype.slice.call(value.__bytes).map(function(v) { return Number(v) & 255; });
            return value.sigBytes == null ? rawBytes : rawBytes.slice(0, Math.max(0, Number(value.sigBytes)));
          }
          if (value.words && value.words.length != null && value.sigBytes != null) {
            var wordBytes = [], wordCount = Math.max(0, Number(value.sigBytes));
            for (var wi = 0; wi < value.words.length && wordBytes.length < wordCount; wi++) {
              var word = Number(value.words[wi]) || 0;
              wordBytes.push((word >>> 24) & 255, (word >>> 16) & 255, (word >>> 8) & 255, word & 255);
            }
            return wordBytes.slice(0, wordCount);
          }
          if (value.__text !== undefined) return __cryptoBytes(value.__text, encoding || value.__encoding);
          if (value.__cryptoValue !== undefined) return __cryptoBytes(value.__cryptoValue, encoding || value.__cryptoEncoding);
          if (value.length != null && typeof value !== 'string') return Array.prototype.slice.call(value).map(function(v) { return Number(v) & 255; });
          var text = String(value);
          var enc = String(encoding || 'utf8').toLowerCase();
          if (enc === 'latin1' || enc === 'iso-8859-1') {
            var latin = []; for (var i = 0; i < text.length; i++) latin.push(text.charCodeAt(i) & 255); return latin;
          }
          if (enc === 'hex') {
            var hex = text.replace(/\\s+/g, ''), bytes = [];
            for (var h = 0; h + 1 < hex.length; h += 2) { var n = parseInt(hex.substr(h, 2), 16); if (!isNaN(n)) bytes.push(n); }
            return bytes;
          }
          return Array.prototype.slice.call(__native_stringToBytes(text)).map(function(v) { return Number(v) & 255; });
        }
        function __cryptoText(value) {
          if (value && value.ciphertext != null) return __cryptoText(value.ciphertext);
          if (value && value.__text !== undefined) return String(value.__text);
          if (value && value.__bytes && value.__encoding === 'latin1') return String.fromCharCode.apply(null, value.__bytes);
          if (value && value.__bytes) return String(__native_bytesToString(value.__bytes) || '');
          return String(value);
        }
        function __cryptoBytesHex(value) {
          var bytes = value && value.length != null ? value : [];
          var out = '';
          for (var i = 0; i < bytes.length; i++) {
            var h = (Number(bytes[i]) & 255).toString(16);
            out += h.length < 2 ? '0' + h : h;
          }
          return out;
        }
        function __cryptoDigestBytes(value, algorithm) {
          var bytes = __cryptoBytes(value, value && value.__encoding);
          return __cryptoDigest(__cryptoBytesHex(__native_digestBytes(bytes, String(algorithm || 'SHA-256'))));
        }
        function __cryptoHmacBytes(value, key, algorithm) {
          var bytes = __cryptoBytes(value, value && value.__encoding);
          var keyBytes = __cryptoBytes(key, key && key.__encoding);
          return __cryptoDigest(__cryptoBytesHex(__native_hmacBytes(bytes, String(algorithm || 'HmacSHA256'), keyBytes)));
        }
        function __cryptoWords(bytes) {
          var words = [];
          for (var wi = 0; wi < bytes.length; wi += 4) {
            words.push(((bytes[wi] || 0) << 24) | ((bytes[wi + 1] || 0) << 16) | ((bytes[wi + 2] || 0) << 8) | (bytes[wi + 3] || 0));
          }
          return words;
        }
        function __cryptoWordArray(value, defaultEncoding) {
          if (value && value.ciphertext != null) value = value.ciphertext;
          var enc = String(defaultEncoding || 'utf8').toLowerCase();
          var bytes = __cryptoBytes(value, enc);
          var text = enc === 'latin1' ? String.fromCharCode.apply(null, bytes) : String(__native_bytesToString(bytes) || '');
          return {
            __bytes: bytes,
            __text: text,
            __encoding: enc,
            sigBytes: bytes.length,
            words: __cryptoWords(bytes),
            concat: function(other) {
              var extra = __cryptoBytes(other, other && other.__encoding);
              for (var ci = 0; ci < extra.length; ci++) bytes.push(extra[ci]);
              this.sigBytes = bytes.length;
              this.words = __cryptoWords(bytes);
              return this;
            },
            clamp: function() { this.sigBytes = Math.max(0, Math.min(bytes.length, Number(this.sigBytes || 0))); bytes.length = this.sigBytes; this.words = __cryptoWords(bytes); return this; },
            clone: function() { return __cryptoWordArray(bytes.slice(), 'bytes'); },
            toString: function(encoder) {
              var outEnc = encoder && encoder.__encoding ? String(encoder.__encoding).toLowerCase() : enc;
              if (outEnc === 'hex') return bytes.map(function(v) { var h = Number(v).toString(16); return h.length < 2 ? '0' + h : h; }).join('');
              if (outEnc === 'base64') return __native_base64EncodeBytes(bytes);
              if (outEnc === 'latin1') return String.fromCharCode.apply(null, bytes);
              return String(__native_bytesToString(bytes) || '');
            },
            valueOf: function() { return text; }
          };
        }
        function __cryptoDigest(hex) {
          var value = String(hex || '');
          return {
            __hex: value,
            toString: function(encoder) {
              var enc = encoder && encoder.__encoding ? String(encoder.__encoding).toLowerCase() : 'hex';
              if (enc === 'utf8') return String(__native_bytesToString(__cryptoBytes(value, 'hex')) || '');
              if (enc === 'base64') return __native_base64EncodeBytes(__cryptoBytes(value, 'hex'));
              return value;
            },
            valueOf: function() { return value; }
          };
        }
        CryptoJS.MD5 = function(value) { return __cryptoDigestBytes(value, 'MD5'); };
        CryptoJS.SHA1 = function(value) { return __cryptoDigestBytes(value, 'SHA-1'); };
        CryptoJS.SHA224 = function(value) { return __cryptoDigestBytes(value, 'SHA-224'); };
        CryptoJS.SHA256 = function(value) { return __cryptoDigestBytes(value, 'SHA-256'); };
        CryptoJS.SHA384 = function(value) { return __cryptoDigestBytes(value, 'SHA-384'); };
        CryptoJS.SHA512 = function(value) { return __cryptoDigestBytes(value, 'SHA-512'); };
        CryptoJS.HmacMD5 = function(value, key) { return __cryptoHmacBytes(value, key, 'HmacMD5'); };
        CryptoJS.HmacSHA1 = function(value, key) { return __cryptoHmacBytes(value, key, 'HmacSHA1'); };
        CryptoJS.HmacSHA224 = function(value, key) { return __cryptoHmacBytes(value, key, 'HmacSHA224'); };
        CryptoJS.HmacSHA256 = function(value, key) { return __cryptoHmacBytes(value, key, 'HmacSHA256'); };
        CryptoJS.HmacSHA384 = function(value, key) { return __cryptoHmacBytes(value, key, 'HmacSHA384'); };
        CryptoJS.HmacSHA512 = function(value, key) { return __cryptoHmacBytes(value, key, 'HmacSHA512'); };
        CryptoJS.enc = CryptoJS.enc || {};
        CryptoJS.enc.Utf8 = {
          __encoding: 'utf8',
          parse: function(value) { return __cryptoWordArray(String(value == null ? '' : value), 'utf8'); },
          stringify: function(value) { return __cryptoWordArray(value, 'bytes').toString(this); }
        };
        CryptoJS.enc.Hex = {
          __encoding: 'hex',
          parse: function(value) { return __cryptoWordArray(String(value == null ? '' : value), 'hex'); },
          stringify: function(value) { return __cryptoWordArray(value, 'bytes').toString(this); }
        };
        CryptoJS.enc.Base64 = {
          __encoding: 'base64',
          parse: function(value) {
            var decoded = __native_base64DecodeBytes(String(value == null ? '' : value));
            return __cryptoWordArray(decoded, 'bytes');
          },
          stringify: function(value) { return __cryptoWordArray(value, 'bytes').toString(this); }
        };
        CryptoJS.enc.Latin1 = {
          __encoding: 'latin1',
          parse: function(value) { return __cryptoWordArray(String(value == null ? '' : value), 'latin1'); },
          stringify: function(value) { return __cryptoWordArray(value, 'latin1').toString(this); }
        };
        CryptoJS.lib = CryptoJS.lib || {};
        CryptoJS.lib.WordArray = CryptoJS.lib.WordArray || {
          create: function(value, sigBytes) {
            var wordArray;
            if (value && value.words && value.sigBytes != null) {
              wordArray = __cryptoWordArray(value, 'bytes');
            } else if (value && value.length != null) {
              var values = Array.prototype.slice.call(value);
              var looksLikeWords = values.some(function(item) { return Number(item) > 255 || Number(item) < 0; });
              if (looksLikeWords) {
                var wordBytes = [];
                for (var wi = 0; wi < values.length; wi++) {
                  var word = Number(values[wi]) || 0;
                  wordBytes.push((word >>> 24) & 255, (word >>> 16) & 255, (word >>> 8) & 255, word & 255);
                }
                wordArray = __cryptoWordArray(wordBytes, 'bytes');
              } else {
                wordArray = __cryptoWordArray(values, 'bytes');
              }
            } else {
              wordArray = __cryptoWordArray([], 'bytes');
            }
            if (sigBytes != null) { wordArray.sigBytes = Number(sigBytes); wordArray.__bytes.length = wordArray.sigBytes; }
            wordArray.words = __cryptoWords(wordArray.__bytes);
            return wordArray;
          }
        };
        CryptoJS.mode = CryptoJS.mode || {};
        CryptoJS.mode.CBC = CryptoJS.mode.CBC || 'CBC';
        CryptoJS.mode.ECB = CryptoJS.mode.ECB || 'ECB';
        CryptoJS.pad = CryptoJS.pad || {};
        CryptoJS.pad.Pkcs7 = CryptoJS.pad.Pkcs7 || 'Pkcs7';
        CryptoJS.pad.PKCS7 = CryptoJS.pad.PKCS7 || CryptoJS.pad.Pkcs7;
        CryptoJS.pad.ZeroPadding = CryptoJS.pad.ZeroPadding || 'ZeroPadding';
        CryptoJS.pad.NoPadding = CryptoJS.pad.NoPadding || 'NoPadding';
        function __cryptoModeName(options) {
          var mode = options && options.mode != null ? String(options.mode) : 'CBC';
          return mode.toLowerCase() === 'ecb' || mode.indexOf('ECB') >= 0 ? 'ECB' : 'CBC';
        }
        function __cryptoPaddingName(options) {
          var padding = options && options.padding != null ? String(options.padding) : 'Pkcs7';
          if (padding.toLowerCase().indexOf('zero') >= 0) return 'ZeroPadding';
          if (padding.toLowerCase().indexOf('no') >= 0) return 'NoPadding';
          return 'PKCS7Padding';
        }
        function __cryptoCipher(algorithm) {
          return {
            encrypt: function(value, key, options) {
              options = options || {};
              // CryptoJS treats a string key without an explicit IV as a
              // passphrase and emits an OpenSSL `Salted__` envelope.  Keep
              // the existing raw-byte path for Legado sources that provide an
              // IV or a WordArray key.
              if (algorithm === 'AES' && typeof key === 'string' && !options.iv) {
                var envelope = __nativeLegado.invoke({ method: 'cipherEncryptPassphrase', args: [value, key] });
                var envelopeWordArray = __cryptoWordArray(envelope, 'bytes');
                return {
                  ciphertext: envelopeWordArray,
                  __passphraseEnvelope: CryptoJS.enc.Base64.stringify(envelopeWordArray),
                  key: key,
                  iv: null,
                  algorithm: algorithm,
                  toString: function(formatter) {
                    if (formatter && typeof formatter.stringify === 'function') return String(formatter.stringify(this));
                    return CryptoJS.enc.Base64.stringify(envelopeWordArray);
                  }
                };
              }
              var transformation = algorithm + '/' + __cryptoModeName(options) + '/' + __cryptoPaddingName(options);
              var output = __nativeLegado.invoke({ method: 'cipherEncryptBytes', args: [
                __cryptoBytes(value, value && value.__encoding),
                __cryptoBytes(key, key && key.__encoding),
                transformation,
                __cryptoBytes(options.iv, options.iv && options.iv.__encoding)
              ]});
              var ciphertext = __cryptoWordArray(output, 'bytes');
              return {
                ciphertext: ciphertext,
                key: key,
                iv: options.iv,
                algorithm: algorithm,
                toString: function(formatter) {
                  if (formatter && typeof formatter.stringify === 'function') return String(formatter.stringify(this));
                  return CryptoJS.enc.Base64.stringify(ciphertext);
                }
              };
            },
            decrypt: function(value, key, options) {
              options = options || {};
              if (algorithm === 'AES' && typeof key === 'string' && !options.iv && value && value.__passphraseEnvelope) {
                var passphraseObjectOutput = __nativeLegado.invoke({ method: 'cipherDecryptPassphrase', args: [value.__passphraseEnvelope, key] });
                return __cryptoWordArray(passphraseObjectOutput, 'bytes');
              }
              var ciphertext = value && value.ciphertext != null ? value.ciphertext : value;
              if (!options.iv && value && value.iv) options.iv = value.iv;
              var bytes = ciphertext && ciphertext.__bytes ? ciphertext.__bytes.slice() :
                (typeof ciphertext === 'string' ? __cryptoBytes(__native_base64DecodeBytes(ciphertext), 'bytes') : __cryptoBytes(ciphertext, ciphertext && ciphertext.__encoding));
              var keyBytes = __cryptoBytes(key, key && key.__encoding);
              var ivBytes = __cryptoBytes(options.iv, options.iv && options.iv.__encoding);
              // CryptoJS's passphrase overload accepts an OpenSSL `Salted__`
              // envelope and derives an AES-256 key/IV with EVP_BytesToKey.
              // Preserve the raw WordArray path above for explicit keys.
              if (algorithm === 'AES' && typeof ciphertext === 'string' && typeof key === 'string' && !options.iv) {
                var passphraseOutput = __nativeLegado.invoke({ method: 'cipherDecryptPassphrase', args: [ciphertext, key] });
                return __cryptoWordArray(passphraseOutput, 'bytes');
              }
              var transformation = algorithm + '/' + __cryptoModeName(options) + '/' + __cryptoPaddingName(options);
              var output = __nativeLegado.invoke({ method: 'cipherDecryptBytes', args: [
                bytes,
                keyBytes,
                transformation,
                ivBytes
              ]});
              return __cryptoWordArray(output, 'bytes');
            }
          };
        }
        CryptoJS.AES = CryptoJS.AES || __cryptoCipher('AES');
        CryptoJS.DES = CryptoJS.DES || __cryptoCipher('DES');
        CryptoJS.TripleDES = CryptoJS.TripleDES || __cryptoCipher('DESede');
        CryptoJS.DESede = CryptoJS.DESede || CryptoJS.TripleDES;
        if (typeof Packages === 'undefined' || Packages === null) Packages = {};
        Packages.org = Packages.org || {};
        Packages.org.jsoup = Packages.org.jsoup || {};
        // Keep the namespace materialized while the rest of the Java aliases
        // are being declared.  The concrete Jsoup facade is installed below,
        // but JavaImporter metadata is assigned before that point.
        Packages.org.jsoup.Jsoup = Packages.org.jsoup.Jsoup || {};
        Packages.java = Packages.java || {};
        Packages.java.lang = Packages.java.lang || {};
        Packages.java.lang.String = Packages.java.lang.String || function(value, charset) {
          if (value && typeof value !== 'string' && value.length != null) {
            var decoded = charset == null ? __native_bytesToString(value) : __native_bytesToStringCharset(value, String(charset));
            var result = new String(String(decoded || ''));
            result.getBytes = function(charset) {
              var name = charset == null ? '' : String(charset);
              return __asJavaList(name ? __native_stringToBytesCharset(String(result), name) : __native_stringToBytes(String(result)));
            };
            return result;
          }
          var result = new String(String(value == null ? '' : value));
          result.getBytes = function(charset) {
            var name = charset == null ? '' : String(charset);
            return __asJavaList(name ? __native_stringToBytesCharset(String(result), name) : __native_stringToBytes(String(result)));
          };
          return result;
        };
        Packages.java.lang.String.valueOf = function(value) { return String(value == null ? 'null' : value); };
        Packages.java.lang.String.format = function(format) {
          var args = Array.prototype.slice.call(arguments, 1), index = 0;
          return String(format || '').replace(/%[sdif]/g, function() { return String(args[index++]); });
        };
        Packages.java.lang.Integer = Packages.java.lang.Integer || {
          parseInt: function(value, radix) { var n = parseInt(String(value || ''), Number(radix || 10)); return isNaN(n) ? 0 : n; },
          valueOf: function(value) { return Number(value || 0); },
          toString: function(value, radix) { return Number(value || 0).toString(Number(radix || 10)); }
        };
        Packages.java.lang.Long = Packages.java.lang.Long || Packages.java.lang.Integer;
        Packages.java.lang.Long.parseLong = function(value, radix) { var n = parseInt(String(value == null ? '0' : value), Number(radix || 10)); return isNaN(n) ? 0 : n; };
        Packages.java.lang.Long.toString = function(value, radix) { return Number(value || 0).toString(Number(radix || 10)); };
        Packages.java.lang.Double = Packages.java.lang.Double || {
          parseDouble: function(value) { var n = parseFloat(String(value || '')); return isNaN(n) ? 0 : n; },
          valueOf: function(value) { return Number(value || 0); }
        };
        Packages.java.lang.Boolean = Packages.java.lang.Boolean || {
          parseBoolean: function(value) { return String(value || '').toLowerCase() === 'true'; },
          valueOf: function(value) { return String(value || '').toLowerCase() === 'true'; }
        };
        Packages.java.lang.StringBuilder = Packages.java.lang.StringBuilder || function(value) {
          this.__parts = [value == null ? '' : String(value)];
          this.append = function(next) { this.__parts.push(next == null ? 'null' : String(next)); return this; };
          this.insert = function(index, next) {
            var text = this.toString(); var i = Math.max(0, Math.min(Number(index) || 0, text.length));
            this.__parts = [text.substring(0, i), next == null ? 'null' : String(next), text.substring(i)]; return this;
          };
          this.delete = function(start, end) {
            var text = this.toString(); var from = Math.max(0, Number(start) || 0); var to = Math.max(from, Number(end) || 0);
            this.__parts = [text.substring(0, from), text.substring(to)]; return this;
          };
          this.deleteCharAt = function(index) { var i = Number(index) || 0; return this.delete(i, i + 1); };
          this.replace = function(start, end, replacement) {
            var text = this.toString(); var from = Math.max(0, Number(start) || 0); var to = Math.max(from, Number(end) || 0);
            this.__parts = [text.substring(0, from), replacement == null ? 'null' : String(replacement), text.substring(to)]; return this;
          };
          this.reverse = function() { this.__parts = [this.toString().split('').reverse().join('')]; return this; };
          this.setLength = function(length) {
            var n = Math.max(0, Number(length) || 0), text = this.toString();
            this.__parts = [n < text.length ? text.substring(0, n) : text + new Array(n - text.length + 1).join('\\0')]; return this;
          };
          this.charAt = function(index) { return this.toString().charAt(Number(index) || 0); };
          this.substring = function(start, end) { return this.toString().substring(Number(start) || 0, end == null ? this.length() : Number(end)); };
          this.capacity = function() { return Math.max(16, this.toString().length); };
          this.length = function() { return this.toString().length; };
          this.toString = function() { return this.__parts.join(''); };
        };
        Packages.java.lang.Thread = Packages.java.lang.Thread || { sleep: function(_) {} };
        Packages.java.lang.System = Packages.java.lang.System || {
          currentTimeMillis: java.currentTimeMillis,
          nanoTime: function() { return Date.now() * 1000000; }
        };
        Packages.java.io = Packages.java.io || {};
        Packages.java.io.ByteArrayInputStream = Packages.java.io.ByteArrayInputStream || function(value) {
          var bytes = value && value.length != null ? Array.prototype.slice.call(value) : __javaBytes(value);
          bytes = bytes.map(function(item) { return Number(item) & 255; });
          var index = 0;
          this.__bytes = bytes;
          this.__javaBytes = bytes;
          var markIndex = 0;
          this.read = function(buffer, offset, length) {
            if (buffer && buffer.length != null) {
              var start = Math.max(0, Number(offset || 0));
              var requested = length == null ? buffer.length - start : Number(length);
              var count = Math.min(Math.max(0, requested), bytes.length - index);
              for (var i = 0; i < count; i++) buffer[start + i] = Number(bytes[index++]) & 255;
              return count > 0 ? count : -1;
            }
            return index < bytes.length ? Number(bytes[index++]) & 255 : -1;
          };
          this.available = function() { return Math.max(0, bytes.length - index); };
          this.skip = function(count) { var moved = Math.min(Math.max(0, Number(count || 0)), bytes.length - index); index += moved; return moved; };
          this.mark = function() { markIndex = index; };
          this.reset = function() { index = markIndex; };
          this.toByteArray = function() { return __asJavaList(bytes.slice()); };
          this.close = function() { index = bytes.length; };
        };
        Packages.java.io.ByteArrayOutputStream = Packages.java.io.ByteArrayOutputStream || function() {
          var bytes = [];
          this.write = function(value, offset, length) {
            if (value && value.length != null) {
              var start = Number(offset || 0), count = length == null ? value.length - start : Number(length);
              for (var i = 0; i < count && start + i < value.length; i++) bytes.push(Number(value[start + i]) & 255);
            } else bytes.push(Number(value || 0) & 255);
          };
          this.size = function() { return bytes.length; };
          this.reset = function() { bytes = []; };
          this.close = function() {};
          this.toByteArray = function() { return __asJavaList(bytes.slice()); };
          this.toString = function(charset) { return String(__native_bytesToStringCharset(bytes, String(charset || 'utf-8')) || ''); };
        };
        Packages.java.util = Packages.java.util || {};
        Packages.java.util.Arrays = Packages.java.util.Arrays || {
          copyOfRange: function(values, start, end) {
            var source = values && values.length != null ? Array.prototype.slice.call(values) : [];
            var from = Math.max(0, Number(start || 0)), to = Math.max(from, Number(end || 0));
            var out = source.slice(from, to);
            while (out.length < to - from) out.push(0);
            return __asJavaList(out);
          },
          asList: function() {
            if (arguments.length === 1 && arguments[0] && arguments[0].length != null && typeof arguments[0] !== 'string') return __asJavaList(Array.prototype.slice.call(arguments[0]));
            return __asJavaList(Array.prototype.slice.call(arguments));
          },
          equals: function(a, b) {
            if (!a || !b || a.length !== b.length) return false;
            for (var i = 0; i < a.length; i++) {
              var left = a[i], right = b[i];
              if (left && typeof left.valueOf === 'function') left = left.valueOf();
              if (right && typeof right.valueOf === 'function') right = right.valueOf();
              if (left !== right && String(left) !== String(right)) return false;
            }
            return true;
          }
        };
        Packages.java.util.Collections = Packages.java.util.Collections || {
          sort: function(list, comparator) {
            var values = list && typeof list.toArray === 'function' ? list.toArray() : Array.prototype.slice.call(list || []);
            values.sort(function(left, right) {
              if (comparator && typeof comparator.compare === 'function') return Number(comparator.compare(left, right)) || 0;
              if (typeof comparator === 'function') return Number(comparator(left, right)) || 0;
              return String(left).localeCompare(String(right));
            });
            if (list && typeof list.clear === 'function' && typeof list.addAll === 'function') { list.clear(); list.addAll(values); return list; }
            for (var i = 0; list && i < values.length; i++) list[i] = values[i];
            return list;
          },
          reverse: function(list) {
            var values = list && typeof list.toArray === 'function' ? list.toArray().reverse() : Array.prototype.reverse.call(list || []);
            if (list && typeof list.clear === 'function' && typeof list.addAll === 'function') { list.clear(); list.addAll(values); }
            return list;
          },
          singletonList: function(value) { return __asJavaList([value]); },
          emptyList: function() { return __asJavaList([]); },
          frequency: function(list, value) {
            var values = list && typeof list.toArray === 'function' ? list.toArray() : Array.prototype.slice.call(list || []);
            var count = 0; for (var i = 0; i < values.length; i++) if (values[i] === value || String(values[i]) === String(value)) count++;
            return count;
          }
        };
        Packages.java.util.Objects = Packages.java.util.Objects || {
          equals: function(left, right) { return left === right || (left != null && right != null && String(left) === String(right)); },
          toString: function(value, fallback) { return value == null ? String(arguments.length > 1 ? fallback : 'null') : String(value); },
          requireNonNull: function(value) { if (value == null) throw new Error('NullPointerException'); return value; }
        };
        Packages.java.net = Packages.java.net || {};
        Packages.java.net.URL = Packages.java.net.URL || function(value, baseValue) {
          // Legado sources are inconsistent about using `new`; mirror the
          // forgiving Java facade and return a proper instance either way.
          if (!(this instanceof Packages.java.net.URL)) return new Packages.java.net.URL(value, baseValue);
          var first = String(value == null ? '' : value);
          var second = String(baseValue == null ? '' : baseValue);
          function hasScheme(text) { return /^[A-Za-z][A-Za-z0-9+.-]*:/.test(String(text || '')); }
          // Java's public constructor is URL(context, spec), while a number
          // of older Legado snippets use URL(spec, context). Accept both.
          var raw = first, base = second;
          if (second && hasScheme(first) && !hasScheme(second)) { raw = second; base = first; }
          function originOf(text) {
            var match = String(text || '').match(/^([A-Za-z][A-Za-z0-9+.-]*:\\/\\/[^/?#]*)/);
            return match ? match[1] : '';
          }
          function normalizePath(path) {
            var leading = path.charAt(0) === '/', trailing = /\\/$/.test(path);
            var parts = path.split('/'), out = [];
            for (var i = 0; i < parts.length; i++) {
              var part = parts[i];
              if (!part || part === '.') continue;
              if (part === '..') { if (out.length && out[out.length - 1] !== '..') out.pop(); else if (!leading) out.push('..'); }
              else out.push(part);
            }
            var result = (leading ? '/' : '') + out.join('/');
            if (!result) result = leading ? '/' : '';
            if (trailing && result.charAt(result.length - 1) !== '/') result += '/';
            return result;
          }
          function resolve(spec, context) {
            spec = String(spec || ''); context = String(context || '');
            if (!context || hasScheme(spec)) return spec;
            if (spec.indexOf('//') === 0) {
              var schemeMatch = context.match(/^([A-Za-z][A-Za-z0-9+.-]*:)/);
              return (schemeMatch ? schemeMatch[1] : '') + spec;
            }
            var hash = '', query = '';
            var hashIndex = spec.indexOf('#');
            if (hashIndex >= 0) { hash = spec.substring(hashIndex); spec = spec.substring(0, hashIndex); }
            var queryIndex = spec.indexOf('?');
            if (queryIndex >= 0) { query = spec.substring(queryIndex); spec = spec.substring(0, queryIndex); }
            var contextNoFrag = context.split('#')[0].split('?')[0];
            var joined;
            if (spec.charAt(0) === '/') joined = originOf(contextNoFrag) + spec;
            else {
              var slash = contextNoFrag.lastIndexOf('/');
              joined = (slash >= 0 ? contextNoFrag.substring(0, slash + 1) : contextNoFrag + '/') + spec;
            }
            var origin = originOf(joined), pathStart = origin ? origin.length : 0;
            var path = joined.substring(pathStart);
            return origin + normalizePath(path) + query + hash;
          }
          if (base && !hasScheme(raw)) raw = resolve(raw, base);
          var schemeMatch = raw.match(/^([A-Za-z][A-Za-z0-9+.-]*):\\/\\/([^/?#]*)([^?#]*)(?:\\?([^#]*))?(?:#(.*))?$/);
          var scheme = '', authority = '', pathOnly = '', queryOnly = '', refOnly = '';
          if (schemeMatch) {
            scheme = schemeMatch[1]; authority = schemeMatch[2]; pathOnly = schemeMatch[3] || '/';
            queryOnly = schemeMatch[4] || ''; refOnly = schemeMatch[5] || '';
          } else {
            var generic = raw.match(/^([A-Za-z][A-Za-z0-9+.-]*:)([^?#]*)(?:\\?([^#]*))?(?:#(.*))?$/);
            if (generic) { scheme = generic[1].replace(/:$/, ''); pathOnly = generic[2] || ''; queryOnly = generic[3] || ''; refOnly = generic[4] || ''; }
            else { pathOnly = raw || ''; }
          }
          var userInfo = '', host = authority, port = -1;
          var at = authority.lastIndexOf('@');
          if (at >= 0) { userInfo = authority.substring(0, at); host = authority.substring(at + 1); }
          var portMatch = host.match(/^(.*):(\\d+)$/);
          if (portMatch && portMatch[1].indexOf(']') < 0) { host = portMatch[1]; port = Number(portMatch[2]); }
          var protocol = scheme.toLowerCase();
          function defaultPort() { return protocol === 'http' ? 80 : (protocol === 'https' ? 443 : -1); }
          this.toString = function() { return raw; };
          this.toExternalForm = this.toString;
          this.getProtocol = function() { return protocol; };
          this.getHost = function() { return host; };
          this.getPort = function() { return port; };
          this.getDefaultPort = defaultPort;
          this.getPath = function() { return pathOnly || ''; };
          this.getQuery = function() { return queryOnly; };
          this.getRef = function() { return refOnly; };
          this.getFile = function() { return (pathOnly || '') + (queryOnly ? '?' + queryOnly : ''); };
          this.getAuthority = function() { return authority; };
          this.getUserInfo = function() { return userInfo; };
          this.getContent = function() { return ''; };
          this.normalize = function() {
            // Normalize only the path component; applying normalizePath to the
            // complete URL would incorrectly treat `https://host` as path data.
            var normalizedPath = normalizePath(pathOnly || '');
            var hasAuthority = scheme && raw.indexOf(scheme + '://') === 0;
            var rebuilt = (scheme ? scheme + ':' : '') + (hasAuthority ? '//' + authority : '') + normalizedPath;
            if (queryOnly) rebuilt += '?' + queryOnly;
            if (refOnly) rebuilt += '#' + refOnly;
            return new Packages.java.net.URL(rebuilt);
          };
          this.resolve = function(spec) { return new Packages.java.net.URL(String(spec || ''), raw); };
          this.toURI = function() { return new Packages.java.net.URI(raw); };
          this.toURL = function() { return this; };
          this.openConnection = function() { return __makeConnect(raw); };
        };
        Packages.java.net.URI = Packages.java.net.URI || function(value, baseValue) {
          var url = new Packages.java.net.URL(value, baseValue);
          this.toString = function() { return url.toString(); };
          this.toASCIIString = this.toString;
          this.getScheme = function() { return url.getProtocol(); };
          this.getHost = function() { return url.getHost(); };
          this.getPort = function() { return url.getPort(); };
          this.getAuthority = function() { return url.getAuthority(); };
          this.getUserInfo = function() { return url.getUserInfo(); };
          this.getPath = function() { return url.getPath(); };
          this.getQuery = function() { return url.getQuery(); };
          this.getFragment = function() { return url.getRef(); };
          this.normalize = function() { return new Packages.java.net.URI(new Packages.java.net.URL(url.toString()).normalize().toString()); };
          this.resolve = function(spec) { return new Packages.java.net.URI(url.resolve(spec).toString()); };
          this.toURL = function() { return url; };
        };
        Packages.java.net.URLEncoder = Packages.java.net.URLEncoder || {
          encode: function(value, charset) { return java.urlEncode(String(value == null ? '' : value)).replace(/%20/g, '+'); }
        };
        Packages.java.net.URLDecoder = Packages.java.net.URLDecoder || {
          decode: function(value, charset) { return java.decodeURI(String(value == null ? '' : value).replace(/\\+/g, '%20')); }
        };
        if (typeof URL === 'undefined') URL = Packages.java.net.URL;
        if (typeof URI === 'undefined') URI = Packages.java.net.URI;
        Packages.java.util = Packages.java.util || {};
        Packages.java.util.UUID = Packages.java.util.UUID || { randomUUID: java.randomUUID };
        Packages.java.util.Base64 = Packages.java.util.Base64 || {
          NO_WRAP: 2,
          DEFAULT: 0,
          getEncoder: function() {
            return { encodeToString: function(value) {
              var bytes = value && value.length != null && typeof value !== 'string' ? value : __native_stringToBytes(String(value == null ? '' : value));
              return __native_base64EncodeBytes(bytes);
            }, encode: function(value) {
              var bytes = value && value.length != null && typeof value !== 'string' ? value : __native_stringToBytes(String(value == null ? '' : value));
              // java.util.Base64.Encoder.encode(byte[]) returns the ASCII
              // bytes of the encoded payload (not the original input bytes).
              return __asJavaList(__native_stringToBytes(__native_base64EncodeBytes(__javaBytes(bytes))));
            }, withoutPadding: function() {
              var encoder = this;
              return { encodeToString: function(value) { return encoder.encodeToString(value).replace(/=+$/g, ''); }, encode: function(value) { return __asJavaList(__native_stringToBytes(encoder.encodeToString(value).replace(/=+$/g, ''))); } };
            } };
          },
          getUrlEncoder: function() {
            return { encodeToString: function(value) { return java.base64UrlEncode(value, true); }, encode: function(value) { return __asJavaList(__native_stringToBytes(java.base64UrlEncode(value, true))); }, withoutPadding: function() { return this; } };
          },
          getDecoder: function() {
            return { decode: function(value) {
              var encoded = value && value.length != null && typeof value !== 'string'
                ? String(__native_bytesToString(__javaBytes(value)) || '')
                : String(value == null ? '' : value);
              return java.base64DecodeToByteArray(encoded);
            } };
          },
          encodeToString: function(value) { return value && value.length != null ? __native_base64EncodeBytes(value) : java.base64Encode(String(value || '')); },
          encode: function(value) {
            var encoded = __native_base64EncodeBytes(value && value.length != null ? __javaBytes(value) : []);
            return __asJavaList(__native_stringToBytes(encoded));
          },
          decode: function(value) {
            var encoded = value && value.length != null && typeof value !== 'string'
              ? String(__native_bytesToString(__javaBytes(value)) || '')
              : String(value == null ? '' : value);
            return java.base64DecodeToByteArray(encoded);
          },
          getUrlDecoder: function() {
            return { decode: function(value) { return java.base64DecodeToByteArray(String(value == null ? '' : value).replace(/-/g, '+').replace(/_/g, '/')); } };
          }
        };
        Packages.java.security = Packages.java.security || {};
        Packages.java.security.MessageDigest = Packages.java.security.MessageDigest || {
          getInstance: function(algorithm) {
            var name = String(algorithm || 'SHA-256');
            var state = { bytes: [] };
            return {
              update: function(value, offset, length) {
                var source = value && value.length != null ? Array.prototype.slice.call(value) : [];
                var start = Math.max(0, Number(offset || 0));
                var count = length == null ? source.length - start : Math.max(0, Number(length));
                state.bytes = state.bytes.concat(source.slice(start, start + count));
                return this;
              },
              digest: function(value) {
                if (value !== undefined) this.update(value);
                var output = __asJavaList(__native_digestBytes(state.bytes, name));
                state.bytes = [];
                return output;
              },
              reset: function() { state.bytes = []; return this; },
              getAlgorithm: function() { return name; }
            };
          }
        };
        Packages.javax = Packages.javax || {};
        Packages.javax.crypto = Packages.javax.crypto || {};
        Packages.javax.crypto.spec = Packages.javax.crypto.spec || {};
        Packages.javax.crypto.spec.SecretKeySpec = Packages.javax.crypto.spec.SecretKeySpec || function(value, algorithm) {
          var start = 0;
          var length = value && value.length != null ? value.length : 0;
          var name = algorithm;
          if (arguments.length >= 4) {
            start = Math.max(0, Number(arguments[1] || 0));
            length = Math.max(0, Number(arguments[2] || 0));
            name = arguments[3];
          }
          var source = value && value.length != null ? Array.prototype.slice.call(value) : [];
          this.bytes = source.slice(start, start + length);
          this.algorithm = String(name || 'HmacSHA1');
          this.getEncoded = function() { return this.bytes; };
        };
        Packages.javax.crypto.spec.IvParameterSpec = Packages.javax.crypto.spec.IvParameterSpec || function(value) {
          var start = arguments.length >= 3 ? Math.max(0, Number(arguments[1] || 0)) : 0;
          var length = arguments.length >= 3 ? Math.max(0, Number(arguments[2] || 0)) : (value && value.length != null ? value.length : 0);
          var source = value && value.length != null ? Array.prototype.slice.call(value) : [];
          this.bytes = source.slice(start, start + length);
          this.getIV = function() { return this.bytes.slice(); };
        };
        Packages.javax.crypto.Cipher = Packages.javax.crypto.Cipher || {
          DECRYPT_MODE: 2,
          ENCRYPT_MODE: 1,
          getInstance: function(transformation) {
            var state = { transformation: String(transformation || 'AES/CBC/PKCS5Padding'), mode: 2, key: [], iv: [] };
            return {
              init: function(mode, keySpec, ivSpec) {
                state.mode = Number(mode || 2);
                state.key = keySpec && keySpec.bytes ? keySpec.bytes : (keySpec && keySpec.getEncoded ? keySpec.getEncoded() : keySpec);
                state.iv = ivSpec && ivSpec.bytes ? ivSpec.bytes : (ivSpec && ivSpec.getIV ? ivSpec.getIV() : []);
                return this;
              },
              update: function(value) { return this.doFinal(value); },
              doFinal: function(value) {
                var method = state.mode === 1 ? 'cipherEncryptBytes' : 'cipherDecryptBytes';
                var input = value && value.length != null ? value : [];
                return __asJavaList(__nativeLegado.invoke({ method: method, args: [input, state.key || [], state.transformation, state.iv || []] }));
              }
            };
          }
        };
        Packages.javax.crypto.Mac = Packages.javax.crypto.Mac || {
          getInstance: function(algorithm) {
            var state = { key: [], algorithm: String(algorithm || 'HmacSHA1') };
            var pending = [];
            return {
              init: function(secret) { state.key = secret && secret.bytes ? secret.bytes : secret; pending = []; return this; },
              update: function(value) { if (value && value.length != null) pending = pending.concat(Array.prototype.slice.call(value)); return this; },
              doFinal: function(value) {
                if (value !== undefined) this.update(value);
                var output = __asJavaList(__native_hmacBytes(pending, state.algorithm, state.key && state.key.length != null ? state.key : []));
                pending = [];
                return output;
              },
              reset: function() { pending = []; return this; }
            };
          }
        };
        var javax = Packages.javax;
        Packages.java.util.HashMap = Packages.java.util.HashMap || function(initial) {
          var self = this;
          this.__map = Object.create(null);
          this.put = function(key, value) { var k = String(key); var old = this.__map[k]; this.__map[k] = value; return old == null ? null : old; };
          this.putAll = function(other) {
            if (!other) return this;
            if (typeof other.entrySet === 'function') { var entries = other.entrySet(); for (var i = 0; i < entries.length; i++) this.put(entries[i].getKey(), entries[i].getValue()); }
            else { for (var k in other) if (Object.prototype.hasOwnProperty.call(other, k)) this.put(k, other[k]); }
            return this;
          };
          this.get = function(key) { var value = this.__map[String(key)]; return value == null ? null : value; };
          this.getOrDefault = function(key, fallback) { var k = String(key); return Object.prototype.hasOwnProperty.call(this.__map, k) ? this.__map[k] : fallback; };
          this.remove = function(key) { var k = String(key); var old = this.__map[k]; delete this.__map[k]; return old == null ? null : old; };
          this.containsKey = function(key) { return Object.prototype.hasOwnProperty.call(this.__map, String(key)); };
          this.containsValue = function(value) { var keys = Object.keys(this.__map); for (var i = 0; i < keys.length; i++) if (this.__map[keys[i]] === value || String(this.__map[keys[i]]) === String(value)) return true; return false; };
          this.replace = function(key, oldValue, newValue) {
            var k = String(key);
            if (arguments.length > 2) { if (!this.containsKey(k) || (this.__map[k] !== oldValue && String(this.__map[k]) !== String(oldValue))) return false; this.__map[k] = newValue; return true; }
            if (!this.containsKey(k)) return null; var old = this.__map[k]; this.__map[k] = oldValue; return old;
          };
          this.replaceAll = function(fn) { var keys = Object.keys(this.__map); for (var i = 0; i < keys.length; i++) { var key = keys[i], old = this.__map[key]; this.__map[key] = typeof fn === 'function' ? fn(key, old) : (fn && typeof fn.apply === 'function' ? fn.apply(key, old) : old); } return this; };
          this.forEach = function(fn) { var keys = Object.keys(this.__map); for (var i = 0; i < keys.length; i++) { if (fn && typeof fn.accept === 'function') fn.accept(keys[i], this.__map[keys[i]]); else if (typeof fn === 'function') fn(keys[i], this.__map[keys[i]], this); } };
          this.isEmpty = function() { return Object.keys(this.__map).length === 0; };
          this.size = function() { return Object.keys(this.__map).length; };
          this.clear = function() { this.__map = Object.create(null); };
          this.keySet = function() { return __asJavaList(Object.keys(this.__map)); };
          this.values = function() { var out = []; var keys = Object.keys(this.__map); for (var i = 0; i < keys.length; i++) out.push(this.__map[keys[i]]); return __asJavaList(out); };
          this.entrySet = function() {
            var out = [], keys = Object.keys(self.__map);
            for (var i = 0; i < keys.length; i++) (function(key) {
              out.push({ getKey: function() { return key; }, getValue: function() { return self.__map[key]; }, setValue: function(value) { var old = self.__map[key]; self.__map[key] = value; return old; } });
            })(keys[i]);
            return __asJavaList(out);
          };
          this.toString = function() { return JSON.stringify(this.__map); };
          if (initial) this.putAll(initial);
        };
        Packages.java.util.LinkedHashMap = Packages.java.util.LinkedHashMap || Packages.java.util.HashMap;
        Packages.java.util.TreeMap = Packages.java.util.TreeMap || Packages.java.util.HashMap;
        Packages.java.util.HashSet = Packages.java.util.HashSet || function(initial) {
          var values = [];
          function indexOf(value) {
            for (var i = 0; i < values.length; i++) if (values[i] === value || String(values[i]) === String(value)) return i;
            return -1;
          }
          var seed = initial && typeof initial.toArray === 'function' ? initial.toArray() : (initial && initial.length != null ? initial : []);
          for (var i = 0; i < seed.length; i++) if (indexOf(seed[i]) < 0) values.push(seed[i]);
          this.add = function(value) { if (indexOf(value) >= 0) return false; values.push(value); return true; };
          this.addAll = function(other) { var changed = false; var list = other && other.toArray ? other.toArray() : (other || []); for (var i = 0; i < list.length; i++) changed = this.add(list[i]) || changed; return changed; };
          this.remove = function(value) { var index = indexOf(value); if (index < 0) return false; values.splice(index, 1); return true; };
          this.contains = function(value) { return indexOf(value) >= 0; };
          this.size = function() { return values.length; };
          this.isEmpty = function() { return values.length === 0; };
          this.clear = function() { values = []; };
          this.toArray = function() { return __asJavaList(values.slice()); };
          this.iterator = function() { var index = 0; return { hasNext: function() { return index < values.length; }, next: function() { return values[index++]; } }; };
          this.toString = function() { return '[' + values.join(', ') + ']'; };
        };
        Packages.java.util.LinkedHashSet = Packages.java.util.LinkedHashSet || Packages.java.util.HashSet;
        Packages.java.util.ArrayList = Packages.java.util.ArrayList || function(initial) {
          var values = [];
          if (initial) {
            if (initial.length != null && typeof initial !== 'string') values = Array.prototype.slice.call(initial);
            else if (typeof initial.toArray === 'function') values = initial.toArray();
          }
          this.add = function(index, value) {
            if (arguments.length > 1) { values.splice(Math.max(0, Number(index) || 0), 0, value); return true; }
            values.push(index); return true;
          };
          this.addAll = function(index, other) {
            if (arguments.length > 1) { var at = Math.max(0, Math.min(values.length, Number(index) || 0)); var list = other && other.toArray ? other.toArray() : (other && other.length != null ? Array.prototype.slice.call(other) : []); values.splice.apply(values, [at, 0].concat(list)); return list.length > 0; }
            var list = index && index.toArray ? index.toArray() : (index && index.length != null && typeof index !== 'string' ? Array.prototype.slice.call(index) : []);
            for (var i = 0; i < list.length; i++) values.push(list[i]); return list.length > 0;
          };
          this.get = function(index) { return values[Number(index)]; };
          this.set = function(index, value) { var old = values[Number(index)]; values[Number(index)] = value; return old; };
          this.removeAt = function(index) { var i = Number(index) || 0; return i >= 0 && i < values.length ? values.splice(i, 1)[0] : null; };
          this.remove = function(index) {
            if (typeof index === 'number' || /^-?\\d+$/.test(String(index))) return this.removeAt(index);
            var match = values.indexOf(index); return match >= 0 ? values.splice(match, 1)[0] : null;
          };
          this.removeAll = function(other) { var list = other && other.toArray ? other.toArray() : (other || []), before = values.length; values = values.filter(function(item) { return list.indexOf(item) < 0; }); return values.length !== before; };
          this.retainAll = function(other) { var list = other && other.toArray ? other.toArray() : (other || []), before = values.length; values = values.filter(function(item) { return list.indexOf(item) >= 0; }); return values.length !== before; };
          this.sort = function(comparator) { values.sort(function(a, b) { if (comparator && typeof comparator.compare === 'function') return Number(comparator.compare(a, b)) || 0; if (typeof comparator === 'function') return Number(comparator(a, b)) || 0; return String(a).localeCompare(String(b)); }); return this; };
          this.forEach = function(fn) { for (var i = 0; i < values.length; i++) fn(values[i], i, this); };
          this.contains = function(value) { return values.indexOf(value) >= 0; };
          this.indexOf = function(value) { return values.indexOf(value); };
          this.lastIndexOf = function(value) { return values.lastIndexOf(value); };
          this.containsAll = function(other) { var list = other && other.toArray ? other.toArray() : (other || []); for (var i = 0; i < list.length; i++) if (values.indexOf(list[i]) < 0) return false; return true; };
          this.subList = function(start, end) { return __asJavaList(values.slice(Number(start) || 0, end == null ? values.length : Number(end))); };
          this.clear = function() { values = []; };
          this.first = function() { return values.length ? values[0] : null; };
          this.last = function() { return values.length ? values[values.length - 1] : null; };
          this.size = function() { return values.length; };
          this.isEmpty = function() { return values.length === 0; };
          this.toArray = function() { return values.slice(); };
          this.iterator = function() { var index = 0; return { hasNext: function() { return index < values.length; }, next: function() { return values[index++]; } }; };
          this.toString = function() { return values.join(','); };
        };
        Packages.java.util.zip = Packages.java.util.zip || {};
        Packages.java.util.zip.InflaterInputStream = Packages.java.util.zip.InflaterInputStream || function(input) {
          var raw = input && input.__bytes ? input.__bytes : (input && input.__javaBytes ? input.__javaBytes : input);
          // A Swift-injected NSArray can expose `count` but no JavaScript
          // `length`.  Do not discard that host-backed value before it reaches
          // the native bridge; the bridge reads JSValue arrays by index and
          // also understands NSArray/count-backed objects.
          var inflated = java.inflate(raw == null ? [] : raw);
          var index = 0;
          this.read = function(buffer, offset, length) {
            if (buffer && buffer.length != null) {
              var start = Number(offset || 0);
              var requested = length == null ? buffer.length - start : Number(length);
              var count = Math.min(Math.max(0, requested), inflated.length - index);
              for (var i = 0; i < count; i++) buffer[start + i] = inflated[index++];
              return count > 0 ? count : -1;
            }
            return index < inflated.length ? Number(inflated[index++]) : -1;
          };
          this.available = function() { return Math.max(0, inflated.length - index); };
          this.close = function() {};
        };
        Packages.java.util.zip.GZIPInputStream = Packages.java.util.zip.GZIPInputStream || function(input) {
          var raw = input && input.__bytes ? input.__bytes : (input && input.__javaBytes ? input.__javaBytes : input);
          var inflated = java.gunzip(raw == null ? [] : raw);
          var index = 0;
          this.read = function(buffer, offset, length) {
            if (buffer && buffer.length != null) {
              var start = Number(offset || 0);
              var requested = length == null ? buffer.length - start : Number(length);
              var count = Math.min(Math.max(0, requested), inflated.length - index);
              for (var i = 0; i < count; i++) buffer[start + i] = inflated[index++];
              return count > 0 ? count : -1;
            }
            return index < inflated.length ? Number(inflated[index++]) : -1;
          };
          this.available = function() { return Math.max(0, inflated.length - index); };
          this.close = function() {};
        };
        Packages.java.util.regex = Packages.java.util.regex || {};
        function __javaRegexFlags(flags) {
          if (flags === undefined || flags === null) return '';
          if (typeof flags === 'number' || /^\\d+$/.test(String(flags))) {
            var bits = Number(flags);
            var numericFlags = '';
            if ((bits & 2) !== 0) numericFlags += 'i';   // CASE_INSENSITIVE
            if ((bits & 8) !== 0) numericFlags += 'm';   // MULTILINE
            if ((bits & 32) !== 0) numericFlags += 's';  // DOTALL
            if ((bits & 64) !== 0) numericFlags += 'u';  // UNICODE_CASE
            return numericFlags;
          }
          var textFlags = String(flags);
          var mapped = '';
          if (/[iI]/.test(textFlags) || /CASE_INSENSITIVE/i.test(textFlags)) mapped += 'i';
          if (/[mM]/.test(textFlags) || /MULTILINE/i.test(textFlags)) mapped += 'm';
          if (/[sS]/.test(textFlags) || /DOTALL/i.test(textFlags)) mapped += 's';
          if (/[uU]/.test(textFlags) || /UNICODE/i.test(textFlags)) mapped += 'u';
          return mapped;
        }
        function __javaGroupCount(pattern) {
          var count = 0, escaped = false, inClass = false;
          var text = String(pattern || '');
          for (var i = 0; i < text.length; i++) {
            var ch = text.charAt(i);
            if (escaped) { escaped = false; continue; }
            if (ch === '\\\\') { escaped = true; continue; }
            if (ch === '[') { inClass = true; continue; }
            if (ch === ']' && inClass) { inClass = false; continue; }
            if (inClass || ch !== '(') continue;
            if (text.charAt(i + 1) !== '?') count++;
            else if (text.charAt(i + 2) === '<' && text.charAt(i + 3) !== '=' && text.charAt(i + 3) !== '!') count++;
          }
          return count;
        }
        function __javaRegex(pattern, flags, global) {
          var effectiveFlags = String(flags || '');
          if (global && effectiveFlags.indexOf('g') < 0) effectiveFlags += 'g';
          // RegExp indices (`d`) provide Java-compatible offsets for nested or
          // repeated capture text.  iOS 16+ JavaScriptCore supports them; keep
          // a fallback for older runtimes instead of failing the whole rule.
          try { return new RegExp(pattern, effectiveFlags.indexOf('d') >= 0 ? effectiveFlags : effectiveFlags + 'd'); }
          catch (_) { return new RegExp(pattern, effectiveFlags.replace(/d/g, '')); }
        }
        Packages.java.util.regex.Pattern = Packages.java.util.regex.Pattern || {
          CASE_INSENSITIVE: 2,
          MULTILINE: 8,
          DOTALL: 32,
          UNICODE_CASE: 64,
          compile: function(pattern, flags) {
            var source = String(pattern == null ? '' : pattern);
            var patternFlags = __javaRegexFlags(flags);
            var compiledGroupCount = __javaGroupCount(source);
            return {
              matcher: function(input) {
                var text = String(input == null ? '' : input);
                var re;
                try { re = __javaRegex(source, patternFlags, false); } catch (_) { re = /$a/; }
                var cursor = 0;
                var regionStart = 0;
                var regionEnd = text.length;
                var lastMatch = null;
                return {
                  reset: function(value) { if (value !== undefined && value !== null) text = String(value); cursor = regionStart = 0; regionEnd = text.length; lastMatch = null; return this; },
                  region: function(start, end) { regionStart = Math.max(0, Number(start) || 0); regionEnd = Math.max(regionStart, Math.min(text.length, Number(end) || 0)); cursor = regionStart; lastMatch = null; return this; },
                  find: function(start) {
                    // Java Matcher.find() advances across repeated calls.
                    if (start !== undefined && start !== null) cursor = Math.max(regionStart, Math.min(regionEnd, Number(start) || 0));
                    try { re = __javaRegex(source, patternFlags, true); } catch (_) { return false; }
                    var regionText = text.substring(regionStart, regionEnd);
                    re.lastIndex = Math.max(0, cursor - regionStart);
                    lastMatch = re.exec(regionText);
                    if (!lastMatch) { lastMatch = null; return false; }
                    lastMatch.__regionOffset = regionStart;
                    lastMatch.index += regionStart;
                    cursor = regionStart + re.lastIndex;
                    if (lastMatch[0] === '') cursor++;
                    return true;
                  },
                  matches: function() {
                    try {
                      var regionText = text.substring(regionStart, regionEnd);
                      var match = __javaRegex('^(?:' + source + ')$', patternFlags, false).exec(regionText);
                      lastMatch = match;
                      if (match) { match.__regionOffset = regionStart; match.index += regionStart; }
                      return !!match;
                    } catch (_) { lastMatch = null; return false; }
                  },
                  lookingAt: function() {
                    try {
                      var regionText = text.substring(regionStart, regionEnd);
                      var match = __javaRegex('^(?:' + source + ')', patternFlags, false).exec(regionText);
                      lastMatch = match;
                      if (match) { match.__regionOffset = regionStart; match.index += regionStart; }
                      return !!match;
                    } catch (_) { lastMatch = null; return false; }
                  },
                  group: function(index) {
                    if (!lastMatch) {
                      try { lastMatch = __javaRegex(source, patternFlags, false).exec(text); if (lastMatch) lastMatch.__regionOffset = 0; } catch (_) { lastMatch = null; }
                    }
                    if (!lastMatch) return '';
                    var position = index == null ? 0 : Number(index);
                    return lastMatch[position] == null ? null : String(lastMatch[position]);
                  },
                  start: function(index) {
                    if (!lastMatch) return -1;
                    var position = index == null ? 0 : Number(index);
                    if (position === 0) return lastMatch.index;
                    var group = lastMatch[position]; if (group == null) return -1;
                    if (lastMatch.indices && lastMatch.indices[position]) return Number(lastMatch.__regionOffset || 0) + lastMatch.indices[position][0];
                    return lastMatch.index + String(lastMatch[0]).indexOf(String(group));
                  },
                  end: function(index) {
                    if (!lastMatch) return -1;
                    var position = index == null ? 0 : Number(index);
                    if (position === 0) return lastMatch.index + String(lastMatch[0]).length;
                    var group = lastMatch[position]; if (group == null) return -1;
                    if (lastMatch.indices && lastMatch.indices[position]) return Number(lastMatch.__regionOffset || 0) + lastMatch.indices[position][1];
                    return this.start(position) + String(group).length;
                  },
                  groupCount: function() { return compiledGroupCount; }
                  ,hitEnd: function() { return !lastMatch || (lastMatch.index + String(lastMatch[0] || '').length >= regionEnd); }
                  ,requireEnd: function() { return false; }
                  ,regionStart: function() { return regionStart; }
                  ,regionEnd: function() { return regionEnd; }
                  ,replaceAll: function(replacement) {
                    var regionText = text.substring(regionStart, regionEnd), replacementText = String(replacement == null ? '' : replacement);
                    try { return text.substring(0, regionStart) + regionText.replace(__javaRegex(source, patternFlags, true), replacementText) + text.substring(regionEnd); }
                    catch (_) { return text; }
                  }
                  ,replaceFirst: function(replacement) {
                    var regionText = text.substring(regionStart, regionEnd), replacementText = String(replacement == null ? '' : replacement);
                    try { return text.substring(0, regionStart) + regionText.replace(__javaRegex(source, patternFlags, false), replacementText) + text.substring(regionEnd); }
                    catch (_) { return text; }
                  }
                };
              }
              ,pattern: function() { return source; }
              ,flags: function() { return patternFlags; }
              ,toString: function() { return source; }
            };
          }
          ,quote: function(value) { return String(value == null ? '' : value).replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&'); }
          ,matches: function(pattern, input) { return this.compile(pattern).matcher(input).matches(); }
          ,split: function(input, limit) {
            try { var values = String(input == null ? '' : input).split(__javaRegex(this.toString ? this.toString() : '', '', false)); return __asJavaList(values); } catch (_) { return __asJavaList([String(input == null ? '' : input)]); }
          }
        };
        // Static Pattern helpers above need a regex source; keep split as a
        // function on compiled instances too for Java-compatible call sites.
        var __patternCompile = Packages.java.util.regex.Pattern.compile;
        Packages.java.util.regex.Pattern.compile = function(pattern, flags) {
          var compiled = __patternCompile(pattern, flags);
          compiled.split = function(input, limit) { try { var values = String(input == null ? '' : input).split(new RegExp(String(pattern || ''), __javaRegexFlags(flags))); if (limit != null && Number(limit) > 0) values = values.slice(0, Number(limit)); return __asJavaList(values); } catch (_) { return __asJavaList([String(input == null ? '' : input)]); } };
          return compiled;
        };
        Packages.android = Packages.android || {};
        Packages.android.os = Packages.android.os || { Build: { MODEL: 'iPhone', MANUFACTURER: 'Apple', BRAND: 'Apple' } };
        Packages.android.text = Packages.android.text || { TextUtils: { isEmpty: function(value) { return value == null || String(value).length === 0; } } };
        Packages.android.util = Packages.android.util || { Base64: Packages.java.util.Base64 };
        var android = Packages.android;
        Packages.util = Packages.java.util;
        java.lang = Packages.java.lang;
        java.util = Packages.java.util;
        java.net = Packages.java.net;
        java.io = Packages.java.io;
        java.security = Packages.java.security;
        java.util.zip = Packages.java.util.zip;
        var javax = Packages.javax;
        Packages.org.jsoup.Jsoup.__javaSimpleName = 'Jsoup';
        Packages.java.lang.String.__javaSimpleName = 'String';
        Packages.java.lang.Integer.__javaSimpleName = 'Integer';
        Packages.java.lang.Long.__javaSimpleName = 'Long';
        Packages.java.util.Arrays.__javaSimpleName = 'Arrays';
        Packages.java.util.ArrayList.__javaSimpleName = 'ArrayList';
        Packages.java.util.HashMap.__javaSimpleName = 'HashMap';
        Packages.java.net.URLEncoder.__javaSimpleName = 'URLEncoder';
        Packages.java.net.URLDecoder.__javaSimpleName = 'URLDecoder';
        Packages.java.net.URI.__javaSimpleName = 'URI';
        Packages.java.io.ByteArrayInputStream.__javaSimpleName = 'ByteArrayInputStream';
        Packages.java.io.ByteArrayOutputStream.__javaSimpleName = 'ByteArrayOutputStream';
        Packages.java.util.zip.InflaterInputStream.__javaSimpleName = 'InflaterInputStream';
        Packages.java.util.zip.GZIPInputStream.__javaSimpleName = 'GZIPInputStream';
        Packages.java.security.MessageDigest.__javaSimpleName = 'MessageDigest';
        Packages.javax.crypto.Mac.__javaSimpleName = 'Mac';
        Packages.javax.crypto.spec.SecretKeySpec.__javaSimpleName = 'SecretKeySpec';
        Packages.javax.crypto.spec.IvParameterSpec.__javaSimpleName = 'IvParameterSpec';
        Packages.javax.crypto.Cipher.__javaSimpleName = 'Cipher';
        function JavaImporter() {
          var importer = {
            importPackage: function(packageRef) {
              if (packageRef && typeof packageRef === 'object') {
                for (var key in packageRef) if (/^[A-Za-z_$][\\w$]*$/.test(key)) importer[key] = packageRef[key];
              }
              return importer;
            },
            importClass: function(classRef) {
              var name = classRef && classRef.__javaSimpleName ? String(classRef.__javaSimpleName) : '';
              if (name) importer[name] = classRef;
              return classRef;
            },
            String: Packages.java.lang.String,
            Integer: Packages.java.lang.Integer,
            Long: Packages.java.lang.Long,
            Arrays: Packages.java.util.Arrays,
            ArrayList: Packages.java.util.ArrayList,
            HashMap: Packages.java.util.HashMap,
            URLEncoder: Packages.java.net.URLEncoder,
            URLDecoder: Packages.java.net.URLDecoder,
            URI: Packages.java.net.URI,
            MessageDigest: Packages.java.security.MessageDigest,
            Mac: Packages.javax.crypto.Mac,
            Cipher: Packages.javax.crypto.Cipher,
            SecretKeySpec: Packages.javax.crypto.spec.SecretKeySpec,
            IvParameterSpec: Packages.javax.crypto.spec.IvParameterSpec,
            ByteArrayOutputStream: Packages.java.io.ByteArrayOutputStream,
            InflaterInputStream: Packages.java.util.zip.InflaterInputStream,
            GZIPInputStream: Packages.java.util.zip.GZIPInputStream,
            Jsoup: Packages.org.jsoup.Jsoup,
            Base64: Packages.java.util.Base64
          };
          return importer;
        }
        function importClass(value) {
          var name = value && value.__javaSimpleName ? String(value.__javaSimpleName) : '';
          if (name && typeof globalThis !== 'undefined') globalThis[name] = value;
          return value;
        }
        function importPackage(value) {
          if (value && typeof value === 'object' && typeof globalThis !== 'undefined') {
            for (var key in value) if (/^[A-Za-z_$][\\w$]*$/.test(key)) globalThis[key] = value[key];
          }
          return value;
        }
        var org = Packages.org;
        function __selectorWithIndex(selector, index) {
          if (index === undefined || index === null || isNaN(Number(index))) return String(selector || '');
          return String(selector || '') + '@' + String(Number(index));
        }
        function __makeJsoupSelection(docState, selector, baseUrlValue, selectionIndex) {
          return {
            select: function(nextSelector) {
              var baseSelector = __selectorWithIndex(selector, selectionIndex);
              if (selectionIndex !== undefined && selectionIndex !== null && !isNaN(Number(selectionIndex))) {
                var subHtml = __native_getString(String(docState.html), baseSelector + '@html', String(baseUrlValue || ''));
                return __makeJsoupSelection({ html: subHtml }, String(nextSelector), baseUrlValue);
              }
              var joined = baseSelector ? baseSelector + ' ' + String(nextSelector) : String(nextSelector);
              return __makeJsoupSelection(docState, joined, baseUrlValue);
            },
            first: function() { return __makeJsoupSelection(docState, selector, baseUrlValue, 0); },
            get: function(index) { return __makeJsoupSelection(docState, selector, baseUrlValue, Number(index)); },
            eq: function(index) { return __makeJsoupSelection(docState, selector, baseUrlValue, Number(index)); },
            size: function() { return __native_countElements(String(docState.html), String(selector), String(baseUrlValue || '')); },
            isEmpty: function() { return this.size() === 0; },
            text: function() {
              var selected = __selectorWithIndex(selector, selectionIndex);
              var list = __native_getStringList(String(docState.html), selected + '@text', String(baseUrlValue || ''));
              var out = [];
              for (var i = 0; i < list.length; i++) out.push(String(list[i]));
              return out.join('\\n');
            },
            html: function() {
              var selected = __selectorWithIndex(selector, selectionIndex);
              return __native_getString(String(docState.html), selected + '@html', String(baseUrlValue || ''));
            },
            outerHtml: function() {
              var selected = __selectorWithIndex(selector, selectionIndex);
              return __native_getString(String(docState.html), selected + '@html', String(baseUrlValue || ''));
            },
            attr: function(name) {
              var selected = __selectorWithIndex(selector, selectionIndex);
              return __native_getString(String(docState.html), selected + '@' + String(name), String(baseUrlValue || ''));
            },
            eachText: function() {
              var selected = __selectorWithIndex(selector, selectionIndex);
              var list = __native_getStringList(String(docState.html), selected + '@text', String(baseUrlValue || ''));
              var out = [];
              for (var i = 0; i < list.length; i++) out.push(String(list[i]));
              return __asJavaList(out);
            },
            children: function() {
              return this.select("> *");
            },
            parents: function() {
              var selected = __selectorWithIndex(selector, selectionIndex);
              var parentHtmls = __native_getParents(String(docState.html), selected, String(baseUrlValue || ''));
              var list = [];
              for (var i = 0; i < parentHtmls.length; i++) list.push(String(parentHtmls[i]));
              return __makeJsoupSelection({ html: list.join('') }, '', baseUrlValue);
            },
            remove: function() {
              var selected = __selectorWithIndex(selector, selectionIndex);
              if (selected) {
                docState.html = __native_removeElements(String(docState.html), selected);
              }
              return this;
            }
          };
        }
        // The overload-aware java.getElements implementation is installed above.
        Packages.org.jsoup.Jsoup = {
          parse: function(html, baseUrlValue) {
            var resolvedBase = String(baseUrlValue || (typeof baseUrl === 'undefined' ? '' : baseUrl));
            if (resolvedBase) return __nativeJsoup.parseWithBase({ html: String(html), baseUrl: resolvedBase });
            return __nativeJsoup.parse(String(html));
          },
          connect: __makeConnect
        };
        java.jsoup = java.jsoup || {
          parse: function(html, baseUrlValue) { return Packages.org.jsoup.Jsoup.parse(String(html || ''), baseUrlValue); },
          select: function(html, selector) { return Packages.org.jsoup.Jsoup.parse(String(html || '')).select(String(selector || '')); },
          selectFirst: function(html, selector) {
            var selection = java.jsoup.select(html, selector);
            if (!selection || typeof selection.first !== 'function' || selection.isEmpty()) return '';
            var node = selection.first();
            return node && typeof node.text === 'function' ? String(node.text()) : String(node || '');
          },
          getAttr: function(html, selector, attr) {
            var selection = java.jsoup.select(html, selector);
            if (!selection || typeof selection.first !== 'function' || selection.isEmpty()) return '';
            var node = selection.first();
              return node && typeof node.rawAttr === 'function' ? String(node.rawAttr(String(attr || '')) || '') : (node && typeof node.attr === 'function' ? String(node.attr(String(attr || '')) || '') : '');
          },
          clean: function(html) { return java.htmlFormat(String(html || '')); }
        };
        // Global aliases used by Android Legado/MR sources.  Keep the return
        // shape deliberately small and predictable: `select` is an array of
        // outerHTML strings, `selectFirst`/`getAttr` are scalar strings.
        function select(html, selector) {
          var selection = java.jsoup.select(String(html || ''), String(selector || ''));
          var out = [];
          var count = selection && typeof selection.size === 'function' ? selection.size() : 0;
          for (var i = 0; i < count; i++) {
            var node = selection.get(i);
            out.push(node && typeof node.outerHtml === 'function' ? String(node.outerHtml()) : String(node || ''));
          }
          return __asJavaList(out);
        }
        function selectFirst(html, selector) {
          var selection = java.jsoup.select(String(html || ''), String(selector || ''));
          if (!selection || typeof selection.first !== 'function' || selection.isEmpty()) return '';
          var node = selection.first();
          return node && typeof node.text === 'function' ? String(node.text()) : String(node || '');
        }
        function getAttr(html, selector, attr) {
          var name = String(attr || '').trim();
          if (!name) return '';
          var selection = java.jsoup.select(String(html || ''), String(selector || 'body'));
          if (!selection || typeof selection.first !== 'function' || selection.isEmpty()) return '';
          var node = selection.first();
           return node && typeof node.rawAttr === 'function' ? String(node.rawAttr(name) || '') : (node && typeof node.attr === 'function' ? String(node.attr(name) || '') : '');
        }
        function clean(html) { return java.htmlFormat(String(html == null ? '' : html)); }
        function htmlFormat(value) { return java.htmlFormat(value); }
        function getString() { return java.getString.apply(java, arguments); }
        function getStringList() { return java.getStringList.apply(java, arguments); }
        function getStr(key, fallback) { return java.getStr(key, fallback); }
        function put() { return java.put.apply(java, arguments); }
        function ajax() { return java.ajax.apply(java, arguments); }
        function request() { return java.fetch.apply(java, arguments); }
        function fetch() { return java.fetch.apply(java, arguments); }
        function importScript() { return java.importScript.apply(java, arguments); }
        function getWebViewUA() { return java.getWebViewUA(); }
        function md5Encode() { return java.md5Encode.apply(java, arguments); }
        function sha1Encode() { return java.sha1Encode.apply(java, arguments); }
        function sha256Encode() { return java.sha256Encode.apply(java, arguments); }
        function sha512Encode() { return java.sha512Encode.apply(java, arguments); }
        // Keep aliases available as properties as well as top-level function
        // declarations; some scripts explicitly access globalThis/window.
        if (typeof globalThis !== 'undefined') {
          globalThis.select = select;
          globalThis.selectFirst = selectFirst;
          globalThis.getAttr = getAttr;
          globalThis.clean = clean;
          globalThis.htmlFormat = htmlFormat;
          globalThis.getString = getString;
          globalThis.getStringList = getStringList;
          globalThis.getStr = getStr;
          globalThis.put = put;
          globalThis.ajax = ajax;
          globalThis.request = request;
          globalThis.fetch = fetch;
          globalThis.importScript = importScript;
          globalThis.getWebViewUA = getWebViewUA;
          globalThis.base64Encode = function() { return java.base64Encode.apply(java, arguments); };
          globalThis.base64Decode = function() { return java.base64Decode.apply(java, arguments); };
          globalThis.md5Encode = md5Encode;
          globalThis.sha1Encode = sha1Encode;
          globalThis.sha256Encode = sha256Encode;
          globalThis.sha512Encode = sha512Encode;
          globalThis.sha224Encode = function(value) { return java.sha224Encode(value); };
          globalThis.sha384Encode = function(value) { return java.sha384Encode(value); };
          globalThis.sha348Encode = function(value) { return java.sha348Encode(value); };
          globalThis.ripemd160Encode = function(value) { return java.ripemd160Encode(value); };
          globalThis.rsaEncrypt = function(value, key) { return java.rsaEncrypt(value, key); };
          globalThis.rsaDecrypt = function(value, key) { return java.rsaDecrypt(value, key); };
          globalThis.RSA_encrypt = function(value, key) { return java.RSA_encrypt(value, key); };
          globalThis.RSA_decrypt = function(value, key) { return java.RSA_decrypt(value, key); };
          globalThis.RSA_encryptWithPrivate = function(value, key) { return java.RSA_encryptWithPrivate(value, key); };
          globalThis.RSA_decryptWithPublic = function(value, key) { return java.RSA_decryptWithPublic(value, key); };
          globalThis.digestBase64Str = function(value, algorithm) { return java.digestBase64Str(value, algorithm); };
          globalThis.uriEncode = function(value) { return java.uriEncode(value); };
          globalThis.uriDecode = function(value) { return java.uriDecode(value); };
          globalThis.timeFormatUTC = function(value) { return java.timeFormatUTC(value); };
          globalThis.putCache = function(key, value) { return java.putCache(key, value); };
          globalThis.getCache = function(key) { return java.getCache(key); };
          globalThis.putField = function(key, value) { return java.putField(key, value); };
          globalThis.getField = function(key) { return java.getField(key); };
        }
        java.regex = java.regex || {};
        java.regex.replace = function(value, pattern, replacement) {
          var text = String(value == null ? '' : value);
          var source = String(pattern == null ? '' : pattern);
          try { return text.replace(new RegExp(source, 'g'), String(replacement == null ? '' : replacement)); }
          catch (_) { return text; }
        };
        java.regex.matchAll = function(value, pattern) {
          var text = String(value == null ? '' : value);
          var source = String(pattern == null ? '' : pattern);
          var out = [];
          try {
            var re = new RegExp(source, 'g');
            var match;
            while ((match = re.exec(text)) !== null) {
              out.push(String(match[0]));
              // Avoid an infinite loop for zero-width expressions.
              if (match[0] === '') re.lastIndex++;
            }
          } catch (_) {}
          return __asJavaList(out);
        };
        java.regex.test = function(value, pattern) {
          try { return new RegExp(String(pattern == null ? '' : pattern)).test(String(value == null ? '' : value)); }
          catch (_) { return false; }
        };
        var ruleResolver = {
          chapter: (typeof chapter === 'undefined' ? null : chapter),
          book: (typeof book === 'undefined' ? null : book),
          nextChapterUrl: (typeof nextChapterUrl === 'undefined' ? '' : nextChapterUrl),
          setContent: function(content, baseUrlValue) {
            if (baseUrlValue != null && String(baseUrlValue) !== '') baseUrl = String(baseUrlValue);
            result = String(content == null ? '' : content);
            return __nativeRule.setContent(result);
          },
          getString: function(rule, isUrl, content) {
            var htmlValue = content == null ? __defaultHtml() : String(content);
            var value = __native_getString(htmlValue, String(rule || ''), __defaultBaseUrl());
            if (isUrl === true && value) {
              try { return String(new URL(value, __defaultBaseUrl())); } catch (_) {}
            }
            return value;
          },
          getStringList: function(rule, isUrl) {
            var values = __native_getStringList(__defaultHtml(), String(rule || ''), __defaultBaseUrl());
            var out = [];
            for (var i = 0; values && i < values.length; i++) {
              var value = String(values[i]);
              if (isUrl === true && value) { try { value = String(new URL(value, __defaultBaseUrl())); } catch (_) {} }
              out.push(value);
            }
            return __asJavaList(out);
          },
          getElement: function(rule) { __nativeRule.setContent(__defaultHtml()); return __nativeRule.getElement(String(rule || '')); },
          getElements: function(rule) { __nativeRule.setContent(__defaultHtml()); return __nativeRule.getElements(String(rule || '')); }
        };
        // Keep the global helper available after the rule resolver declaration;
        // some sources call importClass() late in the script.
        function importClass(value) {
          var name = value && value.__javaSimpleName ? String(value.__javaSimpleName) : '';
          if (name && typeof globalThis !== 'undefined') globalThis[name] = value;
          return value;
        }
        """
        context.exception = nil
        context.evaluateScript(prelude)
        if let exception = context.exception {
            baseBridgeError = exception.toString() ?? "JavaScript bridge prelude exception"
            context.exception = nil
        }
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
            headers.merge(parseStringMap(executionContext.get(key)), uniquingKeysWith: { _, new in new })
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
            let value = executionContext.get(key)
            if !value.isEmpty {
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

    private static func byteValue(_ value: Any) -> UInt8? {
        if let value = value as? NSNumber { return value.uint8Value }
        if let value = value as? UInt8 { return value }
        if let value = value as? UInt16 { return UInt8(clamping: value) }
        if let value = value as? UInt32 { return UInt8(clamping: value) }
        if let value = value as? UInt64 { return UInt8(clamping: value) }
        if let value = value as? Int { return UInt8(clamping: value) }
        if let value = value as? Int8 { return UInt8(clamping: value) }
        if let value = value as? Int16 { return UInt8(clamping: value) }
        if let value = value as? Int32 { return UInt8(clamping: value) }
        if let value = value as? Int64 { return UInt8(clamping: value) }
        if let value = value as? Double { return UInt8(clamping: Int(value)) }
        if let value = value as? Float { return UInt8(clamping: Int(value)) }
        if let value = value as? String, let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return UInt8(clamping: number)
        }
        if let value = value as? NSString, let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return UInt8(clamping: number)
        }
        if let value = value as? JSValue {
            if value.isNumber { return UInt8(clamping: value.toInt32()) }
            if let object = value.toObject(), !(object is JSValue) { return byteValue(object) }
            let text = value.toString() ?? ""
            if let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return UInt8(clamping: number)
            }
        }
        return nil
    }

    /// JavaScriptCore may invoke an NSArray-typed block with a JSValue wrapper
    /// for a JavaScript array. Reading the elements through `atIndex` keeps
    /// bridged NSNumber/JSValue values intact instead of silently producing an
    /// empty NSArray on iOS.
    private static func byteValues(from value: JSValue) -> [UInt8] {
        if value.isArray {
            let length = max(
                0,
                max(
                    Int(value.forProperty("length")?.toInt32() ?? 0),
                    Int(value.forProperty("count")?.toInt32() ?? 0)
                )
            )
            if length == 0, let object = value.toObject() as? NSArray, object.count > 0 {
                return object.compactMap(Self.byteValue)
            }
            return (0..<length).compactMap { byteValue(value.atIndex($0)) }
        }
        if value.isString { return Array((value.toString() ?? "").utf8) }
        if let object = value.toObject() { return objectBytes(object) }
        return []
    }

    private static func objectBytes(_ value: Any) -> [UInt8] {
        if let values = value as? NSArray { return values.compactMap(byteValue) }
        if let values = value as? [Any] { return values.compactMap(byteValue) }
        if let values = value as? Data { return Array(values) }
        return byteValue(value).map { [$0] } ?? []
    }

    private static func data(for value: String, charset: String) -> Data {
        switch normalizedCharset(charset) {
        case "utf16", "utf16le": return value.data(using: .utf16LittleEndian) ?? Data(value.utf8)
        case "utf16be": return value.data(using: .utf16BigEndian) ?? Data(value.utf8)
        case "ascii": return value.data(using: .ascii) ?? Data(value.utf8)
        case "latin1", "iso88591": return value.data(using: .isoLatin1) ?? Data(value.utf8)
        default: return Data(value.utf8)
        }
    }

    private static func string(from data: Data, charset: String) -> String {
        switch normalizedCharset(charset) {
        case "utf16", "utf16le": return String(data: data, encoding: .utf16LittleEndian) ?? ""
        case "utf16be": return String(data: data, encoding: .utf16BigEndian) ?? ""
        case "ascii": return String(data: data, encoding: .ascii) ?? ""
        case "latin1", "iso88591": return String(data: data, encoding: .isoLatin1) ?? ""
        default: return String(data: data, encoding: .utf8) ?? ""
        }
    }

    private static func normalizedCharset(_ charset: String) -> String {
        charset.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
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

    private static func digestHex(value: String, algorithm: String) -> String {
        let normalized = algorithm.lowercased().replacingOccurrences(of: "-", with: "")
        let data = Data(value.utf8)
        switch normalized {
        case "md5": return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha1": return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha224":
            var digest = Array(repeating: UInt8(0), count: Int(CC_SHA224_DIGEST_LENGTH))
            data.withUnsafeBytes { buffer in
                digest.withUnsafeMutableBytes { destination in
                    _ = CC_SHA224(buffer.baseAddress, CC_LONG(data.count), destination.bindMemory(to: UInt8.self).baseAddress)
                }
            }
            return digest.map { String(format: "%02x", $0) }.joined()
        case "sha384": return SHA384.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha512": return SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "ripemd160": return ripemd160(data).map { String(format: "%02x", $0) }.joined()
        default: return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Small dependency-free RIPEMD-160 implementation for Legado's
    /// `java.ripemd160Encode` helper.  CryptoSwift does not expose a stable
    /// API across all package revisions used by the CI matrix, so keeping this
    /// routine local avoids a build-time feature split.
    private static func ripemd160(_ input: Data) -> [UInt8] {
        let r1: [Int] = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,7,4,13,1,10,6,15,3,12,0,9,5,2,14,11,8,3,10,14,4,9,15,8,1,2,7,0,6,13,11,5,12,1,9,11,10,0,8,12,4,13,3,7,15,14,5,6,2,4,0,5,9,7,12,2,10,14,1,3,8,11,6,15,13]
        let r2: [Int] = [5,14,7,0,9,2,11,4,13,6,15,8,1,10,3,12,6,11,3,7,0,13,5,10,14,15,8,12,4,9,1,2,15,5,1,3,7,14,6,9,11,8,12,2,10,0,4,13,8,6,4,1,3,11,15,0,5,12,2,13,9,7,10,14,1,3,8,11,0,5,12,2,13,9,7,10,14,6,15,4]
        let s1: [UInt32] = [11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8,7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12,11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5,11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12,9,15,5,11,6,8,13,12,5,12,13,14,11,8,5,6]
        let s2: [UInt32] = [8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6,9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11,9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5,15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8,8,5,12,9,12,5,14,6,8,13,6,5,15,13,11,11]
        func rol(_ value: UInt32, _ bits: UInt32) -> UInt32 { (value << bits) | (value >> (32 - bits)) }
        func f(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            switch j {
            case 0..<16: return x ^ y ^ z
            case 16..<32: return (x & y) | (~x & z)
            case 32..<48: return (x | ~y) ^ z
            case 48..<64: return (x & z) | (y & ~z)
            default: return x ^ (y | ~z)
            }
        }
        func k1(_ j: Int) -> UInt32 {
            switch j { case 0..<16: return 0; case 16..<32: return 0x5A827999; case 32..<48: return 0x6ED9EBA1; case 48..<64: return 0x8F1BBCDC; default: return 0xA953FD4E }
        }
        func k2(_ j: Int) -> UInt32 {
            switch j { case 0..<16: return 0x50A28BE6; case 16..<32: return 0x5C4DD124; case 32..<48: return 0x6D703EF3; case 48..<64: return 0x7A6D76E9; default: return 0 }
        }
        var bytes = Array(input)
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for i in 0..<8 { bytes.append(UInt8((bitLength >> UInt64(i * 8)) & 0xff)) }
        var h: [UInt32] = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
        for chunk in stride(from: 0, to: bytes.count, by: 64) {
            var x = Array(repeating: UInt32(0), count: 16)
            for i in 0..<16 { let o = chunk + i * 4; x[i] = UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24 }
            var al = h[0], bl = h[1], cl = h[2], dl = h[3], el = h[4]
            var ar = al, br = bl, cr = cl, dr = dl, er = el
            for j in 0..<80 {
                let tl = rol(al &+ f(j, bl, cl, dl) &+ x[r1[j]] &+ k1(j), s1[j]) &+ el
                al = el; el = dl; dl = rol(cl, 10); cl = bl; bl = tl
                let tr = rol(ar &+ f(79 - j, br, cr, dr) &+ x[r2[j]] &+ k2(j), s2[j]) &+ er
                ar = er; er = dr; dr = rol(cr, 10); cr = br; br = tr
            }
            let t = h[1] &+ cl &+ dr; h[1] = h[2] &+ dl &+ er; h[2] = h[3] &+ el &+ ar; h[3] = h[4] &+ al &+ br; h[4] = h[0] &+ bl &+ cr; h[0] = t
        }
        var out: [UInt8] = []
        for value in h { out.append(UInt8(value & 0xff)); out.append(UInt8((value >> 8) & 0xff)); out.append(UInt8((value >> 16) & 0xff)); out.append(UInt8((value >> 24) & 0xff)) }
        return out
    }

    private static func hmacHex(value: String, algorithm: String, key: String) -> String {
        let normalized = algorithm.lowercased().replacingOccurrences(of: "hmac", with: "").replacingOccurrences(of: "-", with: "")
        let message = Data(value.utf8)
        let secret = SymmetricKey(data: Data(key.utf8))
        let bytes: [UInt8]
        switch normalized {
        case "md5":
            var digest = Array(repeating: UInt8(0), count: Int(CC_MD5_DIGEST_LENGTH))
            message.withUnsafeBytes { messageBuffer in
                secret.withUnsafeBytes { keyBuffer in
                    digest.withUnsafeMutableBytes { destination in
                        CCHmac(CCHmacAlgorithm(kCCHmacAlgMD5), keyBuffer.baseAddress, secret.bitCount / 8,
                               messageBuffer.baseAddress, message.count, destination.bindMemory(to: UInt8.self).baseAddress)
                    }
                }
            }
            bytes = digest
        case "sha1": bytes = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: secret))
        case "sha224":
            var digest = Array(repeating: UInt8(0), count: Int(CC_SHA224_DIGEST_LENGTH))
            message.withUnsafeBytes { messageBuffer in
                secret.withUnsafeBytes { keyBuffer in
                    digest.withUnsafeMutableBytes { destination in
                        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA224), keyBuffer.baseAddress, secret.bitCount / 8,
                               messageBuffer.baseAddress, message.count, destination.bindMemory(to: UInt8.self).baseAddress)
                    }
                }
            }
            bytes = digest
        case "sha384": bytes = Array(HMAC<SHA384>.authenticationCode(for: message, using: secret))
        case "sha512": bytes = Array(HMAC<SHA512>.authenticationCode(for: message, using: secret))
        default: bytes = Array(HMAC<SHA256>.authenticationCode(for: message, using: secret))
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacBase64(value: String, algorithm: String, key: String) -> String {
        let hex = hmacHex(value: value, algorithm: algorithm, key: key)
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<end], radix: 16) else { return "" }
            bytes.append(byte)
            index = end
        }
        return Data(bytes).base64EncodedString()
    }

    private static func extractString(from document: Document, rule: String, baseUrl: URL?) throws -> String {
        try HtmlRuleExtractor().value(from: document, rule: rule, baseUrl: baseUrl)
    }

    private static func extractStringList(from document: Document, rule: String, baseUrl: URL?) throws -> [String] {
        let split = XPathRuleTranslator.valueRule(rule) ?? splitSelectorAndAttribute(rule)
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

    private static func countElements(in document: Document, selector: String, baseUrl: URL?) throws -> Int {
        let html = try document.outerHtml()
        return try HtmlRuleExtractor().select(
            html,
            baseUrl: baseUrl ?? URL(fileURLWithPath: "/"),
            listRule: selector
        ).count
    }

    private static func splitSelectorAndAttribute(_ rule: String) -> (selector: String, attribute: String) {
        let parts = rule.components(separatedBy: "@")
        guard parts.count > 1 else {
            return (rule, "text")
        }
        return (parts.dropLast().joined(separator: "@"), parts.last ?? "text")
    }
}
