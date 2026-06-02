import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/routes.dart';
import '../../../ui/widgets/cloudflare_dialog.dart';
import 'legado_session_store.dart';

class CloudflareInterceptor extends Interceptor {
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
    final completer = Completer<bool>();
    late final WebViewController controller;

    final context = rootNavigatorKey.currentContext;
    bool dialogOpen = false;

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            try {
              final cookies = await controller.runJavaScriptReturningResult(
                'document.cookie',
              );
              final cookieStr = cookies.toString().replaceAll('"', '');
              if (cookieStr.isNotEmpty) {
                LegadoSessionStore.setCookieString(uri, cookieStr);
                LegadoSessionStore.persistHost(uri);
              }

              final ua = await controller.runJavaScriptReturningResult(
                'navigator.userAgent',
              );
              LegadoSessionStore.setUserAgent(
                uri,
                ua.toString().replaceAll('"', ''),
              );
              LegadoSessionStore.persistHost(uri);

              final content = await controller.runJavaScriptReturningResult(
                'document.documentElement.outerHTML',
              );
              final html = content.toString();
              final solved =
                  cookieStr.contains('cf_clearance') ||
                  (!html.contains('cf-browser-verification') &&
                      !html.contains('Just a moment') &&
                      !html.contains('/cdn-cgi/challenge-platform'));
              if (solved && !completer.isCompleted) {
                completer.complete(true);
                if (dialogOpen && context != null && context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                }
              }
            } catch (_) {
              // Keep waiting until timeout or a later navigation finishes.
            }
          },
        ),
      );

    Timer(const Duration(seconds: 45), () {
      if (!completer.isCompleted) {
        completer.complete(false);
        if (dialogOpen && context != null && context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    });

    await controller.loadRequest(uri);

    if (context != null && context.mounted) {
      dialogOpen = true;
      await showCupertinoDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => CloudflareDialog(controller: controller),
      );
      dialogOpen = false;
      if (!completer.isCompleted) {
        completer.complete(false); // User closed dialog manually
      }
    }

    final success = await completer.future;
    if (!success) {
      _returnOriginal(originalResponse, handler);
      return;
    }

    final dio = Dio();
    final options = originalResponse.requestOptions;
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
