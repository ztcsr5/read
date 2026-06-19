import CryptoKit
import Flutter
import JavaScriptCore
import Network
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let localNetworkPermissionHelper = LocalNetworkPermissionHelper()
  private let legadoJSCoreBridge = LegadoNativeJSCoreBridge()
  private var localNetworkChannel: FlutterMethodChannel?
  private var legadoJSCoreChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      localNetworkChannel = FlutterMethodChannel(
        name: "read/local_network",
        binaryMessenger: controller.binaryMessenger
      )
      localNetworkChannel?.setMethodCallHandler { [weak self] call, result in
        self?.handleLocalNetworkCall(call, result: result)
      }
      legadoJSCoreChannel = FlutterMethodChannel(
        name: "read/legado_jscore",
        binaryMessenger: controller.binaryMessenger
      )
      legadoJSCoreChannel?.setMethodCallHandler { [weak self] call, result in
        self?.handleLegadoJSCoreCall(call, result: result)
      }
    }
    return result
  }

  private func handleLocalNetworkCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "requestLocalNetworkAuthorization" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard #available(iOS 14.0, *) else {
      result("not_required")
      return
    }
    let args = call.arguments as? [String: Any]
    let timeoutMs = args?["timeoutMs"] as? Int ?? 2500
    localNetworkPermissionHelper.request(timeoutMs: timeoutMs) { status in
      result(status)
    }
  }

  private func handleLegadoJSCoreCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "bad_args", message: "Missing JSCore arguments", details: nil))
      return
    }
    switch call.method {
    case "evaluate":
      legadoJSCoreBridge.evaluate(arguments: args, flutterResult: result)
    case "openLogin":
      openLegadoLoginWebView(arguments: args, result: result)
    case "cookiesForUrl":
      legadoJSCoreBridge.cookiesForUrl(arguments: args, flutterResult: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openLegadoLoginWebView(arguments: [String: Any], result: @escaping FlutterResult) {
    guard let urlText = arguments["url"] as? String, let url = URL(string: urlText) else {
      result(FlutterError(code: "bad_url", message: "Missing loginUrl", details: nil))
      return
    }
    DispatchQueue.main.async {
      let controller = LegadoLoginWebViewController(url: url) { cookies in
        result(["ok": true, "cookieHeader": cookies])
      }
      let nav = UINavigationController(rootViewController: controller)
      nav.modalPresentationStyle = .formSheet
      self.window?.rootViewController?.present(nav, animated: true)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

final class LegadoNativeJSCoreBridge {
  private let queue = DispatchQueue(label: "read.legado-jscore")

  func evaluate(arguments: [String: Any], flutterResult: @escaping FlutterResult) {
    queue.async { let response = self.evaluateSync(arguments: arguments); DispatchQueue.main.async { flutterResult(response) } }
  }

  func cookiesForUrl(arguments: [String: Any], flutterResult: @escaping FlutterResult) {
    queue.async {
      let cookies = self.readWebViewCookies(for: arguments["url"] as? String ?? "")
      DispatchQueue.main.async { flutterResult(["ok": true, "cookieHeader": cookies]) }
    }
  }

  private func evaluateSync(arguments: [String: Any]) -> [String: Any] {
    let code = arguments["code"] as? String ?? ""
    var variables = arguments["variables"] as? [String: Any] ?? [:]
    let libraries = arguments["libraries"] as? [String] ?? []
    let ajaxCache = arguments["ajaxCache"] as? [String: String] ?? [:]
    let nativeCache = arguments["nativeCache"] as? [String: String] ?? [:]
    let wrapScript = arguments["wrapScript"] as? Bool ?? true
    guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return ["ok": true, "result": "", "engine": "jscore"] }
    guard let context = JSContext() else { return ["ok": false, "error": "JSContext unavailable", "engine": "jscore"] }
    var capturedError = ""
    context.exceptionHandler = { _, exception in capturedError = exception?.toString() ?? "JavaScriptCore exception" }
    if let cookieUrl = (variables["baseUrl"] as? String) ?? (variables["url"] as? String) {
      let webCookies = readWebViewCookies(for: cookieUrl)
      if !webCookies.isEmpty { variables["cookieHeader"] = mergeCookieHeaders(variables["cookieHeader"] as? String ?? "", webCookies) }
    }
    installConsole(in: context)
    installLegadoBridge(in: context, ajaxCache: ajaxCache, nativeCache: nativeCache)
    inject(variables: variables, into: context)
    for library in libraries {
      let source = library.trimmingCharacters(in: .whitespacesAndNewlines)
      if source.isEmpty { continue }
      _ = context.evaluateScript(source)
      if !capturedError.isEmpty { return bridgeFailure(capturedError) }
    }
    guard let value = context.evaluateScript(wrapScript ? wrapIfNeeded(code) : code) else {
      return bridgeFailure(capturedError.isEmpty ? "JS returned null" : capturedError)
    }
    if !capturedError.isEmpty { return bridgeFailure(capturedError) }
    let result = stringify(value)
    let cookieHeader = context.objectForKeyedSubscript("cookieHeader")?.toString() ?? ""
    if !cookieHeader.isEmpty, let cookieUrl = (variables["baseUrl"] as? String) ?? (variables["url"] as? String) { writeWebViewCookies(cookieHeader, for: cookieUrl) }
    let storage = context.objectForKeyedSubscript("__legado_storage")?.toDictionary() ?? [:]
    return ["ok": true, "result": result, "cookieHeader": cookieHeader, "storage": storage, "engine": "jscore"]
  }

  private func bridgeFailure(_ error: String) -> [String: Any] {
    if let request = extractMarker(error, marker: "__LEGADO_AJAX__") { return ["ok": false, "ajaxRequest": request, "error": error, "engine": "jscore"] }
    if let login = extractMarker(error, marker: "__LEGADO_LOGIN__") { return ["ok": false, "loginRequest": login, "error": error, "engine": "jscore"] }
    if let native = extractMarker(error, marker: "__LEGADO_NATIVE__") { return ["ok": false, "nativeRequest": native, "error": error, "engine": "jscore"] }
    return ["ok": false, "error": error, "engine": "jscore"]
  }

  private func installConsole(in context: JSContext) {
    let log: @convention(block) (JSValue?) -> Void = { value in
      print("LegadoJSCore:", value?.toString() ?? "")
    }
    let console = JSValue(newObjectIn: context)
    console?.setObject(log, forKeyedSubscript: "log" as NSString); console?.setObject(log, forKeyedSubscript: "warn" as NSString); console?.setObject(log, forKeyedSubscript: "error" as NSString)
    context.setObject(console, forKeyedSubscript: "console" as NSString)
  }

  private func installLegadoBridge(in context: JSContext, ajaxCache: [String: String], nativeCache: [String: String]) {
    let hashBlock: @convention(block) (String, String) -> String = { algorithm, value in self.hashHex(algorithm: algorithm, value: value) }
    context.setObject(hashBlock, forKeyedSubscript: "__legado_native_hash" as NSString)
    let cacheJson = jsonString(ajaxCache) ?? "{}"
    let nativeCacheJson = jsonString(nativeCache) ?? "{}"
    let bridge = """
      var __legado_storage = typeof __legado_storage === 'undefined' ? {} : __legado_storage;
      var __legado_ajax_cache = \(cacheJson);
      var __legado_native_cache = \(nativeCacheJson);
      function __str(v){ return v == null ? '' : String(v); }
      function __array(v){ if (Array.isArray(v)) return v; if (v == null || v === '') return []; return [v]; }
      function __native(kind,payload){ var req=kind+':' + JSON.stringify(payload||{}); if(Object.prototype.hasOwnProperty.call(__legado_native_cache, req)) return __legado_native_cache[req]; throw new Error('__LEGADO_NATIVE__' + req); }
      function __cookieKey(header,key){ var parts=__str(header).split(';'), name=__str(key); for(var i=0;i<parts.length;i++){var p=parts[i].trim(), j=p.indexOf('='); if(j>0&&p.substring(0,j).trim()===name)return p.substring(j+1).trim();} return ''; }
      function __mergeCookie(a,b){ var m={}; [a,b].forEach(function(h){__str(h).split(';').forEach(function(p){p=p.trim();var i=p.indexOf('='); if(i>0)m[p.substring(0,i).trim()]=p.substring(i+1).trim();});}); return Object.keys(m).map(function(k){return k+'='+m[k]}).join('; '); }
      var java = typeof java === 'undefined' ? {} : java;
      java.ajax=function(request){var req=__str(request); if(Object.prototype.hasOwnProperty.call(__legado_ajax_cache,req))return __legado_ajax_cache[req]; throw new Error('__LEGADO_AJAX__'+req);};
      java.post=function(url,body){return java.ajax(__str(url)+','+JSON.stringify({method:'POST',body:body||''}));}; java.postForm=function(url,body){return java.ajax(__str(url)+','+JSON.stringify({method:'POST',body:body||'',headers:{'Content-Type':'application/x-www-form-urlencoded'}}));};
      java.fetch=function(url,opt){var t=java.ajax(__str(url)+','+JSON.stringify(opt||{})); return {text:function(){return t},string:function(){return t},body:function(){return {string:function(){return t},bytes:function(){return []}}},json:function(){return JSON.parse(t)},toString:function(){return t}};};
      java.connect=function(url){var u=__str(url), c={method:'GET',headers:{},body:''}; var x={header:function(k,v){if(k!=null)c.headers[__str(k)]=__str(v);return x},headers:function(h){if(typeof h==='string'){try{h=JSON.parse(h)}catch(e){h={}}}for(var k in(h||{}))c.headers[__str(k)]=__str(h[k]);return x},cookie:function(v){if(v!=null)c.headers.Cookie=__str(v);return x},cookies:function(v){return x.cookie(v)},userAgent:function(v){if(v!=null)c.headers['User-Agent']=__str(v);return x},referrer:function(v){if(v!=null)c.headers.Referer=__str(v);return x},data:function(v){c.body=__str(v);return x},requestBody:function(v){c.body=__str(v);return x},timeout:function(){return x},ignoreContentType:function(){return x},followRedirects:function(){return x},get:function(){c.method='GET';return x},post:function(v){c.method='POST';if(v!=null)c.body=__str(v);return x},execute:function(){return java.fetch(u,c)},body:function(){return java.ajax(u+','+JSON.stringify(c))},toString:function(){return u}}; return x;};
      java.get=function(k){return __legado_storage[__str(k)]||''}; java.put=function(k,v){__legado_storage[__str(k)]=v; return v}; java.getVariable=java.get; java.putVariable=java.put;
      java.base64Encode=function(v){return btoa(unescape(encodeURIComponent(__str(v))))}; java.base64Decode=function(v){return decodeURIComponent(escape(atob(__str(v))))};
      java.md5Encode=function(v){return __legado_native_hash('md5',__str(v))}; java.md5=java.md5Encode; java.sha1Encode=function(v){return __legado_native_hash('sha1',__str(v))}; java.sha256Encode=function(v){return __legado_native_hash('sha256',__str(v))}; java.sha512Encode=function(v){return __legado_native_hash('sha512',__str(v))};
      java.encodeURI=function(v){return encodeURI(__str(v))}; java.encodeURIComponent=function(v){return encodeURIComponent(__str(v))}; java.decodeURI=function(v){return decodeURI(__str(v))}; java.decodeURIComponent=function(v){return decodeURIComponent(__str(v))}; java.currentTimeMillis=function(){return Date.now()}; java.now=java.currentTimeMillis;
      java.startBrowser=function(url){var t=__str(url||(source&&source.loginUrl)||(typeof loginUrl==='undefined'?'':loginUrl)); throw new Error('__LEGADO_LOGIN__'+t)}; java.startBrowserAwait=java.startBrowser; java.getVerificationCode=java.startBrowser;
      var cache={get:function(k){return java.get(k)},put:function(k,v){return java.put(k,v)},getFromCache:function(k){return java.get(k)},putInCache:function(k,v){return java.put(k,v)}};
      var cookie=typeof cookie==='undefined'?{}:cookie; cookie.getCookie=function(){return __str(typeof cookieHeader==='undefined'?'':cookieHeader)}; cookie.getKey=function(url,key){return __cookieKey(cookie.getCookie(url),key)}; cookie.setCookie=function(url,v){cookieHeader=__mergeCookie(cookie.getCookie(url),v);return true}; cookie.removeCookie=function(){cookieHeader='';return true};
      function __makeVariableHost(seed){seed=seed||{};seed.variable=seed.variable||{};seed.putVariable=function(k,v){seed.variable[__str(k)]=v;return v};seed.getVariable=function(k){return seed.variable[__str(k)]||''};seed.put=seed.put||seed.putVariable;seed.get=seed.get||seed.getVariable;return seed;}
      var source=__makeVariableHost(typeof source==='undefined'?{}:source), book=__makeVariableHost(typeof book==='undefined'?{}:book), chapter=__makeVariableHost(typeof chapter==='undefined'?{}:chapter), searchBook=__makeVariableHost(typeof searchBook==='undefined'?{}:searchBook), bookSource=source;
      function __arrayWithMethods(l){l=l||[];l.size=function(){return l.length};l.isEmpty=function(){return l.length===0};l.get=function(i){return l[Number(i)||0]};l.toArray=function(){return l.slice()};return l;}
      function __nativeDom(action,payload){var raw=__native('dom',Object.assign({action:action},payload||{})); try{return JSON.parse(raw)}catch(e){return raw||''}}
      function __wrapElement(n){n=n||{};return {text:function(){return __str(n.text)},ownText:function(){return __str(n.ownText||n.text)},html:function(){return __str(n.html)},outerHtml:function(){return __str(n.outerHtml||n.html)},attr:function(k){return n.attr?__str(n.attr[__str(k)]):''},hasAttr:function(k){return !!(n.attr&&Object.prototype.hasOwnProperty.call(n.attr,__str(k)))},id:function(){return n.id||(n.attr&&n.attr.id)||''},className:function(){return n.className||(n.attr&&n.attr['class'])||''},tagName:function(){return n.tagName||n.nodeName||''},nodeName:function(){return n.nodeName||n.tagName||''},select:function(s){return __wrapElements(__nativeDom('select',{html:this.outerHtml(),selector:__str(s)}))},selectFirst:function(s){return this.select(s).first()},children:function(){return __wrapElements(__nativeDom('children',{html:this.html()}))},child:function(i){return this.children().get(i)},parent:function(){return __wrapElement(n.parent||{})},toString:function(){return this.outerHtml()}};}
      function __wrapElements(nodes){var l=(nodes||[]).map(__wrapElement);__arrayWithMethods(l);l.text=function(){return (nodes||[]).map(function(n){return __str(n.text||n.html||n.outerHtml)}).join('\n')};l.eachText=function(){return __arrayWithMethods((nodes||[]).map(function(n){return __str(n.text||'')}))};l.eachAttr=function(k){return __arrayWithMethods((nodes||[]).map(function(n){return n.attr?__str(n.attr[__str(k)]):''}))};l.html=function(){return (nodes||[]).map(function(n){return __str(n.html)}).join('\n')};l.outerHtml=function(){return (nodes||[]).map(function(n){return __str(n.outerHtml||n.html)}).join('\n')};l.attr=function(k){return l.length?l[0].attr(k):''};l.first=function(){return l.length?l[0]:__wrapElement({})};l.last=function(){return l.length?l[l.length-1]:__wrapElement({})};l.eq=function(i){var n=Number(i)||0;return __wrapElements((nodes||[]).slice(n,n+1))};l.select=function(s){var all=[];(nodes||[]).forEach(function(n){all=all.concat(__nativeDom('select',{html:__str(n.outerHtml||n.html),selector:__str(s)})||[])});return __wrapElements(all)};return l;}
      var org=typeof org==='undefined'?{}:org; org.jsoup=org.jsoup||{}; org.jsoup.Jsoup={parse:function(html){var src=__str(html);return {html:function(){return src},outerHtml:function(){return src},text:function(){return __nativeDom('text',{html:src})},body:function(){return __wrapElement(__nativeDom('body',{html:src}))},select:function(s){return __wrapElements(__nativeDom('select',{html:src,selector:__str(s)}))},selectFirst:function(s){return this.select(s).first()},toString:function(){return src}}},connect:function(url){return java.connect(url)}}; var Packages=typeof Packages==='undefined'?{}:Packages; Packages.org=Packages.org||org; function importClass(cls){return cls;}
      var CryptoJS=typeof CryptoJS==='undefined'?{}:CryptoJS; CryptoJS.enc=CryptoJS.enc||{}; CryptoJS.enc.Utf8={parse:function(v){return {text:__str(v),toString:function(){return __str(v)}}},stringify:function(v){return __str(v&&(v.text||v))}}; CryptoJS.enc.Base64={parse:function(v){return {text:java.base64Decode(v),toString:function(){return java.base64Decode(v)}}},stringify:function(v){return java.base64Encode(v&&(v.text||v))}}; CryptoJS.enc.Hex={parse:function(v){return {text:__str(v),toString:function(){return __str(v)}}},stringify:function(v){return __str(v&&(v.text||v))}};
      CryptoJS.MD5=function(v){return {toString:function(){return java.md5Encode(v)}}}; CryptoJS.SHA1=function(v){return {toString:function(){return java.sha1Encode(v)}}}; CryptoJS.SHA256=function(v){return {toString:function(){return java.sha256Encode(v)}}}; CryptoJS.SHA512=function(v){return {toString:function(){return java.sha512Encode(v)}}}; CryptoJS.HmacSHA1=function(v,k){return {toString:function(){return __legado_native_hash('hmac-sha1:'+__str(k),__str(v))}}}; CryptoJS.HmacSHA256=function(v,k){return {toString:function(){return __legado_native_hash('hmac-sha256:'+__str(k),__str(v))}}};
      function __cipher(kind,op,v,key,cfg){return {toString:function(){return __native('crypto',{kind:kind,op:op,value:__str(v),key:__str(key),iv:__str((cfg&&cfg.iv)||''),transformation:__str((cfg&&cfg.transformation)||kind+'/CBC/PKCS5Padding')})}}} CryptoJS.AES={decrypt:function(v,k,c){return __cipher('AES','decrypt',v,k,c)},encrypt:function(v,k,c){return __cipher('AES','encrypt',v,k,c)}}; CryptoJS.DES={decrypt:function(v,k,c){return __cipher('DES','decrypt',v,k,c)},encrypt:function(v,k,c){return __cipher('DES','encrypt',v,k,c)}}; CryptoJS.RSA={decrypt:function(v,k,c){return {toString:function(){return __native('rsa',{op:'decrypt',value:__str(v),key:__str(k),padding:__str((c&&c.padding)||'PKCS1')})}}},encrypt:function(v,k,c){return {toString:function(){return __native('rsa',{op:'encrypt',value:__str(v),key:__str(k),padding:__str((c&&c.padding)||'PKCS1')})}}}};
      var pako=typeof pako==='undefined'?{inflate:function(v){return __native('pako',{op:'inflate',value:__str(v)})},ungzip:function(v){return __native('pako',{op:'ungzip',value:__str(v)})},deflate:function(v){return __native('pako',{op:'deflate',value:__str(v)})},gzip:function(v){return __native('pako',{op:'gzip',value:__str(v)})}}:pako;
      var RuleResolver=typeof RuleResolver==='undefined'?{resolve:function(input){return __str(input)},resolveList:function(input){return __array(input)}}:RuleResolver; var URLResolver=typeof URLResolver==='undefined'?{resolve:function(base,url){try{return new URL(__str(url),__str(base)).toString()}catch(e){return __str(url)}}}:URLResolver; var RuleAnalyzer=typeof RuleAnalyzer==='undefined'?{split:function(rule){return __str(rule).split('&&')},analyze:function(rule){return {raw:__str(rule),parts:__str(rule).split('&&')}}}:RuleAnalyzer;
    """
    _ = context.evaluateScript(bridge)
  }

  private func inject(variables: [String: Any], into context: JSContext) { for (key, value) in variables { guard isValidIdentifier(key), let json = jsonString(value) else { continue }; _ = context.evaluateScript("var \(key) = \(json);") } }
  private func wrapIfNeeded(_ code: String) -> String { let t = code.trimmingCharacters(in: .whitespacesAndNewlines); if t.hasPrefix("(function") || t.hasPrefix("(()") || t.contains("return") { return t }; return "(function(){ return (\(t)); })()" }
  private func stringify(_ value: JSValue) -> String { if value.isUndefined || value.isNull { return "" }; if value.isString || value.isNumber || value.isBoolean { return value.toString() ?? "" }; if let object = value.toObject(), JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) { return text }; return value.toString() ?? "" }
  private func extractMarker(_ error: String, marker: String) -> String? { guard let range = error.range(of: marker) else { return nil }; let request = String(error[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines); return request.isEmpty ? nil : request }
  private func isValidIdentifier(_ key: String) -> Bool { key.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*$", options: .regularExpression) != nil }
  private func hashHex(algorithm: String, value: String) -> String { let data=Data(value.utf8); let lower=algorithm.lowercased(); if lower=="md5" { return Insecure.MD5.hash(data:data).map{String(format:"%02x",$0)}.joined() }; if lower=="sha1" { return Insecure.SHA1.hash(data:data).map{String(format:"%02x",$0)}.joined() }; if lower=="sha256" { return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }; if lower=="sha512" { return SHA512.hash(data:data).map{String(format:"%02x",$0)}.joined() }; if lower.hasPrefix("hmac-sha1:") { let key=SymmetricKey(data:Data(String(algorithm.dropFirst("hmac-sha1:".count)).utf8)); return HMAC<Insecure.SHA1>.authenticationCode(for:data,using:key).map{String(format:"%02x",$0)}.joined() }; if lower.hasPrefix("hmac-sha256:") { let key=SymmetricKey(data:Data(String(algorithm.dropFirst("hmac-sha256:".count)).utf8)); return HMAC<SHA256>.authenticationCode(for:data,using:key).map{String(format:"%02x",$0)}.joined() }; return "" }
  private func readWebViewCookies(for url: String) -> String { guard let host=URL(string:url)?.host?.lowercased(), !host.isEmpty else { return "" }; let sem=DispatchSemaphore(value:0); var header=""; DispatchQueue.main.async { WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in let matched=cookies.filter{ c in let d=c.domain.trimmingCharacters(in:CharacterSet(charactersIn:".")).lowercased(); return host==d || host.hasSuffix("."+d) }; header=matched.map{"\($0.name)=\($0.value)"}.joined(separator:"; "); sem.signal() } }; _=sem.wait(timeout:.now()+2.0); return header }
  private func writeWebViewCookies(_ header: String, for url: String) { guard let target=URL(string:url), let host=target.host, !header.isEmpty else { return }; for pair in header.split(separator:";").map({$0.trimmingCharacters(in:.whitespacesAndNewlines)}) { let parts=pair.split(separator:"=",maxSplits:1).map(String.init); guard parts.count==2,!parts[0].isEmpty else { continue }; let props:[HTTPCookiePropertyKey:Any]=[.domain:host,.path:"/",.name:parts[0],.value:parts[1],.secure:target.scheme=="https" ? "TRUE":"FALSE"]; guard let cookie=HTTPCookie(properties:props) else { continue }; DispatchQueue.main.async { WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) } } }
  private func mergeCookieHeaders(_ lhs: String, _ rhs: String) -> String { var values:[String:String]=[:]; for header in [lhs,rhs] { for raw in header.split(separator:";") { let parts=raw.trimmingCharacters(in:.whitespacesAndNewlines).split(separator:"=",maxSplits:1).map(String.init); if parts.count==2,!parts[0].isEmpty { values[parts[0]]=parts[1] } } }; return values.map{"\($0.key)=\($0.value)"}.joined(separator:"; ") }
  private func jsonString(_ value: Any) -> String? { if JSONSerialization.isValidJSONObject(value), let data=try? JSONSerialization.data(withJSONObject:value), let text=String(data:data,encoding:.utf8){return text}; if let data=try? JSONSerialization.data(withJSONObject:[value]), let text=String(data:data,encoding:.utf8), text.count>=2 { return String(text.dropFirst().dropLast()) }; return nil }
}

final class LegadoLoginWebViewController: UIViewController, WKNavigationDelegate {
  private let url: URL; private let completion: (String) -> Void; private var webView: WKWebView!
  init(url: URL, completion: @escaping (String) -> Void) { self.url=url; self.completion=completion; super.init(nibName:nil,bundle:nil); title="书源登录" }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func loadView() { let c=WKWebViewConfiguration(); c.websiteDataStore = .default(); webView=WKWebView(frame:.zero,configuration:c); webView.navigationDelegate=self; view=webView }
  override func viewDidLoad() { super.viewDidLoad(); navigationItem.leftBarButtonItem=UIBarButtonItem(title:"完成",style:.done,target:self,action:#selector(done)); navigationItem.rightBarButtonItem=UIBarButtonItem(title:"关闭",style:.plain,target:self,action:#selector(cancel)); webView.load(URLRequest(url:url)) }
  @objc private func done() { collectCookies { [weak self] cookies in self?.completion(cookies); self?.dismiss(animated:true) } }
  @objc private func cancel() { dismiss(animated:true) }
  private func collectCookies(_ completion: @escaping (String) -> Void) { let host=url.host?.lowercased() ?? ""; webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in let matched=cookies.filter{ c in let d=c.domain.trimmingCharacters(in:CharacterSet(charactersIn:".")).lowercased(); return host==d || host.hasSuffix("."+d) }; completion(matched.map{"\($0.name)=\($0.value)"}.joined(separator:"; ")) } }
}


final class LocalNetworkPermissionHelper {
  private let serviceType = "_preflight_check._tcp"
  private let queue = DispatchQueue(label: "read.local-network-preflight")
  private var listener: NWListener?
  private var browser: NWBrowser?
  private var completion: ((String) -> Void)?
  private var resolved = false

  func request(timeoutMs: Int, completion: @escaping (String) -> Void) {
    queue.async {
      self.cancelLocked()
      self.resolved = false
      self.completion = completion

      do {
        let listenerParameters = NWParameters(tls: .none, tcp: NWProtocolTCP.Options())
        listenerParameters.includePeerToPeer = true
        let listener = try NWListener(using: listenerParameters)
        listener.service = NWListener.Service(
          name: UUID().uuidString,
          type: self.serviceType
        )
        listener.newConnectionHandler = { connection in
          connection.cancel()
        }
        listener.stateUpdateHandler = { [weak self] state in
          self?.handle(state: state)
        }

        let browserParameters = NWParameters()
        browserParameters.includePeerToPeer = true
        let browser = NWBrowser(
          for: .bonjour(type: self.serviceType, domain: nil),
          using: browserParameters
        )
        browser.stateUpdateHandler = { [weak self] state in
          self?.handle(state: state)
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
          if !results.isEmpty {
            self?.finish("granted")
          }
        }

        self.listener = listener
        self.browser = browser
        listener.start(queue: self.queue)
        browser.start(queue: self.queue)

        let deadline = DispatchTime.now() + .milliseconds(max(800, timeoutMs))
        self.queue.asyncAfter(deadline: deadline) { [weak self] in
          self?.finish("timeout")
        }
      } catch {
        self.finish("failed:\(error.localizedDescription)")
      }
    }
  }

  private func handle(state: NWListener.State) {
    switch state {
    case .failed(let error):
      finish(status(for: error))
    case .waiting(let error):
      if isPolicyDenied(error) {
        finish("denied")
      }
    default:
      break
    }
  }

  private func handle(state: NWBrowser.State) {
    switch state {
    case .failed(let error):
      finish(status(for: error))
    case .waiting(let error):
      if isPolicyDenied(error) {
        finish("denied")
      }
    default:
      break
    }
  }

  private func status(for error: NWError) -> String {
    isPolicyDenied(error) ? "denied" : "failed:\(error.localizedDescription)"
  }

  private func isPolicyDenied(_ error: NWError) -> Bool {
    String(describing: error).contains("PolicyDenied") ||
      String(describing: error).contains("policy denied")
  }

  private func finish(_ status: String) {
    queue.async {
      guard !self.resolved else { return }
      self.resolved = true
      let completion = self.completion
      self.completion = nil
      self.cancelLocked()
      DispatchQueue.main.async {
        completion?(status)
      }
    }
  }

  private func cancelLocked() {
    browser?.cancel()
    listener?.cancel()
    browser = nil
    listener = nil
  }
}
