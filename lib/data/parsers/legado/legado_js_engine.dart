import 'dart:convert';

import 'package:quickjs_engine/quickjs_engine.dart';

class LegadoJsEngine {
  static final LegadoJsEngine _instance = LegadoJsEngine._internal();

  factory LegadoJsEngine() => _instance;

  JavascriptRuntime? _runtime;
  final Set<String> _loadedLibraryKeys = <String>{};

  LegadoJsEngine._internal() {
    try {
      _runtime = getJavascriptRuntime();
      _initJavaObject();
    } catch (e) {
      print('JS Engine Initialization Error: $e');
    }
  }

  bool get isAvailable => _runtime != null;

  void _initJavaObject() {
    final jsCode = r'''
      var __java_store = {};
      var __cache_store = {};
      var __b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

      if (typeof btoa === "undefined") {
        var btoa = function(input) {
          var str = String(input || "");
          var output = "";
          for (var block = 0, charCode, i = 0, map = __b64chars;
              str.charAt(i | 0) || (map = "=", i % 1);
              output += map.charAt(63 & block >> 8 - i % 1 * 8)) {
            charCode = str.charCodeAt(i += 3 / 4);
            if (charCode > 0xFF) throw new Error("btoa failed");
            block = block << 8 | charCode;
          }
          return output;
        };
      }

      if (typeof atob === "undefined") {
        var atob = function(input) {
          var str = String(input || "").replace(/=+$/, "");
          var output = "";
          if (str.length % 4 == 1) throw new Error("atob failed");
          for (var bc = 0, bs, buffer, i = 0;
              buffer = str.charAt(i++);
              ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer,
                bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
            buffer = __b64chars.indexOf(buffer);
          }
          return output;
        };
      }

      function __utf8ToBase64(str) {
        return btoa(unescape(encodeURIComponent(String(str || ""))));
      }

      function __base64ToUtf8(str) {
        return decodeURIComponent(escape(atob(String(str || ""))));
      }

      function __jsonPathValue(sourceValue, path) {
        var sourceText = sourceValue;
        try {
          if (typeof sourceText === "string") sourceText = JSON.parse(sourceText);
        } catch(e) {
          return "";
        }
        var cleaned = String(path || "").replace(/^\$\.?/, "");
        if (!cleaned) return sourceText == null ? "" : String(sourceText);
        cleaned = cleaned.replace(/\[(\d+)\]/g, ".$1");
        var current = sourceText;
        var parts = cleaned.split(".");
        for (var i = 0; i < parts.length; i++) {
          var key = parts[i];
          if (!key) continue;
          if (Array.isArray(current)) {
            var index = parseInt(key, 10);
            if (isNaN(index) || index < 0 || index >= current.length) return "";
            current = current[index];
          } else if (current && Object.prototype.hasOwnProperty.call(current, key)) {
            current = current[key];
          } else {
            return "";
          }
        }
        if (current == null) return "";
        if (typeof current === "object") return JSON.stringify(current);
        return String(current);
      }

      var java = {
        put: function(key, value) {
          __java_store[String(key)] = value;
          return value;
        },
        get: function(key) {
          var value = __java_store[String(key)];
          return value == null ? "" : value;
        },
        getString: function(key) {
          var text = String(key || "");
          var stored = this.get(text);
          if (stored !== "") return String(stored);
          if (typeof result !== "undefined" && (
              text.indexOf("$") === 0 ||
              text.indexOf(".") === 0 ||
              text.indexOf(".") > 0 ||
              text.indexOf("[") > 0)) {
            return __jsonPathValue(result, text);
          }
          return arguments.length > 1 ? String(arguments[1] || "") : "";
        },
        getInt: function(key, def) {
          var value = parseInt(java.getString(key, def == null ? "0" : def), 10);
          return isNaN(value) ? Number(def || 0) : value;
        },
        getLong: function(key, def) {
          return java.getInt(key, def);
        },
        getDouble: function(key, def) {
          var value = parseFloat(java.getString(key, def == null ? "0" : def));
          return isNaN(value) ? Number(def || 0) : value;
        },
        getStringList: function(key) {
          var value = java.getString(key, "[]");
          try {
            var parsed = JSON.parse(value);
            return Array.isArray(parsed) ? parsed : [];
          } catch(e) {
            return value ? String(value).split(",") : [];
          }
        },
        ajax: function(urlStr) {
          return "";
        },
        getWebViewUA: function() {
          return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
        },
        startBrowser: function() { return ""; },
        startBrowserAwait: function() { return ""; },
        openUrl: function() { return ""; },
        post: function(urlStr, body) {
          return java.ajax(String(urlStr || "") + "," + JSON.stringify({ method: "POST", body: body || "" }));
        },
        connect: function(urlStr) {
          var u = String(urlStr || "");
          var chain = {
            header: function() { return chain; },
            headers: function() { return chain; },
            cookies: function() { return chain; },
            timeout: function() { return chain; },
            ignoreContentType: function() { return chain; },
            followRedirects: function() { return chain; },
            get: function() { return chain; },
            post: function() { return chain; },
            raw: function() { return chain; },
            request: function() { return chain; },
            body: function() { return ""; },
            url: function() { return u; },
            toString: function() { return u; }
          };
          return chain;
        },
        base64Encode: function(str) {
          return __utf8ToBase64(str);
        },
        base64Decode: function(str) {
          return __base64ToUtf8(str);
        },
        base64DecodeToString: function(str) {
          return __base64ToUtf8(str);
        },
        encodeURI: function(str) {
          return encodeURI(String(str || ""));
        },
        encodeURIComponent: function(str) {
          return encodeURIComponent(String(str || ""));
        },
        decodeURI: function(str) {
          return decodeURI(String(str || ""));
        },
        decodeURIComponent: function(str) {
          return decodeURIComponent(String(str || ""));
        },
        md5Encode: function(string) {
          function md5cycle(x, k) {
            var a = x[0], b = x[1], c = x[2], d = x[3];
            a = ff(a, b, c, d, k[0], 7, -680876936); d = ff(d, a, b, c, k[1], 12, -389564586); c = ff(c, d, a, b, k[2], 17, 606105819); b = ff(b, c, d, a, k[3], 22, -1044525330);
            a = ff(a, b, c, d, k[4], 7, -176418897); d = ff(d, a, b, c, k[5], 12, 1200080426); c = ff(c, d, a, b, k[6], 17, -1473231341); b = ff(b, c, d, a, k[7], 22, -45705983);
            a = ff(a, b, c, d, k[8], 7, 1770035416); d = ff(d, a, b, c, k[9], 12, -1958414417); c = ff(c, d, a, b, k[10], 17, -42063); b = ff(b, c, d, a, k[11], 22, -1990404162);
            a = ff(a, b, c, d, k[12], 7, 1804603682); d = ff(d, a, b, c, k[13], 12, -40341101); c = ff(c, d, a, b, k[14], 17, -1502002290); b = ff(b, c, d, a, k[15], 22, 1236535329);
            a = gg(a, b, c, d, k[1], 5, -165796510); d = gg(d, a, b, c, k[6], 9, -1069501632); c = gg(c, d, a, b, k[11], 14, 643717713); b = gg(b, c, d, a, k[0], 20, -373897302);
            a = gg(a, b, c, d, k[5], 5, -701558691); d = gg(d, a, b, c, k[10], 9, 38016083); c = gg(c, d, a, b, k[15], 14, -660478335); b = gg(b, c, d, a, k[4], 20, -405537848);
            a = gg(a, b, c, d, k[9], 5, 568446438); d = gg(d, a, b, c, k[14], 9, -1019803690); c = gg(c, d, a, b, k[3], 14, -187363961); b = gg(b, c, d, a, k[8], 20, 1163531501);
            a = gg(a, b, c, d, k[13], 5, -1444681467); d = gg(d, a, b, c, k[2], 9, -51403784); c = gg(c, d, a, b, k[7], 14, 1735328473); b = gg(b, c, d, a, k[12], 20, -1926607734);
            a = hh(a, b, c, d, k[5], 4, -378558); d = hh(d, a, b, c, k[8], 11, -2022574463); c = hh(c, d, a, b, k[11], 16, 1839030562); b = hh(b, c, d, a, k[14], 23, -35309556);
            a = hh(a, b, c, d, k[1], 4, -1530992060); d = hh(d, a, b, c, k[4], 11, 1272893353); c = hh(c, d, a, b, k[7], 16, -155497632); b = hh(b, c, d, a, k[10], 23, -1094730640);
            a = hh(a, b, c, d, k[13], 4, 681279174); d = hh(d, a, b, c, k[0], 11, -358537222); c = hh(c, d, a, b, k[3], 16, -722521979); b = hh(b, c, d, a, k[6], 23, 76029189);
            a = hh(a, b, c, d, k[9], 4, -640364487); d = hh(d, a, b, c, k[12], 11, -421815835); c = hh(c, d, a, b, k[15], 16, 530742520); b = hh(b, c, d, a, k[2], 23, -995338651);
            a = ii(a, b, c, d, k[0], 6, -198630844); d = ii(d, a, b, c, k[7], 10, 1126891415); c = ii(c, d, a, b, k[14], 15, -1416354905); b = ii(b, c, d, a, k[5], 21, -57434055);
            a = ii(a, b, c, d, k[12], 6, 1700485571); d = ii(d, a, b, c, k[3], 10, -1894986606); c = ii(c, d, a, b, k[10], 15, -1051523); b = ii(b, c, d, a, k[1], 21, -2054922799);
            a = ii(a, b, c, d, k[8], 6, 1873313359); d = ii(d, a, b, c, k[15], 10, -30611744); c = ii(c, d, a, b, k[6], 15, -1560198380); b = ii(b, c, d, a, k[13], 21, 1309151649);
            a = ii(a, b, c, d, k[4], 6, -145523070); d = ii(d, a, b, c, k[11], 10, -1120210379); c = ii(c, d, a, b, k[2], 15, 718787259); b = ii(b, c, d, a, k[9], 21, -343485551);
            x[0] = add32(a, x[0]); x[1] = add32(b, x[1]); x[2] = add32(c, x[2]); x[3] = add32(d, x[3]);
          }
          function cmn(q, a, b, x, s, t) { a = add32(add32(a, q), add32(x, t)); return add32((a << s) | (a >>> (32 - s)), b); }
          function ff(a, b, c, d, x, s, t) { return cmn((b & c) | ((~b) & d), a, b, x, s, t); }
          function gg(a, b, c, d, x, s, t) { return cmn((b & d) | (c & (~d)), a, b, x, s, t); }
          function hh(a, b, c, d, x, s, t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
          function ii(a, b, c, d, x, s, t) { return cmn(c ^ (b | (~d)), a, b, x, s, t); }
          function add32(a, b) { return (a + b) & 0xFFFFFFFF; }
          function md51(s) {
            var n = s.length, state = [1732584193, -271733879, -1732584194, 271733878], i;
            for (i = 64; i <= s.length; i += 64) { md5cycle(state, md5blk(s.substring(i - 64, i))); }
            s = s.substring(i - 64);
            var tail = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
            for (i = 0; i < s.length; i++) tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
            tail[i >> 2] |= 0x80 << ((i % 4) << 3);
            if (i > 55) { md5cycle(state, tail); for (i = 0; i < 16; i++) tail[i] = 0; }
            tail[14] = n * 8; md5cycle(state, tail); return state;
          }
          function md5blk(s) {
            var md5blks = [], i;
            for (i = 0; i < 64; i += 4) { md5blks[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i + 1) << 8) + (s.charCodeAt(i + 2) << 16) + (s.charCodeAt(i + 3) << 24); }
            return md5blks;
          }
          function hex(x) {
            var hex_chr = '0123456789abcdef', str = '', i;
            for (i = 0; i < 4; i++) str += hex_chr.charAt((x >> (i * 8 + 4)) & 0x0F) + hex_chr.charAt((x >> (i * 8)) & 0x0F);
            return str;
          }
          function md5(s) {
            var state = md51(unescape(encodeURIComponent(String(s || "")))), str = '', i;
            for (i = 0; i < 4; i++) str += hex(state[i]);
            return str;
          }
          return md5(string);
        },
        hexDecodeToString: function(input) {
          var text = String(input || "");
          if (text.indexOf("data:") === 0) {
            var parts = text.split(",");
            if (parts.length >= 3 && parts[1].toLowerCase() === "base64") {
              return java.base64Decode(parts[2]);
            }
          }
          var hex = text.replace(/\s+/g, "");
          if (!hex || hex.length % 2 !== 0 || !/^[0-9a-fA-F]+$/.test(hex)) return text;
          var out = "";
          for (var i = 0; i < hex.length; i += 2) {
            out += String.fromCharCode(parseInt(hex.substr(i, 2), 16));
          }
          try { return decodeURIComponent(escape(out)); } catch(e) { return out; }
        },
        t2s: function(str) { return String(str || ""); },
        s2t: function(str) { return String(str || ""); },
        toNumChapter: function(str) { return String(str || ""); },
        log: function() { return ""; },
        toast: function() { return ""; },
        longToast: function() { return ""; },
        timeFormat: function(timestamp) {
          return new Date(Number(timestamp || 0)).toLocaleString();
        },
        timeFormatUTC: function(timestamp) {
          return new Date(Number(timestamp || 0)).toISOString().replace("T", " ").substring(0, 19);
        },
        currentTimeMillis: function() {
          return Date.now();
        },
        randomUUID: function() {
          var d = Date.now();
          return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
            var r = (d + Math.random() * 16) % 16 | 0;
            d = Math.floor(d / 16);
            return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16);
          });
        }
      };

      var cookie = {
        getCookie: function(url) { return ""; },
        getKey: function(url, key) { return ""; },
        setCookie: function(url, c) { },
        removeCookie: function(url) { }
      };

      var cache = {
        get: function(key) {
          var value = __cache_store[String(key)];
          return value == null ? "" : value;
        },
        put: function(key, value) {
          __cache_store[String(key)] = value;
          return value;
        },
        getFromCache: function(key) {
          var value = __cache_store[String(key)];
          return value == null ? "" : value;
        },
        putInCache: function(key, value, time) {
          __cache_store[String(key)] = value;
          return value;
        }
      };

      function Map(key) {
        if (typeof key === "string") return java.get(key);
        return {};
      }

      var CryptoJS = {
        MD5: function(value) {
          return { toString: function() { return java.md5Encode(value); } };
        },
        enc: {
          Utf8: { parse: function(value) { return String(value || ""); } },
          Base64: {
            stringify: function(value) { return java.base64Encode(value); },
            parse: function(value) { return java.base64Decode(value); }
          },
          Hex: { parse: function(value) { return String(value || ""); } }
        }
      };
    ''';

    if (_runtime == null) return;
    try {
      final result = _runtime!.evaluate(jsCode);
      if (result.isError) {
        print('JS Engine Initialization Error: ${result.stringResult}');
      }
    } catch (e) {
      print('JS Engine init failed: $e');
    }
  }

