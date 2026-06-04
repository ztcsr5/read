import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:quickjs_engine/quickjs_engine.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

class LegadoJsEngine {
  static final LegadoJsEngine _instance = LegadoJsEngine._internal();

  factory LegadoJsEngine() => _instance;

  JavascriptRuntime? _runtime;
  final Set<String> _loadedLibraryKeys = <String>{};
  Future<String> Function(String request)? _currentAjaxHandler;
  final Map<String, dynamic> _javaStorage = <String, dynamic>{};
  final Map<String, Document> _jsoupDocuments = {};

  LegadoJsEngine._internal() {
    try {
      _runtime = getJavascriptRuntime();
      _initJavaObject();
      _runtime!.onMessage('java_ajax', (dynamic args) async {
        final handler = _currentAjaxHandler;
        if (handler != null) {
          try {
            return await handler(args.toString());
          } catch (e) {
            print('Ajax in JS failed: $e');
            return 'Error: $e';
          }
        }
        return '';
      });

      _runtime!.onMessage('jsoup_parse', (dynamic args) {
        final html = args.toString();
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        try {
          _jsoupDocuments[id] = parse(html);
          return id;
        } catch (_) {
          return '';
        }
      });

      _runtime!.onMessage('jsoup_select', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final id = data['id'].toString();
          final selector = data['selector'].toString();
          final doc = _jsoupDocuments[id];
          if (doc != null) {
            final elements = doc.querySelectorAll(selector);
            final resultList = elements
                .map(
                  (el) => {
                    'text': el.text.trim(),
                    'html': el.outerHtml,
                    'attr': el.attributes,
                  },
                )
                .toList();
            return jsonEncode(resultList);
          }
        } catch (e) {
          print('Jsoup select failed: $e');
        }
        return '[]';
      });

