import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/book_source.dart';
import 'legado_js_engine.dart';

class LegadoHttpRequest {
  final String url;
  final String method;
  final Map<String, dynamic>? headers;
  final String? body;
  final String? charset;

  const LegadoHttpRequest({
    required this.url,
    required this.method,
    required this.headers,
    required this.body,
    required this.charset,
  });
}

class LegadoRequestBuilder {
  static String buildSearchUrl(
    BookSource source,
    String keyword, {
    int page = 1,
  }) {
    var searchUrl = replaceVariables(
      source.searchUrl!,
      keyword: keyword,
      page: page,
      source: source,
    );
    if (searchUrl.trimLeft().startsWith('@js:') ||
        searchUrl.trimLeft().startsWith('<js>')) {
      try {
        final evaluated = LegadoJsEngine().evaluate(
          searchUrl,
          variables: {
            'keyword': keyword,
            'key': keyword,
            'page': page,
            'source': {
              'key': cleanBaseUrl(source.bookSourceUrl),
              'bookSourceUrl': cleanBaseUrl(source.bookSourceUrl),
            },
          },
        );
        if (evaluated.trim().isNotEmpty) searchUrl = evaluated;
      } catch (_) {
        return '';
      }
    }
    final embedded = splitEmbeddedConfig(searchUrl);
    final resolved = resolveUrl(source.bookSourceUrl, embedded.url);
    if (embedded.config.isEmpty) return resolved;
    return '$resolved,${jsonEncode(embedded.config)}';
  }