  String evaluate(String jsCode, {Map<String, dynamic>? variables}) {
    if (_runtime == null) return '';
    _injectVariables(variables);

    try {
      final result = _runtime!.evaluate(_prepareCode(jsCode));
      if (result.isError) throw Exception(result.stringResult);
      return _stringifyResult(result);
    } catch (e) {
      print('JS Eval failed: $e');
      throw Exception('JS执行异常: $e');
    }
  }

  Future<String> evaluateWithAjax(
    String jsCode, {
    Map<String, dynamic>? variables,
    Iterable<String> libraries = const [],
    required Future<String> Function(String request) ajax,
    int maxRequests = 12,
  }) async {
    if (_runtime == null) return '';

    final cache = <String, String>{};
    for (var attempt = 0; attempt <= maxRequests; attempt++) {
      _injectVariables(variables);
      loadLibraries(libraries);
      _installAjaxTrap(cache);
      try {
        final result = _runtime!.evaluate(_prepareCode(jsCode));
        if (result.isError) throw Exception(result.stringResult);
        return _stringifyResult(result);
      } catch (e) {
        final request = _extractAjaxRequest(e.toString());
        if (request == null || cache.containsKey(request)) rethrow;
        cache[request] = await ajax(request);
      }
    }
    throw Exception('JS ajax requests exceeded $maxRequests');
  }

