import 'dart:convert';

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
    String searchUrl = replaceVariables(
      source.searchUrl!,
      keyword: keyword,
      page: page,
      source: source,
    );

    if (searchUrl.startsWith('@js:') || searchUrl.startsWith('<js>')) {
      searchUrl = LegadoJsEngine().evaluate(searchUrl, variables: {
        'keyword': keyword,
        'page': page,
      });
    }

    final embedded = splitEmbeddedConfig(searchUrl);
    final resolved = resolveUrl(source.bookSourceUrl, embedded.url);
    if (embedded.config.isEmpty) return resolved;
    return '\$resolved,\${jsonEncode(embedded.config)}';
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
        headers[key.toString()] = value.toString();
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
    final bodyTemplate = config['body']?.toString();
    final body = bodyTemplate == null
        ? null
        : replaceVariables(
            bodyTemplate,
            keyword: keyword ?? '',
            page: page,
            source: source,
          );
    if (method == 'POST' &&
        body != null &&
        !headers.containsKey('Content-Type')) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }

    return LegadoHttpRequest(
      url: embedded.url,
      method: method,
      headers: headers.isEmpty ? null : headers,
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
    final sourceKey = _sourceValue(source, 'key');
    return _replaceEncodedPlaceholders(text)
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
        .replaceAll('{{searchKeyRaw}}', keyword)
        .replaceAll('{{page}}', page.toString())
        .replaceAll('{{source.key}}', sourceKey)
        .replaceAll('{{baseUrl}}', source?.bookSourceUrl ?? '')
        .replaceAll('{key}', encoded)
        .replaceAll('{keyword}', encoded)
        .replaceAll('{searchKey}', encoded)
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

    // 🚨 【修复核心】：拦截 JavaScript 规则，交由 JS 引擎执行
    if (text.startsWith('@js:') ||
        text.startsWith('<js>') ||
        text.contains('java.')) {
      try {
        final jsOutput = LegadoJsEngine().evaluate(text);
        if (jsOutput.isNotEmpty) {
          try {
            final json = jsonDecode(jsOutput);
            if (json is Map) {
              final jsHeaders = <String, dynamic>{};
              json.forEach((key, value) {
                jsHeaders[key.toString()] = value.toString();
              });
              return jsHeaders;
            }
          } catch (_) {}

          final jsHeaders = <String, dynamic>{};
          final normalized = jsOutput.replaceAll(r'\n', '\n');
          for (final line in normalized.split(RegExp(r'[\r\n]+'))) {
            final separator = line.indexOf(':');
            if (separator <= 0) continue;
            final key = line.substring(0, separator).trim();
            final value = line.substring(separator + 1).trim();
            if (key.isNotEmpty && value.isNotEmpty && !key.contains(' ') && !key.contains('=')) {
              jsHeaders[key] = value;
            }
          }
          if (jsHeaders.isNotEmpty) return jsHeaders;
        }
      } catch (e) {
        print('JS Header Eval Error: \$e');
      }
      return {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      };
    }

    try {
      final json = jsonDecode(text);
      if (json is Map) {
        json.forEach((key, value) {
          headers[key.toString()] = value.toString();
        });
        return headers;
      }
    } catch (_) {
      // Plain header lines are handled below.
    }

    final normalized = text.replaceAll(r'\n', '\n');
    for (final line in normalized.split(RegExp(r'[\r\n]+'))) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();

      // 🚨 【安全校验】：过滤掉包含空格或等号的非法 Key，防止 Dio 抛出 FormatException
      if (key.isNotEmpty &&
          value.isNotEmpty &&
          !key.contains(' ') &&
          !key.contains('=')) {
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
    if (!tail.startsWith('{') || !tail.endsWith('}')) {
      if (_looksLikeScript(tail)) {
        return (url: url.substring(0, comma), config: {});
      }
      return (url: url, config: {});
    }
    try {
      return (url: url.substring(0, comma), config: jsonConfig(tail));
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

  static String _sourceValue(BookSource? source, String key) {
    if (source == null) return '';
    final config = jsonConfig(source.customConfig);
    final direct = config[key] ?? config['source.$key'];
    if (direct != null) return direct.toString();
    if (key == 'key')
      return source.bookSourceUrl.replaceAll(RegExp(r'/+$'), '');
    return '';
  }
}
