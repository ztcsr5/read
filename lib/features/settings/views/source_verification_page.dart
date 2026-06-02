import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/models/book_source.dart';
import '../../../data/parsers/legado/legado_request_builder.dart';
import '../../../data/parsers/legado/legado_session_store.dart';

class SourceVerificationPage extends StatefulWidget {
  final BookSource source;
  final String? initialUrl;

  const SourceVerificationPage({
    super.key,
    required this.source,
    this.initialUrl,
  });

  @override
  State<SourceVerificationPage> createState() => _SourceVerificationPageState();
}

class _SourceVerificationPageState extends State<SourceVerificationPage> {
  late final WebViewController _controller;
  late final TextEditingController _urlController;
  bool _isLoading = true;
  double _progress = 0;
  String _message = '请在页面里完成验证码、登录或 Cloudflare 验证。完成后点右上角“完成”。';

  Uri get _currentUri {
    final text = _urlController.text.trim();
    return Uri.tryParse(text) ?? Uri.parse(_defaultUrl());
  }

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: widget.initialUrl ?? _defaultUrl(),
    );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress / 100);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _urlController.text = url;
              _message = '正在打开验证页...';
            });
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _urlController.text = url;
            });
            await _captureSession(silent: true);
          },
        ),
      );
    _open(_urlController.text);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('跳验证'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _finish,
          child: const Text('完成'),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      clearButtonMode: OverlayVisibilityMode.editing,
                      onSubmitted: _open,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: () => _open(_urlController.text),
                    child: const Text('打开'),
                  ),
                ],
              ),
            ),
            if (_isLoading || _progress < 1)
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: CupertinoColors.systemYellow.withOpacity(0.18),
              child: Text(
                _message,
                style: const TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel,
                ),
              ),
            ),
            Expanded(child: WebViewWidget(controller: _controller)),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: CupertinoColors.separator),
                ),
              ),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: () => _controller.goBack(),
                    child: const Icon(CupertinoIcons.chevron_left),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: () => _controller.goForward(),
                    child: const Icon(CupertinoIcons.chevron_right),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: () => _controller.reload(),
                    child: const Icon(CupertinoIcons.refresh),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: _clearSession,
                    child: const Text('清除'),
                  ),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    onPressed: _finish,
                    child: const Text('保存验证'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _defaultUrl() {
    final config = LegadoRequestBuilder.jsonConfig(widget.source.customConfig);
    final loginUrl = config['loginUrl']?.toString().trim();
    if (loginUrl != null && loginUrl.startsWith('http')) return loginUrl;
    final base = LegadoRequestBuilder.cleanBaseUrl(widget.source.bookSourceUrl);
    return base.startsWith('http') ? base : 'https://$base';
  }

  void _open(String input) {
    var url = input.trim();
    if (url.isEmpty) url = _defaultUrl();
    if (!url.contains('://')) url = 'https://$url';
    _urlController.text = url;
    _controller.loadRequest(Uri.parse(url));
  }

  Future<void> _finish() async {
    await _captureSession(silent: false);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _clearSession() async {
    await LegadoSessionStore.clearPersistedHost(_currentUri);
    if (!mounted) return;
    setState(() {
      _message = '已清除当前站点验证信息。可以重新完成验证后保存。';
    });
  }

  Future<void> _captureSession({required bool silent}) async {
    try {
      final cookieResult = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final uaResult = await _controller.runJavaScriptReturningResult(
        'navigator.userAgent',
      );
      final htmlResult = await _controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML',
      );
      final cookie = _jsString(cookieResult).trim();
      final ua = _jsString(uaResult).trim();
      final html = _jsString(htmlResult);
      final uri = _currentUri;
      if (cookie.isNotEmpty) {
        LegadoSessionStore.setCookieString(uri, cookie);
      }
      if (ua.isNotEmpty) {
        LegadoSessionStore.setUserAgent(uri, ua);
      }
      await LegadoSessionStore.persistHost(uri);
      if (!mounted || silent) return;
      setState(() {
        _message = _looksLikeChallenge(html)
            ? '仍然像验证页：请先在页面内完成验证，再点保存。'
            : '已保存当前站点 Cookie 和 User-Agent，返回后会自动重试书源请求。';
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() => _message = '保存验证信息失败：$e');
    }
  }

  String _jsString(Object? result) {
    if (result == null) return '';
    final raw = result.toString();
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is String) return decoded;
      } catch (_) {
        return raw.substring(1, raw.length - 1);
      }
    }
    return raw;
  }

  bool _looksLikeChallenge(String html) {
    return html.contains('/cdn-cgi/challenge-platform') ||
        html.contains('Just a moment') ||
        html.contains('cf-browser-verification') ||
        html.contains('challenge-form') ||
        html.contains('Enable JavaScript and cookies');
  }
}