  void loadLibraries(Iterable<String> libraries) {
    if (_runtime == null) return;
    for (final library in libraries) {
      final code = library.trim();
      if (code.isEmpty) continue;
      final key = code.hashCode.toString();
      if (_loadedLibraryKeys.contains(key)) continue;
      try {
        final result = _runtime!.evaluate(code);
        if (!result.isError) {
          _loadedLibraryKeys.add(key);
        }
      } catch (e) {
        print('JS library load failed: $e');
      }
    }
  }

  void _injectVariables(Map<String, dynamic>? variables) {
    if (_runtime == null || variables == null) return;
    try {
      variables.forEach((key, value) {
        _runtime!.evaluate('var $key = ${jsonEncode(value)};');
      });
      _runtime!.evaluate(r'''
        if (typeof cookieHeader !== 'undefined') {
          cookie.getCookie = function() {
            return String(cookieHeader || "");
          };
          cookie.getKey = function(url, key) {
            var name = String(key || "");
            if (!name) return "";
            var parts = String(cookieHeader || "").split(";");
            for (var i = 0; i < parts.length; i++) {
              var part = parts[i].trim();
              var pos = part.indexOf("=");
              if (pos <= 0) continue;
              if (part.substring(0, pos).trim() === name) {
                return part.substring(pos + 1).trim();
              }
            }
            return "";
          };
        }
        if (typeof source !== 'undefined' && source !== null) {
          source.getKey = function() { return source.key || source.bookSourceUrl || ""; };
          source.getVariable = function() { return source.variable || ""; };
          source.getVariableMap = function() {
            var raw = source.variable || "";
            var parsed = {};
            if (raw) {
              try { parsed = JSON.parse(raw); } catch(e) { parsed = {}; }
            }
            return {
              get: function(k) {
                var value = parsed[String(k)];
                return value == null ? "" : value;
              }
            };
          };
          source.getLoginInfoMap = function() {
            return {
              get: function() { return ""; }
            };
          };
        }
      ''');
    } catch (e) {
      print('JS variables injection failed: $e');
    }
  }

