import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/parsers/source_import_link_parser.dart';
import '../viewmodels/book_source_viewmodel.dart';

class WebViewImportPage extends ConsumerStatefulWidget {
  final String? initialUrl;

  const WebViewImportPage({super.key, this.initialUrl});

  @override
  ConsumerState<WebViewImportPage> createState() => _WebViewImportPageState();
}

class _WebViewImportPageState extends ConsumerState<WebViewImportPage> {
  late final WebViewController _controller;
  late final TextEditingController _urlController;
  bool _isLoading = true;
  double _progress = 0;
  String? _message;
  SourceImportInput? _discoveredImport;

  @override
  void initState() {
    super.initState();
    final initialInput = widget.initialUrl?.trim() ?? '';
    _urlController = TextEditingController(text: initialInput);
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
              _message = null;
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _urlController.text = url;
            });
            _discoverImportCandidate();
          },
          onNavigationRequest: (request) {
            return _handleNavigation(request.url);
          },
        ),
      );
    if (initialInput.isEmpty) {
      _loadHelpPage();
    } else {
      _openInput(initialInput);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BookSourceState>(bookSourceViewModelProvider, (previous, next) {
      if (!context.mounted) return;
      final text = next.error ?? next.message;
      if (text == null ||
          text == previous?.error ||
          text == previous?.message) {
        return;
      }
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(next.error == null ? '完成' : '提示'),
          content: Text(text),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    });

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('浏览器导入'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _importCurrentPage,
          child: const Text('导入'),
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
                      placeholder: '输入网页或 JSON 地址',
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      clearButtonMode: OverlayVisibilityMode.editing,
                      onSubmitted: (_) => _loadAddress(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: _loadAddress,
                    child: const Text('打开'),
                  ),
                ],
              ),
            ),
            if (_isLoading || _progress < 1)
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            if (_message != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                color: CupertinoColors.systemYellow.withOpacity(0.18),
                child: Text(
                  _message!,
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
                  if (_discoveredImport != null)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      onPressed: _importDiscovered,
                      child: const Text('导入发现链接'),
                    ),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    onPressed: _importCurrentPage,
                    child: const Text('导入当前页 JSON'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  NavigationDecision _handleNavigation(String url) {
    final parsed = SourceImportLinkParser.parse(url);
    if (parsed.kind == SourceImportInputKind.url && parsed.value != url) {
      setState(() {
        _message = '已拦截导入链接，正在打开其中的 JSON/网页地址。若出现验证页，请完成验证后点底部导入。';
        _urlController.text = parsed.value;
        _discoveredImport = parsed;
      });
      _controller.loadRequest(Uri.parse(parsed.value));
      return NavigationDecision.prevent;
    }
    if (parsed.kind == SourceImportInputKind.unsupportedScheme) {
      setState(() => _message = '拦截到导入链接，但没有找到 src/url 参数。');
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  void _loadAddress() {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      _loadHelpPage();
      return;
    }
    _openInput(raw);
  }

  void _openInput(String input) {
    final parsed = SourceImportLinkParser.parse(input);
    switch (parsed.kind) {
      case SourceImportInputKind.empty:
        _loadHelpPage();
        break;
      case SourceImportInputKind.json:
        setState(() => _message = '识别到 JSON 文本，正在导入。');
        ref
            .read(bookSourceViewModelProvider.notifier)
            .importFromJson(parsed.value, originalUrl: 'webview-input');
        break;
      case SourceImportInputKind.url:
        setState(() {
          _message = null;
          _discoveredImport = null;
          _urlController.text = parsed.value;
        });
        _controller.loadRequest(Uri.parse(parsed.value));
        break;
      case SourceImportInputKind.unsupportedScheme:
        setState(() => _message = '识别到了导入协议，但没有找到 src/url 参数。');
        break;
      case SourceImportInputKind.unknown:
        final url = input.contains('://') ? input : 'https://$input';
        setState(() => _urlController.text = url);
        _controller.loadRequest(Uri.parse(url));
        break;
    }
  }

  void _loadHelpPage() {
    _controller.loadHtmlString('''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 28px; line-height: 1.55; color: #1c1c1e; }
    h1 { font-size: 28px; margin: 24px 0 16px; }
    p, li { font-size: 16px; color: #3a3a3c; }
    code { word-break: break-all; background: #f2f2f7; padding: 2px 5px; border-radius: 5px; }
  </style>
</head>
<body>
  <h1>通用书源导入</h1>
  <p>这里不会绑定任何默认仓库。你可以在上方输入或粘贴：</p>
  <ul>
    <li>网页分享地址</li>
    <li>HTTP/HTTPS JSON 地址</li>
    <li>阅读类导入链接，例如带 <code>src</code> 或 <code>url</code> 参数的链接</li>
  </ul>
  <p>如果网站出现验证页，请手动完成验证，再点底部“导入当前页 JSON”。</p>
</body>
</html>
''');
    setState(() {
      _isLoading = false;
      _progress = 1;
      _message = '请在上方粘贴任意书源分享页、JSON 地址或阅读导入链接。';
    });
  }

  Future<void> _importCurrentPage() async {
    setState(() => _message = '正在读取当前页面内容...');
    try {
      final result = await _controller.runJavaScriptReturningResult('''
(() => {
  const pre = document.querySelector('pre');
  if (pre && pre.innerText.trim()) return pre.innerText;
  const body = document.body ? document.body.innerText : '';
  return body || document.documentElement.innerText || '';
})()
''');
      final text = _normalizeJavaScriptResult(result).trim();
      if (text.isEmpty) {
        setState(() => _message = '当前页面没有可读取文本。');
        return;
      }
      if (!_looksLikeJson(text)) {
        final candidate = await _findCandidateInCurrentPage();
        if (candidate != null) {
          setState(() {
            _discoveredImport = candidate;
            _message = '当前页不是 JSON，但发现了可导入链接。可以点底部“导入发现链接”。';
          });
          return;
        }
        setState(() {
          _message = '当前页不是 JSON。请先进入书源 JSON 链接，或点网页里的“阅读导入/一键导入”。';
        });
        return;
      }
      await ref
          .read(bookSourceViewModelProvider.notifier)
          .importFromJson(text, originalUrl: _urlController.text.trim());
      if (!mounted) return;
      setState(() => _message = '已提交导入。');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '读取当前页失败：$e');
    }
  }

  Future<void> _discoverImportCandidate() async {
    final candidate = await _findCandidateInCurrentPage();
    if (!mounted || candidate == null) return;
    setState(() {
      _discoveredImport = candidate;
      _message = '页面里发现了可能的书源导入链接，可点底部“导入发现链接”。';
    });
  }

  Future<SourceImportInput?> _findCandidateInCurrentPage() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(r'''
(() => {
  const values = new Set();
  const push = (value) => {
    if (value && typeof value === 'string') values.add(value.trim());
  };
  const pushUrl = (value) => {
    if (!value || typeof value !== 'string') return;
    push(value);
    try { push(new URL(value, location.href).href); } catch (_) {}
  };
  document.querySelectorAll('a[href], button, [data-href], [data-url], [data-src]').forEach((el) => {
    pushUrl(el.getAttribute('href'));
    pushUrl(el.href);
    pushUrl(el.getAttribute('data-href'));
    pushUrl(el.getAttribute('data-url'));
    pushUrl(el.getAttribute('data-src'));
    push(el.getAttribute('onclick'));
    push(el.textContent);
  });
  document.querySelectorAll('script').forEach((script) => push(script.textContent));
  document.querySelectorAll('pre, code, textarea').forEach((el) => push(el.textContent || el.value));
  push(document.body ? document.body.innerText : '');
  push(location.href);
  return JSON.stringify(Array.from(values).slice(0, 200));
})()
''');
      final raw = _normalizeJavaScriptResult(result);
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      for (final value in decoded.whereType<String>()) {
        final parsed = SourceImportLinkParser.parse(value);
        if (_isLikelyImportCandidate(parsed, value)) {
          return parsed;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  bool _isLikelyImportCandidate(SourceImportInput parsed, String raw) {
    if (parsed.kind == SourceImportInputKind.json) return true;
    if (parsed.kind != SourceImportInputKind.url) return false;
    final text = '${parsed.value}\n$raw'.toLowerCase();
    return text.contains('.json') ||
        text.contains('booksource') ||
        text.contains('book-source') ||
        text.contains('source') ||
        text.contains('shuyuan') ||
        text.contains('import') ||
        text.contains('collection') ||
        text.contains('/sub') ||
        text.contains('yuedu') ||
        text.contains('legado');
  }

  Future<void> _importDiscovered() async {
    final candidate = _discoveredImport;
    if (candidate == null) return;
    switch (candidate.kind) {
      case SourceImportInputKind.json:
        await ref
            .read(bookSourceViewModelProvider.notifier)
            .importFromJson(
              candidate.value,
              originalUrl: _urlController.text.trim(),
            );
        break;
      case SourceImportInputKind.url:
        await ref
            .read(bookSourceViewModelProvider.notifier)
            .importFromUrl(candidate.value);
        break;
      case SourceImportInputKind.empty:
      case SourceImportInputKind.unsupportedScheme:
      case SourceImportInputKind.unknown:
        setState(() => _message = '发现的内容暂时不能直接导入。');
        return;
    }
    if (!mounted) return;
    setState(() => _message = '已提交发现链接导入。');
  }

  String _normalizeJavaScriptResult(Object? result) {
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

  bool _looksLikeJson(String text) {
    final trimmed = text.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }
}
