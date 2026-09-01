import Foundation
import JavaScriptCore
import SwiftSoup
import CryptoKit

final class JSCoreRuntime {
    private let context: JSContext
    private let ajaxHandler: ((String) -> String)?
    private let executionContext: RuleExecutionContext
    private let javaHostBridge: LegadoJavaHostBridge
    private let ruleHostBridge: LegadoRuleHostBridge
    private let jsoupBridge: LegadoJsoupBridge

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
        if executionContext.networkHandler == nil {
            executionContext.networkHandler = ajaxHandler
        }
        context.setObject(javaHostBridge, forKeyedSubscript: "__nativeLegado" as NSString)
        context.setObject(ruleHostBridge, forKeyedSubscript: "__nativeRule" as NSString)
        context.setObject(jsoupBridge, forKeyedSubscript: "__nativeJsoup" as NSString)
        installNativeClosures()
        installBaseBridge()
    }

    func evaluate(_ script: String, variables: [String: Any] = [:]) -> Result<String, SourceEngineError> {
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
                        return { get: function(k) { var value = parsed[String(k)]; return value == null ? '' : value; } };
                    };
                    source.getLoginInfoMap = function() { return { get: function(k) { return java.getVar('source.login.' + String(k || '')); } }; };
                    source.putLoginHeader = function(k, v) { return java.put('source.loginHeader.' + String(k || ''), v == null ? '' : String(v)); };
                    source.getLoginHeader = function(k) { return java.getVar('source.loginHeader.' + String(k || '')); };
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
                    book.setVariable = function(key, value) {
                        if (arguments.length > 1) return java.put('book.variable.' + String(key), value == null ? '' : String(value));
                        book.variable = key == null ? '' : String(key);
                        return java.put('book.variable', book.variable);
                    };
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
        let ajax: @convention(block) (String, String) -> String = { url, headers in
            let requestText = weakSelf?.requestText(url: url, body: nil, headers: headers, includeStoredBody: false) ?? url
            return ajaxHandler?(requestText) ?? ""
        }
        let post: @convention(block) (String, String, String) -> String = { url, body, headers in
            let requestText = weakSelf?.requestText(url: url, body: body, headers: headers, includeStoredBody: true) ?? "\(url)@Body:\(body)"
            return ajaxHandler?(requestText) ?? ""
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
                        parentsHtml.append(try p.outerHtml())
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
        context.setObject(countElements, forKeyedSubscript: "__native_countElements" as NSString)
        context.setObject(ajax, forKeyedSubscript: "__native_ajax" as NSString)
        context.setObject(post, forKeyedSubscript: "__native_post" as NSString)
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
        var java = java || {};
        java.urlEncode = function(value) { return __native_urlEncode(String(value)); };
        java.encodeURI = function(value, charset) {
          return String(__nativeLegado.invoke({ method: 'encodeURI', args: [String(value), charset == null ? '' : String(charset)] }) || '');
        };
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
        java.md5Encode16 = function(value) { return java.md5(value).substring(8, 24); };
        java.hexMd5 = java.md5;
        java.MD5 = java.md5;
        java.sha1 = function(value) { return __native_sha1(String(value)); };
        java.SHA1 = java.sha1;
        java.sha256 = function(value) { return __native_sha256(String(value)); };
        java.SHA256 = java.sha256;
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
          String.prototype.getBytes = function() {
            var text = String(this);
            var bytes = [];
            for (var i = 0; i < text.length; i++) bytes.push(text.charCodeAt(i) & 0xff);
            return bytes;
          };
        }
        function __asJavaList(list) {
          list.get = function(index) { return list[Number(index)]; };
          list.size = function() { return list.length; };
          list.isEmpty = function() { return list.length === 0; };
          return list;
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
        java.getString = function(input, rule) {
          if (arguments.length <= 1 || typeof rule === 'boolean') {
            return __native_getString(__defaultHtml(), String(input), __defaultBaseUrl());
          }
          return __native_getString(String(input), String(rule), __defaultBaseUrl());
        };
        java.getStringList = function(input, rule) {
          var useDefaultHtml = arguments.length <= 1 || typeof rule === 'boolean';
          var pageHtml = useDefaultHtml ? __defaultHtml() : String(input);
          var actualRule = useDefaultHtml ? String(input) : String(rule);
          var list = __native_getStringList(pageHtml, actualRule, __defaultBaseUrl());
          var out = [];
          for (var i = 0; i < list.length; i++) out.push(String(list[i]));
          return __asJavaList(out);
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
        function __bridgeResponse(text, responseUrl) {
          var value = String(text || '');
          return {
            statusCode: 200,
            body: function() { return value; },
            text: function() { return value; },
            url: function() { return String(responseUrl || ''); },
            header: function(_) { return ''; },
            headers: function() { return {}; },
            toString: function() { return value; },
            valueOf: function() { return value; }
          };
        }
        java.put = function(key, value) {
          return __nativeLegado.invoke({ method: 'put', args: [String(key), value] });
        };
        java.getVar = function(key) {
          return String(__nativeLegado.invoke({ method: 'get', args: [String(key)] }) || '');
        };
        java.ajax = function(url, headers) { return __bridgeResponse(__native_ajax(String(url), __bridgeString(headers || '')), url); };
        java.get = function(url, headers) {
          var key = String(url);
          var value = __bridgeStored(key);
          if (value && key.indexOf('://') < 0 && key.charAt(0) !== '/') return value;
          if (key.indexOf('://') < 0 && key.charAt(0) !== '/') return '';
          return __bridgeResponse(__native_ajax(key, __bridgeString(headers || '')), key);
        };
        java.fetch = function(url, options) {
          options = options || {};
          var method = String(options.method || 'GET').toUpperCase();
          if (method === 'POST' || options.body != null) return java.post(url, options.body || '', options.headers || {});
          return __bridgeResponse(__native_ajax(String(url), __bridgeString(options.headers || options)), url);
        };
        java.post = function(url, body, headers) { return __bridgeResponse(__native_post(String(url), __bridgeString(body || ''), __bridgeString(headers || '')), url); };
        java.ajaxAll = function(urls) {
          var values = [];
          if (urls && typeof urls.length === 'number') {
            for (var i = 0; i < urls.length; i++) values.push(String(urls[i]));
          } else if (urls != null) {
            values.push(String(urls));
          }
          var loaded = __nativeLegado.invoke({ method: 'ajaxAll', args: [values] });
          var out = [];
          for (var j = 0; loaded && j < loaded.length; j++) out.push(__bridgeResponse(loaded[j], values[j] || ''));
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
              return __bridgeResponse(__native_ajax(target, __bridgeString(config.headers)), target);
            },
            post: function(body) {
              if (arguments.length > 0) config.body = __bridgeString(body);
              return __bridgeResponse(__native_post(target, config.body || '', __bridgeString(config.headers)), target);
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
        var cookie = cookie || {};
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
        java.htmlFormat = function(value) { return String(__nativeLegado.invoke({ method: 'htmlFormat', args: [String(value || '')] }) || ''); };
        java.readFile = function(path) { return __nativeLegado.invoke({ method: 'readFile', args: [String(path || '')] }); };
        java.readTxtFile = function(path, charset) { return String(__nativeLegado.invoke({ method: 'readTxtFile', args: [String(path || ''), String(charset || 'utf-8')] }) || ''); };
        java.downloadFile = function(url, path) { return String(__nativeLegado.invoke({ method: 'downloadFile', args: [String(url || ''), String(path || '')] }) || ''); };
        java.unzipFile = function(path) { return String(__nativeLegado.invoke({ method: 'unzipFile', args: [String(path || '')] }) || ''); };
        java.getTxtInFolder = function(path) { return __nativeLegado.invoke({ method: 'getTxtInFolder', args: [String(path || '')] }); };
        java.getZipStringContent = function(path, entry, charset) { return String(__nativeLegado.invoke({ method: 'getZipStringContent', args: [String(path || ''), String(entry || ''), String(charset || 'utf-8')] }) || ''); };
        java.getZipByteArrayContent = function(path, entry) { return __nativeLegado.invoke({ method: 'getZipByteArrayContent', args: [String(path || ''), String(entry || '')] }); };
        java.getSandboxPath = function() { return String(__nativeLegado.invoke({ method: 'sandboxPath', args: [] }) || ''); };
        java.fetchCloudTTS = function(_) { return ''; };
        function __aes(method, input, key, transformation, iv) {
          return __nativeLegado.invoke({ method: method, args: [input, key, String(transformation || 'AES/CBC/PKCS7Padding'), iv] });
        }
        java.aesDecodeToByteArray = function(a,b,c,d) { return __aes('aesDecodeToByteArray',a,b,c,d); };
        java.aesDecodeToString = function(a,b,c,d) { return __aes('aesDecodeToString',a,b,c,d); };
        java.aesBase64DecodeToByteArray = function(a,b,c,d) { return __aes('aesBase64DecodeToByteArray',a,b,c,d); };
        java.aesBase64DecodeToString = function(a,b,c,d) { return __aes('aesBase64DecodeToString',a,b,c,d); };
        java.aesEncodeToByteArray = function(a,b,c,d) { return __aes('aesEncodeToByteArray',a,b,c,d); };
        java.aesEncodeToString = function(a,b,c,d) { return __aes('aesEncodeToString',a,b,c,d); };
        java.aesEncodeToBase64ByteArray = function(a,b,c,d) { return __aes('aesEncodeToBase64ByteArray',a,b,c,d); };
        java.aesEncodeToBase64String = function(a,b,c,d) { return __aes('aesEncodeToBase64String',a,b,c,d); };
        java.setContent = function(value) {
          result = String(value == null ? '' : value);
          return String(__nativeRule.setContent(result));
        };
        function __installSourceAndBook() {
          if (typeof source === 'undefined' || source === null) source = {};
          source.getKey = function() { return source.key || source.bookSourceUrl || source.sourceUrl || ''; };
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
            return { get: function(k) { var value = parsed[String(k)]; return value == null ? '' : value; } };
          };
          source.getLoginInfoMap = function() { return { get: function(k) { return java.getVar('source.login.' + String(k || '')); } }; };
          source.putLoginHeader = function(k, v) { return java.put('source.loginHeader.' + String(k || ''), v == null ? '' : String(v)); };
          source.getLoginHeader = function(k) { return java.getVar('source.loginHeader.' + String(k || '')); };
          if (typeof book === 'undefined' || book === null) book = {};
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
          book.variableMap = book.variableMap || { get: function(k) { return book.getVariable(k); }, put: function(k,v) { return book.setVariable(k,v); } };
          if (typeof chapter === 'undefined' || chapter === null) chapter = {};
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
        Packages.java.lang = Packages.java.lang || {};
        Packages.java.lang.String = Packages.java.lang.String || function(value) { return new String(String(value || '')); };
        Packages.java.lang.Thread = Packages.java.lang.Thread || { sleep: function(_) {} };
        Packages.java.util = Packages.java.util || {};
        Packages.java.util.UUID = Packages.java.util.UUID || { randomUUID: java.randomUUID };
        Packages.java.util.Base64 = Packages.java.util.Base64 || {
          encodeToString: function(value) { return java.base64Encode(value && value.join ? String.fromCharCode.apply(null, value) : String(value || '')); },
          decode: function(value) {
            var text = java.base64Decode(value);
            var out = [];
            for (var i = 0; i < text.length; i++) out.push(text.charCodeAt(i));
            return out;
          }
        };
        Packages.android = Packages.android || {};
        Packages.android.os = Packages.android.os || { Build: { MODEL: 'iPhone', MANUFACTURER: 'Apple', BRAND: 'Apple' } };
        Packages.android.text = Packages.android.text || { TextUtils: { isEmpty: function(value) { return value == null || String(value).length === 0; } } };
        Packages.android.util = Packages.android.util || { Base64: Packages.java.util.Base64 };
        Packages.util = Packages.java.util;
        java.lang = Packages.java.lang;
        java.util = Packages.java.util;
        function JavaImporter() {
          return {
            importPackage: function(_) {},
            importClass: function(_) {},
            String: Packages.java.lang.String,
            Jsoup: Packages.org.jsoup.Jsoup,
            Base64: Packages.java.util.Base64
          };
        }
        function importPackage(value) { return value; }
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
        java.getElements = function(rule) {
          __nativeRule.setContent(__defaultHtml());
          return __nativeRule.getElements(String(rule || ''));
        };
        Packages.org.jsoup.Jsoup = {
          parse: function(html, baseUrlValue) {
            var resolvedBase = String(baseUrlValue || (typeof baseUrl === 'undefined' ? '' : baseUrl));
            if (resolvedBase) return __nativeJsoup.parseWithBase({ html: String(html), baseUrl: resolvedBase });
            return __nativeJsoup.parse(String(html));
          },
          connect: __makeConnect
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
