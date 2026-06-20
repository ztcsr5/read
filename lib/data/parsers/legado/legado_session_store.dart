import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LegadoSessionStore {
  static const _prefsKey = 'legado.host.sessions.v1';
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
    if (ua != null && ua.isNotEmpty) {
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

  static String? userAgentFor(Uri uri) {
    final host = _hostKey(uri);
    for (final domain in _parentDomains(host)) {
      final ua = _userAgentsByHost[domain];
      if (ua != null && ua.isNotEmpty) return ua;
    }
    return null;
  }

  static String? cookieHeaderFor(Uri uri) {
    final host = _hostKey(uri);
    final merged = <String, String>{};
    for (final domain in _parentDomains(host)) {
      final jar = _cookiesByHost[domain];
      if (jar != null) {
        jar.forEach((name, value) => merged[name] = value);
      }
    }
    if (merged.isEmpty) return null;
    return merged.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  static bool hasSessionFor(Uri uri) {
    final host = _hostKey(uri);
    for (final domain in _parentDomains(host)) {
      if ((_cookiesByHost[domain]?.isNotEmpty ?? false) ||
          (_userAgentsByHost[domain]?.isNotEmpty ?? false)) {
        return true;
      }
    }
    return false;
  }

  static void clearHost(Uri uri) {
    final key = _hostKey(uri);
    _cookiesByHost.remove(key);
    _userAgentsByHost.remove(key);
  }

  static Future<void> restorePersistedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((host, value) {
        if (value is! Map) return;
        final cookies = value['cookies'];
        final ua = value['userAgent'];
        if (cookies is Map) {
          _cookiesByHost[host.toString()] = cookies.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          );
        }
        if (ua is String && ua.trim().isNotEmpty) {
          _userAgentsByHost[host.toString()] = ua.trim();
        }
      });
    } catch (_) {
      // Session persistence is best-effort.
    }
  }

  static Future<void> persistHost(Uri uri) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = _hostKey(uri);
      final raw = prefs.getString(_prefsKey);
      final decoded = raw == null || raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      data[host] = {
        'cookies': _cookiesByHost[host] ?? const <String, String>{},
        'userAgent': _userAgentsByHost[host] ?? '',
      };
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (_) {
      // Session persistence is best-effort.
    }
  }

  static Future<void> clearPersistedHost(Uri uri) async {
    clearHost(uri);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final data = decoded.map((key, value) => MapEntry(key.toString(), value));
      data.remove(_hostKey(uri));
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (_) {
      // Session persistence is best-effort.
    }
  }

  static String _hostKey(Uri uri) => uri.host.toLowerCase();

  /// 返回 host 本身 + 所有父域名,用于 Cookie/UA 父域名匹配。
  /// 例如 www.example.com → [www.example.com, example.com]
  ///      m.example.com → [m.example.com, example.com]
  ///      example.com → [example.com]
  /// 单部分域名(如 localhost)只返回自身。
  static List<String> _parentDomains(String host) {
    final parts = host.split('.');
    if (parts.length <= 2) return [host];
    final domains = <String>[];
    for (var i = 0; i < parts.length - 1; i++) {
      domains.add(parts.sublist(i).join('.'));
    }
    return domains;
  }

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
