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
            let bytes = values.compactMap { ($0 as? NSNumber)?.uint8Value }
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
        let bytesToString: @convention(block) (NSArray) -> String = { values in
            let bytes = values.compactMap { ($0 as? NSNumber)?.uint8Value }
            return String(data: Data(bytes), encoding: .utf8) ?? ""
        }
        let bytesToStringCharset: @convention(block) (NSArray, String) -> String = { values, charset in
            let bytes = values.compactMap { ($0 as? NSNumber)?.uint8Value }
            return Self.string(from: Data(bytes), charset: charset)
        }
        let digestBytes: @convention(block) (NSArray, String) -> NSArray = { values, algorithm in
            let bytes = values.compactMap { ($0 as? NSNumber)?.uint8Value }
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
            default: digest = Array(SHA256.hash(data: data))
            }
            return digest.map { NSNumber(value: $0) } as NSArray
        }
        let hmacBytes: @convention(block) (NSArray, String, NSArray) -> NSArray = { values, algorithm, keyValues in
            let message = Data(values.compactMap { ($0 as? NSNumber)?.uint8Value })
            let key = SymmetricKey(data: Data(keyValues.compactMap { ($0 as? NSNumber)?.uint8Value }))
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
                return response.body
            }
            return weakSelf?.executionContext.networkHandler?(requestText) ?? ajaxHandler?(requestText) ?? ""
        }
        let postResponse: @convention(block) (String, String, String) -> NSDictionary = { url, body, headers in
            guard let runtime = weakSelf else { return [:] }
            let requestText = runtime.requestText(url: url, body: body, headers: headers, includeStoredBody: true)
            if let response = runtime.executionContext.responseHandler?(requestText) {
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
        java.inflate = function(value) {
          return __asJavaList(__nativeLegado.invoke({ method: 'inflateBytes', args: [__javaBytes(value)] }));
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
          var list = value && value.length != null ? value : [];
          return String(__native_bytesToString(list) || '');
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
          return {
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
          var config = { headers: {}, body: '' };
          var api = {
            header: function(key, value) {
              config.headers[String(key)] = String(value);
              return api;
            },
            headers: function(value) {
              if (value) {
                var parsed = value;
                if (typeof parsed === 'string') {
                  try { parsed = JSON.parse(parsed); } catch (_) { parsed = {}; }
                }
                for (var key in parsed) config.headers[String(key)] = String(parsed[key]);
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
              return api;
            },
            requestBody: function(value) {
              config.body = String(value || '');
              return api;
            },
            timeout: function(_) { return api; },
            ignoreContentType: function(_) { return api; },
            ignoreHttpErrors: function(_) { return api; },
            followRedirects: function(_) { return api; },
            raw: function() { return api; },
            request: function() { return api; },
            userAgent: function(value) {
              config.headers['User-Agent'] = String(value);
              return api;
            },
            get: function() {
              return __bridgeResponse('', target, __native_ajaxResponse(target, __bridgeString(config.headers)));
            },
            post: function(body) {
              if (arguments.length > 0) config.body = __bridgeString(body);
              return __bridgeResponse('', target, __native_postResponse(target, config.body || '', __bridgeString(config.headers)));
            },
            body: function() {
              return config.body ? api.post() : api.get();
            },
            execute: function() {
              return config.body ? api.post() : api.get();
            },
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
          if (value.__bytes && value.__bytes.length != null) return Array.prototype.slice.call(value.__bytes).map(function(v) { return Number(v) & 255; });
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
          stringify: function(value) { return __cryptoWordArray(value, 'utf8').toString(this); }
        };
        CryptoJS.enc.Hex = {
          __encoding: 'hex',
          parse: function(value) { return __cryptoWordArray(String(value == null ? '' : value), 'hex'); },
          stringify: function(value) { return __cryptoWordArray(value, 'utf8').toString(this); }
        };
        CryptoJS.enc.Base64 = {
          __encoding: 'base64',
          parse: function(value) {
            var decoded = __native_base64DecodeBytes(String(value == null ? '' : value));
            return __cryptoWordArray(decoded, 'bytes');
          },
          stringify: function(value) { return __cryptoWordArray(value, 'utf8').toString(this); }
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
              var ciphertext = value && value.ciphertext != null ? value.ciphertext : value;
              if (!options.iv && value && value.iv) options.iv = value.iv;
              var bytes = ciphertext && ciphertext.__bytes ? ciphertext.__bytes :
                (typeof ciphertext === 'string' ? __cryptoBytes(__native_base64DecodeBytes(ciphertext), 'bytes') : __cryptoBytes(ciphertext, ciphertext && ciphertext.__encoding));
              var transformation = algorithm + '/' + __cryptoModeName(options) + '/' + __cryptoPaddingName(options);
              var output = __nativeLegado.invoke({ method: 'cipherDecryptBytes', args: [
                bytes,
                __cryptoBytes(key, key && key.__encoding),
                transformation,
                __cryptoBytes(options.iv, options.iv && options.iv.__encoding)
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
            var text = this.toString(); this.__parts = [text.substring(0, Number(start) || 0), text.substring(Number(end) || 0)]; return this;
          };
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
          var bytes = value && value.length != null ? Array.prototype.slice.call(value) : [];
          var index = 0;
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
        Packages.java.net = Packages.java.net || {};
        Packages.java.net.URL = Packages.java.net.URL || function(value, baseValue) {
          var raw = String(value == null ? '' : value);
          var base = String(baseValue == null ? '' : baseValue);
          function hasScheme(value) { var marker = value.indexOf('://'); return marker > 0 && /^[A-Za-z]/.test(value.substring(0, marker)); }
          if (base && !hasScheme(raw)) {
            try {
              if (raw.charAt(0) === '/') {
                var schemeEnd = base.indexOf('://'), pathStart = base.indexOf('/', schemeEnd + 3);
                raw = schemeEnd > 0 ? base.substring(0, pathStart > 0 ? pathStart : base.length) + raw : raw;
              } else {
                var cleanBase = base.split('#')[0].split('?')[0], slash = cleanBase.lastIndexOf('/');
                raw = (slash >= 0 ? cleanBase.substring(0, slash + 1) : cleanBase + '/') + raw;
              }
              var originEnd = raw.indexOf('/', raw.indexOf('://') + 3);
              if (originEnd > 0) {
                var originText = raw.substring(0, originEnd), parts = raw.substring(originEnd).split('/'), normalized = [];
                for (var p = 0; p < parts.length; p++) {
                  if (!parts[p] || parts[p] === '.') continue;
                  if (parts[p] === '..') { if (normalized.length) normalized.pop(); }
                  else normalized.push(parts[p]);
                }
                raw = originText + '/' + normalized.join('/');
              }
            } catch (_) {}
          }
          var schemeEnd = raw.indexOf('://'), authorityEnd = schemeEnd > 0 ? raw.length : -1;
          var slashPos = schemeEnd > 0 ? raw.indexOf('/', schemeEnd + 3) : -1;
          var queryPos = schemeEnd > 0 ? raw.indexOf('?', schemeEnd + 3) : -1;
          var hashPos = schemeEnd > 0 ? raw.indexOf('#', schemeEnd + 3) : -1;
          if (slashPos >= 0) authorityEnd = Math.min(authorityEnd, slashPos);
          if (queryPos >= 0) authorityEnd = Math.min(authorityEnd, queryPos);
          if (hashPos >= 0) authorityEnd = Math.min(authorityEnd, hashPos);
          var scheme = schemeEnd > 0 ? raw.substring(0, schemeEnd) : '', authority = schemeEnd > 0 ? raw.substring(schemeEnd + 3, authorityEnd) : '';
          var host = authority, port = -1, colon = authority.lastIndexOf(':');
          var portText = colon > 0 ? authority.substring(colon + 1) : '';
          var portIsNumeric = portText.length > 0;
          for (var portIndex = 0; portIndex < portText.length; portIndex++) {
            var portChar = portText.charAt(portIndex);
            if (portChar < '0' || portChar > '9') { portIsNumeric = false; break; }
          }
          if (colon > 0 && portIsNumeric) { port = Number(portText); host = authority.substring(0, colon); }
          var pathPart = schemeEnd > 0 ? raw.substring(authorityEnd) : raw, hash = pathPart.indexOf('#'), query = pathPart.indexOf('?');
          var pathOnly = pathPart; if (query >= 0) pathOnly = pathPart.substring(0, query); else if (hash >= 0) pathOnly = pathPart.substring(0, hash);
          var queryOnly = query >= 0 ? pathPart.substring(query + 1, hash >= 0 ? hash : pathPart.length) : '', refOnly = hash >= 0 ? pathPart.substring(hash + 1) : '';
          this.toString = function() { return raw; };
          this.toExternalForm = this.toString;
          this.getProtocol = function() { return scheme; };
          this.getHost = function() { return host; };
          this.getPort = function() { return port; };
          this.getPath = function() { return pathOnly || ''; };
          this.getQuery = function() { return queryOnly; };
          this.getRef = function() { return refOnly; };
          this.getFile = function() { return (this.getPath() || '') + (queryOnly ? '?' + queryOnly : ''); };
          this.getAuthority = function() { return authority; };
          this.openConnection = function() { return __makeConnect(raw); };
        };
        Packages.java.net.URLEncoder = Packages.java.net.URLEncoder || {
          encode: function(value, charset) { return java.urlEncode(String(value == null ? '' : value)).replace(/%20/g, '+'); }
        };
        Packages.java.net.URLDecoder = Packages.java.net.URLDecoder || {
          decode: function(value, charset) { return java.decodeURI(String(value == null ? '' : value).replace(/\\+/g, '%20')); }
        };
        if (typeof URL === 'undefined') URL = Packages.java.net.URL;
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
            } };
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
        Packages.java.util.HashMap = Packages.java.util.HashMap || function() {
          this.__map = {};
          this.put = function(key, value) { var k = String(key); var old = this.__map[k]; this.__map[k] = value; return old == null ? null : old; };
          this.get = function(key) { var value = this.__map[String(key)]; return value == null ? null : value; };
          this.remove = function(key) { var k = String(key); var old = this.__map[k]; delete this.__map[k]; return old == null ? null : old; };
          this.containsKey = function(key) { return Object.prototype.hasOwnProperty.call(this.__map, String(key)); };
          this.isEmpty = function() { return Object.keys(this.__map).length === 0; };
          this.size = function() { return Object.keys(this.__map).length; };
          this.clear = function() { this.__map = {}; };
          this.keySet = function() { return __asJavaList(Object.keys(this.__map)); };
          this.values = function() { var out = []; for (var k in this.__map) out.push(this.__map[k]); return __asJavaList(out); };
          this.entrySet = function() { var out = []; for (var k in this.__map) { (function(key, value) { out.push({ getKey: function() { return key; }, getValue: function() { return value; } }); })(k, this.__map[k]); } return __asJavaList(out); };
          this.toString = function() { return JSON.stringify(this.__map); };
        };
        Packages.java.util.ArrayList = Packages.java.util.ArrayList || function() {
          var values = [];
          if (arguments.length && arguments[0]) {
            if (arguments[0].length != null) values = Array.prototype.slice.call(arguments[0]);
            else if (typeof arguments[0].toArray === 'function') values = arguments[0].toArray();
          }
          this.add = function(value) { values.push(value); return true; };
          this.addAll = function(other) { if (other && other.length != null) for (var i = 0; i < other.length; i++) values.push(other[i]); else if (other && other.toArray) values = values.concat(other.toArray()); return true; };
          this.get = function(index) { return values[Number(index)]; };
          this.set = function(index, value) { var old = values[Number(index)]; values[Number(index)] = value; return old; };
          this.remove = function(index) { return values.splice(Number(index), 1)[0]; };
          this.contains = function(value) { return values.indexOf(value) >= 0; };
          this.clear = function() { values = []; };
          this.first = function() { return values.length ? values[0] : null; };
          this.last = function() { return values.length ? values[values.length - 1] : null; };
          this.size = function() { return values.length; };
          this.isEmpty = function() { return values.length === 0; };
          this.toArray = function() { return values.slice(); };
          this.toString = function() { return values.join(','); };
        };
        Packages.java.util.zip = Packages.java.util.zip || {};
        Packages.java.util.zip.InflaterInputStream = Packages.java.util.zip.InflaterInputStream || function(input) {
          var raw = input && input.__bytes ? input.__bytes : (input && input.__javaBytes ? input.__javaBytes : input);
          var inflated = java.inflate(raw && raw.length != null ? raw : []);
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
                  find: function() {
                    // Java Matcher.find() advances across repeated calls.
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
                };
              }
            };
          }
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
        Packages.java.io.ByteArrayInputStream.__javaSimpleName = 'ByteArrayInputStream';
        Packages.java.io.ByteArrayOutputStream.__javaSimpleName = 'ByteArrayOutputStream';
        Packages.java.util.zip.InflaterInputStream.__javaSimpleName = 'InflaterInputStream';
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
            MessageDigest: Packages.java.security.MessageDigest,
            Mac: Packages.javax.crypto.Mac,
            Cipher: Packages.javax.crypto.Cipher,
            SecretKeySpec: Packages.javax.crypto.spec.SecretKeySpec,
            IvParameterSpec: Packages.javax.crypto.spec.IvParameterSpec,
            ByteArrayOutputStream: Packages.java.io.ByteArrayOutputStream,
            InflaterInputStream: Packages.java.util.zip.InflaterInputStream,
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
            baseBridgeError = exception.toString()
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
        default: return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
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
