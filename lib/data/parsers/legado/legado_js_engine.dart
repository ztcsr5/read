import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:quickjs_engine/quickjs_engine.dart';
import 'package:html/dom.dart';

import 'legacy_js_evaluator.dart';
import 'package:html/parser.dart' show parse, parseFragment;

import 'legado_session_store.dart';
import 'query_ttf.dart';

class LegadoJsEngine {
  static final LegadoJsEngine _instance = LegadoJsEngine._internal();

  factory LegadoJsEngine() => _instance;

  JavascriptRuntime? _runtime;
  String? _initErrorMessage; // 一次性修补:把 getJavascriptRuntime 失败原因记下来,让 report 能看到
  final Set<String> _loadedLibraryKeys = <String>{};
  final Set<String> _loadedNodeLibraryKeys = <String>{};
  final List<String> _loadedNodeLibraries = <String>[];
  Future<String> Function(String request)? _currentAjaxHandler;
  Future<Uint8List> Function(String request)? _currentAjaxBytesHandler;
  final Map<String, dynamic> _javaStorage = <String, dynamic>{};
  final Map<String, Document> _jsoupDocuments = {};
  final LinkedHashMap<String, QueryTTF> _queryTtfCache =
      LinkedHashMap<String, QueryTTF>();
  static const int _maxTtfCacheEntries = 16;
  static const int _maxFontBytes = 5 * 1024 * 1024;
  // 一次性修补:JS 内部字体下载(用 java.ajaxBytes 拉远程 .ttf/.otf)15s 太短,
  // 一些老牌书站自定义字体跨域慢,15s 后 fetch reject 上抛 TimeoutException。
  // 提到 25s 与外层 testSource 25s wrapper 一致。
  static const Duration _fontTimeout = Duration(seconds: 25);
  static const String _defaultUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 '
      'Mobile/15E148 Safari/604.1';