  static LegadoHttpRequest buildRequest(
    BookSource source,
    String url, {
    String? keyword,
    int page = 1,
  }) {
    final embedded = splitEmbeddedConfig(url);
    final config = <String, dynamic>{};
    config.addAll(jsonConfig(source.customConfig));
    config.addAll(embedded.config);

    final headers = <String, dynamic>{};
    final rawHeaders =
        config['headers'] ?? config['header'] ?? config['bookSourceHeader'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        final name = key.toString().trim();
        final headerValue = value.toString();
        if (_isSafeHeaderName(name) && headerValue.isNotEmpty) {
          headers[name] = headerValue;
        }
      });
    } else if (rawHeaders is String) {
      headers.addAll(parseHeaderString(rawHeaders));
    }
    final cookie = config['cookie'] ?? config['Cookie'];
    if (cookie != null && cookie.toString().isNotEmpty) {
      headers['Cookie'] = cookie.toString();
    }

    final method = (config['method'] ?? config['type'] ?? 'GET')
        .toString()
        .toUpperCase();
    final rawBody = config['body'] ?? config['data'];
    final body = _buildBody(
      rawBody,
      keyword: keyword ?? '',
      page: page,
      source: source,
    );
    if (method == 'POST' &&
        body != null &&
        !headers.containsKey('Content-Type')) {
      headers['Content-Type'] = rawBody is Map || rawBody is List
          ? 'application/json'
          : 'application/x-www-form-urlencoded';
    }
    final safeHeaders = _sanitizeHeaders(headers);

    return LegadoHttpRequest(
      url: embedded.url,
      method: method,
      headers: safeHeaders.isEmpty ? null : safeHeaders,
      body: body,
      charset: config['charset']?.toString(),
    );
  }

  static String replaceVariables(
    String text, {
    required String keyword,
    int page = 1,
    BookSource? source,
  }) {
    final encoded = Uri.encodeComponent(keyword);
    final rawKey = keyword;
    final baseUrl = source == null ? '' : cleanBaseUrl(source.bookSourceUrl);
    final sourceKey = _sourceValue(source, 'key');
    return _replaceJavaHelpers(
          _replaceEncodedPlaceholders(text),
          keyword: keyword,
          page: page,
        )
        .replaceAllMapped(RegExp(r'\{\{page([+-]\d+)\}\}'), (match) {
          final offset = int.tryParse(match.group(1) ?? '') ?? 0;
          return (page + offset).toString();
        })
        .replaceAllMapped(RegExp(r'\{page([+-]\d+)\}'), (match) {
          final offset = int.tryParse(match.group(1) ?? '') ?? 0;
          return (page + offset).toString();
        })
        .replaceAll('{{key}}', encoded)
        .replaceAll('{{keyword}}', encoded)
        .replaceAll('{{searchKey}}', encoded)
        .replaceAll('{{keyRaw}}', rawKey)
        .replaceAll('{{searchKeyRaw}}', keyword)
        .replaceAll('{{page}}', page.toString())
        .replaceAll('{{source.key}}', sourceKey)
        .replaceAll('{{source.bookSourceUrl}}', baseUrl)
        .replaceAll('{{baseUrl}}', baseUrl)
        .replaceAll('{key}', encoded)
        .replaceAll('{keyword}', encoded)
        .replaceAll('{searchKey}', encoded)
        .replaceAll('{keyRaw}', rawKey)
        .replaceAll('{page}', page.toString())
        .replaceAll('%s', encoded);
  }

  static String _replaceEncodedPlaceholders(String text) {
    var output = text;
    for (var i = 0; i < 2; i++) {
      final decoded = output
          .replaceAll('%7B', '{')
          .replaceAll('%7b', '{')
          .replaceAll('%7D', '}')
          .replaceAll('%7d', '}');
      if (decoded == output) break;
      output = decoded;
    }
    return output;
  }

  static String resolveUrl(String baseUrl, String url) {
    if (url.isEmpty || url.startsWith('data:')) return url;
    final cleanBase = cleanBaseUrl(baseUrl);
    try {
      final uri = Uri.parse(url);
      if (uri.hasScheme) return url;
      return Uri.parse(cleanBase).resolve(url).toString();
    } catch (_) {
      return url.startsWith('http')
          ? url
          : '${cleanBase.replaceAll(RegExp(r'/+$'), '')}/$url';
    }
  }

  static String cleanBaseUrl(String baseUrl) {
    return baseUrl.split('##').first;
  }

  static Map<String, dynamic> jsonConfig(String? customConfig) {
    if (customConfig == null || customConfig.trim().isEmpty) return {};
    try {
      final json = jsonDecode(customConfig);
      if (json is Map<String, dynamic>) return json;
      if (json is Map) {
        return json.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return {};
    }
    return {};
  }

  static Map<String, dynamic> parseHeaderString(String rawHeaders) {
    final headers = <String, dynamic>{};
    final text = rawHeaders.trim();
    if (text.isEmpty) return headers;

    if (_looksLikeJsHeader(text)) {
      try {
        final evaluated = LegadoJsEngine().evaluate(text);
        final parsed = _parseEvaluatedHeaders(evaluated);
        if (parsed.isNotEmpty) return parsed;
      } catch (_) {
        // Fall back to loose object extraction and safe browser defaults.
      }
      final parsed = _parseLooseHeaderObject(text);
      return parsed.isEmpty ? _defaultBrowserHeaders() : parsed;
    }

    try {
      final json = jsonDecode(text);
      if (json is Map) {
        json.forEach((key, value) {
          final name = key.toString().trim();
          final headerValue = value.toString();
          if (_isSafeHeaderName(name) && headerValue.isNotEmpty) {
            headers[name] = headerValue;
          }
        });
        return headers;
      }
    } catch (_) {
      // Plain header lines are handled below.
    }

    headers.addAll(_parseLooseHeaderObject(text));
    if (headers.isNotEmpty) return headers;

    final normalized = text.replaceAll(r'\n', '\n');
    for (final line in normalized.split(RegExp(r'[\r\n]+'))) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (_isSafeHeaderName(key) && value.isNotEmpty) {
        headers[key] = value;
      }
    }
    return headers;
  }

  static ({String url, Map<String, dynamic> config}) splitEmbeddedConfig(
    String url,
  ) {
    final comma = url.indexOf(',{');
    if (comma <= 0 || comma >= url.length - 1) {
      return (url: url, config: {});
    }
    final tail = url.substring(comma + 1).trim();
    if (!tail.startsWith('{')) {
      if (_looksLikeScript(tail)) {
        return (url: url.substring(0, comma), config: {});
      }
      return (url: url, config: {});
    }
    final configText = _extractLeadingJsonObject(tail);
    if (configText == null) {
      return (url: url.substring(0, comma), config: {});
    }
    try {
      return (url: url.substring(0, comma), config: jsonConfig(configText));
    } catch (_) {
      return (url: url, config: {});
    }
  }

  static bool _looksLikeScript(String tail) {
    return tail.contains('=>') ||
        tail.contains('function') ||
        tail.contains('if ') ||
        tail.contains('return') ||
        tail.contains('java.') ||
        tail.contains('JSON.') ||
        tail.contains('String');
  }

  static bool _looksLikeJsHeader(String text) {
    final value = text.trimLeft();
    return value.startsWith('@js:') ||
        value.startsWith('<js>') ||
        value.contains('</js>') ||
        value.contains('java.') ||
        value.contains('JSON.stringify') ||
        value.contains('function') ||
        value.contains('=>');
  }

  static Map<String, dynamic> _defaultBrowserHeaders() {
    return const {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    };
  }

  static Map<String, dynamic> _parseLooseHeaderObject(String text) {
    final headers = <String, dynamic>{};
    final objectText =
        _extractLeadingJsonObject(text) ?? _extractAnyJsonObject(text);
    if (objectText == null) return headers;

    final quotedPairPattern = RegExp(
      r'''["']([^"'\r\n:{}=]+)["']\s*:\s*["']([^"'\r\n]*)["']''',
      multiLine: true,
    );
    for (final match in quotedPairPattern.allMatches(objectText)) {
      final key = match.group(1)?.trim() ?? '';
      final value = match.group(2)?.trim() ?? '';
      if (_isSafeHeaderName(key) && value.isNotEmpty) {
        headers[key] = value;
      }
    }
    return headers;
  }

  static Map<String, dynamic> _parseEvaluatedHeaders(String text) {
    final headers = <String, dynamic>{};
    final trimmed = text.trim();
    if (trimmed.isEmpty) return headers;
    try {
      final json = jsonDecode(trimmed);
      if (json is Map) {
        json.forEach((key, value) {
          final name = key.toString().trim();
          final headerValue = value.toString();
          if (_isSafeHeaderName(name) && headerValue.isNotEmpty) {
            headers[name] = headerValue;
          }
        });
        return headers;
      }
    } catch (_) {
      // Plain header lines are handled below.
    }

    final objectHeaders = _parseLooseHeaderObject(trimmed);
    if (objectHeaders.isNotEmpty) return objectHeaders;

    final normalized = trimmed.replaceAll(r'\n', '\n');
    for (final line in normalized.split(RegExp(r'[\r\n]+'))) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (_isSafeHeaderName(key) && value.isNotEmpty) {
        headers[key] = value;
      }
    }
    return headers;
  }

  static bool _isSafeHeaderName(String key) {
    return key.isNotEmpty &&
        RegExp(r"^[A-Za-z0-9!#$%&'*+.^_`|~-]+$").hasMatch(key);
  }

  static String? _extractAnyJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    return _extractBalanced(text.substring(start), 0, 0x7b, 0x7d);
  }

  static String? _extractLeadingJsonObject(String text) {
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('{')) return null;
    return _extractBalanced(trimmed, 0, 0x7b, 0x7d);
  }

  static String? _extractBalanced(String text, int start, int open, int close) {
    var depth = 0;
    var inString = false;
    var escaping = false;
    var quote = 0;
    for (var i = start; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (inString) {
        if (escaping) {
          escaping = false;
        } else if (code == 0x5c) {
          escaping = true;
        } else if (code == quote) {
          inString = false;
        }
        continue;
      }
      if (code == 0x22 || code == 0x27) {
        inString = true;
        quote = code;
      } else if (code == open) {
        depth++;
      } else if (code == close) {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  static String _replaceJavaHelpers(
    String text, {
    required String keyword,
    required int page,
  }) {
    return text.replaceAllMapped(
      RegExp(r'\{\{java\.(base64Encode|md5Encode)\((.*?)\)\}\}'),
      (match) {
        final helper = match.group(1) ?? '';
        final expression = match.group(2) ?? '';
        final value = _evaluateSimpleStringExpression(
          expression,
          keyword: keyword,
          page: page,
        );
        if (helper == 'md5Encode') {
          return md5.convert(utf8.encode(value)).toString();
        }
        return base64Encode(utf8.encode(value));
      },
    );
  }

  static String? _buildBody(
    dynamic bodyValue, {
    required String keyword,
    required int page,
    required BookSource source,
  }) {
    if (bodyValue == null) return null;
    if (bodyValue is Map || bodyValue is List) {
      return jsonEncode(
        _replaceBodyValue(
          bodyValue,
          keyword: keyword,
          page: page,
          source: source,
        ),
      );
    }
    return replaceVariables(
      bodyValue.toString(),
      keyword: keyword,
      page: page,
      source: source,
    );
  }

  static dynamic _replaceBodyValue(
    dynamic value, {
    required String keyword,
    required int page,
    required BookSource source,
  }) {
    if (value is String) {
      return replaceVariables(
        value,
        keyword: keyword,
        page: page,
        source: source,
      );
    }
    if (value is Map) {
      return value.map(
        (key, child) => MapEntry(
          key.toString(),
          _replaceBodyValue(
            child,
            keyword: keyword,
            page: page,
            source: source,
          ),
        ),
      );
    }
    if (value is List) {
      return value
          .map(
            (child) => _replaceBodyValue(
              child,
              keyword: keyword,
              page: page,
              source: source,
            ),
          )
          .toList();
    }
    return value;
  }

  static Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    final safe = <String, dynamic>{};
    headers.forEach((key, value) {
      final name = key.trim();
      final headerValue = value.toString();
      if (_isSafeHeaderName(name) && headerValue.isNotEmpty) {
        safe[name] = headerValue;
      }
    });
    return safe;
  }

  static String _evaluateSimpleStringExpression(
    String expression, {
    required String keyword,
    required int page,
  }) {
    final output = StringBuffer();
    for (final token in expression.split('+')) {
      final value = token.trim();
      if (value == 'key') {
        output.write(keyword);
      } else if (value == 'page') {
        output.write(page);
      } else if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        output.write(value.substring(1, value.length - 1));
      }
    }
    return output.toString();
  }

  static String _sourceValue(BookSource? source, String key) {
    if (source == null) return '';
    final config = jsonConfig(source.customConfig);
    final direct = config[key] ?? config['source.$key'];
    if (direct != null) return direct.toString();
    if (key == 'key') {
      return cleanBaseUrl(source.bookSourceUrl).replaceAll(RegExp(r'/+$'), '');
    }
    return '';
  }
}
