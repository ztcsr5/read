import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/cupertino.dart';
import 'package:webview_cookie_manager/webview_cookie_manager.dart' as wcm;
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/routes.dart';
import '../../../ui/widgets/cloudflare_dialog.dart';
import 'legado_session_store.dart';

class CloudflareChallengeQueue {
  CloudflareChallengeQueue._();

  static final CloudflareChallengeQueue instance = CloudflareChallengeQueue._();

  final Map<String, Completer<bool>> _activeByHost = {};
  final Map<String, DateTime> _lastSuccessByHost = {};
  final List<Completer<void>> _dialogQueue = [];
  bool _isDialogShowing = false;

  bool isCoolingDown(
    String host, {
    Duration cooldown = const Duration(seconds: 15),
  }) {
    final lastSuccess = _lastSuccessByHost[host.toLowerCase()];
    return lastSuccess != null &&
        DateTime.now().difference(lastSuccess) < cooldown;
  }

  Future<bool> runForHost(String host, Future<bool> Function() task) async {
    final normalizedHost = host.toLowerCase();
    final active = _activeByHost[normalizedHost];
    if (active != null) return active.future;

    final completer = Completer<bool>();
    _activeByHost[normalizedHost] = completer;
    try {
      final success = await task();
      if (success) _lastSuccessByHost[normalizedHost] = DateTime.now();
      if (!completer.isCompleted) completer.complete(success);
      return success;
    } catch (_) {
      if (!completer.isCompleted) completer.complete(false);
      return false;
    } finally {
      _activeByHost.remove(normalizedHost);
    }
  }

  Future<T> runDialog<T>(Future<T> Function() task) async {
    await _waitForDialogTurn();
    try {
      return await task();
    } finally {
      _releaseDialogTurn();
    }
  }

  Future<void> _waitForDialogTurn() async {
    if (!_isDialogShowing) {
      _isDialogShowing = true;
      return;
    }
    final completer = Completer<void>();
    _dialogQueue.add(completer);
    await completer.future;
  }

  void _releaseDialogTurn() {
    if (_dialogQueue.isNotEmpty) {
      final next = _dialogQueue.removeAt(0);
      next.complete();
    } else {
      _isDialogShowing = false;
    }
  }
}

class CloudflareInterceptor extends Interceptor {
  static final CloudflareChallengeQueue _queue =
      CloudflareChallengeQueue.instance;

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
    final serverHeader = response.headers.value('server')?.toLowerCase() ?? '';

    final isChallengeHtml =
        data.contains('cf-browser-verification') ||
        data.contains('/cdn-cgi/challenge-platform') ||
        data.contains('challenge-form') ||
        data.contains('just a moment') ||
        data.contains('enable javascript and cookies') ||
        data.contains('ddos protection by cloudflare') ||
        data.contains('checking your browser') ||
        data.contains('\u767e\u5ea6\u5b89\u5168\u9a8c\u8bc1');

    if (statusCode == 503 || statusCode == 403) {
      return isChallengeHtml ||
          serverHeader.contains('cloudflare') ||
          serverHeader.contains('ddos-guard');
    }

    return isChallengeHtml;
  }

  Future<void> _bypassCloudflare(
    Response originalResponse,
    dynamic handler,
  ) async {
    final uri = originalResponse.requestOptions.uri;
    final host = uri.host.toLowerCase();

    if (_queue.isCoolingDown(host)) {
      _returnOriginal(originalResponse, handler);
      return;
    }

    final success = await _queue.runForHost(host, () async {
      final originalHeaders = originalResponse.requestOptions.headers;
      final customUa =
          originalHeaders['User-Agent']?.toString() ??
          originalHeaders['user-agent']?.toString();
      return _showBypassDialog(uri, customUa: customUa);
    });

    if (!success) {
      _returnOriginal(originalResponse, handler);
      return;
    }

    final dio = Dio();
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (_, _, _) => true;
        return client;
      },
    );

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

  Future<bool> _showBypassDialog(Uri uri, {String? customUa}) async {
    final completer = Completer<bool>();
    final context = rootNavigatorKey.currentContext;
    var dialogOpen = false;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);

    if (customUa != null && customUa.isNotEmpty) {
      await controller.setUserAgent(customUa);
      LegadoSessionStore.setUserAgent(uri, customUa);
    }

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) async {
          try {
            if (customUa == null || customUa.isEmpty) {
              final ua = await controller.runJavaScriptReturningResult(
                'navigator.userAgent',
              );
              final uaStr = ua.toString().replaceAll('"', '').trim();
              if (uaStr.isNotEmpty) {
                LegadoSessionStore.setUserAgent(uri, uaStr);
              }
            }

            final cookieManager = wcm.WebviewCookieManager();
            final gotCookies = await cookieManager.getCookies(uri.toString());

            var cookieStr = '';
            var hasCfClearance = false;
            if (gotCookies.isNotEmpty) {
              cookieStr = gotCookies
                  .map((c) => '${c.name}=${c.value}')
                  .join('; ');
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
            final html = content.toString().toLowerCase();

            final solved =
                hasCfClearance ||
                cookieStr.contains('cf_clearance') ||
                (!html.contains('cf-browser-verification') &&
                    !html.contains('just a moment') &&
                    !html.contains('/cdn-cgi/challenge-platform') &&
                    !html.contains('ddos protection by cloudflare') &&
                    !html.contains('checking your browser'));

            if (solved && !completer.isCompleted) {
              await LegadoSessionStore.persistHost(uri);
              completer.complete(true);
              if (dialogOpen && context != null && context.mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }
            }
          } catch (_) {}
        },
      ),
    );

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
        await _queue.runDialog(() async {
          if (completer.isCompleted) {
            timeoutTimer.cancel();
            return;
          }
          dialogOpen = true;
          try {
            await showCupertinoDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => CloudflareDialog(controller: controller),
            );
          } finally {
            dialogOpen = false;
          }
        });
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      } else if (!completer.isCompleted) {
        completer.complete(false);
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