  String _prepareCode(String jsCode) {
    var codeToRun = jsCode.trim();
    if (codeToRun.startsWith('@js:')) {
      codeToRun = codeToRun.substring(4);
    } else if (codeToRun.startsWith('<js>') && codeToRun.endsWith('</js>')) {
      codeToRun = codeToRun.substring(4, codeToRun.length - 5);
    }

    if (codeToRun.contains('return ') && !codeToRun.contains('function')) {
      codeToRun = '(function() { $codeToRun })()';
    }
    return codeToRun;
  }

  void _installAjaxTrap(Map<String, String> cache) {
    if (_runtime == null) return;
    _runtime!.evaluate('''
      var __legado_ajax_cache = ${jsonEncode(cache)};
      java.ajax = function(urlStr) {
        var url = String(urlStr || "");
        if (Object.prototype.hasOwnProperty.call(__legado_ajax_cache, url)) {
          return __legado_ajax_cache[url];
        }
        throw new Error("__LEGADO_AJAX__" + url);
      };
      java.post = function(urlStr, body) {
        var payload = String(urlStr || "") + "," + JSON.stringify({ method: "POST", body: body || "" });
        return java.ajax(payload);
      };
      java.connect = function(urlStr) {
        var u = String(urlStr || "");
        var config = { method: "GET", headers: {} };
        var chain = {
          header: function(k, v) {
            if (k != null) config.headers[String(k)] = String(v == null ? "" : v);
            return chain;
          },
          headers: function(value) {
            if (typeof value === "string") {
              try { value = JSON.parse(value); } catch(e) { value = {}; }
            }
            if (value) {
              for (var k in value) config.headers[String(k)] = String(value[k]);
            }
            return chain;
          },
          cookie: function(value) {
            if (value != null) config.headers.Cookie = String(value);
            return chain;
          },
          cookies: function(value) {
            if (value != null) config.headers.Cookie = String(value);
            return chain;
          },
          timeout: function() { return chain; },
          ignoreContentType: function() { return chain; },
          followRedirects: function() { return chain; },
          get: function() { config.method = "GET"; return chain; },
          post: function(body) { config.method = "POST"; config.body = body == null ? "" : String(body); return chain; },
          data: function(body) { config.body = body == null ? "" : String(body); return chain; },
          requestBody: function(body) { config.body = body == null ? "" : String(body); return chain; },
          raw: function() { return chain; },
          request: function() { return chain; },
          body: function() {
            var payload = Object.keys(config.headers).length || config.method !== "GET" || config.body
              ? u + "," + JSON.stringify(config)
              : u;
            return java.ajax(payload);
          },
          execute: function() { return chain.body(); },
          url: function() { return u; },
          toString: function() { return u; }
        };
        return chain;
      };
    ''');
  }

  String? _extractAjaxRequest(String error) {
    final marker = error.indexOf('__LEGADO_AJAX__');
    if (marker < 0) return null;
    final request = error
        .substring(marker + '__LEGADO_AJAX__'.length)
        .replaceFirst(RegExp(r'^[\s:]+'), '')
        .replaceFirst(RegExp(r'[\s\)]+$'), '')
        .trim();
    return request.isEmpty ? null : request;
  }

  String _stringifyResult(dynamic result) {
    final text = result.stringResult?.toString() ?? '';
    try {
      final jsonText = _runtime?.jsonStringify(result).trim() ?? '';
      if (jsonText.isNotEmpty && jsonText != 'undefined') {
        if (jsonText.startsWith('{') || jsonText.startsWith('[')) {
          return jsonText;
        }
        if (text.isEmpty ||
            text == '[object Object]' ||
            text.startsWith('[object')) {
          final decoded = jsonDecode(jsonText);
          if (decoded is String) return decoded;
          return jsonText;
        }
      }
    } catch (_) {
      // Keep stringResult.
    }
    return text;
  }

  void dispose() {
    _runtime?.dispose();
  }
}
