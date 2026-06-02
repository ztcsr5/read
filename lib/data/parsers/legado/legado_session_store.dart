import 'package:dio/dio.dart';

class LegadoSessionStore {
  static final Map<String, Map<String, String>> _cookiesByHost = {};
  static final Map<String, String> _userAgentsByHost = {};

  static void apply(Uri uri, Map<String, dynamic> headers) {
    final key = _hostKey(uri);
    final cookieHeader = cookieHeaderFor(uri);
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      final existing = headers['Cookie']?.toString().trim();
      headers['Cookie'] = existing == null || existing.isEmpty
          ? cookieHeader
          : _mergeCookieHeaders(existing, cookieHeader);
    }
    final ua = _userAgentsByHost[key];
    if (ua != null && ua.isNotEmpty && !headers.containsKey('User-Agent')) {
      headers['User-Agent'] = ua;
    }
  }

  static void rememberResponse(Uri uri, Headers headers) {
    final values = headers.map.entries
        .where((entry) => entry.key.toLowerCase() == 'set-cookie')
        .expand((entry) => entry.value)
        .toList();
    for (final value in values) {
      setCookieString(uri, value);
    }
  }

  static void setCookieString(Uri uri, String rawCookie) {
    final host = _hostKey(uri);
    final jar = _cookiesByHost.putIfAbsent(host, () => <String, String>{});
    for (final part in rawCookie.split(';')) {
      final segment = part.trim();
      final equal = segment.indexOf('=');
      if (equal <= 0) continue;
      final name = segment.substring(0, equal).trim();
      final value = segment.substring(equal + 1).trim();
      if (name.isEmpty ||
          name.toLowerCase() == 'path' ||
          name.toLowerCase() == 'domain' ||
          name.toLowerCase() == 'expires' ||
          name.toLowerCase() == 'max-age' ||
          name.toLowerCase() == 'samesite') {
        continue;
      }
      jar[name] = value;
    }
  }

  static void setUserAgent(Uri uri, String userAgent) {
    final value = userAgent.trim();
    if (value.isEmpty) return;
    _userAgentsByHost[_hostKey(uri)] = value;
  }

  static String? userAgentFor(Uri uri) => _userAgentsByHost[_hostKey(uri)];

  static String? cookieHeaderFor(Uri uri) {
    final jar = _cookiesByHost[_hostKey(uri)];
    if (jar == null || jar.isEmpty) return null;
    return jar.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  static void clearHost(Uri uri) {
    final key = _hostKey(uri);
    _cookiesByHost.remove(key);
    _userAgentsByHost.remove(key);
  }

  static String _hostKey(Uri uri) => uri.host.toLowerCase();

  static String _mergeCookieHeaders(String existing, String incoming) {
    final merged = <String, String>{};
    void add(String header) {
      for (final part in header.split(';')) {
        final equal = part.indexOf('=');
        if (equal <= 0) continue;
        final name = part.substring(0, equal).trim();
        final value = part.substring(equal + 1).trim();
        if (name.isNotEmpty && value.isNotEmpty) merged[name] = value;
      }
    }

    add(existing);
    add(incoming);
    return merged.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }
}
