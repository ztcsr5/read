import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CloudflareInterceptor extends Interceptor {
  // 缓存提取到的 Cookie 和 UA
  static final Map<String, String> _clearanceCookies = {};
  static final Map<String, String> _userAgents = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final host = options.uri.host;
    if (_clearanceCookies.containsKey(host)) {
      final existingCookie = options.headers['Cookie'] as String? ?? '';
      final cfCookie = _clearanceCookies[host]!;
      if (!existingCookie.contains(cfCookie)) {
        options.headers['Cookie'] = existingCookie.isEmpty
            ? cfCookie
            : '\$existingCookie; \$cfCookie';
      }
    }
    if (_userAgents.containsKey(host)) {
      options.headers['User-Agent'] = _userAgents[host];
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // 检查是否是被拦截的 CF 页面
    if (_isCloudflareChallenge(response)) {
      _bypassCloudflare(response, handler);
    } else {
      handler.next(response);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response != null && _isCloudflareChallenge(err.response!)) {
      _bypassCloudflare(err.response!, handler);
    } else {
      handler.next(err);
    }
  }

  bool _isCloudflareChallenge(Response response) {
    if (response.statusCode == 503 || response.statusCode == 403) {
      final data = response.data?.toString() ?? '';
      return data.contains('cf-browser-verification') ||
          data.contains('Just a moment') ||
          data.contains('/cdn-cgi/challenge-platform');
    }
    return false;
  }

  void _bypassCloudflare(Response originalResponse, dynamic handler) async {
    final url = originalResponse.requestOptions.uri.toString();
    final host = originalResponse.requestOptions.uri.host;
    
    print('🚨 触发 Cloudflare 5秒盾，尝试使用 WebView 嗅探: \$url');

    final completer = Completer<bool>();
    late final WebViewController controller;

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String currentUrl) async {
            // 检查是否拿到 cf_clearance
            try {
              final cookies = await controller.runJavaScriptReturningResult('document.cookie');
              final cookieStr = (cookies as String).replaceAll('"', '');
              
              if (cookieStr.contains('cf_clearance')) {
                final cfCookieMatch = RegExp(r'cf_clearance=[^;]+').firstMatch(cookieStr);
                if (cfCookieMatch != null) {
                  _clearanceCookies[host] = cfCookieMatch.group(0)!;
                  final ua = await controller.runJavaScriptReturningResult('navigator.userAgent');
                  _userAgents[host] = (ua as String).replaceAll('"', '');
                  print('✅ 成功提取 cf_clearance: \${_clearanceCookies[host]}');
                  if (!completer.isCompleted) completer.complete(true);
                }
              } else {
                // 判断页面内容是否已经跳过了 challenge
                final content = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
                if (!content.toString().contains('cf-browser-verification') && 
                    !content.toString().contains('Just a moment')) {
                  print('✅ 页面似乎已跳过 CF 盾，但未找到 cf_clearance');
                  if (!completer.isCompleted) completer.complete(false);
                }
              }
            } catch (e) {
              print('WebView 嗅探异常: \$e');
            }
          },
        ),
      );

    // 设置超时 15 秒
    Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        print('❌ Cloudflare 嗅探超时');
        completer.complete(false);
      }
    });

    await controller.loadRequest(Uri.parse(url));
    
    final success = await completer.future;

    if (success) {
      // 重试原请求
      final dio = Dio();
      final options = originalResponse.requestOptions;
      
      final existingCookie = options.headers['Cookie'] as String? ?? '';
      final cfCookie = _clearanceCookies[host]!;
      options.headers['Cookie'] = existingCookie.isEmpty
          ? cfCookie
          : '\$existingCookie; \$cfCookie';
      options.headers['User-Agent'] = _userAgents[host];

      try {
        final retryResponse = await dio.fetch(options);
        if (handler is ErrorInterceptorHandler) {
          handler.resolve(retryResponse);
        } else if (handler is ResponseInterceptorHandler) {
          handler.next(retryResponse);
        }
      } on DioException catch (e) {
        if (handler is ErrorInterceptorHandler) {
          handler.next(e);
        } else if (handler is ResponseInterceptorHandler) {
          handler.next(e.response ?? originalResponse);
        }
      }
    } else {
      // 失败，返回原响应
      if (handler is ErrorInterceptorHandler) {
        handler.next(DioException(requestOptions: originalResponse.requestOptions, response: originalResponse));
      } else if (handler is ResponseInterceptorHandler) {
        handler.next(originalResponse);
      }
    }
  }
}
