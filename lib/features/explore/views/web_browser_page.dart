import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/book.dart';
import '../../../data/models/book_source.dart';
import '../../../data/repositories/book_repository.dart';

class WebBrowserPage extends ConsumerStatefulWidget {
  final String? initialUrl;
  
  const WebBrowserPage({super.key, this.initialUrl});

  @override
  ConsumerState<WebBrowserPage> createState() => _WebBrowserPageState();
}

class _WebBrowserPageState extends ConsumerState<WebBrowserPage> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = true;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.initialUrl ?? 'https://m.baidu.com';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _progress = progress / 100.0;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _urlController.text = url;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_urlController.text));
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _extractNovel() async {
    const js = '''
    (function() {
      try {
        var pTags = document.getElementsByTagName("p");
        var content = "";
        var bestDiv = null;
        var maxWords = 0;
        
        // 启发式：寻找包含最多文字的 div/article 作为正文
        var divScores = new Map();
        for (var i = 0; i < pTags.length; i++) {
            var parent = pTags[i].parentNode;
            var words = (pTags[i].innerText || "").length;
            if (divScores.has(parent)) {
                divScores.set(parent, divScores.get(parent) + words);
            } else {
                divScores.set(parent, words);
            }
        }
        
        divScores.forEach(function(words, div) {
            if (words > maxWords) {
                maxWords = words;
                bestDiv = div;
            }
        });
        
        // 扩展兼容非 p 标签的大段落
        var brTags = document.getElementsByTagName("br");
        if (maxWords < 200 && brTags.length > 5) {
           var bodyText = document.body.innerText;
           if (bodyText.length > maxWords) {
              return JSON.stringify({
                  title: document.title || "未知章节",
                  content: document.body.innerHTML,
                  url: window.location.href
              });
           }
        }
        
        if (bestDiv != null) {
            content = bestDiv.innerHTML;
        } else {
            var article = document.querySelector('article') || document.querySelector('#content') || document.querySelector('.content');
            if (article) {
                content = article.innerHTML;
            } else {
                content = document.body.innerHTML; 
            }
        }
        
        return JSON.stringify({
            title: document.title || "网页提取章节",
            content: content,
            url: window.location.href
        });
      } catch (e) {
        return JSON.stringify({error: e.toString()});
      }
    })();
    ''';

    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CupertinoActivityIndicator()),
    );

    try {
      final result = await _controller.runJavaScriptReturningResult(js);
      if (mounted) Navigator.pop(context); // close dialog

      String jsonStr = result.toString();
      // 在 iOS WKWebView 中，返回的字符串首尾带有引号，需要去掉
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        jsonStr = jsonStr.substring(1, jsonStr.length - 1);
        jsonStr = jsonStr.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
      }

      final data = jsonDecode(jsonStr);
      if (data['error'] != null) {
        _showError('提取失败: ${data["error"]}');
        return;
      }

      final title = data['title'] as String;
      final rawContent = data['content'] as String;
      final url = data['url'] as String;

      // 创建一个临时的 Mock BookSource 和 Book
      final mockSource = BookSource(
        id: 'web_extract',
        name: '网页智能提取',
        sourceUrl: url,
        type: 0,
        enabled: true,
      )..ruleContent = 'body@html'; // 因为我们已经提取出 HTML，直接解析整个 body

      final mockBook = Book(
        id: 'web_${DateTime.now().millisecondsSinceEpoch}',
        sourceId: mockSource.id,
        title: title,
        author: '网页抓取',
        coverPath: '',
        filePath: url,
        intro: url,
        totalChapters: 1,
        isLocal: true,
      );
      mockBook.lastReadTime = DateTime.now();

      final bookRepo = ref.read(bookRepositoryProvider);
      await bookRepo.saveBook(mockBook);
      await bookRepo.saveBookSource(mockSource);

      if (mounted) {
        context.push('/reader/${mockBook.id}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // close dialog
      _showError('解析失败: $e');
    }
  }

  void _showError(String msg) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('错误'),
        content: Text(msg),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: SizedBox(
          height: 38,
          child: CupertinoTextField(
            controller: _urlController,
            placeholder: '输入网址并前往',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: Icon(CupertinoIcons.search, size: 20, color: CupertinoColors.systemGrey),
            ),
            clearButtonMode: OverlayVisibilityMode.editing,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (val) {
              if (val.isNotEmpty) {
                var url = val;
                if (!url.startsWith('http')) {
                  url = 'https://$url';
                }
                _controller.loadRequest(Uri.parse(url));
              }
            },
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_isLoading)
              SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: CupertinoColors.systemGrey5,
                  valueColor: const AlwaysStoppedAnimation(CupertinoColors.activeBlue),
                ),
              ),
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: CupertinoTheme.of(context).barBackgroundColor,
                border: const Border(
                  top: BorderSide(color: CupertinoColors.systemGrey4, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(CupertinoIcons.back),
                    onPressed: () async {
                      if (await _controller.canGoBack()) {
                        _controller.goBack();
                      } else if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(CupertinoIcons.forward),
                    onPressed: () async {
                      if (await _controller.canGoForward()) {
                        _controller.goForward();
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(CupertinoIcons.refresh),
                    onPressed: () => _controller.reload(),
                  ),
                  const Spacer(),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: const Row(
                      children: [
                        Icon(CupertinoIcons.doc_text_viewfinder, size: 20),
                        SizedBox(width: 6),
                        Text('智能提取正文', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    onPressed: _extractNovel,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
