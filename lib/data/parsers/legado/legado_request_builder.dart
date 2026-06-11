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
    var output =
        _replaceScriptBlocks(
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
    output = _replaceStoredGetTokens(output);
    if (text.contains('@js:') || text.contains('<js>')) {
      return output;
    }
    return _replaceBareLegacySearchTokens(output, encoded, page);
  }

  static String _replaceBareLegacySearchTokens(
    String text,
    String encodedKeyword,
    int page,
  ) {
    var output = text
        .replaceAll('{{searchPage}}', page.toString())
        .replaceAll('{searchPage}', page.toString());
    output = output.replaceAllMapped(RegExp(r'searchPage([+-]\d+)'), (match) {
      final offset = int.tryParse(match.group(1) ?? '') ?? 0;
      return (page + offset).toString();
    });
    output = _replaceBareWord(output, 'searchPage', page.toString());
    output = _replaceBareWord(output, 'searchKey', encodedKeyword);
    return output;
  }

  static String _replaceStoredGetTokens(String text) {
    return text.replaceAllMapped(
      RegExp(r'@get:\{([^}]+)\}', caseSensitive: false),
      (match) => LegadoJsEngine().getStoredString(match.group(1)?.trim() ?? ''),
    );
  }

  static String _replaceBareWord(String text, String token, String value) {
    final buffer = StringBuffer();
    var index = 0;
    while (index < text.length) {
      final found = text.indexOf(token, index);
      if (found < 0) {
        buffer.write(text.substring(index));
        break;
      }
      final before = found == 0 ? '' : text[found - 1];
      final afterIndex = found + token.length;
      final after = afterIndex >= text.length ? '' : text[afterIndex];
      if (_isIdentifierChar(before) || _isIdentifierChar(after)) {
        buffer.write(text.substring(index, afterIndex));
      } else {
        buffer.write(text.substring(index, found));
        buffer.write(value);
      }
      index = afterIndex;
    }
    return buffer.toString();
  }

  static bool _isIdentifierChar(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5a) ||
        (code >= 0x61 && code <= 0x7a) ||
        code == 0x5f ||
        code == 0x24;
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
    url = _replaceStoredGetTokens(url);
    if (url.isEmpty) return '';
    if (url.startsWith(',') &&
        _extractLeadingJsonObject(url.substring(1).trimLeft()) != null) {
      return '';
    }
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
      final loose = _parseLooseConfigObject(customConfig);
      if (loose.isNotEmpty) return loose;
    }
    return {};
  }

  static Map<String, dynamic> _parseLooseConfigObject(String text) {
    final objectText =
        _extractLeadingJsonObject(text) ?? _extractAnyJsonObject(text);
    if (objectText == null) return {};
    final normalized = _normalizeLooseJsonObject(objectText);
    if (normalized == null) return {};
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return {};
  }

  static String? _normalizeLooseJsonObject(String text) {
    var output = text.trim();
    if (output.isEmpty) return null;
    output = output.replaceAllMapped(
      RegExp(r'''([{,]\s*)([A-Za-z_][A-Za-z0-9_\-]*)\s*:'''),
      (match) => '${match.group(1)}"${match.group(2)}":',
    );
    output = _replaceLooseSingleQuotedStrings(output);
    output = output.replaceAllMapped(
      RegExp(r',\s*([}\]])'),
      (match) => match.group(1) ?? '',
    );
    return output;
  }

  static String _replaceLooseSingleQuotedStrings(String text) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < text.length) {
      if (text.codeUnitAt(i) != 0x27) {
        buffer.write(text[i]);
        i++;
        continue;
      }

      final raw = StringBuffer();
      var closed = false;
      var escaped = false;
      i++;
      while (i < text.length) {
        final ch = text[i];
        if (escaped) {
          raw.write(r'\');
          raw.write(ch);
          escaped = false;
          i++;
          continue;
        }
        if (ch == r'\') {
          escaped = true;
          i++;
          continue;
        }
        if (ch == "'") {
          closed = true;
          i++;
          break;
        }
        raw.write(ch);
        i++;
      }
      if (!closed) {
        buffer.write("'");
        buffer.write(raw.toString());
        break;
      }
      buffer.write(jsonEncode(_decodeLooseSingleQuoted(raw.toString())));
    }
    return buffer.toString();
  }

  static String _decodeLooseSingleQuoted(String value) {
    final buffer = StringBuffer();
    var escaped = false;
    for (var i = 0; i < value.length; i++) {
      final ch = value[i];
      if (!escaped) {
        if (ch == r'\') {
          escaped = true;
        } else {
          buffer.write(ch);
        }
        continue;
      }
      switch (ch) {
        case 'n':
          buffer.write('\n');
          break;
        case 'r':
          buffer.write('\r');
          break;
        case 't':
          buffer.write('\t');
          break;
        default:
          buffer.write(ch);
      }
      escaped = false;
    }
    if (escaped) buffer.write(r'\');
    return buffer.toString();
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
    if (config.isEmpty && configText.trim() != '{}') {
      return (url: url, config: {});
    }
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
    final output = text.replaceAllMapped(
      RegExp(
        r'\{\{java\.(base64Encode|base64Decode|base64DecodeToString|base64Decoder|hexDecodeToString|md5Encode|encodeURI|encodeURIComponent|decodeURI|decodeURIComponent)\(([\s\S]*?)\)\}\}',
      ),
      (match) {
        final helper = match.group(1) ?? '';
        final expression = match.group(2) ?? '';
        if (_shouldEvaluateAsInlineScript(expression)) {
          return match.group(0) ?? '';
        }
        final args = _splitTopLevelArguments(expression);
        final value = _evaluateSimpleStringExpression(
          args.isEmpty ? expression : args.first,
          keyword: keyword,
          page: page,
        );
        final charset = args.length > 1 ? _stripStringLiteral(args[1]) : '';
        switch (helper) {
          case 'md5Encode':
            return md5.convert(utf8.encode(value)).toString();
          case 'base64Encode':
            return base64Encode(utf8.encode(value));
          case 'base64Decode':
          case 'base64DecodeToString':
          case 'base64Decoder':
            return utf8.decode(base64Decode(value), allowMalformed: true);
          case 'hexDecodeToString':
            return _hexDecodeToString(value);
          case 'encodeURI':
            if (_isGbkCharset(charset)) return _encodeGbkPercent(value);
            return Uri.encodeFull(value);
          case 'encodeURIComponent':
            if (_isGbkCharset(charset)) return _encodeGbkPercent(value);
            return Uri.encodeComponent(value);
          case 'decodeURI':
            return Uri.decodeFull(value);
          case 'decodeURIComponent':
            return Uri.decodeComponent(value);
        }
        return value;
      },
    );
    return _replacePackagesStringByteTemplates(
      output,
      keyword: keyword,
      page: page,
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
        return _evaluateInlineScriptFallback(
              script,
              keyword: keyword,
              page: page,
            ) ??
            '';
      }
    });
  }

  static bool _shouldEvaluateAsInlineScript(String expression) {
    return expression.contains('java.') ||
        expression.contains('Packages.') ||
        expression.contains('android.') ||
        expression.contains('Math.') ||
        expression.contains('new Date') ||
        expression.contains(';') ||
        expression.contains('=>') ||
        expression.contains('function');
  }

  static List<String> _splitTopLevelArguments(String expression) {
    final args = <String>[];
    final current = StringBuffer();
    var depth = 0;
    var quote = 0;
    var escaping = false;
    for (var i = 0; i < expression.length; i++) {
      final code = expression.codeUnitAt(i);
      if (quote != 0) {
        current.writeCharCode(code);
        if (escaping) {
          escaping = false;
        } else if (code == 0x5c) {
          escaping = true;
        } else if (code == quote) {
          quote = 0;
        }
        continue;
      }
      if (code == 0x22 || code == 0x27) {
        quote = code;
        current.writeCharCode(code);
      } else if (code == 0x28 || code == 0x5b || code == 0x7b) {
        depth++;
        current.writeCharCode(code);
      } else if (code == 0x29 || code == 0x5d || code == 0x7d) {
        if (depth > 0) depth--;
        current.writeCharCode(code);
      } else if (code == 0x2c && depth == 0) {
        args.add(current.toString().trim());
        current.clear();
      } else {
        current.writeCharCode(code);
      }
    }
    final tail = current.toString().trim();
    if (tail.isNotEmpty) args.add(tail);
    return args;
  }

  static String _stripStringLiteral(String value) {
    final text = value.trim();
    if (text.length >= 2) {
      final first = text[0];
      final last = text[text.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return text.substring(1, text.length - 1);
      }
    }
    return text;
  }

  static bool _isGbkCharset(String charset) {
    final value = charset.toLowerCase().replaceAll('-', '');
    return value == 'gbk' || value == 'gb2312' || value == 'gb18030';
  }

  static String _encodeGbkPercent(String value) {
    try {
      return gbk
          .encode(value)
          .map(
            (byte) =>
                '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
          )
          .join();
    } catch (_) {
      return Uri.encodeComponent(value);
    }
  }

  static String _replacePackagesStringByteTemplates(
    String text, {
    required String keyword,
    required int page,
  }) {
    return text.replaceAllMapped(RegExp(r'\{\{([\s\S]*?)\}\}'), (match) {
      final script = match.group(1) ?? '';
      return _evaluatePackagesStringBytes(
            script,
            keyword: keyword,
            page: page,
          ) ??
          (match.group(0) ?? '');
    });
  }

  static String? _evaluateInlineScriptFallback(
    String script, {
    required String keyword,
    required int page,
  }) {
    return _evaluatePackagesStringBytes(script, keyword: keyword, page: page);
  }

  static String? _evaluatePackagesStringBytes(
    String script, {
    required String keyword,
    required int page,
  }) {
    if (!script.contains('Packages.java.lang.String') ||
        !script.contains('.getBytes') ||
        !script.contains('toString(16)')) {
      return null;
    }
    final valueMatch = RegExp(
      r'''Packages\.java\.lang\.String\(\s*(['"]?)(.*?)\1\s*\)''',
    ).firstMatch(script);
    if (valueMatch == null) return null;
    final rawValue = valueMatch.group(2)?.trim() ?? '';
    final value = rawValue == 'key'
        ? keyword
        : rawValue == 'page'
        ? page.toString()
        : _stripStringLiteral(rawValue);

    final charsetMatch = RegExp(
      r'''\.getBytes\(\s*(['"])(.*?)\1\s*\)''',
    ).firstMatch(script);
    final charset = charsetMatch?.group(2) ?? 'utf-8';
    final bytes = _isGbkCharset(charset)
        ? gbk.encode(value)
        : utf8.encode(value);
    final joinMatch = RegExp(
      r'''\.join\(\s*(['"])(.*?)\1\s*\)''',
    ).firstMatch(script);
    final separator = joinMatch?.group(2) ?? '';
    final prefix = script.contains("'%'") || script.contains('"%') ? '%' : '';
    final upper = script.contains('toUpperCase()');
    return bytes
        .map((byte) {
          final hex = byte.toRadixString(16);
          return '$prefix${upper ? hex.toUpperCase() : hex}';
        })
        .join(separator);
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
