import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:pointycastle/export.dart';
import 'package:quickjs_engine/quickjs_engine.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

import 'legado_session_store.dart';

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

      _runtime!.onMessage('java_hash', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          return _hashHex(
            data['type']?.toString() ?? '',
            data['value']?.toString() ?? '',
          );
        } catch (_) {
          return '';
        }
      });

      _runtime!.onMessage('java_encode_type', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          return _encodeByType(
            data['type']?.toString() ?? '',
            data['value']?.toString() ?? '',
          );
        } catch (_) {
          return '';
        }
      });

      _runtime!.onMessage('java_decode_type', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          return _decodeByType(
            data['type']?.toString() ?? '',
            data['value']?.toString() ?? '',
          );
        } catch (_) {
          return '';
        }
      });

      _runtime!.onMessage('java_aes_base64_encode', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          return jsonEncode(
            _aesEncodeToMap(
              data['value']?.toString() ?? '',
              data['key']?.toString() ?? '',
              data['iv']?.toString() ?? '',
              data['mode']?.toString() ?? 'cbc',
            ),
          );
        } catch (e) {
          print('java_aes_base64_encode failed: $e');
          return '{}';
        }
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

      _runtime!.onMessage('cookie_get', (dynamic args) {
        try {
          final uri = Uri.tryParse(args?.toString() ?? '');
          if (uri == null) return '';
          return LegadoSessionStore.cookieHeaderFor(uri) ?? '';
        } catch (_) {
          return '';
        }
      });

      _runtime!.onMessage('cookie_set', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final uri = Uri.tryParse(data['url']?.toString() ?? '');
          final value = data['cookie']?.toString() ?? '';
          if (uri == null || value.trim().isEmpty) return false;
          LegadoSessionStore.setCookieString(uri, value);
          return true;
        } catch (_) {
          return false;
        }
      });

      _runtime!.onMessage('cookie_remove', (dynamic args) {
        try {
          final uri = Uri.tryParse(args?.toString() ?? '');
          if (uri == null) return false;
          LegadoSessionStore.clearHost(uri);
          return true;
        } catch (_) {
          return false;
        }
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

      function __wrapJsoupElement(node) {
        node = node || {};
        return {
          text: function() { return String(node.text || ""); },
          html: function() { return String(node.html || ""); },
          outerHtml: function() { return String(node.html || ""); },
          attr: function(name) {
            return node.attr ? String(node.attr[String(name)] || "") : "";
          },
          select: function(selector) {
            return __selectFromHtml(String(node.html || ""), selector);
          },
          toJSON: function() { return String(node.html || ""); },
          toString: function() { return String(node.html || ""); }
        };
      }

      function __wrapJsoupNodes(nodes) {
        nodes = Array.isArray(nodes) ? nodes : [];
        var wrapper = {
          length: nodes.length,
          text: function() { return nodes.map(function(n) { return n.text || ""; }).join("\n"); },
          html: function() { return nodes.map(function(n) { return n.html || ""; }).join("\n"); },
          outerHtml: function() { return wrapper.html(); },
          attr: function(name) {
            return nodes.length > 0 && nodes[0].attr ? String(nodes[0].attr[String(name)] || "") : "";
          },
          first: function() { return __wrapJsoupNodes(nodes.length ? [nodes[0]] : []); },
          get: function(index) {
            index = Number(index || 0);
            return __wrapJsoupNodes(index >= 0 && index < nodes.length ? [nodes[index]] : []);
          },
          eq: function(index) { return wrapper.get(index); },
          size: function() { return nodes.length; },
          isEmpty: function() { return nodes.length === 0; },
          select: function(selector) {
            var merged = [];
            for (var i = 0; i < nodes.length; i++) {
              var docId = sendMessage("jsoup_parse", String(nodes[i].html || ""));
              var raw = sendMessage("jsoup_select", JSON.stringify({id: docId, selector: String(selector || "")}));
              try {
                var parsed = JSON.parse(raw);
                if (Array.isArray(parsed)) merged = merged.concat(parsed);
              } catch(e) {}
            }
            return __wrapJsoupNodes(merged);
          },
          map: function(fn) { return nodes.map(fn); },
          forEach: function(fn) { return nodes.forEach(fn); },
          toArray: function() { return nodes.slice(); },
          toJSON: function() { return wrapper.html(); },
          toString: function() { return wrapper.html(); }
        };
        for (var i = 0; i < nodes.length; i++) wrapper[i] = __wrapJsoupElement(nodes[i]);
        return wrapper;
      }

      function __arrayWithToArray(values) {
        var list = Array.isArray(values) ? values : [];
        if (typeof list.toArray !== "function") {
          list.toArray = function() { return list.slice(); };
        }
        if (typeof list.size !== "function") {
          list.size = function() { return list.length; };
        }
        if (typeof list.isEmpty !== "function") {
          list.isEmpty = function() { return list.length === 0; };
        }
        if (typeof list.get !== "function") {
          list.get = function(index) { return list[Number(index || 0)]; };
        }
        return list;
      }

      function __selectFromHtml(html, selector) {
        var docId = sendMessage("jsoup_parse", String(html || ""));
        var rawResult = sendMessage("jsoup_select", JSON.stringify({id: docId, selector: String(selector || "")}));
        var nodes = [];
        try {
          nodes = JSON.parse(rawResult);
        } catch(e) {}
        return __wrapJsoupNodes(nodes);
      }

      function __looksLikeHtmlInput(value) {
        return /<[a-zA-Z][\s\S]*>/.test(String(value || ""));
      }

      function __looksLikeHtmlRule(ruleStr) {
        var rule = String(ruleStr || "").trim();
        while (rule.indexOf("@@") === 0) rule = rule.substring(2).trim();
        return rule.indexOf("@") >= 0 ||
          rule.indexOf("||") >= 0 ||
          rule.indexOf("&&") >= 0 ||
          rule.indexOf("#") === 0 ||
          rule.indexOf(".") === 0 ||
          rule.indexOf("class.") === 0 ||
          rule.indexOf("id.") === 0 ||
          rule.indexOf("tag.") === 0;
      }

      function __stripHtmlRulePrefix(ruleStr) {
        var value = String(ruleStr || "").trim();
        while (value.indexOf("@@") === 0) value = value.substring(2).trim();
        if (value.indexOf("@css:") === 0) value = value.substring(5).trim();
        return value;
      }

      function __isHtmlAttrToken(token) {
        var value = String(token || "").trim();
        var lower = value.toLowerCase();
        return lower === "text" ||
          lower === "owntext" ||
          lower === "html" ||
          lower === "outerhtml" ||
          lower === "all" ||
          lower === "href" ||
          lower === "src" ||
          lower.indexOf("attr.") === 0 ||
          lower.indexOf("attr(") === 0;
      }

      function __normalizeLegadoSelectorToken(token) {
        var value = __stripHtmlRulePrefix(token);
        value = value.replace(/![^\\s>+~.#\\[]+$/g, "");
        value = value.replace(/\\.\\d+$/g, "");
        if (!value || value === "text" || value === "@text") return "body";
        if (value.indexOf("class.") === 0) return "." + value.substring(6).replace(/\\s+/g, ".");
        if (value.indexOf("id.") === 0) return "#" + value.substring(3).trim();
        if (value.indexOf("tag.") === 0) return value.substring(4).trim().replace(/\\.\\d+$/g, "");
        return value;
      }

      function __normalizeLegadoSelector(selector) {
        var value = __stripHtmlRulePrefix(selector);
        if (value.indexOf("@") >= 0) {
          return value.split("@")
            .filter(function(part) { return String(part || "").trim() !== ""; })
            .map(__normalizeLegadoSelectorToken)
            .join(" ");
        }
        if (!value || value === "text" || value === "@text") return "body";
        if (value.indexOf("class.") === 0) return "." + value.substring(6).replace(/\s+/g, ".");
        if (value.indexOf("id.") === 0) return "#" + value.substring(3).trim();
        if (value.indexOf("tag.") === 0) return value.substring(4).trim();
        return value;
      }

      function __splitHtmlRule(ruleStr) {
        var rule = __stripHtmlRulePrefix(ruleStr);
        var parts = rule.split("@")
          .filter(function(part) { return String(part || "").trim() !== ""; });
        if (parts.length > 1) {
          var last = String(parts[parts.length - 1] || "").trim();
          var attr = __isHtmlAttrToken(last) ? last : "text";
          var selectorParts = __isHtmlAttrToken(last) ? parts.slice(0, -1) : parts;
          return {
            selector: selectorParts.map(__normalizeLegadoSelectorToken).join(" "),
            attr: attr || "text"
          };
        }
        var at = rule.lastIndexOf("@");
        var selector = at >= 0 ? rule.substring(0, at).trim() : rule;
        var attr = at >= 0 ? rule.substring(at + 1).trim() : "text";
        return { selector: __normalizeLegadoSelector(selector), attr: attr || "text" };
      }

      function __nodeValueByAttr(node, attr) {
        attr = String(attr || "text");
        if (attr === "text" || attr === "ownText") return String(node.text || "");
        if (attr === "html" || attr === "outerHtml" || attr === "all") return String(node.html || "");
        if (attr === "href" || attr === "src") return node.attr ? String(node.attr[attr] || "") : "";
        if (attr.indexOf("attr.") === 0) attr = attr.substring(5);
        var attrFn = /^attr\(\s*([^)]+?)\s*\)$/.exec(attr);
        if (attrFn) attr = attrFn[1];
        return node.attr ? String(node.attr[attr] || "") : "";
      }

      function __extractHtmlRuleString(html, ruleStr) {
        var parts = __splitHtmlRule(ruleStr);
        var nodes = __selectFromHtml(html, parts.selector).toArray();
        if (!nodes.length) return "";
        if (parts.attr === "text" || parts.attr === "ownText") {
          return nodes.map(function(n) { return __nodeValueByAttr(n, parts.attr); }).join("\n");
        }
        return __nodeValueByAttr(nodes[0], parts.attr);
      }

      function __extractHtmlRuleList(html, ruleStr) {
        var parts = __splitHtmlRule(ruleStr);
        var nodes = __selectFromHtml(html, parts.selector).toArray();
        return __arrayWithToArray(nodes.map(function(n) { return __nodeValueByAttr(n, parts.attr); }));
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
          if (typeof result !== "undefined" && __looksLikeHtmlInput(result) && __looksLikeHtmlRule(text)) {
            var htmlValue = __extractHtmlRuleString(result, text);
            if (htmlValue !== "") return htmlValue;
          }
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
          var text = String(key || "");
          if (typeof result !== "undefined" && __looksLikeHtmlInput(result) && __looksLikeHtmlRule(text)) {
            return __extractHtmlRuleList(result, text);
          }
          var value = java.getString(key, "[]");
          try {
            var parsed = JSON.parse(value);
            return __arrayWithToArray(Array.isArray(parsed) ? parsed : []);
          } catch(e) {
            return __arrayWithToArray(value ? String(value).split(",") : []);
          }
        },
        getElements: function(ruleStr) {
          var html = typeof result === "undefined" ? "" : result;
          return __selectFromHtml(html, ruleStr);
        },
        getElement: function(ruleStr) {
          return java.getElements(ruleStr).first();
        },
        setContent: function(content) {
          if (content && typeof content === "object") {
            if (typeof content.html === "function") {
              result = content.html();
            } else if (content.html != null) {
              result = String(content.html);
            } else if (content.outerHtml != null) {
              result = String(content.outerHtml);
            } else {
              result = String(content);
            }
          } else {
            result = content == null ? "" : String(content);
          }
          return result;
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
          var config = { method: "GET", headers: {}, body: "" };
          function payload() {
            return Object.keys(config.headers).length || config.method !== "GET" || config.body
              ? u + "," + JSON.stringify(config)
              : u;
          }
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
            followRedirects: function(value) { config.followRedirects = value !== false; return chain; },
            get: function() { config.method = "GET"; return chain; },
            post: function(body) { config.method = "POST"; config.body = body == null ? "" : String(body); return chain; },
            data: function(body) { config.body = body == null ? "" : String(body); return chain; },
            requestBody: function(body) { config.body = body == null ? "" : String(body); return chain; },
            raw: function() { return chain; },
            request: function() { return chain; },
            body: function() { return java.ajax(payload()); },
            execute: function() { return chain.body(); },
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

      var AESMode = {
        cbc: "cbc",
        cfb64: "cfb64",
        ctr: "ctr",
        ecb: "ecb",
        ofb64Gctr: "ofb64Gctr",
        ofb64: "ofb64",
        sic: "sic"
      };

      var esoTools = {
        encode: function(type, body) {
          return sendMessage("java_encode_type", JSON.stringify({type: String(type || ""), value: String(body || "")}));
        },
        decode: function(type, body) {
          return sendMessage("java_decode_type", JSON.stringify({type: String(type || ""), value: String(body || "")}));
        },
        md5Encode: function(str) { return java.md5Encode(str); },
        base64Encode: function(str) { return java.base64Encode(str); },
        base64Decode: function(str) { return java.base64Decode(str); },
        sha1Encode: function(str) { return sendMessage("java_hash", JSON.stringify({type: "sha1", value: String(str || "")})); },
        sha224Encode: function(str) { return sendMessage("java_hash", JSON.stringify({type: "sha224", value: String(str || "")})); },
        sha256Encode: function(str) { return sendMessage("java_hash", JSON.stringify({type: "sha256", value: String(str || "")})); },
        sha348Encode: function(str) { return sendMessage("java_hash", JSON.stringify({type: "sha384", value: String(str || "")})); },
        sha384Encode: function(str) { return sendMessage("java_hash", JSON.stringify({type: "sha384", value: String(str || "")})); },
        sha512Encode: function(str) { return sendMessage("java_hash", JSON.stringify({type: "sha512", value: String(str || "")})); },
        ripemd160Encode: function(str) { return sendMessage("java_hash", JSON.stringify({type: "ripemd160", value: String(str || "")})); },
        AES_Encode: function(string, inkey, opt) {
          opt = opt || {};
          var mode = String(opt.mode || AESMode.cbc || "cbc");
          var raw = sendMessage("java_aes_base64_encode", JSON.stringify({
            value: String(string || ""),
            key: String(inkey || ""),
            iv: String(opt.iv || ""),
            mode: mode
          }));
          try { return JSON.parse(raw); } catch(e) { return {base16: "", base64: "", bytes: []}; }
        },
        AES_Decode: function(string, inkey, opt) {
          opt = opt || {};
          return java.aesBase64DecodeToString(string, inkey, opt.iv || "", String(opt.mode || AESMode.cbc || "cbc"));
        },
        AES_EncodeCBC: function(string, inkey, iniv) { return esoTools.AES_Encode(string, inkey, {mode: AESMode.cbc, iv: iniv}); },
        AES_DecodeCBC: function(string, inkey, iniv) { return esoTools.AES_Decode(string, inkey, {mode: AESMode.cbc, iv: iniv}); },
        AES_EncodeECB: function(string, inkey) { return esoTools.AES_Encode(string, inkey, {mode: AESMode.ecb}); },
        AES_DecodeECB: function(string, inkey) { return esoTools.AES_Decode(string, inkey, {mode: AESMode.ecb}); },
        RSA_encrypt: function() { return ""; },
        RSA_decrypt: function() { return ""; },
        RSA_encryptWithPrivate: function() { return ""; },
        RSA_decryptWithPublic: function() { return ""; }
      };

      var tools = typeof tools === "undefined" ? esoTools : tools;
      tools.md5Encode = tools.md5Encode || esoTools.md5Encode;
      tools.base64Encode = tools.base64Encode || esoTools.base64Encode;
      tools.base64Decode = tools.base64Decode || esoTools.base64Decode;

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

      function __cookieKey(header, key) {
        var name = String(key || "");
        if (!name) return "";
        var parts = String(header || "").split(";");
        for (var i = 0; i < parts.length; i++) {
          var part = parts[i].trim();
          var pos = part.indexOf("=");
          if (pos <= 0) continue;
          if (part.substring(0, pos).trim() === name) {
            return part.substring(pos + 1).trim();
          }
        }
        return "";
      }

      var cookie = {
        getCookie: function(url) {
          return sendMessage("cookie_get", String(url || (typeof baseUrl === "undefined" ? "" : baseUrl)));
        },
        getKey: function(url, key) {
          return __cookieKey(cookie.getCookie(url), key);
        },
        setCookie: function(url, c) {
          return sendMessage("cookie_set", JSON.stringify({url: String(url || (typeof baseUrl === "undefined" ? "" : baseUrl)), cookie: String(c || "")}));
        },
        removeCookie: function(url) {
          return sendMessage("cookie_remove", String(url || (typeof baseUrl === "undefined" ? "" : baseUrl)));
        }
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
                  return __selectFromHtml(html, selector);
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
          source.getVariable = function(key) {
            if (arguments.length > 0 && key != null && String(key) !== "") {
              return java.get("source.variable." + String(key)) || "";
            }
            return source.variable || java.get("source.variable") || "";
          };
          source.setVariable = function(key, value) {
            if (arguments.length > 1) {
              var k = String(key || "");
              var v = value == null ? "" : String(value);
              java.put("source.variable." + k, v);
              return v;
            }
            source.variable = key == null ? "" : String(key);
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
              get: function(k) {
                return java.get("source.login." + String(k || "")) || "";
              }
            };
          };
          source.putLoginHeader = function(k, v) {
            java.put("source.loginHeader." + String(k || ""), v == null ? "" : String(v));
            return v == null ? "" : String(v);
          };
          source.getLoginHeader = function(k) {
            return java.get("source.loginHeader." + String(k || "")) || "";
          };
          source.loginUrl = source.loginUrl || "";
        }
        if (typeof book === 'undefined' || book === null) {
          var book = {};
        }
        book.getVariable = function(key) {
          if (arguments.length > 0 && key != null && String(key) !== "") {
            return java.get("book.variable." + String(key)) || "";
          }
          return book.variable || java.get("book.variable") || "";
        };
        book.setVariable = function(key, value) {
          if (arguments.length > 1) {
            var k = String(key || "");
            var v = value == null ? "" : String(value);
            java.put("book.variable." + k, v);
            return v;
          }
          book.variable = key == null ? "" : String(key);
          java.put("book.variable", book.variable);
          return book.variable;
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
    return _wrapLegadoScript(codeToRun);
  }

  String prepareForTesting(String jsCode) => _prepareCode(jsCode);

  String _wrapLegadoScript(String codeToRun) {
    codeToRun = codeToRun.trim();
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
      }
      final withReturn = _wrapLastExpression(codeToRun, isAsync: true);
      if (withReturn != null) return withReturn;
      final resultMutation = _wrapResultMutationScript(
        codeToRun,
        isAsync: true,
      );
      if (resultMutation != null) return resultMutation;
      if (!codeToRun.startsWith('(async') &&
          !_startsWithDeclaration(codeToRun)) {
        return '(async () => { return ($codeToRun); })()';
      }
    } else {
      if (codeToRun.contains('return ') && !codeToRun.contains('function')) {
        codeToRun = '(function() { $codeToRun })()';
      }
      final withReturn = _wrapLastExpression(codeToRun, isAsync: false);
      if (withReturn != null) return withReturn;
      final resultMutation = _wrapResultMutationScript(
        codeToRun,
        isAsync: false,
      );
      if (resultMutation != null) return resultMutation;
    }
    return codeToRun;
  }

  bool _startsWithDeclaration(String code) {
    final clean = code.trimLeft();
    return clean.startsWith('var ') ||
        clean.startsWith('let ') ||
        clean.startsWith('const ') ||
        clean.startsWith('function ') ||
        clean.startsWith('if ') ||
        clean.startsWith('if(') ||
        clean.startsWith('for ') ||
        clean.startsWith('for(') ||
        clean.startsWith('while ') ||
        clean.startsWith('while(') ||
        clean.startsWith('switch ') ||
        clean.startsWith('try ');
  }

  String? _wrapLastExpression(String code, {required bool isAsync}) {
    final clean = _trimTrailingSemicolons(code.trim());
    if (clean.isEmpty ||
        clean.startsWith('(function') ||
        clean.startsWith('(async') ||
        _hasTopLevelReturn(clean)) {
      return null;
    }

    final split = _splitLastTopLevelStatement(clean);
    if (split == null) return null;
    final prefix = split.$1.trimRight();
    final last = _trimTrailingSemicolons(split.$2.trim());
    if (last.isEmpty || !_looksLikeReturnableExpression(last)) return null;

    final body = prefix.isEmpty ? '' : '$prefix\n';
    final asyncPrefix = isAsync ? 'async ' : '';
    return '(${asyncPrefix}function() { ${body}return ($last); })()';
  }

  String? _wrapResultMutationScript(String code, {required bool isAsync}) {
    final clean = code.trim();
    if (!RegExp(r'\bresult\s*=').hasMatch(clean) || _hasTopLevelReturn(clean)) {
      return null;
    }
    final asyncPrefix = isAsync ? 'async ' : '';
    return '(${asyncPrefix}function() { $clean; return (typeof result === "undefined" ? "" : result); })()';
  }

  String _trimTrailingSemicolons(String value) {
    var end = value.length;
    while (end > 0 && value.codeUnitAt(end - 1) == 0x3b) {
      end--;
    }
    return value.substring(0, end);
  }

  (String, String)? _splitLastTopLevelStatement(String code) {
    var depth = 0;
    var quote = 0;
    var escaped = false;

    for (var i = code.length - 1; i >= 0; i--) {
      final unit = code.codeUnitAt(i);
      if (quote != 0) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == quote) {
          quote = 0;
        }
        continue;
      }

      if (unit == 0x22 || unit == 0x27 || unit == 0x60) {
        quote = unit;
        continue;
      }
      if (unit == 0x29 || unit == 0x5d || unit == 0x7d) {
        depth++;
        continue;
      }
      if (unit == 0x28 || unit == 0x5b || unit == 0x7b) {
        if (depth > 0) depth--;
        continue;
      }
      if (depth == 0 && (unit == 0x3b || unit == 0x0a || unit == 0x0d)) {
        return (code.substring(0, i), code.substring(i + 1));
      }
    }

    if (_looksLikeReturnableExpression(code)) return ('', code);
    return null;
  }

  bool _looksLikeReturnableExpression(String value) {
    final text = value.trim();
    if (text.isEmpty || _startsWithDeclaration(text)) return false;
    if (text.startsWith('//') || text.startsWith('/*')) return false;
    if (RegExp(r'^[A-Za-z_$][\w$]*\s*=').hasMatch(text)) return false;
    return text.startsWith('"') ||
        text.startsWith("'") ||
        text.startsWith('`') ||
        text.startsWith('(') ||
        text.startsWith('[') ||
        text.startsWith('{') ||
        text.startsWith('/') ||
        text.startsWith('java.') ||
        text.startsWith('source.') ||
        text.startsWith('JSON.') ||
        text.startsWith('String(') ||
        text.contains('+') ||
        text.contains('?') ||
        RegExp(r'^[A-Za-z_$][\w$]*(\.[\w$]+|\(|\[)').hasMatch(text);
  }

  bool _hasTopLevelReturn(String code) {
    var depth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < code.length; i++) {
      final unit = code.codeUnitAt(i);
      if (quote != 0) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == quote) {
          quote = 0;
        }
        continue;
      }
      if (unit == 0x22 || unit == 0x27 || unit == 0x60) {
        quote = unit;
        continue;
      }
      if (unit == 0x28 || unit == 0x5b || unit == 0x7b) {
        depth++;
        continue;
      }
      if (unit == 0x29 || unit == 0x5d || unit == 0x7d) {
        if (depth > 0) depth--;
        continue;
      }
      if (depth == 0 &&
          i + 6 <= code.length &&
          code.substring(i, i + 6) == 'return' &&
          _isWordBoundary(code, i - 1) &&
          _isWordBoundary(code, i + 6)) {
        return true;
      }
    }
    return false;
  }

  bool _isWordBoundary(String code, int index) {
    if (index < 0 || index >= code.length) return true;
    final unit = code.codeUnitAt(index);
    return !((unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5a) ||
        (unit >= 0x61 && unit <= 0x7a) ||
        unit == 0x5f ||
        unit == 0x24);
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

  Map<String, dynamic> _aesEncodeToMap(
    String value,
    String key,
    String iv,
    String mode,
  ) {
    try {
      final keyBytes = Uint8List.fromList(utf8.encode(key));
      if (keyBytes.length != 16 &&
          keyBytes.length != 24 &&
          keyBytes.length != 32) {
        return const {'base16': '', 'base64': '', 'bytes': <int>[]};
      }

      final cipher = _aesCipher(
        encrypting: true,
        keyBytes: keyBytes,
        iv: iv,
        mode: mode,
      );
      final encrypted = cipher.process(Uint8List.fromList(utf8.encode(value)));
      return {
        'base16': _bytesToHex(encrypted),
        'base64': base64Encode(encrypted),
        'bytes': encrypted.toList(),
      };
    } catch (_) {
      return const {'base16': '', 'base64': '', 'bytes': <int>[]};
    }
  }

  PaddedBlockCipher _aesCipher({
    required bool encrypting,
    required Uint8List keyBytes,
    required String iv,
    required String mode,
  }) {
    final normalizedMode = mode.toLowerCase();
    final blockCipher = normalizedMode == 'ecb'
        ? ECBBlockCipher(AESEngine())
        : CBCBlockCipher(AESEngine());
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), blockCipher);
    if (normalizedMode == 'ecb') {
      cipher.init(
        encrypting,
        PaddedBlockCipherParameters<KeyParameter, Null>(
          KeyParameter(keyBytes),
          null,
        ),
      );
      return cipher;
    }

    var ivBytes = Uint8List.fromList(utf8.encode(iv));
    if (ivBytes.length != 16) {
      ivBytes = Uint8List(16);
    }
    cipher.init(
      encrypting,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes),
        null,
      ),
    );
    return cipher;
  }

  String _hashHex(String type, String value) {
    final bytes = utf8.encode(value);
    switch (type.toLowerCase()) {
      case 'md5':
        return md5.convert(bytes).toString();
      case 'sha1':
        return sha1.convert(bytes).toString();
      case 'sha224':
        return sha224.convert(bytes).toString();
      case 'sha256':
        return sha256.convert(bytes).toString();
      case 'sha348':
      case 'sha384':
        return sha384.convert(bytes).toString();
      case 'sha512':
        return sha512.convert(bytes).toString();
      case 'ripemd160':
        final digest = RIPEMD160Digest().process(Uint8List.fromList(bytes));
        return _bytesToHex(digest);
      default:
        return '';
    }
  }

  String _encodeByType(String type, String value) {
    switch (type.toLowerCase()) {
      case 'base64':
        return base64Encode(utf8.encode(value));
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
        return gbk
            .encode(value)
            .map(
              (byte) =>
                  '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
            )
            .join();
      case 'utf8':
      case 'utf-8':
        return Uri.encodeComponent(value);
      case 'md5':
        return md5.convert(utf8.encode(value)).toString();
      default:
        return value;
    }
  }

  String _decodeByType(String type, String value) {
    switch (type.toLowerCase()) {
      case 'base64':
        return utf8.decode(base64Decode(value), allowMalformed: true);
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
        return gbk.decode(_percentBytes(value));
      case 'utf8':
      case 'utf-8':
        return Uri.decodeComponent(value);
      default:
        return value;
    }
  }

  Uint8List _percentBytes(String value) {
    final bytes = <int>[];
    for (var i = 0; i < value.length; i++) {
      if (value.codeUnitAt(i) == 0x25 && i + 2 < value.length) {
        final byte = int.tryParse(value.substring(i + 1, i + 3), radix: 16);
        if (byte != null) {
          bytes.add(byte);
          i += 2;
          continue;
        }
      }
      bytes.add(value.codeUnitAt(i));
    }
    return Uint8List.fromList(bytes);
  }

  String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
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