  bool? _nodeFallbackAvailableCache;
  String? _nodePathCache;
  File? _nodeScriptFile;

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
            debugPrint('Ajax in JS failed: $e');
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
            final resultList = elements.map(_serializeJsoupElement).toList();
            return jsonEncode(resultList);
          }
        } catch (e) {
          debugPrint('Jsoup select failed: $e');
        }
        return '[]';
      });

      _runtime!.onMessage('jsoup_children_html', (dynamic args) {
        try {
          final fragment = parseFragment(args?.toString() ?? '');
          final resultList = fragment.nodes
              .whereType<Element>()
              .map(_serializeJsoupElement)
              .toList();
          return jsonEncode(resultList);
        } catch (e) {
          debugPrint('Jsoup children failed: $e');
          return '[]';
        }
      });

      _runtime!.onMessage('jsoup_html', (dynamic args) {
        try {
          final doc = _jsoupDocuments[args.toString()];
          return doc?.documentElement?.outerHtml ?? doc?.outerHtml ?? '';
        } catch (_) {
          return '';
        }
      });

      _runtime!.onMessage('jsoup_text', (dynamic args) {
        try {
          final doc = _jsoupDocuments[args.toString()];
          return doc?.documentElement?.text.trim() ??
              doc?.body?.text.trim() ??
              '';
        } catch (_) {
          return '';
        }
      });

      _runtime!.onMessage('jsoup_remove', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final id = data['id'].toString();
          final selector = data['selector'].toString();
          final doc = _jsoupDocuments[id];
          if (doc == null || selector.isEmpty) return false;
          for (final element in doc.querySelectorAll(selector).toList()) {
            element.remove();
          }
          return true;
        } catch (e) {
          debugPrint('Jsoup remove failed: $e');
          return false;
        }
      });

      _runtime!.onMessage('jsoup_before', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final id = data['id'].toString();
          final selector = data['selector'].toString();
          final html = data['html']?.toString() ?? '';
          final doc = _jsoupDocuments[id];
          if (doc == null || selector.isEmpty || html.isEmpty) return false;
          for (final element in doc.querySelectorAll(selector).toList()) {
            final parent = element.parentNode;
            if (parent == null) continue;
            final fragment = parseFragment(html);
            for (final node in fragment.nodes.toList()) {
              parent.insertBefore(node, element);
            }
          }
          return true;
        } catch (e) {
          debugPrint('Jsoup before failed: $e');
          return false;
        }
      });

      _runtime!.onMessage('java_put', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final String key = data['key'].toString();
          final dynamic value = data['value'];
          _javaStorage[key] = value;
          return value;
        } catch (e) {
          debugPrint('java_put failed: $e');
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

      _runtime!.onMessage('java_hmac_hex', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          return _hmac(
            data['algorithm']?.toString() ?? 'HmacSHA1',
            data['key']?.toString() ?? '',
            data['value']?.toString() ?? '',
            base64Output: false,
          );
        } catch (_) {
          return '';
        }
      });

      _runtime!.onMessage('java_hmac_base64', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          return _hmac(
            data['algorithm']?.toString() ?? 'HmacSHA1',
            data['key']?.toString() ?? '',
            data['value']?.toString() ?? '',
            base64Output: true,
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

      _runtime!.onMessage('java_bytes_to_string', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final bytes = base64Decode(data['value']?.toString() ?? '');
          return _decodeBytesByType(
            Uint8List.fromList(bytes),
            data['type']?.toString() ?? 'utf-8',
          );
        } catch (_) {
          return '';
        }
      });

      _runtime!.onMessage('java_cipher_base64_encode', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          return _cipherBase64Encode(
            data['value']?.toString() ?? '',
            data['key']?.toString() ?? '',
            data['iv']?.toString() ?? '',
            data['transformation']?.toString() ?? 'AES/CBC/PKCS5Padding',
          );
        } catch (e) {
          debugPrint('java_cipher_base64_encode failed: $e');
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
          debugPrint('java_aes_base64_encode failed: $e');
          return '{}';
        }
      });

      _runtime!.onMessage('java_rsa_decrypt', (dynamic args) {
        return '';
      });

      _runtime!.onMessage('java_aes_base64_decode', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          return _aesBase64Decode(
            data['value']?.toString() ?? '',
            data['key']?.toString() ?? '',
            data['iv']?.toString() ?? '',
            data['transformation']?.toString() ?? 'AES/CBC/PKCS5Padding',
          );
        } catch (e) {
          debugPrint('java_aes_base64_decode failed: $e');
          return '';
        }
      });

      _runtime!.onMessage('java_aes_base64_decode_bytes', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final decoded = _cipherBase64Decode(
            data['value']?.toString() ?? '',
            data['key']?.toString() ?? '',
            data['iv']?.toString() ?? '',
            data['transformation']?.toString() ?? 'AES/CBC/PKCS5Padding',
          );
          return base64Encode(decoded);
        } catch (e) {
          debugPrint('java_aes_base64_decode_bytes failed: $e');
          return '';
        }
      });

      _runtime!.onMessage('java_cipher_bytes_decode', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final decoded = _cipherDecodeBytes(
            input: Uint8List.fromList(
              base64Decode(data['input']?.toString() ?? ''),
            ),
            keyBytes: Uint8List.fromList(
              base64Decode(data['key']?.toString() ?? ''),
            ),
            ivBytes: Uint8List.fromList(
              base64Decode(data['iv']?.toString() ?? ''),
            ),
            transformation:
                data['transformation']?.toString() ?? 'AES/CBC/PKCS5Padding',
          );
          return base64Encode(decoded);
        } catch (e) {
          debugPrint('java_cipher_bytes_decode failed: $e');
          return '';
        }
      });

      _runtime!.onMessage('java_inflate_bytes', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final bytes = Uint8List.fromList(
            base64Decode(data['value']?.toString() ?? ''),
          );
          return _inflateBytesToString(bytes);
        } catch (e) {
          debugPrint('java_inflate_bytes failed: $e');
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

      _runtime!.onMessage('java_ajax_bytes', (dynamic args) async {
        try {
          final bytes = await _fetchAjaxBytes(args?.toString() ?? '');
          return base64Encode(bytes);
        } catch (e) {
          print('java_ajax_bytes failed: $e');
          return '';
        }
      });

      _runtime!.onMessage('query_ttf_parse', (dynamic args) {
        try {
          final data = jsonDecode(args?.toString() ?? '{}');
          final b64 = data['data']?.toString() ?? '';
          if (b64.isEmpty) return '';
          final bytes = Uint8List.fromList(base64Decode(b64));
          final key = data['key']?.toString().trim();
          final cacheKey = (key == null || key.isEmpty)
              ? sha1.convert(bytes).toString()
              : '$key#${bytes.length}';
          _getOrParseTtf(cacheKey, bytes);
          return cacheKey;
        } catch (e) {
          print('query_ttf_parse failed: $e');
          return '';
        }
      });

      _runtime!.onMessage('query_ttf_glyf_by_unicode', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final ttf = _queryTtfCache[data['h']?.toString() ?? ''];
          if (ttf == null) return '';
          final code = (data['code'] as num?)?.toInt() ?? 0;
          return ttf.getGlyfByUnicode(code) ?? '';
        } catch (e) {
          print('query_ttf_glyf_by_unicode failed: $e');
          return '';
        }
      });

      _runtime!.onMessage('query_ttf_unicode_by_glyf', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final ttf = _queryTtfCache[data['h']?.toString() ?? ''];
          if (ttf == null) return 0;
          return ttf.getUnicodeByGlyf(data['glyf']?.toString() ?? '');
        } catch (e) {
          print('query_ttf_unicode_by_glyf failed: $e');
          return 0;
        }
      });

      _runtime!.onMessage('query_ttf_glyf_id_by_unicode', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final ttf = _queryTtfCache[data['h']?.toString() ?? ''];
          if (ttf == null) return 0;
          final code = (data['code'] as num?)?.toInt() ?? 0;
          return ttf.getGlyfIdByUnicode(code);
        } catch (e) {
          print('query_ttf_glyf_id_by_unicode failed: $e');
          return 0;
        }
      });

      _runtime!.onMessage('query_ttf_is_blank', (dynamic args) {
        try {
          final data = jsonDecode(args.toString());
          final ttf = _queryTtfCache[data['h']?.toString() ?? ''];
          if (ttf == null) return false;
          final code = (data['code'] as num?)?.toInt() ?? 0;
          return ttf.isBlankUnicode(code);
        } catch (_) {
          return false;
        }
      });
    } catch (e) {
      _initErrorMessage = e.toString();
      debugPrint('JS Engine Initialization Error: $e');
    }
  }

  bool get isAvailable => _runtime != null;

  bool get canEvaluate => _runtime != null || _nodeFallbackAvailable;

  bool get isUsingNodeFallback => _runtime == null && _nodeFallbackAvailable;

  /// 一次性修补:返回 QuickJS 初始化失败的异常信息(让 report 能看到根因)。
  String? get initErrorMessage => _initErrorMessage;

  /// 一次性修补:把 @js: / <js>...</js> 包装的 JS 规则字符串剥成纯 JS 代码,便于
  /// LegacyJsEvaluator 直接求值。
  static String _unwrapJsRule(String code) {
    var s = code.trim();
    if (s.startsWith('@js:')) {
      s = s.substring(4).trim();
    } else if (s.startsWith('<js>') && s.endsWith('</js>')) {
      s = s.substring(4, s.length - 5).trim();
    } else if (s.startsWith('<js>')) {
      s = s.substring(4).trim();
    }
    return s;
  }

  Future<Uint8List> _fetchAjaxBytes(String rawRequest) async {
    final handler = _currentAjaxBytesHandler;
    if (handler != null) {
      final bytes = await handler(rawRequest).timeout(_fontTimeout);
      _validateFontBytes(bytes);
      return bytes;
    }

    final data = _decodeAjaxBytesRequest(rawRequest);
    final url = data['url']?.toString() ?? rawRequest;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw ArgumentError('Invalid font url: $url');
    }

    final headers = <String, String>{
      HttpHeaders.userAgentHeader:
          LegadoSessionStore.userAgentFor(uri) ?? _defaultUserAgent,
    };
    final cookie = LegadoSessionStore.cookieHeaderFor(uri);
    if (cookie != null && cookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = cookie;
    }
    final referer = data['referer']?.toString();
    if (referer != null && referer.isNotEmpty) {
      headers[HttpHeaders.refererHeader] = referer;
    }
    final requestHeaders = data['headers'];
    if (requestHeaders is Map) {
      requestHeaders.forEach((key, value) {
        final name = key?.toString() ?? '';
        if (name.isNotEmpty && value != null) {
          headers[name] = value.toString();
        }
      });
    }

    final client = HttpClient()..connectionTimeout = _fontTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_fontTimeout);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(_fontTimeout);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_fontTimeout)) {
        builder.add(chunk);
        if (builder.length > _maxFontBytes) {
          throw StateError('Font response exceeds $_maxFontBytes bytes');
        }
      }
      final bytes = builder.takeBytes();
      _validateFontBytes(bytes);
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _decodeAjaxBytesRequest(String rawRequest) {
    final text = rawRequest.trim();
    if (text.startsWith('{') && text.endsWith('}')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        // Fall through and treat it as a URL.
      }
    }
    return <String, dynamic>{'url': text};
  }

  void _validateFontBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw StateError('Font response is empty');
    }
    if (bytes.length > _maxFontBytes) {
      throw StateError('Font response exceeds $_maxFontBytes bytes');
    }
  }

  QueryTTF _getOrParseTtf(String key, Uint8List fontBytes) {
    final cached = _queryTtfCache.remove(key);
    if (cached != null) {
      _queryTtfCache[key] = cached;
      return cached;
    }
    final ttf = QueryTTF(fontBytes);
    _queryTtfCache[key] = ttf;
    if (_queryTtfCache.length > _maxTtfCacheEntries) {
      _queryTtfCache.remove(_queryTtfCache.keys.first);
    }
    return ttf;
  }

  String _ownText(Element element) {
    final parts = <String>[];
    for (final node in element.nodes) {
      if (node is Text) {
        final text = node.data.trim();
        if (text.isNotEmpty) parts.add(text);
      }
    }
    return parts.join(' ');
  }

  List<String> _directTextNodes(Element element) {
    final parts = <String>[];
    for (final node in element.nodes) {
      if (node is Text) {
        final text = node.data.trim();
        if (text.isNotEmpty) parts.add(text);
      }
    }
    return parts;
  }

  Map<String, dynamic> _serializeJsoupElement(
    Element element, {
    int parentDepth = 6,
  }) {
    final parent = element.parent;
    return {
      'text': element.text.trim(),
      'ownText': _ownText(element),
      'textNodes': _directTextNodes(element),
      'html': element.innerHtml,
      'outerHtml': element.outerHtml,
      'attr': element.attributes,
      'tagName': element.localName,
      'id': element.id,
      'className': element.classes.join(' '),
      if (parent != null && parentDepth > 0)
        'parent': _serializeJsoupElement(parent, parentDepth: parentDepth - 1),
    };
  }

  String getStoredString(String key) {
    final value = _javaStorage[key];
    return value == null ? '' : value.toString();
  }

  void putStoredValue(String key, dynamic value) {
    _javaStorage[key] = value;
  }

  void _initJavaObject() {
    const jsCode = r'''
      var __cache_store = {};
      var __storage = {};
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
        function elementHtml() {
          return String(node.html != null ? node.html : (node.outerHtml || ""));
        }
        function elementOuterHtml() {
          return String(node.outerHtml != null ? node.outerHtml : elementHtml());
        }
        return {
          text: function() { return String(node.text || ""); },
          ownText: function() { return String(node.ownText || node.text || ""); },
          textNodes: function() {
            return __arrayWithToArray((node.textNodes || []).map(function(v) { return String(v || ""); }));
          },
          html: elementHtml,
          outerHtml: elementOuterHtml,
          attr: function(name) {
            return node.attr ? String(node.attr[String(name)] || "") : "";
          },
          hasAttr: function(name) {
            return !!(node.attr && Object.prototype.hasOwnProperty.call(node.attr, String(name)));
          },
          hasClass: function(name) {
            var cls = node.attr ? String(node.attr["class"] || "") : "";
            return cls.split(/\s+/).indexOf(String(name || "")) >= 0;
          },
          className: function() {
            return String(node.className || (node.attr ? node.attr["class"] || "" : ""));
          },
          id: function() {
            return String(node.id || (node.attr ? node.attr.id || "" : ""));
          },
          tagName: function() {
            return String(node.tagName || node.nodeName || "");
          },
          nodeName: function() {
            return String(node.tagName || node.nodeName || "");
          },
          select: function(selector) {
            return __selectFromHtml(elementOuterHtml(), selector);
          },
          selectFirst: function(selector) {
            return this.select(selector).first();
          },
          children: function() {
            return __childrenFromHtml(elementHtml());
          },
          child: function(index) {
            return this.children().get(Number(index || 0));
          },
          parentNode: function() {
            return __wrapJsoupElement(node.parent || {});
          },
          parent: function() {
            return __wrapJsoupElement(node.parent || {});
          },
          toJSON: elementOuterHtml,
          toString: elementOuterHtml
        };
      }

      function __combineSelectors(parentSelector, childSelector) {
        var parent = String(parentSelector || "").trim();
        var child = String(childSelector || "").trim();
        if (!parent) return child;
        if (!child) return parent;
        if (child.charAt(0) === ">") return parent + child;
        return parent + " " + child;
      }

      function __wrapJsoupDocument(docId) {
        return {
          select: function(selector) {
            return __selectFromDoc(docId, selector);
          },
          html: function() {
            return String(sendMessage("jsoup_html", String(docId || "")) || "");
          },
          outerHtml: function() {
            return String(sendMessage("jsoup_html", String(docId || "")) || "");
          },
          text: function() {
            return String(sendMessage("jsoup_text", String(docId || "")) || "");
          },
          body: function() {
            return __selectFromDoc(docId, "body").first();
          },
          selectFirst: function(selector) {
            return __selectFromDoc(docId, selector).first();
          },
          toString: function() {
            return String(sendMessage("jsoup_html", String(docId || "")) || "");
          }
        };
      }

      function __selectFromDoc(docId, selector) {
        var rawResult = sendMessage("jsoup_select", JSON.stringify({
          id: String(docId || ""),
          selector: String(selector || "")
        }));
        var selected = [];
        try {
          selected = JSON.parse(rawResult);
        } catch(e) {}
        return __wrapJsoupNodes(selected, docId, String(selector || ""));
      }

      function __childrenFromHtml(html) {
        var rawResult = sendMessage("jsoup_children_html", String(html || ""));
        var nodes = [];
        try {
          nodes = JSON.parse(rawResult);
        } catch(e) {}
        return __wrapJsoupNodes(nodes);
      }

      function __wrapJsoupNodes(nodes, docId, selector) {
        nodes = Array.isArray(nodes) ? nodes : [];
        var wrapper = nodes.map(function(node) { return __wrapJsoupElement(node); });
        function define(name, value) {
          Object.defineProperty(wrapper, name, {
            value: value,
            enumerable: false,
            configurable: true
          });
        }
        function currentNodes() {
          if (docId && selector) {
            var raw = sendMessage("jsoup_select", JSON.stringify({
              id: String(docId || ""),
              selector: String(selector || "")
            }));
            try {
              var parsed = JSON.parse(raw);
              if (Array.isArray(parsed)) return parsed;
            } catch(e) {}
          }
          return nodes;
        }
        function nodeHtml(node) {
          return String(node && node.html != null ? node.html : (node && node.outerHtml ? node.outerHtml : ""));
        }
        function nodeOuterHtml(node) {
          return String(node && node.outerHtml != null ? node.outerHtml : nodeHtml(node));
        }
        function normalizeIndex(index, length) {
          index = Number(index || 0);
          if (index < 0) index = length + index;
          return index;
        }
        define("text", function() { return currentNodes().map(function(n) { return n.text || ""; }).join("\n"); });
        define("eachText", function() {
          return __arrayWithToArray(currentNodes().map(function(n) { return String(n.text || ""); }));
        });
        define("textNodes", function() {
          var values = [];
          var list = currentNodes();
          for (var i = 0; i < list.length; i++) {
            var textNodes = list[i].textNodes || [];
            for (var j = 0; j < textNodes.length; j++) values.push(String(textNodes[j] || ""));
          }
          return __arrayWithToArray(values);
        });
        define("html", function() { return currentNodes().map(nodeHtml).join("\n"); });
        define("outerHtml", function() { return currentNodes().map(nodeOuterHtml).join("\n"); });
        define("attr", function(name) {
          var list = currentNodes();
          return list.length > 0 && list[0].attr ? String(list[0].attr[String(name)] || "") : "";
        });
        define("hasAttr", function(name) {
          var list = currentNodes();
          return !!(list.length > 0 && list[0].attr && Object.prototype.hasOwnProperty.call(list[0].attr, String(name)));
        });
        define("hasClass", function(name) {
          var list = currentNodes();
          if (!list.length || !list[0].attr) return false;
          return String(list[0].attr["class"] || "").split(/\s+/).indexOf(String(name || "")) >= 0;
        });
        define("className", function() {
          var list = currentNodes();
          if (!list.length) return "";
          return String(list[0].className || (list[0].attr ? list[0].attr["class"] || "" : ""));
        });
        define("id", function() {
          var list = currentNodes();
          if (!list.length) return "";
          return String(list[0].id || (list[0].attr ? list[0].attr.id || "" : ""));
        });
        define("tagName", function() {
          var list = currentNodes();
          return list.length ? String(list[0].tagName || list[0].nodeName || "") : "";
        });
        define("nodeName", function() {
          var list = currentNodes();
          return list.length ? String(list[0].tagName || list[0].nodeName || "") : "";
        });
        define("first", function() {
          var list = currentNodes();
          return list.length ? __wrapJsoupElement(list[0]) : __wrapJsoupElement({});
        });
        define("last", function() {
          var list = currentNodes();
          return list.length ? __wrapJsoupElement(list[list.length - 1]) : __wrapJsoupElement({});
        });
        define("get", function(index) {
          var list = currentNodes();
          index = normalizeIndex(index, list.length);
          return index >= 0 && index < list.length ? __wrapJsoupElement(list[index]) : __wrapJsoupElement({});
        });
        define("eq", function(index) {
          var list = currentNodes();
          index = normalizeIndex(index, list.length);
          return __wrapJsoupNodes(index >= 0 && index < list.length ? [list[index]] : []);
        });
        define("children", function() {
          var merged = [];
          var list = currentNodes();
          for (var i = 0; i < list.length; i++) {
            var raw = sendMessage("jsoup_children_html", nodeHtml(list[i]));
            var children = [];
            try {
              children = JSON.parse(raw);
            } catch(e) {}
            merged = merged.concat(children);
          }
          return __wrapJsoupNodes(merged);
        });
        define("child", function(index) {
          return wrapper.children().get(Number(index || 0));
        });
        define("parentNode", function() {
          var list = currentNodes();
          return list.length ? __wrapJsoupElement(list[0].parent || {}) : __wrapJsoupElement({});
        });
        define("parent", function() {
          return wrapper.parentNode();
        });
        define("size", function() { return currentNodes().length; });
        define("isEmpty", function() { return currentNodes().length === 0; });
        define("select", function(selector) {
          if (docId && selector) {
            return __selectFromDoc(
              docId,
              __combineSelectors(wrapper.selector || "", selector)
            );
          }
          var merged = [];
          var list = currentNodes();
          for (var i = 0; i < list.length; i++) {
            var childDocId = sendMessage("jsoup_parse", nodeOuterHtml(list[i]));
            var raw = sendMessage("jsoup_select", JSON.stringify({id: childDocId, selector: String(selector || "")}));
            try {
              var parsed = JSON.parse(raw);
              if (Array.isArray(parsed)) merged = merged.concat(parsed);
            } catch(e) {}
          }
          return __wrapJsoupNodes(merged);
        });
        define("selectFirst", function(selector) {
          return wrapper.select(selector).first();
        });
        define("remove", function() {
          if (docId && selector) {
            sendMessage("jsoup_remove", JSON.stringify({
              id: String(docId || ""),
              selector: String(selector || "")
            }));
          }
          return wrapper;
        });
        define("before", function(html) {
          if (docId && selector) {
            sendMessage("jsoup_before", JSON.stringify({
              id: String(docId || ""),
              selector: String(selector || ""),
              html: String(html || "")
            }));
          }
          return wrapper;
        });
        define("toArray", function() { return currentNodes().map(function(node) { return __wrapJsoupElement(node); }); });
        define("toJSON", function() { return wrapper.outerHtml(); });
        define("toString", function() { return wrapper.outerHtml(); });
        define("selector", String(selector || ""));
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

      function __encodedTextToBytes(encoded) {
        var text = String(encoded || "");
        var bytes = [];
        for (var i = 0; i < text.length; i++) {
          if (text.charAt(i) === "%" && i + 2 < text.length) {
            var hex = text.substring(i + 1, i + 3);
            if (/^[0-9a-fA-F]{2}$/.test(hex)) {
              bytes.push(parseInt(hex, 16));
              i += 2;
              continue;
            }
          }
          bytes.push(text.charCodeAt(i) & 0xff);
        }
        return __arrayWithToArray(bytes);
      }

      function __bytesFromString(value, charset) {
        var type = String(charset || "utf-8");
        var encoded = sendMessage("java_encode_type", JSON.stringify({
          type: type,
          value: String(value == null ? "" : value)
        }));
        return __encodedTextToBytes(encoded);
      }

      function __bytesToBinaryString(bytes) {
        if (bytes == null) return "";
        if (typeof bytes === "string") return bytes;
        var list = Array.isArray(bytes) ? bytes : [];
        var out = "";
        for (var i = 0; i < list.length; i++) {
          out += String.fromCharCode(Number(list[i] || 0) & 0xff);
        }
        return out;
      }

      function __bytesToBase64(bytes) {
        return btoa(__bytesToBinaryString(__javaBytes(bytes)));
      }

      function __base64ToBytes(str) {
        var raw = atob(String(str || ""));
        var bytes = [];
        for (var i = 0; i < raw.length; i++) bytes.push(raw.charCodeAt(i) & 0xff);
        return __arrayWithToArray(bytes);
      }

      function __javaBytes(value) {
        if (value == null) return __arrayWithToArray([]);
        if (Array.isArray(value)) {
          return __arrayWithToArray(value.map(function(v) { return Number(v || 0) & 0xff; }));
        }
        if (value.__javaBytes) return __javaBytes(value.__javaBytes);
        if (value.getBytes && typeof value.getBytes === "function") return __javaBytes(value.getBytes());
        if (typeof value === "string") return __bytesFromString(value, "utf-8");
        return __bytesFromString(String(value), "utf-8");
      }

      function __bytesToString(bytes, charset) {
        return sendMessage("java_bytes_to_string", JSON.stringify({
          value: __bytesToBase64(bytes),
          type: String(charset || "utf-8")
        }));
      }

      function __javaString(value) {
        var text = Array.isArray(value) || (value && value.__javaBytes)
          ? __bytesToString(value, "utf-8")
          : String(value == null ? "" : value);
        return {
          __javaString: text,
          getBytes: function(charset) { return __bytesFromString(text, charset || "utf-8"); },
          toString: function() { return text; },
          toJSON: function() { return text; },
          valueOf: function() { return text; }
        };
      }

      function __responseFromText(text) {
        var bodyText = String(text == null ? "" : text);
        var body = {
          string: function() { return bodyText; },
          text: function() { return bodyText; },
          bytes: function() { return __bytesFromString(bodyText, "utf-8"); },
          toString: function() { return bodyText; }
        };
        return {
          body: function() { return body; },
          string: function() { return bodyText; },
          text: function() { return bodyText; },
          json: function() { return JSON.parse(bodyText); },
          toString: function() { return bodyText; }
        };
      }

      function __jsoupResponseFromText(text) {
        var bodyText = String(text == null ? "" : text);
        var htmlText = /<html[\s>]/i.test(bodyText)
          ? bodyText
          : "<html><head></head><body>" + bodyText + "</body></html>";
        return {
          body: function() { return bodyText; },
          text: function() { return bodyText; },
          html: function() { return htmlText; },
          select: function(selector) { return __selectFromHtml(htmlText, selector); },
          toString: function() { return htmlText; }
        };
      }

      function __jsoupConnect(urlStr) {
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
          requestBody: function(body) { config.body = body == null ? "" : String(body); return chain; },
          data: function(body) { config.body = body == null ? "" : String(body); return chain; },
          timeout: function() { return chain; },
          ignoreContentType: function() { return chain; },
          followRedirects: function() { return chain; },
          userAgent: function(value) { if (value != null) config.headers["User-Agent"] = String(value); return chain; },
          referrer: function(value) { if (value != null) config.headers.Referer = String(value); return chain; },
          get: function() { config.method = "GET"; return __jsoupResponseFromText(java.ajax(u + "," + JSON.stringify(config))); },
          post: function() { config.method = "POST"; return __jsoupResponseFromText(java.ajax(u + "," + JSON.stringify(config))); },
          execute: function() {
            return __jsoupResponseFromText(java.ajax(u + "," + JSON.stringify(config)));
          },
          toString: function() { return u; }
        };
        return chain;
      }

      function __selectFromHtml(html, selector) {
        var docId = sendMessage("jsoup_parse", String(html || ""));
        var selectorText = String(selector || "");
        var rawResult = sendMessage("jsoup_select", JSON.stringify({id: docId, selector: selectorText}));
        var nodes = [];
        try {
          nodes = JSON.parse(rawResult);
        } catch(e) {}
        return __wrapJsoupNodes(nodes, docId, selectorText);
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
          lower === "textnodes" ||
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
        var lowerAttr = attr.toLowerCase();
        if (lowerAttr === "text" || lowerAttr === "owntext") return String(node.text || "");
        if (lowerAttr === "textnodes") {
          return (node.textNodes || []).map(function(v) { return String(v || ""); }).join("\n");
        }
        if (lowerAttr === "innerhtml") return String(node.html || "");
        if (lowerAttr === "html" || lowerAttr === "outerhtml" || lowerAttr === "all") {
          return String(node.outerHtml || node.html || "");
        }
        if (lowerAttr === "href" || lowerAttr === "src") return node.attr ? String(node.attr[lowerAttr] || "") : "";
        if (lowerAttr.indexOf("attr.") === 0) attr = attr.substring(5);
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
        postForm: function(urlStr, body) {
          return java.ajax(String(urlStr || "") + "," + JSON.stringify({
            method: "POST",
            body: body || "",
            headers: {"Content-Type": "application/x-www-form-urlencoded"}
          }));
        },
        fetch: function(urlStr, options) {
          var config = options || {};
          return __responseFromText(java.ajax(String(urlStr || "") + "," + JSON.stringify(config)));
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
        base64Decoder: function(str) {
          return java.base64Decode(str);
        },
        base64DecodeToString: function(str) {
          return __base64ToUtf8(str);
        },
        base64DecodeToByteArray: function(str) {
          return __base64ToBytes(str);
        },
        encodeURI: function(str, charset) {
          if (charset) {
            return sendMessage("java_encode_type", JSON.stringify({type: charset, value: String(str || "")}));
          }
          return encodeURI(String(str || ""));
        },
        encodeURIComponent: function(str, charset) {
          if (charset) {
            return sendMessage("java_encode_type", JSON.stringify({type: charset, value: String(str || "")}));
          }
          return encodeURIComponent(String(str || ""));
        },
        decodeURI: function(str) {
          return decodeURI(String(str || ""));
        },
        decodeURIComponent: function(str) {
          return decodeURIComponent(String(str || ""));
        },
        uriEncode: function(str) {
          return java.encodeURI(str);
        },
        uriDecode: function(str) {
          return java.decodeURI(str);
        },
        htmlFormat: function(str) {
          return String(str || "").replace(/<\/?(?:br|p|div|span)[^>]*>/gi, '\n').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
        },
        md5Encode: function(string) {
          return sendMessage("java_md5", String(string || ""));
        },
        sha1Encode: function(str) { return sendMessage("java_hash", JSON.stringify({type: "sha1", value: String(str || "")})); },
        sha256Encode: function(str) { return sendMessage("java_hash", JSON.stringify({type: "sha256", value: String(str || "")})); },
        sha512Encode: function(str) { return sendMessage("java_hash", JSON.stringify({type: "sha512", value: String(str || "")})); },
        rsaDecrypt: function(value, key) {
          return sendMessage("java_rsa_decrypt", JSON.stringify({value: String(value || ""), key: String(key || "")}));
        },
        digestHex: function(value, algorithm) {
          return sendMessage("java_hash", JSON.stringify({
            type: String(algorithm || "sha256"),
            value: String(value || "")
          }));
        },
        HMacHex: function(value, algorithm, key) {
          return sendMessage("java_hmac_hex", JSON.stringify({
            value: String(value || ""),
            algorithm: String(algorithm || "HmacSHA1"),
            key: String(key || "")
          }));
        },
        HMacBase64: function(value, algorithm, key) {
          return sendMessage("java_hmac_base64", JSON.stringify({
            value: String(value || ""),
            algorithm: String(algorithm || "HmacSHA1"),
            key: String(key || "")
          }));
        },
        aesEncodeToBase64String: function(value, key, iv, transformation) {
          var actualIv = iv;
          var actualTransformation = transformation;
          var third = String(iv || "");
          if (third.indexOf("/") >= 0 || /^(AES|DES|DESede|TripleDES)/i.test(third)) {
            actualTransformation = iv;
            actualIv = transformation;
          }
          return sendMessage("java_cipher_base64_encode", JSON.stringify({
            value: String(value || ""),
            key: String(key || ""),
            iv: String(actualIv || ""),
            transformation: String(actualTransformation || "AES/CBC/PKCS5Padding")
          }));
        },
        desEncodeToBase64String: function(value, key, iv, transformation) {
          var actualIv = iv;
          var actualTransformation = transformation;
          var third = String(iv || "");
          if (third.indexOf("/") >= 0 || /^(AES|DES|DESede|TripleDES)/i.test(third)) {
            actualTransformation = iv;
            actualIv = transformation;
          }
          return sendMessage("java_cipher_base64_encode", JSON.stringify({
            value: String(value || ""),
            key: String(key || ""),
            iv: String(actualIv || ""),
            transformation: String(actualTransformation || "DES/CBC/PKCS5Padding")
          }));
        },
        tripleDESEncodeBase64Str: function(value, key, mode, padding, iv) {
          var transformation = "DESede/" + String(mode || "CBC") + "/" + String(padding || "PKCS5Padding");
          return sendMessage("java_cipher_base64_encode", JSON.stringify({
            value: String(value || ""),
            key: String(key || ""),
            iv: String(iv || ""),
            transformation: transformation
          }));
        },
        aesBase64DecodeToString: function(value, key, iv, transformation) {
          var actualIv = iv;
          var actualTransformation = transformation;
          var third = String(iv || "");
          if (third.indexOf("/") >= 0 || /^(AES|DES|DESede|TripleDES)/i.test(third)) {
            actualTransformation = iv;
            actualIv = transformation;
          }
          return sendMessage("java_aes_base64_decode", JSON.stringify({
            value: String(value || ""),
            key: String(key || ""),
            iv: String(actualIv || ""),
            transformation: String(actualTransformation || "AES/CBC/PKCS5Padding")
          }));
        },
        aesDecodeToString: function(value, key, iv, transformation) {
          return java.aesBase64DecodeToString(value, key, iv, transformation);
        },
        aesBase64DecodeToByteArray: function(value, key, iv, transformation) {
          var actualIv = iv;
          var actualTransformation = transformation;
          var third = String(iv || "");
          if (third.indexOf("/") >= 0 || /^(AES|DES|DESede|TripleDES)/i.test(third)) {
            actualTransformation = iv;
            actualIv = transformation;
          }
          var raw = sendMessage("java_aes_base64_decode_bytes", JSON.stringify({
            value: String(value || ""),
            key: String(key || ""),
            iv: String(actualIv || ""),
            transformation: String(actualTransformation || "AES/CBC/PKCS5Padding")
          }));
          return __base64ToBytes(raw);
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
        queryTTF: function(str, opts) {
          if (str == null) return null;
          var s = String(str);
          var b64 = "";
          var key = "";
          if (/^https?:/i.test(s)) {
            key = s;
            b64 = String(sendMessage("java_ajax_bytes", JSON.stringify({
              url: s,
              headers: opts && opts.headers ? opts.headers : {},
              referer: opts && opts.referer ? String(opts.referer) : ""
            })) || "");
          } else if (s.indexOf("data:") === 0) {
            var ci = s.indexOf("base64,");
            b64 = ci >= 0 ? s.substring(ci + 7) : "";
            key = "data:" + String(b64.length);
          } else {
            b64 = s;
            key = "base64:" + String(b64.length);
          }
          if (!b64) return null;
          var handle = String(sendMessage("query_ttf_parse", JSON.stringify({
            key: key,
            data: b64
          })) || "");
          if (!handle) return null;
          return {
            getGlyfByUnicode: function(code) {
              return String(sendMessage("query_ttf_glyf_by_unicode", JSON.stringify({h: handle, code: Number(code) || 0})) || "");
            },
            getUnicodeByGlyf: function(glyf) {
              return Number(sendMessage("query_ttf_unicode_by_glyf", JSON.stringify({h: handle, glyf: String(glyf || "")})) || 0);
            },
            getGlyfIdByUnicode: function(code) {
              return Number(sendMessage("query_ttf_glyf_id_by_unicode", JSON.stringify({h: handle, code: Number(code) || 0})) || 0);
            },
            isBlankUnicode: function(code) {
              var r = sendMessage("query_ttf_is_blank", JSON.stringify({h: handle, code: Number(code) || 0}));
              return r === true || r === "true";
            }
          };
        },
        t2s: function(str) { return String(str || ""); },
        s2t: function(str) { return String(str || ""); },
        toNumChapter: function(str) { return String(str || ""); },
        log: function(msg) {
          console.log(String(msg || ""));
          return msg;
        },
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
        },
        putCache: function(key, value) {
          return cache.put(key, value);
        },
        getCache: function(key) {
          return cache.get(key);
        },
        putField: function(key, value) {
          __storage[String(key)] = value;
          return value;
        },
        getField: function(key) {
          return __storage[String(key)] || "";
        },
        putVariable: function(key, value) {
          return java.put(key, value);
        },
        getVariable: function(key) {
          return java.get(key);
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

      var __javaBase64 = {
        NO_WRAP: 2,
        DEFAULT: 0,
        getDecoder: function() {
          return {
            decode: function(value) {
              return __base64ToBytes(value);
            }
          };
        },
        getEncoder: function() {
          return {
            encodeToString: function(bytes) {
              return __bytesToBase64(bytes);
            }
          };
        },
        encode: function(bytes, flags) {
          return __bytesFromString(__bytesToBase64(bytes), "utf-8");
        },
        encodeToString: function(bytes, flags) {
          return __bytesToBase64(bytes);
        },
        decode: function(value, flags) {
          if (Array.isArray(value) || (value && value.__javaBytes)) {
            value = __bytesToString(value, "utf-8");
          }
          return __base64ToBytes(value);
        }
      };

      var __javaArrays = {
        copyOfRange: function(bytes, start, end) {
          return __arrayWithToArray(__javaBytes(bytes).slice(Number(start || 0), Number(end || 0)));
        },
        asList: function() {
          return __arrayWithToArray(Array.prototype.slice.call(arguments));
        }
      };

      function __ArrayList() {
        var list = [];
        list.add = function(value) {
          list.push(value);
          return true;
        };
        list.addAll = function(values) {
          if (values == null) return false;
          var arr = Array.isArray(values) ? values : Array.prototype.slice.call(values);
          for (var i = 0; i < arr.length; i++) list.push(arr[i]);
          return arr.length > 0;
        };
        list.get = function(index) {
          return list[Number(index || 0)];
        };
        list.size = function() {
          return list.length;
        };
        list.isEmpty = function() {
          return list.length === 0;
        };
        list.toArray = function() {
          return list.slice();
        };
        return list;
      }

      var __JavaInteger = {
        parseInt: function(value, radix) {
          var parsed = parseInt(String(value || "0"), radix == null ? 10 : Number(radix));
          return isNaN(parsed) ? 0 : parsed;
        },
        valueOf: function(value, radix) {
          return __JavaInteger.parseInt(value, radix);
        },
        toString: function(value) {
          return String(value == null ? 0 : value);
        }
      };

      var __JavaLong = {
        parseLong: function(value, radix) {
          var parsed = parseInt(String(value || "0"), radix == null ? 10 : Number(radix));
          return isNaN(parsed) ? 0 : parsed;
        },
        valueOf: function(value, radix) {
          return __JavaLong.parseLong(value, radix);
        },
        toString: function(value) {
          return String(value == null ? 0 : value);
        }
      };

      var __JavaURLEncoder = {
        encode: function(value, charset) {
          return encodeURIComponent(String(value == null ? "" : value));
        }
      };

      var __JavaURLDecoder = {
        decode: function(value, charset) {
          try {
            return decodeURIComponent(String(value == null ? "" : value).replace(/\+/g, "%20"));
          } catch(e) {
            return String(value == null ? "" : value);
          }
        }
      };

      function __SecretKeySpec(bytes, algorithm) {
        return {
          __keyBytes: __javaBytes(bytes),
          algorithm: String(algorithm || "")
        };
      }

      function __IvParameterSpec(bytes) {
        return {
          __ivBytes: __javaBytes(bytes)
        };
      }

      var __Mac = {
        getInstance: function(algorithm) {
          var mac = {
            __algorithm: String(algorithm || "HmacSHA1"),
            __keyBytes: [],
            init: function(keySpec) {
              mac.__keyBytes = __javaBytes(keySpec && keySpec.__keyBytes ? keySpec.__keyBytes : keySpec);
              return mac;
            },
            doFinal: function(bytes) {
              var raw = sendMessage("java_hmac_base64", JSON.stringify({
                value: __bytesToString(__javaBytes(bytes), "utf-8"),
                algorithm: mac.__algorithm,
                key: __bytesToString(mac.__keyBytes, "utf-8")
              }));
              return __base64ToBytes(raw);
            }
          };
          return mac;
        }
      };

      var __Cipher = {
        DECRYPT_MODE: 2,
        ENCRYPT_MODE: 1,
        getInstance: function(transformation) {
          var cipher = {
            __transformation: String(transformation || "AES/CBC/PKCS5Padding"),
            __mode: 2,
            __keyBytes: [],
            __ivBytes: [],
            init: function(mode, keySpec, ivSpec) {
              cipher.__mode = Number(mode || 2);
              cipher.__keyBytes = __javaBytes(keySpec && keySpec.__keyBytes ? keySpec.__keyBytes : keySpec);
              cipher.__ivBytes = ivSpec && ivSpec.__ivBytes ? __javaBytes(ivSpec.__ivBytes) : [];
              return cipher;
            },
            doFinal: function(bytes) {
              if (cipher.__mode !== 2) return __arrayWithToArray([]);
              var raw = sendMessage("java_cipher_bytes_decode", JSON.stringify({
                input: __bytesToBase64(bytes),
                key: __bytesToBase64(cipher.__keyBytes),
                iv: __bytesToBase64(cipher.__ivBytes),
                transformation: cipher.__transformation
              }));
              return __base64ToBytes(raw);
            }
          };
          return cipher;
        }
      };

      function __ByteArrayInputStream(bytes) {
        return {
          __javaBytes: __javaBytes(bytes)
        };
      }

      function __inflateBytes(bytes) {
        var text = sendMessage("java_inflate_bytes", JSON.stringify({
          value: __bytesToBase64(bytes)
        }));
        return __bytesFromString(text, "utf-8");
      }

      function __InflaterInputStream(input) {
        var bytes = __inflateBytes(input && input.__javaBytes ? input.__javaBytes : input);
        var index = 0;
        return {
          read: function() {
            if (index >= bytes.length) return -1;
            return Number(bytes[index++]) & 0xff;
          },
          close: function() {}
        };
      }

      function __ByteArrayOutputStream(size) {
        var bytes = [];
        return {
          write: function(value) {
            bytes.push(Number(value || 0) & 0xff);
          },
          close: function() {},
          toByteArray: function() {
            return __arrayWithToArray(bytes.slice());
          },
          toString: function(charset) {
            return __bytesToString(bytes, charset || "utf-8");
          }
        };
      }

      function __markJavaClass(value, simpleName) {
        try {
          Object.defineProperty(value, "__javaSimpleName", {
            value: simpleName,
            enumerable: false,
            configurable: true
          });
        } catch(e) {}
        return value;
      }

      function __JavaImporter() {
        var importer = {
          importPackage: function() {
            for (var i = 0; i < arguments.length; i++) {
              var pkg = arguments[i];
              if (pkg && typeof pkg === "object") {
                for (var key in pkg) {
                  if (/^[A-Za-z_$][\w$]*$/.test(key)) importer[key] = pkg[key];
                }
              }
            }
            return importer;
          },
          importClass: function(classRef) {
            var name = classRef && classRef.__javaSimpleName ? String(classRef.__javaSimpleName) : "";
            if (name) importer[name] = classRef;
            return classRef;
          },
          String: function(value) { return __javaString(value); },
          Integer: __JavaInteger,
          Long: __JavaLong,
          Base64: __javaBase64,
          Arrays: __javaArrays,
          ArrayList: __ArrayList,
          URLEncoder: __JavaURLEncoder,
          URLDecoder: __JavaURLDecoder,
          Mac: __Mac,
          Cipher: __Cipher,
          SecretKeySpec: __SecretKeySpec,
          IvParameterSpec: __IvParameterSpec,
          ByteArrayInputStream: __ByteArrayInputStream,
          ByteArrayOutputStream: __ByteArrayOutputStream,
          InflaterInputStream: __InflaterInputStream
        };
        return importer;
      }

      var JavaImporter = __JavaImporter;

      var Packages = {
        java: {
          lang: {
            String: function(value) { return __javaString(value); },
            Integer: __JavaInteger,
            Long: __JavaLong
          },
          net: {
            URLEncoder: __JavaURLEncoder,
            URLDecoder: __JavaURLDecoder
          },
          io: {
            ByteArrayInputStream: __ByteArrayInputStream,
            ByteArrayOutputStream: __ByteArrayOutputStream
          },
          security: {
            interfaces: {},
            spec: {}
          },
          util: {
            UUID: {
              randomUUID: function() { return java.randomUUID(); }
            },
            Arrays: __javaArrays,
            Base64: __javaBase64,
            ArrayList: __ArrayList,
            zip: {
              InflaterInputStream: __InflaterInputStream
            }
          }
        },
        javax: {
          crypto: {
            Mac: __Mac,
            Cipher: __Cipher,
            spec: {
              SecretKeySpec: __SecretKeySpec,
              IvParameterSpec: __IvParameterSpec
            }
          }
        },
        android: {
          os: {
            Build: {
              MODEL: "Android",
              MANUFACTURER: "Android",
              BRAND: "Android"
            }
          },
          text: {
            TextUtils: {
              isEmpty: function(value) { return value == null || String(value).length === 0; }
            }
          },
          util: {
            Base64: __javaBase64
          }
        }
      };
      Packages.util = Packages.java.util;
      java.lang = Packages.java.lang;
      java.io = Packages.java.io;
      java.util = Packages.java.util;
      java.net = Packages.java.net;
      var Base64 = __javaBase64;
      var Integer = __JavaInteger;
      var Long = __JavaLong;
      var URLEncoder = __JavaURLEncoder;
      var URLDecoder = __JavaURLDecoder;

      var android = {
        os: Packages.android.os,
        text: Packages.android.text,
        util: {
          Base64: __javaBase64
        }
      };

      var CryptoJS = {
        MD5: function(value) {
          return { toString: function() { return java.md5Encode(value); } };
        },
        enc: {
          Utf8: {
            parse: function(value) { return __cryptoWord(String(value || ""), "utf8"); },
            stringify: function(value) { return __cryptoValueToString(value); }
          },
          Base64: {
            stringify: function(value) { return java.base64Encode(__cryptoValueToString(value)); },
            parse: function(value) { return __cryptoWord(java.base64Decode(value), "base64"); }
          },
          Hex: {
            parse: function(value) { return __cryptoWord(__hexToString(value), "hex"); },
            stringify: function(value) { return __stringToHex(__cryptoValueToString(value)); }
          },
          Latin1: {
            parse: function(value) { return __cryptoWord(String(value || ""), "latin1"); },
            stringify: function(value) { return __cryptoValueToString(value); }
          }
        },
        mode: {
          CBC: "CBC",
          ECB: "ECB"
        },
        pad: {
          Pkcs7: "Pkcs7",
          PKCS7: "Pkcs7",
          ZeroPadding: "ZeroPadding",
          NoPadding: "NoPadding"
        }
      };
      CryptoJS.AES = __cryptoCipher("AES");
      CryptoJS.DES = __cryptoCipher("DES");

      function __cryptoWord(value, encoding) {
        var text = String(value == null ? "" : value);
        return {
          __cryptoValue: text,
          __cryptoEncoding: encoding || "utf8",
          toString: function(encoder) {
            if (encoder === CryptoJS.enc.Base64) return java.base64Encode(text);
            if (encoder === CryptoJS.enc.Hex) return __stringToHex(text);
            return text;
          },
          valueOf: function() { return text; }
        };
      }

      function __cryptoValueToString(value) {
        if (value == null) return "";
        if (value.__cryptoValue != null) return String(value.__cryptoValue);
        if (value.ciphertext != null) return __cryptoValueToString(value.ciphertext);
        if (typeof value.toString === "function" && value.toString !== Object.prototype.toString) {
          return String(value.toString());
        }
        return String(value);
      }

      function __cryptoModeName(options) {
        if (!options || !options.mode) return "CBC";
        var mode = String(options.mode);
        if (mode.indexOf("ECB") >= 0 || mode.toLowerCase() === "ecb") return "ECB";
        return "CBC";
      }

      function __cryptoPaddingName(options) {
        if (!options || !options.padding) return "PKCS5Padding";
        var padding = String(options.padding);
        if (padding.toLowerCase().indexOf("zero") >= 0) return "ZeroPadding";
        if (padding.toLowerCase().indexOf("no") >= 0) return "NoPadding";
        return "PKCS5Padding";
      }

      function __cryptoCipher(algorithm) {
        return {
          decrypt: function(cipherText, key, options) {
            options = options || {};
            var input = __cryptoValueToString(cipherText);
            var keyText = __cryptoValueToString(key);
            var ivText = options.iv == null ? "" : __cryptoValueToString(options.iv);
            var transformation = algorithm + "/" + __cryptoModeName(options) + "/" + __cryptoPaddingName(options);
            var decoded = java.aesBase64DecodeToString(input, keyText, transformation, ivText);
            return __cryptoWord(decoded, "utf8");
          },
          encrypt: function(plainText, key, options) {
            return __cryptoWord("", "base64");
          }
        };
      }

      function __hexToString(value) {
        var hex = String(value || "").replace(/\s+/g, "");
        var out = "";
        for (var i = 0; i + 1 < hex.length; i += 2) {
          var byte = parseInt(hex.substr(i, 2), 16);
          if (!isNaN(byte)) out += String.fromCharCode(byte);
        }
        return out;
      }

      function __stringToHex(value) {
        var text = String(value || "");
        var out = "";
        for (var i = 0; i < text.length; i++) {
          var h = (text.charCodeAt(i) & 0xff).toString(16);
          out += h.length === 1 ? "0" + h : h;
        }
        return out;
      }

      var org = {
        jsoup: {
          Jsoup: {
            parse: function(html) {
              var docId = sendMessage("jsoup_parse", String(html || ""));
              return __wrapJsoupDocument(docId);
            },
            connect: function(urlStr) {
              return __jsoupConnect(urlStr);
            }
          }
        }
      };

      __markJavaClass(org.jsoup.Jsoup, "Jsoup");
      __markJavaClass(__ArrayList, "ArrayList");
      __markJavaClass(__Mac, "Mac");
      __markJavaClass(__Cipher, "Cipher");
      __markJavaClass(__SecretKeySpec, "SecretKeySpec");
      __markJavaClass(__IvParameterSpec, "IvParameterSpec");
      __markJavaClass(__ByteArrayInputStream, "ByteArrayInputStream");
      __markJavaClass(__ByteArrayOutputStream, "ByteArrayOutputStream");
      __markJavaClass(__InflaterInputStream, "InflaterInputStream");

      function importClass(classRef) {
        var name = classRef && classRef.__javaSimpleName ? String(classRef.__javaSimpleName) : "";
        if (!name && classRef === org.jsoup.Jsoup) name = "Jsoup";
        if (name) globalThis[name] = classRef;
        return classRef;
      }

      function importPackage(packageRef) {
        if (packageRef && typeof packageRef === "object") {
          for (var key in packageRef) {
            if (/^[A-Za-z_$][\w$]*$/.test(key)) globalThis[key] = packageRef[key];
          }
        }
        return packageRef;
      }

      java.md5 = function(string) {
        return this.md5Encode(string);
      };
    ''';

    if (_runtime == null) return;
    try {
      final result = _runtime!.evaluate(jsCode);
      if (result.isError) {
        debugPrint('JS Engine Initialization Error: ${result.stringResult}');
      }
    } catch (e) {
      debugPrint('JS Engine init failed: $e');
    }
  }

  String evaluate(String jsCode, {Map<String, dynamic>? variables}) {
    if (_runtime == null) {
      // 一次性修补:iOS release 模式下 _runtime 为 null 且 Node 兜底不可用,导致
      // 所有 @js/<js> 规则失败。先尝试 Dart 版 LegacyJsEvaluator(支持 80% 常见
      // JS 表达式:Date.now/encodeURI/MD5/SHA/JSON/变量拼接/CryptoJS/java 桥),失败再走 Node。
      try {
        // user 传入的 variables 已经是完整结构(result/baseUrl/source/book/chapter/key/page/...),
        // 直接转发即可,不要重建(重建会丢 source.bookSourceUrl/getKey/getVariable 等)。
        final result = LegacyJsEvaluator.evaluate(
          _unwrapJsRule(jsCode),
          variables: variables,
        );
        return result?.toString() ?? '';
      } catch (e) {
        return _evaluateWithNodeFallbackSync(jsCode, variables: variables);
      }
    }
    _injectVariables(variables);

    try {
      final result = _runtime!.evaluate(_prepareCode(jsCode));
      if (result.isError) throw Exception(result.stringResult);
      return _stringifyResult(result);
    } catch (e) {
      debugPrint('JS Eval failed: $e');
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
    Future<Uint8List> Function(String request)? ajaxBytes,
    int maxRequests = 12,
  }) async {
    if (_runtime == null) {
      // 一次性修补:iOS release 模式下 _runtime 为 null 且 Node 兜底不可用,
      // toc/content/explore 等需要 ajax 的 JS 规则完全失败。先用 LegacyJsEvaluator
      // 跑一遍(支持简单 java.ajax("...") 字面量参数调用,先 pre-fetch 再注入)。
      // 失败再走 Node 兜底(Node 在 iOS 上不存在,会返回空)。
      try {
        // JS 整体加 8s 超时,避免某个 timeoutException 源把 worker 挂死
        final result = await _evaluateWithLegacyAsync(
          _unwrapJsRule(jsCode),
          variables: variables,
          ajax: ajax,
        ).timeout(const Duration(seconds: 8));
        if (result.isNotEmpty) return result;
      } on TimeoutException {
        debugPrint('Legacy async JS eval timed out after 8s');
      } catch (e) {
        debugPrint('Legacy async JS eval failed: $e');
      }
      return _evaluateWithNodeFallback(
        jsCode,
        variables: variables,
        libraries: libraries,
      );
    }

    _currentAjaxHandler = ajax;
    _currentAjaxBytesHandler = ajaxBytes;
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
      debugPrint('JS Eval with AJAX failed: $e');
      rethrow;
    } finally {
      _currentAjaxHandler = null;
      _currentAjaxBytesHandler = null;
      _jsoupDocuments.clear();
    }
  }

  void loadLibraries(Iterable<String> libraries) {
    if (_runtime == null) {
      for (final library in libraries) {
        final code = library.trim();
        if (code.isEmpty) continue;
        final key = code.hashCode.toString();
        if (_loadedNodeLibraryKeys.add(key)) {
          _loadedNodeLibraries.add(code);
        }
      }
      return;
    }
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
        debugPrint('JS library load failed: $e');
      }
    }
  }

  Map<String, dynamic> _normalizedVariables(Map<String, dynamic>? variables) {
    final vars = <String, dynamic>{};
    if (variables != null) {
      vars.addAll(variables);
    }

    // Alias data flow
    if (vars.containsKey('result') && !vars.containsKey('input')) {
      vars['input'] = vars['result'];
    }
    if (vars.containsKey('result') && !vars.containsKey('src')) {
      vars['src'] = vars['result'];
    }
    if (vars.containsKey('input') && !vars.containsKey('result')) {
      vars['result'] = vars['input'];
    }
    if (vars.containsKey('input') && !vars.containsKey('src')) {
      vars['src'] = vars['input'];
    }
    if (vars.containsKey('src') && !vars.containsKey('result')) {
      vars['result'] = vars['src'];
    }
    if (vars.containsKey('src') && !vars.containsKey('input')) {
      vars['input'] = vars['src'];
    }

    // Alias URL
    if (vars.containsKey('baseUrl') && !vars.containsKey('base_url')) {
      vars['base_url'] = vars['baseUrl'];
    }
    if (vars.containsKey('baseUrl') && !vars.containsKey('url')) {
      vars['url'] = vars['baseUrl'];
    }
    if (vars.containsKey('base_url') && !vars.containsKey('baseUrl')) {
      vars['baseUrl'] = vars['base_url'];
    }
    if (vars.containsKey('base_url') && !vars.containsKey('url')) {
      vars['url'] = vars['base_url'];
    }
    if (vars.containsKey('url') && !vars.containsKey('baseUrl')) {
      vars['baseUrl'] = vars['url'];
    }
    if (vars.containsKey('url') && !vars.containsKey('base_url')) {
      vars['base_url'] = vars['url'];
    }

    return vars;
  }

  bool get _nodeFallbackAvailable {
    if (kIsWeb) return false;
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return false;
    }
    if (Platform.environment['LEGADO_DISABLE_NODE_JS_FALLBACK'] == '1') {
      return false;
    }
    final cached = _nodeFallbackAvailableCache;
    if (cached != null) return cached;
    final path = _resolveNodePath();
    final available = path != null && File(path).existsSync();
    _nodeFallbackAvailableCache = available;
    return available;
  }

  String? _resolveNodePath() {
    final cached = _nodePathCache;
    if (cached != null) return cached;

    final envPath = Platform.environment['LEGADO_NODE_PATH'];
    if (envPath != null && envPath.trim().isNotEmpty) {
      final file = File(envPath.trim());
      if (file.existsSync()) {
        _nodePathCache = file.path;
        return _nodePathCache;
      }
    }

    final candidates = <String>[if (Platform.isWindows) r'D:\Node\node.exe'];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) {
        _nodePathCache = file.path;
        return _nodePathCache;
      }
    }

    try {
      final result = Process.runSync(
        Platform.isWindows ? 'where.exe' : 'which',
        ['node'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode == 0) {
        final first = result.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .firstWhere((line) => line.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty && File(first).existsSync()) {
          _nodePathCache = first;
          return _nodePathCache;
        }
      }
    } catch (_) {
      // Node is optional. QuickJS remains the production runtime.
    }
    return null;
  }

  String _evaluateWithNodeFallbackSync(
    String jsCode, {
    Map<String, dynamic>? variables,
  }) {
    if (!_nodeFallbackAvailable) return '';
    final payloadFile = _writeNodePayloadFile(
      _nodePayload(jsCode, variables: variables, libraries: const []),
    );
    try {
      final result = Process.runSync(
        _resolveNodePath()!,
        [_ensureNodeScriptPath(), payloadFile.path],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return _decodeNodeResult(result.exitCode, result.stdout, result.stderr);
    } catch (e) {
      throw Exception('JS鎵ц寮傚父: $e');
    } finally {
      try {
        if (payloadFile.existsSync()) payloadFile.deleteSync();
        final parent = payloadFile.parent;
        if (parent.existsSync()) parent.deleteSync();
      } catch (_) {}
    }
  }

  Future<String> _evaluateWithNodeFallback(
    String jsCode, {
    Map<String, dynamic>? variables,
    Iterable<String> libraries = const [],
  }) async {
    if (!_nodeFallbackAvailable) return '';
    final payloadFile = _writeNodePayloadFile(
      _nodePayload(jsCode, variables: variables, libraries: libraries),
    );
    try {
      final result = await Process.run(
        _resolveNodePath()!,
        [_ensureNodeScriptPath(), payloadFile.path],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return _decodeNodeResult(result.exitCode, result.stdout, result.stderr);
    } catch (e) {
      throw Exception('JS执行异常: $e');
    } finally {
      try {
        if (payloadFile.existsSync()) await payloadFile.delete();
        final parent = payloadFile.parent;
        if (await parent.exists()) await parent.delete();
      } catch (_) {}
    }
  }

  Map<String, dynamic> _nodePayload(
    String jsCode, {
    Map<String, dynamic>? variables,
    Iterable<String> libraries = const [],
  }) {
    return {
      'code': _prepareCode(jsCode),
      'variables': _normalizedVariables(variables),
      'storage': _javaStorage,
      'libraries': [..._loadedNodeLibraries, ...libraries],
    };
  }

  String _decodeNodeResult(int exitCode, dynamic stdout, dynamic stderr) {
    final output = stdout?.toString().trim() ?? '';
    if (exitCode != 0) {
      final err = stderr?.toString().trim() ?? '';
      throw Exception(err.isEmpty ? 'Node exited with code $exitCode' : err);
    }
    if (output.isEmpty) return '';
    final decoded = jsonDecode(output);
    if (decoded is! Map || decoded['ok'] != true) {
      throw Exception(decoded.toString());
    }
    final storage = decoded['storage'];
    if (storage is Map) {
      _javaStorage
        ..clear()
        ..addAll(storage.map((key, value) => MapEntry(key.toString(), value)));
    }
    return decoded['result']?.toString() ?? '';
  }

  String _ensureNodeScriptPath() {
    final existing = _nodeScriptFile;
    if (existing != null && existing.existsSync()) return existing.path;
    final dir = Directory.systemTemp.createTempSync('legado_node_js_');
    final file = File('${dir.path}${Platform.pathSeparator}runner.cjs');
    file.writeAsStringSync(_nodeFallbackScript, encoding: utf8);
    _nodeScriptFile = file;
    return file.path;
  }

  File _writeNodePayloadFile(Map<String, dynamic> payload) {
    final dir = Directory.systemTemp.createTempSync('legado_node_payload_');
    final file = File('${dir.path}${Platform.pathSeparator}payload.json');
    file.writeAsStringSync(jsonEncode(payload), encoding: utf8);
    return file;
  }

  /// 一次性修补:LegacyJsEvaluator 异步兜底。
  ///
  /// iOS release 模式下 _runtime == null,Node 也不存在。
  /// toc/content/explore 等需要 ajax 的 JS 规则直接走 _evaluateWithNodeFallback 返回空。
  ///
  /// 这个方法做两件事:
  /// 1) 预扫描 code,把 `java.ajax("...")` / `java.ajax('...')` 这种
  ///    参数是单一字面量字符串的简单调用先 await 发出去,把结果用占位符注入;
  /// 2) 跑同步 LegacyJsEvaluator.evaluate,占位符作为 String 变量参与求值。
  ///
  /// 覆盖范围(2026-06 基线):
  /// - 宜搜 ruleToc: java.ajax 不出现,直接用 result 变量 → 能修
  /// - 新龙 ruleToc/chapterName/chapterUrl: 用 src.match(),不含 ajax → 能修
  /// - 起点限免 ruleToc: java.ajax("https://...") 字面量 → 能修
  /// - 米读 searchUrl: java.ajax(url) 变量参数 → 不能修(走 Node 兜底)
  /// - 飞卢 bookUrl: java.get('tsign').split(',') → split 不支持,不能修
  /// - 繁星 bookUrl: eval(source.bookSourceComment) → eval 不支持,不能修
  Future<String> _evaluateWithLegacyAsync(
    String code, {
    Map<String, dynamic>? variables,
    required Future<String> Function(String request) ajax,
  }) async {
    var processed = code;
    final results = <String>[];

    // 1) 找所有 java.ajax("...") / java.ajax('...') 调用,先发 ajax
    final pattern = RegExp(
      r'''java\.ajax\(\s*(["'])([^"'\\]*(?:\\.[^"'\\]*)*)\1\s*\)''',
    );
    final matches = pattern.allMatches(processed).toList();
    // 从后往前替换避免偏移
    for (var i = matches.length - 1; i >= 0; i--) {
      final m = matches[i];
      final url = m.group(2) ?? '';
      String response;
      try {
        // 构造 legado ajax 协议:{url,method,headers,body} 序列化
        final req = jsonEncode({
          'url': url,
          'method': 'GET',
        });
        response = await ajax(req);
      } catch (e) {
        response = '';
      }
      results.insert(0, response);
      final placeholder = '__LEGACY_AJAX_RESULT_${i}__';
      processed =
          processed.substring(0, m.start) + placeholder + processed.substring(m.end);
    }

    // 2) 注入 ajax 结果到 variables
    final vars = <String, dynamic>{...?variables};
    for (var i = 0; i < results.length; i++) {
      vars['__LEGACY_AJAX_RESULT_${i}__'] = results[i];
    }

    // 3) 同步 LegacyJsEvaluator 求值
    final result = LegacyJsEvaluator.evaluate(processed, variables: vars);
    return result?.toString() ?? '';
  }

  static const String _nodeFallbackScript = r'''
const fs = require("fs");
const crypto = require("crypto");
const { TextDecoder } = require("util");

const payloadPath = process.argv[2];
const payload = JSON.parse(fs.readFileSync(payloadPath || 0, "utf8") || "{}");
const __storage = Object.assign({}, payload.storage || {});
const __vars = Object.assign({}, payload.variables || {});
const __libraries = Array.isArray(payload.libraries) ? payload.libraries : [];
const __ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

console.log = function() {};
console.warn = function() {};
console.error = function() {};

Object.assign(globalThis, __vars);
try {
  if (globalThis.result != null && globalThis.$ == null) {
    globalThis.$ = typeof globalThis.result === "string"
      ? JSON.parse(globalThis.result)
      : globalThis.result;
  }
} catch (_) {}

function __str(value) {
  return value == null ? "" : String(value);
}

function __looseLegadoJs(code) {
  return __str(code)
    .replace(/<\/?js>/gi, "")
    .replace(/\b(let|const)\s+/g, "var ");
}

function __hash(algorithm, value) {
  return crypto.createHash(String(algorithm || "md5").toLowerCase().replace(/^sha-/, "sha")).update(__str(value)).digest("hex");
}

function __hmacHex(value, algorithm, key) {
  let alg = String(algorithm || "HmacMD5").toLowerCase().replace(/^hmac-?/, "");
  if (alg === "sha") alg = "sha1";
  return crypto.createHmac(alg, __str(key)).update(__str(value)).digest("hex");
}

function __jsonPathValue(sourceValue, path) {
  let source = sourceValue;
  try {
    if (typeof source === "string") source = JSON.parse(source);
  } catch (_) {
    return "";
  }
  let p = String(path || "").trim();
  if (!p || p === "$") return typeof source === "object" ? JSON.stringify(source) : __str(source);
  const deep = /^\$\.\.?(.+)$/.exec(p);
  if (p.indexOf("..") >= 0) {
    const key = p.split("..").pop().replace(/^\./, "").replace(/\[.*$/, "");
    const found = [];
    (function walk(node) {
      if (node == null) return;
      if (Array.isArray(node)) {
        node.forEach(walk);
      } else if (typeof node === "object") {
        if (Object.prototype.hasOwnProperty.call(node, key)) found.push(node[key]);
        Object.keys(node).forEach(k => walk(node[k]));
      }
    })(source);
    const value = found.length ? found[0] : "";
    return typeof value === "object" ? JSON.stringify(value) : __str(value);
  }
  p = p.replace(/^\$\.?/, "").replace(/\[(\d+)\]/g, ".$1");
  let current = source;
  for (const part of p.split(".")) {
    if (!part) continue;
    if (Array.isArray(current)) {
      const index = Number(part);
      if (!Number.isInteger(index) || index < 0 || index >= current.length) return "";
      current = current[index];
    } else if (current && Object.prototype.hasOwnProperty.call(current, part)) {
      current = current[part];
    } else {
      return "";
    }
  }
  return typeof current === "object" ? JSON.stringify(current) : __str(current);
}

function __resolveUrl(rawUrl) {
  const text = __str(rawUrl).trim();
  if (!text) return text;
  try {
    return new URL(text).toString();
  } catch (_) {
    const base = __str(globalThis.baseUrl || globalThis.base_url || globalThis.url || (globalThis.source && globalThis.source.bookSourceUrl) || "");
    try {
      return base ? new URL(text, base).toString() : text;
    } catch (_) {
      return text;
    }
  }
}

function __splitRequest(request) {
  const text = __str(request);
  let url = text;
  let config = {};
  const comma = text.indexOf(",");
  if (comma > 0) {
    const tail = text.slice(comma + 1).trim();
    if (tail.startsWith("{")) {
      try {
        config = JSON.parse(tail);
        url = text.slice(0, comma);
      } catch (_) {}
    }
  }
  return { url: __resolveUrl(url), config };
}

async function __fetchText(rawUrl, config) {
  const url = __resolveUrl(rawUrl);
  if (url.startsWith("data:")) {
    const commaIdx = url.indexOf(",");
    if (commaIdx >= 0) {
      const meta = url.slice(0, commaIdx);
      const rawData = decodeURIComponent(url.slice(commaIdx + 1));
      const isBase64 = meta.toLowerCase().indexOf(";base64") >= 0;
      if (isBase64) {
        return Buffer.from(rawData, "base64").toString("utf8");
      } else {
        return rawData;
      }
    }
  }
  config = config || {};
  const headers = Object.assign({ "User-Agent": __ua }, config.headers || {});
  if (globalThis.cookieHeader && !headers.Cookie && !headers.cookie) {
    headers.Cookie = __str(globalThis.cookieHeader);
  }
  const method = __str(config.method || "GET").toUpperCase() || "GET";
  const controller = new AbortController();
  // 一次性修补:JS 内部 __fetchText 的 abort 定时器默认 15s 太短,
  // 真慢站(频控重试 + 编码探测 + 章节抓取)经常要 18-22s 才返回。
  // 提到 25s,与外层 source_batch_check_page.dart 的 25s wrapper 对齐,
  // 否则内层先抛 TimeoutException 后,外层 25s 永远等不到。
  const timer = setTimeout(() => controller.abort(), Number(config.timeout || config.timeoutMs || 25000));
  try {
    const init = { method, headers, signal: controller.signal };
    if (method !== "GET" && method !== "HEAD" && config.body != null) {
      init.body = typeof config.body === "string" ? config.body : JSON.stringify(config.body);
    }
    const response = await fetch(url, init);
    const buffer = Buffer.from(await response.arrayBuffer());
    const contentType = response.headers.get("content-type") || "";
    const charsetMatch = /charset\s*=\s*([^;\s]+)/i.exec(contentType);
    const charset = charsetMatch ? charsetMatch[1].toLowerCase() : "utf-8";
    try {
      return new TextDecoder(charset).decode(buffer);
    } catch (_) {
      return buffer.toString("utf8");
    }
  } finally {
    clearTimeout(timer);
  }
}

async function __ajax(request) {
  const parsed = __splitRequest(request);
  return __fetchText(parsed.url, parsed.config);
}

function __responseProxy(url, config) {
  let cached;
  return {
    body: async function() {
      if (cached === undefined) cached = await __fetchText(url, config || {});
      return cached;
    },
    text: async function() { return this.body(); },
    string: async function() { return this.body(); },
    json: async function() { return JSON.parse(await this.body()); },
    code: function() { return 200; },
    statusCode: function() { return 200; },
    headers: function() { return {}; },
    toString: function() { return cached == null ? "" : String(cached); }
  };
}

function __base64Encode(value) {
  return Buffer.from(__str(value), "utf8").toString("base64");
}

function __base64Decode(value) {
  return Buffer.from(__str(value), "base64").toString("utf8");
}

function __hexDecode(value) {
  const text = __str(value).trim();
  if (text.startsWith("data:")) {
    const parts = text.split(",");
    if (parts.length >= 3 && parts[1].toLowerCase() === "base64") {
      return __base64Decode(parts[2]);
    }
  }
  const hex = text.replace(/\s+/g, "");
  if (!hex || hex.length % 2 || !/^[0-9a-f]+$/i.test(hex)) return text;
  return Buffer.from(hex, "hex").toString("utf8");
}

function __encodeGBK(str) {
  const map = {
    "\u6597": "%B6%B7",
    "\u7834": "%C6%C6",
    "\u82cd": "%B2%D4",
    "\u7a79": "%C7%E5",
    "\u4e2d": "%D6%D0",
    "\u51e1": "%B7%B2",
    "\u4eba": "%C8%CB"
  };
  let result = "";
  for (let i = 0; i < str.length; i++) {
    const char = str[i];
    if (map[char]) {
      result += map[char];
    } else {
      result += encodeURIComponent(char);
    }
  }
  return result;
}

function __desCompatibleKey(raw) {
  const key = Buffer.from(raw);
  if (key.length === 24) return key;
  if (key.length === 16) return Buffer.concat([key, key.subarray(0, 8)]);
  if (key.length === 8) return Buffer.concat([key, key, key]);
  return Buffer.alloc(24);
}

function __cipherBase64Encode(value, key, iv, transformation) {
  const upper = __str(transformation || "AES/CBC/PKCS5Padding").toUpperCase();
  const isDes = upper.indexOf("DES") >= 0;
  const mode = upper.indexOf("/ECB/") >= 0 ? "ecb" : "cbc";
  let keyBytes = Buffer.from(__str(key), "utf8");
  let algorithm = "";
  let blockSize = 16;
  if (isDes) {
    keyBytes = __desCompatibleKey(keyBytes);
    algorithm = mode === "ecb" ? "des-ede3-ecb" : "des-ede3-cbc";
    blockSize = 8;
  } else {
    const bits = keyBytes.length * 8;
    if (![128, 192, 256].includes(bits)) return "";
    algorithm = "aes-" + bits + "-" + mode;
  }
  let ivBytes = null;
  if (mode !== "ecb") {
    ivBytes = Buffer.from(__str(iv), "utf8");
    if (ivBytes.length !== blockSize) ivBytes = Buffer.alloc(blockSize);
  }
  try {
    const cipher = crypto.createCipheriv(algorithm, keyBytes, ivBytes);
    return Buffer.concat([
      cipher.update(Buffer.from(__str(value), "utf8")),
      cipher.final()
    ]).toString("base64");
  } catch (_) {
    return "";
  }
}

function __normalizeTransformation(third, fourth, fallback) {
  const t = __str(third);
  if (t.indexOf("/") >= 0 || /^(AES|DES|DESede|TripleDES)/i.test(t)) {
    return { transformation: t || fallback, iv: fourth };
  }
  return { transformation: fourth || fallback, iv: third };
}

const java = {
  put: function(key, value) {
    const k = __str(key);
    if (k.startsWith("http://") || k.startsWith("https://")) {
      return __responseProxy(k, { method: "PUT", body: value == null ? "" : __str(value) });
    }
    __storage[k] = value;
    return value == null ? "" : value;
  },
  get: function(key, headers) {
    const k = __str(key);
    if (k.startsWith("http://") || k.startsWith("https://")) {
      return __responseProxy(k, { method: "GET", headers: headers || {} });
    }
    const value = __storage[k];
    return value == null ? "" : value;
  },
  ajax: __ajax,
  post: function(url, body, headers) {
    return __responseProxy(url, { method: "POST", body: body == null ? "" : __str(body), headers: headers || {} });
  },
  fetch: function(url, options) {
    return __responseProxy(url, options || {});
  },
  connect: function(url) {
    const config = { method: "GET", headers: {}, body: "" };
    const chain = {
      header: function(k, v) { if (k != null) config.headers[__str(k)] = __str(v); return chain; },
      headers: function(value) {
        if (typeof value === "string") {
          try { value = JSON.parse(value); } catch (_) { value = {}; }
        }
        Object.assign(config.headers, value || {});
        return chain;
      },
      cookie: function(value) { if (value != null) config.headers.Cookie = __str(value); return chain; },
      cookies: function(value) { if (value != null) config.headers.Cookie = __str(value); return chain; },
      timeout: function(value) { if (value != null) config.timeoutMs = Number(value); return chain; },
      ignoreContentType: function() { return chain; },
      followRedirects: function() { return chain; },
      get: function() { config.method = "GET"; return chain; },
      post: function(body) { config.method = "POST"; config.body = body == null ? "" : __str(body); return chain; },
      data: function(body) { config.body = body == null ? "" : __str(body); return chain; },
      requestBody: function(body) { config.body = body == null ? "" : __str(body); return chain; },
      raw: function() { return chain; },
      request: function() { return chain; },
      body: async function() { return __fetchText(url, config); },
      execute: async function() { return chain.body(); },
      url: function() { return __resolveUrl(url); },
      toString: function() { return __resolveUrl(url); }
    };
    return chain;
  },
  getString: function(path, sourceValue) {
    if (arguments.length > 1) {
      const value = __jsonPathValue(sourceValue, path);
      return value === "" ? __str(sourceValue) : value;
    }
    const stored = java.get(path);
    if (stored !== "") return __str(stored);
    if (__str(path).startsWith("$") && globalThis.result != null) {
      return __jsonPathValue(globalThis.result, path);
    }
    return "";
  },
  getInt: function(path, def) { const n = parseInt(java.getString(path, def == null ? "0" : def), 10); return Number.isNaN(n) ? Number(def || 0) : n; },
  getLong: function(path, def) { return java.getInt(path, def); },
  getDouble: function(path, def) { const n = parseFloat(java.getString(path, def == null ? "0" : def)); return Number.isNaN(n) ? Number(def || 0) : n; },
  getStringList: function(path) {
    const value = java.getString(path, "[]");
    try { const parsed = JSON.parse(value); return Array.isArray(parsed) ? parsed : []; } catch (_) { return value ? __str(value).split(",") : []; }
  },
  getElement: function(path) { return java.getString(path); },
  getElements: function() { return []; },
  setContent: function(value) { globalThis.result = value == null ? "" : __str(value); return globalThis.result; },
  md5Encode: function(value) { return __hash("md5", value); },
  md5: function(value) { return __hash("md5", value); },
  digestHex: function(value, algorithm) { return __hash(algorithm || "sha256", value); },
  HMacHex: function(value, algorithm, key) { return __hmacHex(value, algorithm, key); },
  HMacBase64: function(value, algorithm, key) {
    let alg = __str(algorithm || "HmacSHA1").toLowerCase().replace(/^hmac-?/, "");
    return crypto.createHmac(alg, __str(key)).update(__str(value)).digest("base64");
  },
  aesEncodeToBase64String: function(value, key, iv, transformation) {
    const normalized = __normalizeTransformation(iv, transformation, "AES/CBC/PKCS5Padding");
    return __cipherBase64Encode(value, key, normalized.iv, normalized.transformation);
  },
  desEncodeToBase64String: function(value, key, iv, transformation) {
    const normalized = __normalizeTransformation(iv, transformation, "DES/CBC/PKCS5Padding");
    return __cipherBase64Encode(value, key, normalized.iv, normalized.transformation);
  },
  tripleDESEncodeBase64Str: function(value, key, mode, padding, iv) {
    const transformation = "DESede/" + __str(mode || "CBC") + "/" + __str(padding || "PKCS5Padding");
    return __cipherBase64Encode(value, key, iv || "", transformation);
  },
  cipherEncodeToBase64String: function(value, key, iv, transformation) {
    const normalized = __normalizeTransformation(iv, transformation, "AES/CBC/PKCS5Padding");
    return __cipherBase64Encode(value, key, normalized.iv, normalized.transformation);
  },
  base64Encode: __base64Encode,
  base64Decode: __base64Decode,
  base64DecodeToString: __base64Decode,
  hexDecodeToString: __hexDecode,
  encodeURI: function(value, charset) {
    if (charset && (charset.toLowerCase() === "gbk" || charset.toLowerCase() === "gb2312")) {
      return __encodeGBK(__str(value));
    }
    return encodeURI(__str(value));
  },
  encodeURIComponent: function(value, charset) {
    if (charset && (charset.toLowerCase() === "gbk" || charset.toLowerCase() === "gb2312")) {
      return __encodeGBK(__str(value));
    }
    return encodeURIComponent(__str(value));
  },
  decodeURI: function(value) { return decodeURI(__str(value)); },
  decodeURIComponent: function(value) { return decodeURIComponent(__str(value)); },
  randomUUID: function() { return crypto.randomUUID(); },
  uuid: function() { return crypto.randomUUID(); },
  currentTimeMillis: function() { return Date.now(); },
  now: function() { return Date.now(); },
  timeFormat: function(timestamp) { return new Date(Number(timestamp || Date.now())).toISOString().replace("T", " ").substring(0, 19); },
  timeFormatUTC: function(timestamp) { return new Date(Number(timestamp || Date.now())).toISOString().replace("T", " ").substring(0, 19); },
  t2s: function(value) { return __str(value); },
  s2t: function(value) { return __str(value); },
  toNumChapter: function(value) { return __str(value); },
  getCookie: function() { return __str(globalThis.cookieHeader || ""); },
  getWebViewUA: function() { return __ua; },
  startBrowser: function() { return ""; },
  startBrowserAwait: function() { return ""; },
  webView: function() { return ""; },
  log: function() { return ""; },
  toast: function() { return ""; },
  longToast: function() { return ""; }
};

const cookie = {
  getCookie: function() { return __str(globalThis.cookieHeader || ""); },
  getKey: function(url, key) {
    const name = __str(key);
    return __str(globalThis.cookieHeader || "").split(";").map(v => v.trim()).reduce((found, part) => {
      if (found) return found;
      const pos = part.indexOf("=");
      return pos > 0 && part.slice(0, pos).trim() === name ? part.slice(pos + 1).trim() : "";
    }, "");
  },
  setCookie: function(value) { globalThis.cookieHeader = __str(value); return globalThis.cookieHeader; },
  removeCookie: function() { globalThis.cookieHeader = ""; return true; }
};

function __installSourceAndBook() {
  if (globalThis.source == null || typeof globalThis.source !== "object") globalThis.source = {};
  source.getKey = function() { return source.key || source.bookSourceUrl || source.bookSourceUrlName || ""; };
  source.getVariable = function(key) {
    if (arguments.length > 0 && key != null && __str(key) !== "") return java.get("source.variable." + __str(key));
    return source.variable || java.get("source.variable") || "";
  };
  source.setVariable = function(key, value) {
    if (arguments.length > 1) {
      java.put("source.variable." + __str(key), value == null ? "" : __str(value));
      return value == null ? "" : __str(value);
    }
    source.variable = key == null ? "" : __str(key);
    java.put("source.variable", source.variable);
    return source.variable;
  };
  source.getVariableMap = function() {
    let parsed = {};
    try { parsed = JSON.parse(source.getVariable() || "{}"); } catch (_) {}
    return { get: function(k) { const value = parsed[__str(k)]; return value == null ? "" : value; } };
  };
  source.getLoginInfoMap = function() { return { get: function(k) { return java.get("source.login." + __str(k)); } }; };
  source.putLoginHeader = function(k, v) { return java.put("source.loginHeader." + __str(k || ""), v == null ? "" : __str(v)); };
  source.getLoginHeader = function(k) { return java.get("source.loginHeader." + __str(k || "")); };
  if (globalThis.book == null || typeof globalThis.book !== "object") globalThis.book = {};
  book.getVariable = function(key) {
    if (arguments.length > 0 && key != null && __str(key) !== "") return java.get("book.variable." + __str(key));
    return book.variable || java.get("book.variable") || "";
  };
  book.setVariable = function(key, value) {
    if (arguments.length > 1) return java.put("book.variable." + __str(key), value == null ? "" : __str(value));
    book.variable = key == null ? "" : __str(key);
    java.put("book.variable", book.variable);
    return book.variable;
  };
}

globalThis.java = java;
globalThis.cookie = cookie;
if (!String.prototype.getBytes) {
  Object.defineProperty(String.prototype, "getBytes", {
    value: function() { return Array.from(Buffer.from(String(this), "utf8")); },
    enumerable: false
  });
}
function __nodeBytes(value) {
  if (Buffer.isBuffer(value)) return value;
  if (Array.isArray(value)) return Buffer.from(value.map(v => Number(v) & 0xff));
  if (value && value.__keyBytes) return __nodeBytes(value.__keyBytes);
  return Buffer.from(__str(value), "utf8");
}
function __nodeSecretKeySpec(bytes, algorithm) {
  return { __keyBytes: __nodeBytes(bytes), algorithm: __str(algorithm) };
}
const __nodeMac = {
  getInstance: function(algorithm) {
    const state = { algorithm: __str(algorithm || "HmacSHA1"), key: Buffer.alloc(0) };
    return {
      init: function(keySpec) { state.key = __nodeBytes(keySpec && keySpec.__keyBytes ? keySpec.__keyBytes : keySpec); },
      doFinal: function(bytes) {
        const alg = state.algorithm.toLowerCase().replace(/^hmac-?/, "");
        return Array.from(crypto.createHmac(alg, state.key).update(__nodeBytes(bytes)).digest());
      }
    };
  }
};
const __nodeBase64 = {
  encodeToString: function(v) { return Buffer.from(__nodeBytes(v)).toString("base64"); },
  decode: function(v) { return Array.from(Buffer.from(__str(v), "base64")); }
};
globalThis.Packages = globalThis.Packages || {
  java: {
    lang: {
      String: function(v) { return new String(__str(v)); },
      Thread: { sleep: function() {} }
    },
    io: {},
    security: { interfaces: {}, spec: {} },
    util: {
      UUID: { randomUUID: function() { return crypto.randomUUID(); } },
      Base64: __nodeBase64
    }
  },
  javax: {
    crypto: {
      Mac: __nodeMac,
      spec: { SecretKeySpec: __nodeSecretKeySpec }
    }
  },
  android: {
    os: { Build: { MODEL: "Android", MANUFACTURER: "Android", BRAND: "Android" } },
    text: { TextUtils: { isEmpty: function(value) { return value == null || __str(value).length === 0; } } },
    util: { Base64: __nodeBase64 }
  }
};
globalThis.Packages.util = globalThis.Packages.java.util;
globalThis.java.lang = globalThis.Packages.java.lang;
globalThis.java.util = globalThis.Packages.java.util;
globalThis.JavaImporter = function() {
  return {
    importPackage: function() {},
    importClass: function() {},
    Mac: __nodeMac,
    SecretKeySpec: __nodeSecretKeySpec,
    String: globalThis.Packages.java.lang.String
  };
};
globalThis.importClass = function(value) { return value; };
globalThis.importPackage = function(value) { return value; };
globalThis.esoTools = { md5Encode: java.md5Encode, base64Encode: java.base64Encode, base64Decode: java.base64Decode };
__installSourceAndBook();

async function __stringifyResult(value) {
  if (value && typeof value.then === "function") value = await value;
  if (value === undefined && globalThis.result !== undefined) value = globalThis.result;
  if (value && typeof value.body === "function") value = await value.body();
  if (value == null) return "";
  if (typeof value === "string") return value;
  if (Buffer.isBuffer(value)) return value.toString("utf8");
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

(async function main() {
  for (const library of __libraries) {
    if (!__str(library).trim()) continue;
    (0, eval)(__looseLegadoJs(library));
  }
  const value = await (0, eval)(__looseLegadoJs(payload.code || ""));
  const result = await __stringifyResult(value);
  process.stdout.write(JSON.stringify({ ok: true, result, storage: __storage }));
})().catch(error => {
  process.stderr.write(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
''';

  void _injectVariables(Map<String, dynamic>? variables) {
    if (_runtime == null) return;
    final vars = _normalizedVariables(variables);

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
      debugPrint('JS variables injection failed: $e');
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
    codeToRun = codeToRun.replaceAllMapped(
      RegExp(r'@get:\{([^}]+)\}', caseSensitive: false),
      (match) => getStoredString(match.group(1)?.trim() ?? ''),
    );

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
      final clean = codeToRun.trim();
      if (clean.startsWith('(function(') ||
          clean.startsWith('(()=>') ||
          clean.startsWith('(() =>')) {
        return clean;
      }
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

  // ignore: unused_element
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

  // ignore: unused_element
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

  String _aesBase64Decode(
    String value,
    String key,
    String iv,
    String transformation,
  ) {
    final decoded = _cipherBase64Decode(value, key, iv, transformation);
    if (decoded.isEmpty) return '';
    return utf8.decode(decoded, allowMalformed: true);
  }

  Uint8List _cipherBase64Decode(
    String value,
    String key,
    String iv,
    String transformation,
  ) {
    try {
      final encrypted = base64Decode(value);
      return _cipherDecodeBytes(
        input: Uint8List.fromList(encrypted),
        keyBytes: Uint8List.fromList(utf8.encode(key)),
        ivBytes: Uint8List.fromList(utf8.encode(iv)),
        transformation: transformation,
      );
    } catch (_) {
      return Uint8List(0);
    }
  }

  String _cipherBase64Encode(
    String value,
    String key,
    String iv,
    String transformation,
  ) {
    try {
      final encoded = _cipherProcessBytes(
        input: Uint8List.fromList(utf8.encode(value)),
        keyBytes: Uint8List.fromList(utf8.encode(key)),
        ivBytes: Uint8List.fromList(utf8.encode(iv)),
        transformation: transformation,
        encrypting: true,
      );
      return base64Encode(encoded);
    } catch (_) {
      return '';
    }
  }

  Uint8List _cipherDecodeBytes({
    required Uint8List input,
    required Uint8List keyBytes,
    required Uint8List ivBytes,
    required String transformation,
  }) {
    return _cipherProcessBytes(
      input: input,
      keyBytes: keyBytes,
      ivBytes: ivBytes,
      transformation: transformation,
      encrypting: false,
    );
  }

  Uint8List _cipherProcessBytes({
    required Uint8List input,
    required Uint8List keyBytes,
    required Uint8List ivBytes,
    required String transformation,
    required bool encrypting,
  }) {
    try {
      return _cipherProcessBytesInternal(
        input: input,
        keyBytes: keyBytes,
        ivBytes: ivBytes,
        transformation: transformation,
        encrypting: encrypting,
      );
    } catch (_) {
      return Uint8List(0);
    }
  }

  Uint8List cipherProcessBytesForTesting({
    required Uint8List input,
    required Uint8List keyBytes,
    required Uint8List ivBytes,
    required String transformation,
    required bool encrypting,
  }) {
    return _cipherProcessBytes(
      input: input,
      keyBytes: keyBytes,
      ivBytes: ivBytes,
      transformation: transformation,
      encrypting: encrypting,
    );
  }

  Uint8List _cipherProcessBytesInternal({
    required Uint8List input,
    required Uint8List keyBytes,
    required Uint8List ivBytes,
    required String transformation,
    required bool encrypting,
  }) {
    final upper = transformation.toUpperCase();
    final isNoPadding = upper.contains('NOPADDING');
    final isZeroPadding =
        upper.contains('ZEROPADDING') || upper.contains('ZEROBYTEPADDING');
    if (isNoPadding || isZeroPadding) {
      return _rawBlockProcess(
        input: input,
        keyBytes: keyBytes,
        ivBytes: ivBytes,
        transformation: transformation,
        encrypting: encrypting,
        zeroPad: isZeroPadding,
      );
    }

    final cipher = _decodeCipher(
      transformation: transformation,
      keyBytes: keyBytes,
      ivBytes: ivBytes,
      encrypting: encrypting,
    );
    return cipher.process(input);
  }

  Uint8List _rawBlockProcess({
    required Uint8List input,
    required Uint8List keyBytes,
    required Uint8List ivBytes,
    required String transformation,
    required bool encrypting,
    required bool zeroPad,
  }) {
    final upper = transformation.toUpperCase();
    final isDes = upper.contains('DES');
    final mode = upper.contains('/ECB/') ? 'ecb' : 'cbc';
    final engine = isDes ? DESedeEngine() : AESEngine();
    final blockSize = engine.blockSize;
    final normalizedKeyBytes = isDes
        ? _desCompatibleKeyBytes(keyBytes)
        : keyBytes;
    if (!isDes &&
        normalizedKeyBytes.length != 16 &&
        normalizedKeyBytes.length != 24 &&
        normalizedKeyBytes.length != 32) {
      throw ArgumentError('Invalid AES key length');
    }
    final CipherParameters keyParam = isDes
        ? DESedeParameters(normalizedKeyBytes)
        : KeyParameter(normalizedKeyBytes);

    final BlockCipher blockCipher = mode == 'ecb'
        ? ECBBlockCipher(engine)
        : CBCBlockCipher(engine);
    if (mode == 'ecb') {
      blockCipher.init(encrypting, keyParam);
    } else {
      var normalizedIvBytes = ivBytes;
      if (normalizedIvBytes.length != blockSize) {
        normalizedIvBytes = Uint8List(blockSize);
      }
      blockCipher.init(
        encrypting,
        ParametersWithIV<CipherParameters>(keyParam, normalizedIvBytes),
      );
    }

    var data = input;
    if (encrypting && zeroPad && data.length % blockSize != 0) {
      final padded = Uint8List(((data.length ~/ blockSize) + 1) * blockSize);
      padded.setAll(0, data);
      data = padded;
    }
    if (data.isEmpty || data.length % blockSize != 0) {
      throw ArgumentError('Input is not block aligned');
    }
    final out = Uint8List(data.length);
    var offset = 0;
    while (offset < data.length) {
      offset += blockCipher.processBlock(data, offset, out, offset);
    }
    return out;
  }

  PaddedBlockCipher _decodeCipher({
    required String transformation,
    required Uint8List keyBytes,
    required Uint8List ivBytes,
    required bool encrypting,
  }) {
    final upper = transformation.toUpperCase();
    final isDes = upper.contains('DES');
    final mode = upper.contains('/ECB/') ? 'ecb' : 'cbc';
    final engine = isDes ? DESedeEngine() : AESEngine();
    final normalizedKeyBytes = isDes
        ? _desCompatibleKeyBytes(keyBytes)
        : keyBytes;
    if (!isDes &&
        normalizedKeyBytes.length != 16 &&
        normalizedKeyBytes.length != 24 &&
        normalizedKeyBytes.length != 32) {
      throw ArgumentError('Invalid AES key length');
    }
    final keyParam = isDes
        ? DESedeParameters(normalizedKeyBytes)
        : KeyParameter(normalizedKeyBytes);

    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      mode == 'ecb' ? ECBBlockCipher(engine) : CBCBlockCipher(engine),
    );
    if (mode == 'ecb') {
      cipher.init(
        encrypting,
        PaddedBlockCipherParameters<CipherParameters, Null>(keyParam, null),
      );
    } else {
      var normalizedIvBytes = ivBytes;
      if (normalizedIvBytes.length != engine.blockSize) {
        normalizedIvBytes = Uint8List(engine.blockSize);
      }
      cipher.init(
        encrypting,
        PaddedBlockCipherParameters<ParametersWithIV<CipherParameters>, Null>(
          ParametersWithIV<CipherParameters>(keyParam, normalizedIvBytes),
          null,
        ),
      );
    }
    return cipher;
  }

  Uint8List _desCompatibleKeyBytes(Uint8List raw) {
    if (raw.length == 24) return raw;
    if (raw.length == 16) {
      return Uint8List.fromList([...raw, ...raw.sublist(0, 8)]);
    }
    if (raw.length == 8) {
      return Uint8List.fromList([...raw, ...raw, ...raw]);
    }
    throw ArgumentError('Invalid DES key length');
  }

  String _inflateBytesToString(Uint8List bytes) {
    final decoders = <List<int> Function()>[
      () => ZLibDecoder().convert(bytes),
      () => ZLibDecoder(raw: true).convert(bytes),
      () => ZLibDecoder(gzip: true).convert(bytes),
      () => GZipCodec().decode(bytes),
    ];
    for (final decode in decoders) {
      try {
        final inflated = decode();
        if (inflated.isNotEmpty) {
          return utf8.decode(inflated, allowMalformed: true);
        }
      } catch (_) {
        // Try the next common deflate/gzip flavor.
      }
    }
    return '';
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

  String _hmac(
    String algorithm,
    String key,
    String value, {
    required bool base64Output,
  }) {
    final normalized = algorithm.toLowerCase().replaceFirst(
      RegExp(r'^hmac-?'),
      '',
    );
    final mac = HMac(_digestForHmac(normalized), _hmacBlockLength(normalized))
      ..init(KeyParameter(Uint8List.fromList(utf8.encode(key))));
    final digest = mac.process(Uint8List.fromList(utf8.encode(value)));
    return base64Output ? base64Encode(digest) : _bytesToHex(digest);
  }

  dynamic _digestForHmac(String algorithm) {
    switch (algorithm) {
      case 'md5':
        return MD5Digest();
      case 'sha1':
        return SHA1Digest();
      case 'sha224':
        return SHA224Digest();
      case 'sha256':
        return SHA256Digest();
      case 'sha384':
        return SHA384Digest();
      case 'sha512':
        return SHA512Digest();
      default:
        return SHA1Digest();
    }
  }

  int _hmacBlockLength(String algorithm) {
    switch (algorithm) {
      case 'sha384':
      case 'sha512':
        return 128;
      default:
        return 64;
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

  String _decodeBytesByType(Uint8List bytes, String type) {
    switch (type.toLowerCase()) {
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
        return gbk.decode(bytes);
      case 'utf8':
      case 'utf-8':
      default:
        return utf8.decode(bytes, allowMalformed: true);
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
  static String transform(String code, {bool wrapScript = true}) {
    var transformed = code;

    final hasJavaCall = RegExp(
      r'java\.(ajax|post|connect|startBrowser|get|fetch|postForm|ajax_bytes)\b',
    ).hasMatch(transformed);
    final hasDynamicLoginEval = RegExp(
      r'eval\s*\(\s*(?:String\s*\(\s*)?source\.loginUrl',
    ).hasMatch(transformed);
    if (!hasJavaCall && !hasDynamicLoginEval) {
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
      RegExp(r'(?<!await\s+)java\.(ajax|post|connect|startBrowser|get|fetch|postForm|ajax_bytes)\b'),
      (match) => 'await java.${match.group(1)}',
    );

    if (hasDynamicLoginEval) {
      transformed = _awaitKnownFunctionCalls(transformed, const ['login']);
    }

    if (!wrapScript ||
        !transformed.contains('await') ||
        _isAsyncIife(transformed)) {
      return transformed;
    }

    return '(async function() { ${_returnLastExpression(transformed)} })()';
  }

  static String _awaitKnownFunctionCalls(String code, Iterable<String> names) {
    var transformed = code;
    for (final name in names) {
      transformed = transformed.replaceAllMapped(
        RegExp('(^|[^\\w\$.])(${RegExp.escape(name)})\\s*\\('),
        (match) {
          final prefix = match.group(1) ?? '';
          final before = match.input.substring(0, match.start + prefix.length);
          final tail = before.trimRight();
          if (tail.endsWith('await') ||
              tail.endsWith('function') ||
              tail.endsWith('async function')) {
            return match.group(0)!;
          }
          return '${prefix}await ${match.group(2)}(';
        },
      );
    }
    return transformed;
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

    final split = _splitLastTopLevelStatement(trimmed);
    if (split == null) return '$trimmed;';
    final prefix = split.$1.trimRight();
    final last = split.$2.trim();
    if (last.isEmpty || _isStatementOnly(last)) return '$trimmed;';
    final body = prefix.isEmpty ? '' : '$prefix\n';
    return '$body return ($last);';
  }

  static bool _isStatementOnly(String text) {
    final trimmed = text.trimLeft();
    return RegExp(
      r'^(var|let|const|if|for|while|switch|try|throw|class|function)\b',
    ).hasMatch(trimmed);
  }

  static (String, String)? _splitLastTopLevelStatement(String code) {
    var quote = 0;
    var escaped = false;
    var depth = 0;

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
        if (depth > 0) {
          depth--;
        }
        continue;
      }
      if (depth == 0 && (unit == 0x3b || unit == 0x0a || unit == 0x0d)) {
        return (code.substring(0, i), code.substring(i + 1));
      }
    }

    return _isStatementOnly(code) ? null : ('', code);
  }
}