      _runtime!.onMessage('java_put', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final String key = data['key'].toString();
          final dynamic value = data['value'];
          _javaStorage[key] = value;
          return value;
        } catch (e) {
          print('java_put failed: $e');
          return null;
        }
      });

      _runtime!.onMessage('java_get', (dynamic args) {
        final String key = args.toString();
        return _javaStorage[key];
      });

      _runtime!.onMessage('java_md5', (dynamic args) {
        final String input = args?.toString() ?? '';
        final bytes = utf8.encode(input);
        final digest = md5.convert(bytes);
        return digest.toString().toLowerCase();
      });

      _runtime!.onMessage('java_aes_base64_decode', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          return _aesBase64Decode(
            data['value']?.toString() ?? '',
            data['key']?.toString() ?? '',
            data['iv']?.toString() ?? '',
          );
        } catch (e) {
          print('java_aes_base64_decode failed: $e');
          return '';
        }
      });

      _runtime!.onMessage('java_time', (dynamic args) {
        return DateTime.now().millisecondsSinceEpoch;
      });
    } catch (e) {
      print('JS Engine Initialization Error: $e');
    }
  }

  bool get isAvailable => _runtime != null;

  void _initJavaObject() {
    final jsCode = r'''
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
          if (typeof key === "string" && (key.indexOf("http://") === 0 || key.indexOf("https://") === 0)) {
            return java.ajax(key + "," + JSON.stringify({ method: "PUT", body: value || "" }));
          }
          sendMessage("java_put", JSON.stringify({key: String(key), value: value}));
          return value;
        },
        get: function(key) {
          if (typeof key === "string" && (key.indexOf("http://") === 0 || key.indexOf("https://") === 0)) {
            return this.ajax(key);
          }
          var value = sendMessage("java_get", String(key));
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
          return sendMessage("java_ajax", String(urlStr || ""));
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
          return sendMessage("java_md5", String(string || ""));
        },
        aesBase64DecodeToString: function(value, key, iv, transformation) {
          return sendMessage("java_aes_base64_decode", JSON.stringify({
            value: String(value || ""),
            key: String(key || ""),
            iv: String(iv || "")
          }));
        },
        aesDecodeToString: function(value, key, iv, transformation) {
          return java.aesBase64DecodeToString(value, key, iv, transformation);
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
          return sendMessage("java_time", "");
        },
        randomUUID: function() {
          var d = Date.now();
          return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
            var r = (d + Math.random() * 16) % 16 | 0;
            d = Math.floor(d / 16);
            return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16);
          });
        },
        uuid: function() {
          return this.randomUUID();
        },
        now: function() {
          return this.currentTimeMillis();
        }
      };

      function kv_get(key) {
        return java.get(key);
      }
      function kv_put(key, value) {
        return java.put(key, value);
      }
      function regex_replace(input, pattern, replace) {
        var str = String(input || "");
        var pat = String(pattern || "");
        var rep = String(replace || "");
        try {
          var regex = new RegExp(pat, "g");
          return str.replace(regex, rep);
        } catch(e) {
          return str;
        }
      }
      function strip_ws(input) {
        return String(input || "").replace(/\s+/g, "");
      }

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

      var org = {
        jsoup: {
          Jsoup: {
            parse: function(html) {
              var docId = sendMessage("jsoup_parse", String(html || ""));
              var mockDoc = {
                select: function(selector) {
                  var rawResult = sendMessage("jsoup_select", JSON.stringify({id: docId, selector: String(selector || "")}));
                  var nodes = [];
                  try {
                    nodes = JSON.parse(rawResult);
                  } catch(e) {}
                  
                  var wrapper = {
                    text: function() { return nodes.map(n => n.text).join("\n"); },
                    html: function() { return nodes.map(n => n.html).join("\n"); },
                    attr: function(name) { return nodes.length > 0 ? String(nodes[0].attr[name] || "") : ""; },
                    first: function() { return wrapper; },
                    get: function(index) { return wrapper; },
                    eq: function(index) { return wrapper; },
                    size: function() { return nodes.length; },
                    isEmpty: function() { return nodes.length === 0; }
                  };
                  return wrapper;
                }
              };
              return mockDoc;
            }
          }
        }
      };

      java.md5 = function(string) {
        return this.md5Encode(string);
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
    } finally {
      _jsoupDocuments.clear();
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

    _currentAjaxHandler = ajax;
    _injectVariables(variables);
    loadLibraries(libraries);
    try {
      final prepared = _prepareCode(jsCode);
      var result = _runtime!.evaluate(prepared);
      if (result.isError) throw Exception(result.stringResult);
      if (result.isPromise) {
        _runtime!.executePendingJob();
        result = await _runtime!.handlePromise(result);
        if (result.isError) throw Exception(result.stringResult);
      }
      return _stringifyResult(result);
    } catch (e) {
      print('JS Eval with AJAX failed: $e');
      rethrow;
    } finally {
      _currentAjaxHandler = null;
      _jsoupDocuments.clear();
    }
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
    if (_runtime == null) return;
    final Map<String, dynamic> vars = <String, dynamic>{};
    if (variables != null) {
      vars.addAll(variables);
    }

    // Alias data flow
    if (vars.containsKey('result') && !vars.containsKey('input'))
      vars['input'] = vars['result'];
    if (vars.containsKey('result') && !vars.containsKey('src'))
      vars['src'] = vars['result'];
    if (vars.containsKey('input') && !vars.containsKey('result'))
      vars['result'] = vars['input'];
    if (vars.containsKey('input') && !vars.containsKey('src'))
      vars['src'] = vars['input'];
    if (vars.containsKey('src') && !vars.containsKey('result'))
      vars['result'] = vars['src'];
    if (vars.containsKey('src') && !vars.containsKey('input'))
      vars['input'] = vars['src'];

    // Alias URL
    if (vars.containsKey('baseUrl') && !vars.containsKey('base_url'))
      vars['base_url'] = vars['baseUrl'];
    if (vars.containsKey('baseUrl') && !vars.containsKey('url'))
      vars['url'] = vars['baseUrl'];
    if (vars.containsKey('base_url') && !vars.containsKey('baseUrl'))
      vars['baseUrl'] = vars['base_url'];
    if (vars.containsKey('base_url') && !vars.containsKey('url'))
      vars['url'] = vars['base_url'];
    if (vars.containsKey('url') && !vars.containsKey('baseUrl'))
      vars['baseUrl'] = vars['url'];
    if (vars.containsKey('url') && !vars.containsKey('base_url'))
      vars['base_url'] = vars['url'];

    try {
      vars.forEach((key, value) {
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
          source.getVariable = function() {
            return source.variable || java.get("source.variable") || "";
          };
          source.setVariable = function(value) {
            source.variable = value == null ? "" : String(value);
            java.put("source.variable", source.variable);
            return source.variable;
          };
          source.variable = source.getVariable();
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

    codeToRun = codeToRun.trim();

    // Use JsCompatibilityTransformer to upgrade functions with java.ajax calls to async and insert await correctly
    codeToRun = JsCompatibilityTransformer.transform(codeToRun);

    final hasAwait = codeToRun.contains('await');

    if (hasAwait) {
      final clean = codeToRun.trim();
      if (clean.startsWith('(function(') ||
          clean.startsWith('(async function(')) {
        return clean.replaceFirst(
          RegExp(r'^\((async\s+)?function\('),
          '(async function(',
        );
      } else if (clean.startsWith('(()') || clean.startsWith('(async()')) {
        return clean.replaceFirst(RegExp(r'^\((async\s*)?\(\)'), '(async()');
      }

      if (codeToRun.contains('return ') && !codeToRun.startsWith('(async')) {
        return '(async function() { $codeToRun })()';
      } else if (!codeToRun.startsWith('(async') &&
          !codeToRun.startsWith('var') &&
          !codeToRun.startsWith('let') &&
          !codeToRun.startsWith('const')) {
        return '(async () => { return ($codeToRun); })()';
      }
    } else {
      if (codeToRun.contains('return ') && !codeToRun.contains('function')) {
        codeToRun = '(function() { $codeToRun })()';
      }
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

  String _aesBase64Decode(String value, String key, String iv) {
    try {
      final keyBytes = Uint8List.fromList(utf8.encode(key));
      if (keyBytes.length != 16 &&
          keyBytes.length != 24 &&
          keyBytes.length != 32) {
        return '';
      }
      var ivBytes = Uint8List.fromList(utf8.encode(iv));
      if (ivBytes.length != 16) {
        ivBytes = Uint8List(16);
      }

      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        CBCBlockCipher(AESEngine()),
      );
      cipher.init(
        false,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes),
          null,
        ),
      );
      final encrypted = base64Decode(value);
      return utf8.decode(cipher.process(Uint8List.fromList(encrypted)));
    } catch (_) {
      return '';
    }
  }

  void dispose() {
    _runtime?.dispose();
  }
}

class JsCompatibilityTransformer {
  static String transform(String code) {
    var transformed = code;

    final hasJavaCall = RegExp(
      r'java\.(ajax|post|connect|startBrowser)\b',
    ).hasMatch(transformed);
    if (!hasJavaCall) {
      return transformed;
    }

    transformed = transformed.replaceAllMapped(
      RegExp(r'\bfunction\b(\s+\w+)?\s*\(([^)]*)\)'),
      (match) {
        final name = match.group(1) ?? '';
        final params = match.group(2) ?? '';
        final before = match.input.substring(0, match.start);
        if (before.trim().endsWith('async')) {
          return match.group(0)!;
        }
        return 'async function$name($params)';
      },
    );

    transformed = transformed.replaceAllMapped(RegExp(r'\(([^)]*)\)\s*=>'), (
      match,
    ) {
      final params = match.group(1) ?? '';
      final before = match.input.substring(0, match.start);
      if (before.trim().endsWith('async')) {
        return match.group(0)!;
      }
      return 'async ($params) =>';
    });

    transformed = transformed.replaceAllMapped(
      RegExp(
        r'\b(?!(?:return|yield|await|throw|delete|typeof|void)\b)(\w+)\s*=>',
      ),
      (match) {
        final param = match.group(1) ?? '';
        final before = match.input.substring(0, match.start);
        if (before.trim().endsWith('async')) {
          return match.group(0)!;
        }
        return 'async $param =>';
      },
    );

    transformed = transformed.replaceAllMapped(
      RegExp(r'(?<!await\s+)java\.(ajax|post|connect|startBrowser)\b'),
      (match) => 'await java.${match.group(1)}',
    );

    if (!transformed.contains('await') || _isAsyncIife(transformed)) {
      return transformed;
    }

    return '(async function() { ${_returnLastExpression(transformed)} })()';
  }

  static bool _isAsyncIife(String code) {
    final trimmed = code.trimLeft();
    return trimmed.startsWith('(async function') ||
        trimmed.startsWith('(async ()') ||
        trimmed.startsWith('(async(');
  }

  static String _returnLastExpression(String code) {
    final trimmed = code.trim().replaceFirst(RegExp(r';+\s*$'), '');
    if (trimmed.isEmpty || RegExp(r'\breturn\b').hasMatch(trimmed)) {
      return code;
    }

    final split = _lastTopLevelSemicolon(trimmed);
    final prefix = split < 0 ? '' : trimmed.substring(0, split + 1);
    final last = split < 0 ? trimmed : trimmed.substring(split + 1).trim();
    if (last.isEmpty || _isStatementOnly(last)) {
      return '$trimmed;';
    }
    return '$prefix return ($last);';
  }

  static bool _isStatementOnly(String text) {
    final trimmed = text.trimLeft();
    return RegExp(
      r'^(var|let|const|if|for|while|switch|try|throw|class|function)\b',
    ).hasMatch(trimmed);
  }

  static int _lastTopLevelSemicolon(String code) {
    var quote = 0;
    var escaping = false;
    var depth = 0;
    var last = -1;

    for (var i = 0; i < code.length; i++) {
      final unit = code.codeUnitAt(i);
      if (escaping) {
        escaping = false;
        continue;
      }
      if (unit == 0x5C) {
        escaping = true;
        continue;
      }
      if (quote != 0) {
        if (unit == quote) quote = 0;
        continue;
      }
      if (unit == 0x22 || unit == 0x27 || unit == 0x60) {
        quote = unit;
        continue;
      }
      if (unit == 0x28 || unit == 0x5B || unit == 0x7B) {
        depth++;
        continue;
      }
      if (unit == 0x29 || unit == 0x5D || unit == 0x7D) {
        if (depth > 0) depth--;
        continue;
      }
      if (unit == 0x3B && depth == 0) {
        last = i;
      }
    }

    return last;
  }
}
