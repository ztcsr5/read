import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';

/// 一次性 频控/反爬/404/empty 自动重试 1 次。
/// 配合 slow network:第一次请求在限速/限频/反爬页时,第二次往往能拿到正常页。
class RetryOnceInterceptor extends Interceptor {
  static const _retryableStatuses = {403, 429, 502, 503, 504};

  @override
  Future<void> onResponse(Response response, ResponseInterceptorHandler handler) async {
    final body = response.data;
    final isEmpty =
        body == null || (body is String && body.trim().isEmpty);
    final isAntiBot = body is String && _looksLikeAntiBot(body);
    final status = response.statusCode ?? 0;
    final isRetryable = _retryableStatuses.contains(status) || isEmpty || isAntiBot;
    if (!isRetryable) {
      handler.next(response);
      return;
    }
    // 退避 800ms,降低被打的概率
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final req = response.requestOptions;
    final dio = Dio(BaseOptions(
      baseUrl: req.baseUrl,
      connectTimeout: req.connectTimeout ?? const Duration(seconds: 20),
      receiveTimeout: req.receiveTimeout ?? const Duration(seconds: 20),
      headers: Map<String, dynamic>.from(req.headers),
      responseType: req.responseType,
      followRedirects: req.followRedirects,
      validateStatus: (s) => s != null && s < 600,
    ));
    try {
      final r = await dio.fetch<dynamic>(req);
      handler.resolve(r);
    } catch (e) {
      handler.next(response);
    }
  }

  static bool _looksLikeAntiBot(String s) {
    if (s.length > 5000) return false;
    final lower = s.toLowerCase();
    return lower.contains('请勿频繁') ||
        lower.contains('访问频繁') ||
        lower.contains('操作过于频繁') ||
        lower.contains('request too fast') ||
        lower.contains('rate limit') ||
        lower.contains('too many requests') ||
        lower.contains('captcha') ||
        lower.contains('验证') ||
        lower.contains('forbidden') ||
        lower.contains('access denied');
  }
}

/// 根据 Content-Type / HTML <meta charset> 智能选择编码
/// 解决 GBK / GB2312 / UTF-8 误判问题(典型如大美书网等老站)。
String decodeResponseBody({
  required List<int> bytes,
  required Headers headers,
  String? hintContentType,
}) {
  // 1. 优先用 Content-Type
  final ct = (hintContentType ??
          headers.value(HttpHeaders.contentTypeHeader) ??
          '')
      .toLowerCase();
  if (ct.contains('gbk') || ct.contains('gb2312') || ct.contains('gb18030')) {
    try {
      return gbk.decode(bytes);
    } catch (_) {}
  }
  if (ct.contains('utf-8') || ct.contains('utf8')) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {}
  }

  // 2. 扫前 4KB 找 BOM / meta charset
  final headLen = bytes.length > 4096 ? 4096 : bytes.length;
  final head = bytes.sublist(0, headLen);
  // UTF-8 BOM
  if (head.length >= 3 &&
      head[0] == 0xEF &&
      head[1] == 0xBB &&
      head[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  // UTF-16 LE/BE BOM
  if (head.length >= 2) {
    if (head[0] == 0xFF && head[1] == 0xFE) {
      return utf8.decode(bytes.sublist(2), allowMalformed: true);
    }
    if (head[0] == 0xFE && head[1] == 0xFF) {
      return utf8.decode(bytes.sublist(2), allowMalformed: true);
    }
  }
  // meta charset
  final headStr = _safeAscii(head);
  final m = RegExp(
    r'''charset\s*=\s*["']?\s*([A-Za-z0-9_\-]+)''',
    caseSensitive: false,
  ).firstMatch(headStr);
  if (m != null) {
    final enc = m.group(1)?.toLowerCase();
    if (enc != null) {
      if (enc == 'gbk' || enc == 'gb2312' || enc == 'gb18030') {
        try {
          return gbk.decode(bytes);
        } catch (_) {}
      }
      if (enc == 'utf-8' || enc == 'utf8') {
        try {
          return utf8.decode(bytes, allowMalformed: true);
        } catch (_) {}
      }
    }
  }

  // 3. 启发式:如果 UTF-8 解码出大量非法字符,fallback 到 GBK
  try {
    final utf8Str = utf8.decode(bytes, allowMalformed: true);
    // 中文网站常见字 '的'/'一' 在 GBK 下是合法字节,UTF-8 下不合法
    // 简单方法:尝试重新编 UTF-8,如果 byte 数差异巨大说明编码错
    if (_looksLikeMojibake(utf8Str, bytes)) {
      try {
        return gbk.decode(bytes);
      } catch (_) {}
    }
    return utf8Str;
  } catch (_) {
    try {
      return gbk.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }
}

String _safeAscii(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    if (b >= 0x20 && b < 0x7F) {
      sb.writeCharCode(b);
    } else {
      sb.write(' ');
    }
  }
  return sb.toString();
}

bool _looksLikeMojibake(String utf8Str, List<int> rawBytes) {
  // 简单启发:有大量 0xC2/0xC3 字节是 UTF-8 中文,
  // 出现大量 0xB0-0xF7 + 0xA1-0xFE 的双字节是 GBK,
  // 错把 GBK 当 UTF-8 时会产生  0xC2 + 0xXX (XX=0x80..0xBF) 这种"半字符"。
  if (utf8Str.contains('Ã') ||
      utf8Str.contains('Â') ||
      utf8Str.contains('Ä') ||
      utf8Str.contains('Å')) {
    return true;
  }
  return false;
}
