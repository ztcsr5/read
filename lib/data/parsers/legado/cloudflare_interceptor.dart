import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_cookie_manager/webview_cookie_manager.dart' as wcm;

import '../../../app/routes.dart';
import '../../../ui/widgets/cloudflare_dialog.dart';
import 'legado_session_store.dart';

class CloudflareInterceptor extends Interceptor {
  // 全局域名级 Completer 锁，防止并发请求导致 Cupertino 弹窗重叠死锁
  static final Map<String, Completer<bool>> _activeBypassCompleters = {};
  
  // 域名过盾成功时间戳缓存，用于实现过盾冷却保护，防止短时间连续高频弹窗
  static final Map<String, DateTime> _lastBypassSuccessTime = {};

  // 全局弹窗队列，防止不同域名并发请求导致多个 Cupertino 弹窗重叠 Navigator 冲突
  static final List<Completer<void>> _dialogQueue = [];
  static bool _isDialogShowing = false;

  static Future<void> _waitForDialogTurn() async {
    if (!_isDialogShowing) {
      _isDialogShowing = true;
      return;
    }
    final completer = Completer<void>();
    _dialogQueue.add(completer);
    await completer.future;
  }

  static void _releaseDialogTurn() {
    if (_dialogQueue.isNotEmpty) {
      final next = _dialogQueue.removeAt(0);
      next.complete();
    } else {
      _isDialogShowing = false;
    }
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    LegadoSessionStore.apply(options.uri, options.headers);
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    LegadoSessionStore.rememberResponse(response.realUri, response.headers);
    if (_isCloudflareChallenge(response)) {
      _bypassCloudflare(response, handler);
    } else {
      handler.next(response);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null && _isCloudflareChallenge(response)) {
      _bypassCloudflare(response, handler);
    } else {
      handler.next(err);
    }
  }

  bool _isCloudflareChallenge(Response response) {
    final statusCode = response.statusCode ?? 200;
    final data = response.data?.toString().toLowerCase() ?? '';
    
    final isChallengeHtml = data.contains('cf-browser-verification') ||
        data.contains('/cdn-cgi/challenge-platform') ||
        data.contains('challenge-form') ||
        data.contains('just a moment') ||
        data.contains('enable javascript and cookies') ||
        data.contains('ddos protection by cloudflare') ||
        data.contains('checking your browser') ||
        data.contains('百度安全验证');

    if (statusCode == 503 || statusCode == 403) {
      final serverHeader = response.headers.value('server')?.toLowerCase() ?? '';
      if (isChallengeHtml || serverHeader.contains('cloudflare') || serverHeader.contains('ddos-guard')) {
        return true;
      }
    }
    
    return isChallengeHtml;
  }

