import 'dart:convert';
import 'package:fast_gbk/fast_gbk.dart';

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
    final raw = source.searchUrl!;
    var searchUrl = raw;
    if (_isWholeJsRule(raw)) {
      try {
        final evaluated = LegadoJsEngine().evaluate(
          raw,
          variables: {
            'keyword': keyword,
            'key': keyword,
            'page': page,
            'source': {
              'key': _sourceValue(source, 'key'),
              'bookSourceUrl': _sourceValue(source, 'key'),
            },
          },
        );
        if (evaluated.trim().isNotEmpty) searchUrl = evaluated;
      } catch (_) {
        return '';
      }
    } else {
      searchUrl = replaceVariables(
        raw,
        keyword: keyword,
        page: page,
        source: source,
      );
      if (_isWholeJsRule(searchUrl)) {
        try {
          final evaluated = LegadoJsEngine().evaluate(
            searchUrl,
            variables: {
              'keyword': keyword,
              'key': keyword,
              'page': page,
              'source': {
                'key': _sourceValue(source, 'key'),
                'bookSourceUrl': _sourceValue(source, 'key'),
              },
            },
          );
          if (evaluated.trim().isNotEmpty) searchUrl = evaluated;
        } catch (_) {
          return '';
        }
      }
    }
    final embedded = splitEmbeddedConfig(searchUrl);
    final resolved = resolveUrl(source.bookSourceUrl, embedded.url);
    if (embedded.config.isEmpty) return resolved;
    return '$resolved,${jsonEncode(embedded.config)}';
  }

  static bool _isWholeJsRule(String text) {
    final value = text.trimLeft();
    return value.startsWith('@js:') || value.startsWith('<js>');
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
        if (_isSafeHeaderName(name)) {
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
    final fullConfigStr = [
      text,
      source?.searchUrl ?? '',
      source?.customConfig ?? '',
    ].join(' ').toLowerCase();

    bool isGbk =
        fullConfigStr.contains('gbk') || fullConfigStr.contains('gb2312');

    String encoded;
    if (isGbk) {
      try {
        final bytes = gbk.encode(keyword);
        encoded = bytes
            .map((b) => '%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}')
            .join();
      } catch (_) {
        encoded = Uri.encodeComponent(keyword);
      }
    } else {
      encoded = Uri.encodeComponent(keyword);
    }

    final rawKey = keyword;
    final baseUrl = source == null ? '' : _sourceValue(source, 'key');
    final sourceKey = _sourceValue(source, 'key');
    return _replaceScriptBlocks(
          _replaceJavaHelpers(
            _replaceEncodedPlaceholders(text),
            keyword: keyword,
            page: page,
          ),
          keyword: keyword,
          page: page,
          source: source,
        )
        .replaceAllMapped(RegExp(r'\{\{page([+-]\d+)\}\}'), (match) {
          final offset = int.tryParse(match.group(1) ?? '') ?? 0;
          return (page + offset).toString();
        })
        .replaceAllMapped(RegExp(r'\{page([+-]\d+)\}'), (match) {
          final offset = int.tryParse(match.group(1) ?? '') ?? 0;
          return (page + offset).toString();
        })
        .replaceAllMapped(RegExp(r'<([^<>]+)>'), (match) {
          return _replacePageSequence(
            match.group(0) ?? '',
            match.group(1),
            page,
          );
        })
        .replaceAll('{{key}}', encoded)
        .replaceAll('{{keyword}}', encoded)
        .replaceAll('{{searchKey}}', encoded)
        .replaceAll('{{keyRaw}}', rawKey)
        .replaceAll('{{searchKeyRaw}}', keyword)
        .replaceAll('{{page}}', page.toString())
        .replaceAll('{{source.key}}', sourceKey)
        .replaceAll('{{source.getKey()}}', sourceKey)
        .replaceAll('{{source.getKey}}', sourceKey)
        .replaceAll('{{source.bookSourceUrl}}', baseUrl)
        .replaceAll('{{baseUrl}}', baseUrl)
        .replaceAll('{key}', encoded)
        .replaceAll('{keyword}', encoded)
        .replaceAll('{searchKey}', encoded)
        .replaceAll('{keyRaw}', rawKey)
        .replaceAll('{page}', page.toString())
        .replaceAll('{source.key}', sourceKey)
        .replaceAll('{source.getKey()}', sourceKey)
        .replaceAll('{source.getKey}', sourceKey)
        .replaceAll('{source.bookSourceUrl}', baseUrl)
        .replaceAll('{baseUrl}', baseUrl)
        .replaceAll('%s', encoded);
  }

  static String _replacePageSequence(String original, String? body, int page) {
    final value = body?.trim() ?? '';
    if (value.isEmpty || !value.contains(',')) return original;
    final parts = value.split(',').map((part) => part.trim()).toList();
    if (parts.any((part) => part.isEmpty)) return original;
    if (parts.any((part) => part.contains('{') || part.contains('}'))) {
      return original;
    }
    final index = page - 1;
    return index >= 0 && index < parts.length ? parts[index] : parts.last;
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
    baseUrl = baseUrl
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll('%0A', '')
        .replaceAll('%0D', '')
        .replaceAll('%0a', '')
        .replaceAll('%0d', '')
        .trim();
    url = url
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll('%0A', '')
        .replaceAll('%0D', '')
        .replaceAll('%0a', '')
        .replaceAll('%0d', '')
        .trim();
    if (url.isEmpty) return '';
    if (_isWholeJsRule(url)) return '';
    if (url.startsWith('data:') || url.startsWith('javascript:')) return url;

    // 1. Separate Legado config
    final embedded = splitEmbeddedConfig(url);
    var cleanUrl = embedded.url.trim();
    final configMap = embedded.config;

    // Check if cleanUrl contains obvious rule syntax like rule markers
    if (cleanUrl.contains(r'$.') ||
        cleanUrl.contains('@css') ||
        cleanUrl.contains('xpath:') ||
        cleanUrl.contains('{{') ||
        cleanUrl.contains('}}')) {
      return ''; // Invalid URL
    }

    // Normalize backslashes to slashes
    cleanUrl = cleanUrl.replaceAll('\\', '/');

    // 2. Resolve relative path
    String resolvedUrl = '';
    try {
      final baseUri = Uri.parse(cleanBaseUrl(baseUrl).trim());

      // Check if cleanUrl is already absolute
      final cleanUri = Uri.parse(cleanUrl);
      if (cleanUri.hasScheme) {
        resolvedUrl = cleanUrl;
      } else {
        if (cleanUrl.startsWith('//')) {
          final scheme = baseUri.hasScheme ? baseUri.scheme : 'https';
          resolvedUrl = '$scheme:$cleanUrl';
        } else {
          resolvedUrl = baseUri.resolveUri(cleanUri).toString();
        }
      }
    } catch (_) {
      try {
        final encodedUrl = Uri.encodeFull(cleanUrl);
        final baseUri = Uri.parse(cleanBaseUrl(baseUrl).trim());
        final cleanUri = Uri.parse(encodedUrl);
        if (cleanUri.hasScheme) {
          resolvedUrl = encodedUrl;
        } else {
          if (encodedUrl.startsWith('//')) {
            final scheme = baseUri.hasScheme ? baseUri.scheme : 'https';
            resolvedUrl = '$scheme:$encodedUrl';
          } else {
            resolvedUrl = baseUri.resolveUri(cleanUri).toString();
          }
        }
      } catch (_) {
        final baseStr = cleanBaseUrl(
          baseUrl,
        ).trim().replaceAll(RegExp(r'/+$'), '');
        if (cleanUrl.startsWith('http')) {
          resolvedUrl = cleanUrl;
        } else if (cleanUrl.startsWith('//')) {
          final baseUri = Uri.tryParse(baseStr);
          final scheme = (baseUri != null && baseUri.hasScheme)
              ? baseUri.scheme
              : 'https';
          resolvedUrl = '$scheme:$cleanUrl';
        } else if (cleanUrl.startsWith('/')) {
          final baseUri = Uri.tryParse(baseStr);
          if (baseUri != null && baseUri.hasScheme) {
            resolvedUrl = '${baseUri.scheme}://${baseUri.host}$cleanUrl';
          } else {
            resolvedUrl = '$baseStr$cleanUrl';
          }
        } else {
          resolvedUrl = '$baseStr/$cleanUrl';
        }
      }
    }

    // 3. Re-append config
    if (configMap.isEmpty) {
      return resolvedUrl;
    } else {
      return '$resolvedUrl,${jsonEncode(configMap)}';
    }
  }

  static String cleanBaseUrl(String baseUrl) {
    final withoutProcessor = baseUrl.split('##').first;
    final fragment = withoutProcessor.indexOf('#');
    if (fragment > 0) return withoutProcessor.substring(0, fragment);
    return withoutProcessor;
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
          if (_isSafeHeaderName(name)) {
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
      if (_isSafeHeaderName(key)) {
        headers[key] = value;
      }
    }
    return headers;
  }

  static ({String url, Map<String, dynamic> config}) splitEmbeddedConfig(
    String url,
  ) {
    url = url
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll('%0A', '')
        .replaceAll('%0D', '')
        .replaceAll('%0a', '')
        .replaceAll('%0d', '')
        .trim();
    final comma = _findEmbeddedConfigComma(url);
    if (comma <= 0 || comma >= url.length - 1) return (url: url, config: {});
    final tail = url.substring(comma + 1).trimLeft();
    final configText = _extractLeadingJsonObject(tail);
    if (configText == null) return (url: url, config: {});
    final config = jsonConfig(configText);
    if (config.isEmpty && configText.trim() != '{}')
      return (url: url, config: {});
    return (url: url.substring(0, comma).trimRight(), config: config);
  }

  static int _findEmbeddedConfigComma(String text) {
    var inString = false;
    var escaping = false;
    var quote = 0;
    for (var i = 0; i < text.length; i++) {
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
      } else if (code == 0x2c) {
        final tail = text.substring(i + 1).trimLeft();
        if (tail.startsWith('{')) return i;
      }
    }
    return -1;
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
        value.startsWith('var ') ||
        value.contains('var headers') ||
        value.contains('var heders') ||
        value.contains('headers =') ||
        value.contains('heders =') ||
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
      if (_isSafeHeaderName(key)) {
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
          if (_isSafeHeaderName(name)) {
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
      if (_isSafeHeaderName(key)) {
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
      RegExp(
        r'\{\{java\.(base64Encode|base64Decode|base64DecodeToString|hexDecodeToString|md5Encode|encodeURI|encodeURIComponent|decodeURI|decodeURIComponent)\((.*?)\)\}\}',
      ),
      (match) {
        final helper = match.group(1) ?? '';
        final expression = match.group(2) ?? '';
        final value = _evaluateSimpleStringExpression(
          expression,
          keyword: keyword,
          page: page,
        );
        switch (helper) {
          case 'md5Encode':
            return md5.convert(utf8.encode(value)).toString();
          case 'base64Encode':
            return base64Encode(utf8.encode(value));
          case 'base64Decode':
          case 'base64DecodeToString':
            return utf8.decode(base64Decode(value), allowMalformed: true);
          case 'hexDecodeToString':
            return _hexDecodeToString(value);
          case 'encodeURI':
            return Uri.encodeFull(value);
          case 'encodeURIComponent':
            return Uri.encodeComponent(value);
          case 'decodeURI':
            return Uri.decodeFull(value);
          case 'decodeURIComponent':
            return Uri.decodeComponent(value);
        }
        return value;
      },
    );
  }

  static String _replaceScriptBlocks(
    String text, {
    required String keyword,
    required int page,
    BookSource? source,
  }) {
    return text.replaceAllMapped(RegExp(r'\{\{([\s\S]*?)\}\}'), (match) {
      final script = match.group(1) ?? '';
      if (!_looksLikeInlineScript(script)) return match.group(0) ?? '';
      try {
        final baseUrl = source == null
            ? ''
            : cleanBaseUrl(source.bookSourceUrl);
        final value = LegadoJsEngine().evaluate(
          script,
          variables: {
            'keyword': keyword,
            'key': keyword,
            'page': page,
            'source': {'key': baseUrl, 'bookSourceUrl': baseUrl},
            'params': {'pageIndex': page, 'tabIndex': 0, 'filters': {}},
          },
        );
        return value.trim();
      } catch (_) {
        return '';
      }
    });
  }

  static bool _looksLikeInlineScript(String script) {
    final text = script.trim();
    if (text.isEmpty) return false;
    if (RegExp(
      r'^source\.(key|bookSourceUrl|getKey|getKey\(\))$',
    ).hasMatch(text)) {
      return false;
    }
    return text.contains('\n') ||
        text.contains(';') ||
        text.contains('var ') ||
        text.contains('let ') ||
        text.contains('const ') ||
        text.contains('java.') ||
        text.contains('return ') ||
        text.contains('=>');
  }

  static String _hexDecodeToString(String value) {
    final text = value.trim();
    if (text.startsWith('data:')) {
      final parts = text.split(',');
      if (parts.length >= 3 && parts[1].toLowerCase() == 'base64') {
        try {
          return utf8.decode(base64Decode(parts[2]), allowMalformed: true);
        } catch (_) {
          return value;
        }
      }
    }
    final hexText = text.replaceAll(RegExp(r'\s+'), '');
    if (hexText.isEmpty ||
        hexText.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hexText)) {
      return value;
    }
    try {
      final bytes = <int>[];
      for (var i = 0; i < hexText.length; i += 2) {
        bytes.add(int.parse(hexText.substring(i, i + 2), radix: 16));
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return value;
    }
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
      if (_isSafeHeaderName(name)) {
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
      } else if (value == 'java.encodeURI(key)') {
        output.write(Uri.encodeFull(keyword));
      } else if (value == 'java.encodeURIComponent(key)') {
        output.write(Uri.encodeComponent(keyword));
      } else if (value == 'java.md5Encode(key)') {
        output.write(md5.convert(utf8.encode(keyword)).toString());
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
    if (key == 'key') {
      return cleanBaseUrl(source.bookSourceUrl).replaceAll(RegExp(r'/+$'), '');
    }
    final config = jsonConfig(source.customConfig);
    final direct = config[key] ?? config['source.$key'];
    if (direct != null) return direct.toString();
    return '';
  }
}