  Future<void> _bypassCloudflare(
    Response originalResponse,
    dynamic handler,
  ) async {
    final uri = originalResponse.requestOptions.uri;
    final host = uri.host.toLowerCase();

    // 1. 冷却时间保护逻辑：如果 15 秒内该域名刚刚成功过盾，则不重复弹窗，直接返回原始错误
    final lastSuccess = _lastBypassSuccessTime[host];
    if (lastSuccess != null && DateTime.now().difference(lastSuccess).inSeconds < 15) {
      _returnOriginal(originalResponse, handler);
      return;
    }

    Completer<bool>? activeCompleter;
    bool isInitiator = false;

    // 2. 检查该域名是否已经有过盾任务在执行
    if (_activeBypassCompleters.containsKey(host)) {
      activeCompleter = _activeBypassCompleters[host];
    } else {
      activeCompleter = Completer<bool>();
      _activeBypassCompleters[host] = activeCompleter;
      isInitiator = true;
    }

    bool success = false;

    if (isInitiator) {
      // 发起者请求：提取原始请求的 UA，注入 WebView 并拉起弹窗
      final originalHeaders = originalResponse.requestOptions.headers;
      final customUa = originalHeaders['User-Agent']?.toString() ?? 
                       originalHeaders['user-agent']?.toString();

      try {
        success = await _showBypassDialog(uri, customUa: customUa);
        if (success) {
          _lastBypassSuccessTime[host] = DateTime.now(); // 记录过盾成功时间戳
        }
        activeCompleter!.complete(success);
      } catch (e) {
        activeCompleter!.complete(false);
      } finally {
        // 完成后移除锁
        _activeBypassCompleters.remove(host);
      }
    } else {
      // 并发跟随请求：原地等待发起者的过盾结果，直接复用其成果
      success = await activeCompleter!.future;
    }

    if (!success) {
      _returnOriginal(originalResponse, handler);
      return;
    }

    // 重试原网络请求
    final dio = Dio();
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (_, _, _) => true;
        return client;
      },
    );

    final options = originalResponse.requestOptions;
    // 注入最新成功获取到的 Cookie 与 User-Agent
    LegadoSessionStore.apply(options.uri, options.headers);
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
  }

  Future<bool> _showBypassDialog(Uri uri, {String? customUa}) async {
    final completer = Completer<bool>();
    late final WebViewController controller;

    final context = rootNavigatorKey.currentContext;
    bool dialogOpen = false;

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);

    // 关键安全点：如果原始网络请求配置了自定义 User-Agent，强制 WebView 使用该 UA 以保证人机挑战绑定 UA 的一致性
    if (customUa != null && customUa.isNotEmpty) {
      await controller.setUserAgent(customUa);
      LegadoSessionStore.setUserAgent(uri, customUa);
    }

    controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            try {
              // 1. 若原始请求没有 UA，则提取 Webview 的默认 User-Agent 进行同步
              if (customUa == null || customUa.isEmpty) {
                final ua = await controller.runJavaScriptReturningResult(
                  'navigator.userAgent',
                );
                final uaStr = ua.toString().replaceAll('"', '').trim();
                if (uaStr.isNotEmpty) {
                  LegadoSessionStore.setUserAgent(uri, uaStr);
                }
              }

              // 2. 利用 WebviewCookieManager 提取包含 HttpOnly 属性的完整 Cookie 环
              final cookieManager = wcm.WebviewCookieManager();
              final gotCookies = await cookieManager.getCookies(uri.toString());
              
              String cookieStr = '';
              bool hasCfClearance = false;
              if (gotCookies.isNotEmpty) {
                cookieStr = gotCookies.map((c) => '${c.name}=${c.value}').join('; ');
                hasCfClearance = gotCookies.any((c) => c.name == 'cf_clearance');
                LegadoSessionStore.setCookieString(uri, cookieStr);
              } else {
                final jsCookies = await controller.runJavaScriptReturningResult(
                  'document.cookie',
                );
                cookieStr = jsCookies.toString().replaceAll('"', '').trim();
                if (cookieStr.isNotEmpty) {
                  LegadoSessionStore.setCookieString(uri, cookieStr);
                }
              }

              final content = await controller.runJavaScriptReturningResult(
                'document.documentElement.outerHTML',
              );
              final html = content.toString();
              
              final solved = hasCfClearance ||
                  (cookieStr.contains('cf_clearance') ||
                  (!html.contains('cf-browser-verification') &&
                      !html.contains('Just a moment') &&
                      !html.contains('/cdn-cgi/challenge-platform') &&
                      !html.contains('ddos protection by cloudflare') &&
                      !html.contains('checking your browser') &&
                      !html.contains('百度安全验证')));

              if (solved && !completer.isCompleted) {
                await LegadoSessionStore.persistHost(uri);
                completer.complete(true);
                if (dialogOpen && context != null && context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                }
              }
            } catch (_) {
              // 忽略 JS 执行异常，继续等待页面完成或用户手动过盾
            }
          },
        ),
      );

    // 45 秒兜底超时器，确保 Completer 无论如何都会被解决，杜绝网络死锁
    final timeoutTimer = Timer(const Duration(seconds: 45), () {
      if (!completer.isCompleted) {
        completer.complete(false);
        if (dialogOpen && context != null && context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    });

    try {
      await controller.loadRequest(uri);

      if (context != null && context.mounted) {
        if (completer.isCompleted) {
          timeoutTimer.cancel();
          return completer.future;
        }
        await _waitForDialogTurn();
        try {
          if (completer.isCompleted) {
            timeoutTimer.cancel();
            return completer.future;
          }
          dialogOpen = true;
          await showCupertinoDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => CloudflareDialog(controller: controller),
          );
        } finally {
          dialogOpen = false;
          _releaseDialogTurn();
        }
        if (!completer.isCompleted) {
          completer.complete(false); // 用户手动关闭弹窗
        }
      }
    } catch (_) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    } finally {
      timeoutTimer.cancel();
    }

    return completer.future;
  }

  void _returnOriginal(Response originalResponse, dynamic handler) {
    if (handler is ErrorInterceptorHandler) {
      handler.next(
        DioException(
          requestOptions: originalResponse.requestOptions,
          response: originalResponse,
        ),
      );
    } else if (handler is ResponseInterceptorHandler) {
      handler.next(originalResponse);
    }
  }
}
