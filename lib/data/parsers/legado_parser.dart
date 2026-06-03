import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/material.dart' hide Element;
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:json_path/json_path.dart';
import 'package:webview_cookie_manager/webview_cookie_manager.dart' as wcm;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xml/xml.dart' as xml;

import '../../app/routes.dart';
import '../models/book.dart';
import '../models/book_source.dart';
import '../models/chapter.dart';
import '../models/rss_article.dart';
import '../models/rss_source.dart';
import 'legado/cloudflare_interceptor.dart';
import 'legado/legado_js_engine.dart';
import 'legado/legado_request_builder.dart';
import 'legado/legado_rule_evaluator.dart';
import 'legado/legado_session_store.dart';

class LegadoVerificationRequiredException implements Exception {
  final String sourceName;
  final String url;
  final int? statusCode;
  final String message;

  const LegadoVerificationRequiredException({
    required this.sourceName,
    required this.url,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() {
    final status = statusCode == null ? '' : ' HTTP $statusCode';
    return '需要跳验证$status: $sourceName $url $message';
  }
}

/// 基础的开源阅读 (Legado) 规则解析器。
class LegadoParser {
  static final Dio _dio = _createDio();
  static final Map<String, String> _jsLibraryCache = <String, String>{};

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (status) => status != null && status < 600,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
        },
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (_, _, _) => true;
        return client;
      },
    );
    dio.interceptors.add(CloudflareInterceptor());
    return dio;
  }

  /// 从搜索到正文逐步测试书源，方便定位是哪一段规则失效。
  static Future<LegadoTestReport> testSource(
    BookSource source,
    String keyword,
  ) async {
    final steps = <LegadoTestStep>[];

    try {
      if (source.searchUrl == null || source.searchUrl!.isEmpty) {
        steps.add(const LegadoTestStep.fail('搜索 URL', 'searchUrl 为空'));
        return LegadoTestReport(steps: steps);
      }

      final searchUrl = await _buildSearchUrlAsync(source, keyword);
      steps.add(LegadoTestStep.ok('搜索 URL', searchUrl));

      if (_containsJsRule(source.searchUrl) ||
          _containsJsRule(source.ruleSearch) ||
          _containsJsRule(source.ruleBookInfo) ||
          _containsJsRule(source.ruleToc) ||
          _containsJsRule(source.ruleContent)) {
        steps.add(
          const LegadoTestStep.ok(
            'JS 引擎',
            '检测到 @js/<js>/java.* 规则，将使用 QuickJS 引擎执行。',
          ),
        );
      }

      final searchResponse = await _request(
        source,
        searchUrl,
        keyword: keyword,
      );
      steps.add(
        LegadoTestStep.ok(
          '请求搜索页',
          'HTTP ${searchResponse.statusCode}',
          sample: _sample(searchResponse.data),
        ),
      );

      final books = await searchBooks(source, keyword);
      if (books.isEmpty) {
        steps.add(
          const LegadoTestStep.fail(
            '搜索结果',
            '没有解析出书籍，请检查 ruleSearch.bookList/name/bookUrl',
          ),
        );
        return LegadoTestReport(steps: steps);
      }

      var firstBook = books.first;
      steps.add(
        LegadoTestStep.ok(
          '搜索结果',
          '解析到 ${books.length} 本，首本：${firstBook.title}',
          sample: '${firstBook.title}\n${firstBook.filePath}',
        ),
      );

      if (source.ruleBookInfo != null && source.ruleBookInfo!.isNotEmpty) {
        final detail = await parseBookInfo(source, firstBook);
        firstBook = detail;
        steps.add(
          LegadoTestStep.ok(
            '书籍详情',
            detail.title,
            sample: detail.coverPath ?? detail.filePath,
          ),
        );
      } else {
        steps.add(
          const LegadoTestStep.skip('书籍详情', '未配置 ruleBookInfo，使用搜索结果里的详情链接'),
        );
      }

      final chapters = await getChapterList(source, firstBook);
      if (chapters.isEmpty) {
        steps.add(
          const LegadoTestStep.fail(
            '目录',
            '没有解析出章节，请检查 ruleToc.chapterList/chapterName/chapterUrl',
          ),
        );
        return LegadoTestReport(steps: steps);
      }

      steps.add(
        LegadoTestStep.ok(
          '目录',
          '解析到 ${chapters.length} 章，首章：${chapters.first.title}',
          sample:
              '${chapters.first.title}\n${chapters.first.content ?? chapters.first.url ?? ''}',
        ),
      );

      final chapterUrl = chapters.first.content ?? chapters.first.url ?? '';
      if (chapterUrl.trim().isEmpty) {
        steps.add(
          const LegadoTestStep.fail(
            '正文',
            '章节链接解析为空，请检查 ruleToc.chapterUrl',
          ),
        );
        return LegadoTestReport(steps: steps);
      }

      final content = await getChapterContent(source, chapterUrl);
      if (content.isEmpty) {
        steps.add(const LegadoTestStep.fail('正文', '没有解析出正文内容'));
      } else {
        steps.add(
          LegadoTestStep.ok('正文', '首章正文解析成功', sample: _sample(content)),
        );
      }
    } catch (e) {
      steps.add(LegadoTestStep.fail('异常', e.toString()));
    }

    return LegadoTestReport(steps: steps);
  }

  /// 搜索书籍。
  static Future<List<Book>> searchBooks(
    BookSource source,
    String keyword,
  ) async {
    final firstPage = await _searchBooksPage(source, keyword, page: 1);
    if (firstPage.isNotEmpty ||
        !(source.searchUrl?.contains('page') ?? false)) {
      return firstPage;
    }
    return _searchBooksPage(source, keyword, page: 0);
  }

  static Future<List<Book>> _searchBooksPage(
    BookSource source,
    String keyword, {
    required int page,
  }) async {
    if (source.searchUrl == null || source.ruleSearch == null) return [];

    final response = await _request(
      source,
      await _buildSearchUrlAsync(source, keyword, page: page),
      keyword: keyword,
    );
    var data = response.data;

    final rule = _ruleMap(source.ruleSearch);
    var bookListRule = _firstRule(rule, const ['bookList', 'list']);
    if (bookListRule != null) {
      final prepared = await _prepareDataForRule(
        source,
        data,
        bookListRule,
        baseUrl: response.realUri.toString(),
        keyword: keyword,
      );
      data = prepared.data;
      bookListRule = prepared.rule;
    }

    final results = <Book>[];
    if ((bookListRule == null || bookListRule.isEmpty) &&
        _looksLikeJsonData(data, null)) {
      return _parseBooksByJsonFallback(data, rule, source);
    }
    if (bookListRule != null &&
        _isJsonRule(bookListRule) &&
        _looksLikeJsonData(data, bookListRule)) {
      try {
        final jsonData = data is String ? jsonDecode(data) : data;
        final nodes = _extractJsonNodes(jsonData, bookListRule);
        for (final node in nodes) {
          if (node is Map<String, dynamic>) {
            results.add(_parseBookFromJson(node, rule, source));
          } else if (node is Map) {
            results.add(
              _parseBookFromJson(
                node.map((key, value) => MapEntry(key.toString(), value)),
                rule,
                source,
              ),
            );
          }
        }
        if (results.isNotEmpty) return results;
        return _parseBooksByJsonFallback(data, rule, source);
      } catch (_) {
        return _parseBooksByJsonFallback(data, rule, source);
      }
    }

    if (bookListRule == null || _looksLikeJsonData(data, bookListRule)) {
      return _parseBooksByJsonFallback(data, rule, source);
    }

    final document = parse(data.toString());
    final nodes = _queryAll(document, bookListRule);
    for (final node in nodes) {
      results.add(_parseBookFromHtmlNode(node, rule, source));
    }

    return results.where((book) => book.title.trim().isNotEmpty).toList();
  }

  /// 获取书籍详情信息。
  static Future<Book> parseBookInfo(BookSource source, Book book) async {
    if (source.ruleBookInfo == null || source.ruleBookInfo!.isEmpty) {
      return book;
    }

    final rule = _ruleMap(source.ruleBookInfo);
    final response = await _request(source, book.filePath);
    var data = response.data;
    final initRule = _firstRule(rule, const ['init']);
    final preparedInit = initRule == null
        ? null
        : await _prepareDataForRule(
            source,
            data,
            initRule,
            baseUrl: response.realUri.toString(),
          );
    if (preparedInit != null) {
      data = preparedInit.data;
    }
    final sampleRule = preparedInit?.rule.isNotEmpty == true
        ? preparedInit!.rule
        : initRule ?? rule.values.whereType<String>().firstOrNull ?? '';

    if (_isJsonRule(sampleRule) && _looksLikeJsonData(data, sampleRule)) {
      final jsonData = data is String ? jsonDecode(data) : data;
      final root = initRule == null || sampleRule.isEmpty
          ? jsonData
          : _extractJsonNodes(jsonData, sampleRule).firstOrNull ?? jsonData;
      if (root is Map<String, dynamic>) {
        return _mergeBookInfo(
          book,
          _parseBookFromJson(root, rule, source, baseUrl: book.filePath, isBookInfo: true),
        );
      } else if (root is Map) {
        return _mergeBookInfo(
          book,
          _parseBookFromJson(
            _stringKeyMap(root),
            rule,
            source,
            baseUrl: book.filePath,
            isBookInfo: true,
          ),
        );
      }
      return book;
    }

    final document = parse(data.toString());
    final root = initRule == null || sampleRule.isEmpty
        ? document.documentElement ?? document.body
        : _queryOne(document, sampleRule) ??
              document.documentElement ??
              document.body;
    if (root == null) return book;

    return _mergeBookInfo(
      book,
      _parseBookFromHtmlNode(root, rule, source, baseUrl: book.filePath, isBookInfo: true),
    );
  }

  /// 获取目录。
  static Future<List<Chapter>> getChapterList(
    BookSource source,
    Book book, {
    int? limit,
  }) async {
    final ruleTocStr = source.ruleToc;
    if (ruleTocStr == null) return [];

    final rule = _ruleMap(ruleTocStr);
    var listRule = _firstRule(rule, const ['chapterList', 'list']);
    if (listRule == null) return [];

    final chapters = <Chapter>[];
    final visitedUrls = <String>{};

    var currentResponse = await _request(source, book.filePath);
    currentResponse = await _followTocUrl(source, book.filePath, currentResponse, rule);
    
    var currentUrlStr = currentResponse.realUri.toString();
    currentUrlStr = currentUrlStr
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll('%0A', '')
        .replaceAll('%0D', '')
        .replaceAll('%0a', '')
        .replaceAll('%0d', '')
        .trim();
    
    var data = currentResponse.data;

    while (true) {
      if (currentUrlStr.isEmpty || visitedUrls.contains(currentUrlStr)) {
        break;
      }
      visitedUrls.add(currentUrlStr);

      final prepared = await _prepareDataForRule(
        source,
        data,
        listRule,
        baseUrl: currentUrlStr,
      );
      final pageData = prepared.data;
      final pageListRule = prepared.rule;

      final pageChapters = <Chapter>[];
      if (pageListRule.isEmpty && _looksLikeJsonData(pageData, null)) {
        pageChapters.addAll(_parseChaptersByJsonFallback(
          pageData,
          rule,
          source,
          book,
          currentUrlStr,
          limit: limit,
        ));
      } else if (_isJsonRule(pageListRule) && _looksLikeJsonData(pageData, pageListRule)) {
        try {
          final jsonData = pageData is String ? jsonDecode(pageData) : pageData;
          var index = chapters.length;
          for (final node in _extractJsonNodes(jsonData, pageListRule)) {
            if (limit != null && (chapters.length + pageChapters.length) >= limit) break;
            if (node is! Map) continue;
            final item = node.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            
            var titleRule = _firstRule(rule, const [
                  'chapterName',
                  'name',
                  'title',
                  'ChapterName',
                  'N',
                ]) ??
                '';
            if (titleRule.trim().isEmpty) titleRule = 'title';
            final title = _extractJsonValue(
              item,
              _sourceScopedRule(titleRule, source),
            );
            
            var urlRule = _firstRule(rule, const [
                  'chapterUrl',
                  'url',
                  'link',
                  'ChapterUrl',
                  'C',
                ]) ??
                '';
            if (urlRule.trim().isEmpty) urlRule = 'url';
            final url = _extractJsonValue(
              item,
              _sourceScopedRule(urlRule, source),
            );
            final fullUrl = _resolveUrl(currentUrlStr, url);

            pageChapters.add(
              Chapter(
                bookId: book.id,
                title: title.isEmpty ? '第${index + 1}章' : title,
                index: index++,
                content: fullUrl,
                url: fullUrl,
                wordCount: 0,
                isDownloaded: false,
              ),
            );
          }
          if (pageChapters.isEmpty) {
            pageChapters.addAll(_parseChaptersByJsonFallback(
              pageData,
              rule,
              source,
              book,
              currentUrlStr,
              limit: limit,
            ));
          }
        } catch (_) {
          pageChapters.addAll(_parseChaptersByJsonFallback(
            pageData,
            rule,
            source,
            book,
            currentUrlStr,
            limit: limit,
          ));
        }
      } else if (_isJsOnlyRule(pageListRule) && _looksLikeJsonData(pageData, pageListRule)) {
        pageChapters.addAll(_parseChaptersByJsonFallback(
          pageData,
          rule,
          source,
          book,
          currentUrlStr,
          limit: limit,
        ));
      } else {
        final document = parse(pageData.toString());
        final nodes = _queryAll(document, pageListRule);
        var index = chapters.length;
        for (final node in nodes) {
          if (limit != null && (chapters.length + pageChapters.length) >= limit) break;
          
          var titleRule = _firstRule(rule, const ['chapterName', 'name', 'title']) ?? '';
          if (titleRule.trim().isEmpty) titleRule = 'text'; // 默认脑补 'text'
          final title = _extractHtmlValue(
            node,
            _sourceScopedRule(titleRule, source),
          );
          
          var urlRule = _firstRule(rule, const ['chapterUrl', 'url', 'link']) ?? '';
          if (urlRule.trim().isEmpty) urlRule = 'href'; // 默认脑补 'href'
          final url = _extractHtmlValue(
            node,
            _sourceScopedRule(urlRule, source),
          );
          if (title.trim().isEmpty && url.trim().isEmpty) continue;
          final fullUrl = _resolveUrl(currentUrlStr, url);

          pageChapters.add(
            Chapter(
              bookId: book.id,
              title: title.isEmpty ? '第${index + 1}章' : title,
              index: index++,
              content: fullUrl,
              url: fullUrl,
              wordCount: 0,
              isDownloaded: false,
            ),
          );
        }
        if (pageChapters.isEmpty) {
          pageChapters.addAll(_parseChaptersByJsonFallback(
            pageData,
            rule,
            source,
            book,
            currentUrlStr,
            limit: limit,
          ));
        }
      }

      chapters.addAll(pageChapters);

      if (limit != null && chapters.length >= limit) {
        break;
      }

      // 提取下一页目录 URL
      final nextRule = _firstRule(rule, const ['nextTocUrl', 'nextPageUrl', 'nextUrl']);
      if (nextRule == null || nextRule.isEmpty) {
        break;
      }

      String nextPage = '';
      if (_looksLikeJsonData(pageData, nextRule) && _isJsonRule(nextRule)) {
        try {
          final jsonData = pageData is String ? jsonDecode(pageData) : pageData;
          nextPage = _extractJsonValue(jsonData, nextRule);
        } catch (_) {
          nextPage = '';
        }
      } else {
        final document = parse(pageData.toString());
        final root = document.documentElement ?? document.body;
        if (root != null) nextPage = _extractHtmlValue(root, nextRule);
      }

      nextPage = nextPage
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .replaceAll('%0A', '')
          .replaceAll('%0D', '')
          .replaceAll('%0a', '')
          .replaceAll('%0d', '')
          .trim();
      if (nextPage.isEmpty) {
        break;
      }

      final nextUrlResolved = _resolveUrl(currentUrlStr, nextPage);
      if (nextUrlResolved == currentUrlStr || visitedUrls.contains(nextUrlResolved)) {
        break;
      }

      try {
        final nextResponse = await _request(source, nextUrlResolved);
        currentUrlStr = nextUrlResolved;
        data = nextResponse.data;
      } catch (innerError) {
        print('Error processing chapter list page: $innerError');
        break;
      }
    }

    return chapters;
  }

  static Future<String> getChapterContent(
    BookSource source,
    String chapterUrl,
  ) async {
    if (chapterUrl.trim().isEmpty) return '解析失败：章节链接为空';

    final ruleContentStr = source.ruleContent;
    if (ruleContentStr == null) return '解析规则缺失';

    final rule = _ruleMap(ruleContentStr);
    final contentRule = _firstRule(rule, const ['content', 'text']);
    if (contentRule == null || contentRule.isEmpty) {
      return '解析失败：未配置正文规则';
    }

    try {
      final parts = <String>[];
      var currentUrl = chapterUrl;
      final visitedUrls = <String>{};

      while (true) {
        try {
          currentUrl = currentUrl
              .replaceAll('\n', '')
              .replaceAll('\r', '')
              .replaceAll('%0A', '')
              .replaceAll('%0D', '')
              .replaceAll('%0a', '')
              .replaceAll('%0d', '')
              .trim();
          if (currentUrl.isEmpty || visitedUrls.contains(currentUrl)) {
            break;
          }
          visitedUrls.add(currentUrl);

          var response = await _request(source, currentUrl);
          response = await _followContentUrl(source, currentUrl, response, rule);
          final prepared = await _prepareDataForRule(
            source,
            response.data,
            contentRule,
            baseUrl: currentUrl,
          );
          final contentText = _extractContentFromResponse(prepared.data, prepared.rule);
          parts.add(contentText);

          final nextUrl = _extractNextContentUrl(
            response.realUri.toString(),
            response.data,
            rule,
          );
          if (nextUrl == null) break;

          final cleanedNextUrl = nextUrl
              .replaceAll('\n', '')
              .replaceAll('\r', '')
              .replaceAll('%0A', '')
              .replaceAll('%0D', '')
              .replaceAll('%0a', '')
              .replaceAll('%0d', '')
              .trim();
          if (cleanedNextUrl.isEmpty || cleanedNextUrl == currentUrl || visitedUrls.contains(cleanedNextUrl)) {
            break;
          }
          
          final resolvedNextUrl = _resolveUrl(currentUrl, cleanedNextUrl);
          if (resolvedNextUrl == currentUrl || visitedUrls.contains(resolvedNextUrl)) break;
          
          currentUrl = resolvedNextUrl;
        } catch (innerError) {
          // 容错机制：如果某一个分页面由于网络等原因报错，捕获异常并跳出，保证之前解析成功的部分依然可以返回
          print('Error processing chapter content page: $innerError');
          break;
        }
      }

      final content = parts
          .map((part) => _applyContentReplaceRegex(part, rule))
          .where((part) => part.trim().isNotEmpty)
          .join('\n');
          
      var finalContent = content.trim();
      if (finalContent.isEmpty) {
        try {
          print('正文解析为空，尝试 Headless WebView 二次抓取...');
          final fallbackHtml = await _requestViaHeadlessWebView(source, chapterUrl);
          final prepared = await _prepareDataForRule(source, fallbackHtml, contentRule, baseUrl: chapterUrl);
          final fallbackText = _extractContentFromResponse(prepared.data, prepared.rule);
          finalContent = _applyContentReplaceRegex(fallbackText, rule).trim();
        } catch (_) {}
      }
      
      if (finalContent.isEmpty) return '解析失败：正文为空';
      
      // 执行清理与实体转换
      return _cleanHtmlEntities(finalContent);
    } catch (e) {
      return '解析失败：${e.toString()}';
    }
  }

  /// 正文清洗器：将 HTML 实体及标签规范地转化为换行符及普通空格
  static String _cleanHtmlEntities(String html) {
    if (html.isEmpty) return html;
    var content = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'&lt;', caseSensitive: false), '<')
        .replaceAll(RegExp(r'&gt;', caseSensitive: false), '>')
        .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&')
        .replaceAll(RegExp(r'&quot;', caseSensitive: false), '"')
        .replaceAll(RegExp(r'&apos;', caseSensitive: false), "'")
        .replaceAll(RegExp(r'&#039;', caseSensitive: false), "'")
        .replaceAll(RegExp(r'&ldquo;', caseSensitive: false), '“')
        .replaceAll(RegExp(r'&rdquo;', caseSensitive: false), '”')
        .replaceAll(RegExp(r'&hellip;', caseSensitive: false), '…')
        .replaceAll(RegExp(r'&mdash;', caseSensitive: false), '—');
        
    // 解码常见的 &#xxxx; 数字实体
    content = content.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      try {
        final code = int.parse(match.group(1)!);
        return String.fromCharCode(code);
      } catch (_) {
        return match.group(0)!;
      }
    });
    
    // 解码 &#[xX]XXXX; 十六进制实体
    content = content.replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'), (match) {
      try {
        final code = int.parse(match.group(1)!, radix: 16);
        return String.fromCharCode(code);
      } catch (_) {
        return match.group(0)!;
      }
    });

    return content.trim();
  }

  static String _extractContentFromResponse(dynamic data, String contentRule) {
    if (contentRule.trim().isEmpty) return data.toString().trim();
    if (_isJsonRule(contentRule) && _looksLikeJsonData(data, contentRule)) {
      final jsonData = data is String ? jsonDecode(data) : data;
      return _extractJsonValue(jsonData, contentRule);
    }

    final document = parse(data.toString());
    final node = _queryOne(document, contentRule);
    if (node == null) return '解析失败';

    node
        .querySelectorAll('script, style, noscript, iframe')
        .forEach((element) => element.remove());
    var html = node.outerHtml;
    html = html.replaceAll(
      RegExp(r'</p>|</div>|</li>|<br\s*/?>', caseSensitive: false),
      '\n',
    );
    html = html.replaceAll(
      RegExp(r'<[^>]*>', multiLine: true, caseSensitive: false),
      '',
    );
    return html.trim();
  }

  // --- Helpers ---

  static Book _parseBookFromJson(
    Map<String, dynamic> item,
    Map<String, dynamic> rule,
    BookSource source, {
    String? baseUrl,
    bool isBookInfo = false,
  }) {
    final name = _cleanRuleOutput(
      _extractJsonValue(
        item,
        _sourceScopedRule(
          _ruleOrKey(rule['name'], item, [
            'name',
            'Name',
            'title',
            'Title',
            'bookName',
            'BookName',
            'book_name',
            'bookTitle',
            'BookTitle',
            'articleName',
            'novelName',
            'novel_name',
            'original_title',
            'bName',
          ]),
          source,
        ),
      ),
    );
    final author = _cleanRuleOutput(
      _extractJsonValue(
        item,
        _sourceScopedRule(
          _ruleOrKey(rule['author'], item, [
            'author',
            'Author',
            'authorName',
            'AuthorName',
            'author_name',
            'writer',
            'writerName',
            'writer_name',
            'original_author',
            'penName',
          ]),
          source,
        ),
      ),
    );
    final coverUrl = _cleanRuleOutput(
      _extractJsonValue(
        item,
        _sourceScopedRule(
          _ruleOrKey(rule['coverUrl'], item, [
            'coverUrl',
            'CoverUrl',
            'cover',
            'Cover',
            'cover_url',
            'picUrl',
            'pic',
            'imgUrl',
            'imageUrl',
            'thumb',
            'image',
            'coverPath',
          ]),
          source,
        ),
      ),
    );
    final bookUrlRule = rule['bookUrl'] ?? rule['tocUrl'] ?? rule['catalogUrl'];
    final bookUrl = _cleanRuleOutput(
      _extractJsonValue(
        item,
        _sourceScopedRule(
          _ruleOrKey(bookUrlRule, item, [
            'bookUrl',
            'BookUrl',
            'url',
            'Url',
            'detailUrl',
            'detail_url',
            'book_url',
            'tocUrl',
            'catalogUrl',
            'bookId',
            'BookId',
            'book_id',
            'book_id',
            'bookID',
            'book_id',
            'articleid',
            'articleId',
            'novelId',
            'novel_id',
            'nid',
            'id',
            'Id',
          ]),
          source,
        ),
      ),
    );
    final base = baseUrl ?? source.bookSourceUrl;

    return Book(
      title: name.isNotEmpty ? name : '未知',
      author: author,
      filePath: _resolveBookUrl(base, bookUrl),
      fileType: 'online',
      coverPath: _resolveUrl(base, coverUrl),
      isFromSource: true,
      sourceUrl: source.id.toString(),
    );
  }

  static Book _parseBookFromHtmlNode(
    Element node,
    Map<String, dynamic> rule,
    BookSource source, {
    String? baseUrl,
    bool isBookInfo = false,
  }) {
    final name = _extractHtmlValue(
      node,
      _firstRule(rule, const ['name']) ?? '',
    );
    final author = _extractHtmlValue(
      node,
      _firstRule(rule, const ['author']) ?? '',
    );
    final coverUrl = _extractHtmlValue(
      node,
      _firstRule(rule, const ['coverUrl', 'cover']) ?? '',
    );
    final bookUrlKeys = isBookInfo 
        ? const ['tocUrl', 'catalogUrl'] 
        : const ['bookUrl', 'tocUrl', 'catalogUrl', 'url'];
    final bookUrl = _extractHtmlValue(
      node,
      _firstRule(rule, bookUrlKeys) ?? '',
    );
    final base = baseUrl ?? source.bookSourceUrl;

    return Book(
      title: name.isNotEmpty ? name : '未知',
      author: author,
      filePath: _resolveUrl(base, bookUrl),
      fileType: 'online',
      coverPath: _resolveUrl(base, coverUrl),
      isFromSource: true,
      sourceUrl: source.id.toString(),
    );
  }

  static Book _mergeBookInfo(Book origin, Book detail) {
    return origin.copyWith(
      title: detail.title == '未知' ? origin.title : detail.title,
      author: detail.author.isEmpty ? origin.author : detail.author,
      coverPath: detail.coverPath?.isEmpty ?? true
          ? origin.coverPath
          : detail.coverPath,
      filePath: detail.filePath.isEmpty ? origin.filePath : detail.filePath,
    );
  }

  static String _ruleOrKey(
    dynamic ruleValue,
    Map<String, dynamic> item,
    List<String> candidates,
  ) {
    final value = ruleValue?.toString() ?? '';
    if (value.isNotEmpty) return value;
    for (final key in candidates) {
      if (item.containsKey(key)) return key;
    }
    return '';
  }

  static String _sourceScopedRule(String rule, BookSource source) {
    if (rule.isEmpty) return '';
    final baseUrl = LegadoRequestBuilder.cleanBaseUrl(
      source.bookSourceUrl,
    ).replaceAll(RegExp(r'/+$'), '');
    return rule
        .replaceAll('{{source.bookSourceUrl}}', baseUrl)
        .replaceAll('{source.bookSourceUrl}', baseUrl)
        .replaceAll('{{source.key}}', baseUrl)
        .replaceAll('{source.key}', baseUrl)
        .replaceAll('{{source.getKey()}}', baseUrl)
        .replaceAll('{source.getKey()}', baseUrl)
        .replaceAll('{{baseUrl}}', baseUrl)
        .replaceAll('{baseUrl}', baseUrl);
  }

  static Map<String, dynamic> _ruleMap(String? ruleJson) {
    if (ruleJson == null || ruleJson.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(ruleJson);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return _stringKeyMap(decoded);
    } catch (_) {
      return {};
    }
    return {};
  }

  static String? _firstRule(Map<String, dynamic> rule, List<String> keys) {
    for (final key in keys) {
      final value = rule[key];
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static Future<Response<dynamic>> _followTocUrl(
    BookSource source,
    String baseUrl,
    Response<dynamic> response,
    Map<String, dynamic> rule,
  ) async {
    final tocUrlRule = _firstRule(rule, const ['tocUrl', 'catalogUrl']);
    if (tocUrlRule == null) return response;
    final data = response.data;
    String tocUrl = '';
    if (_looksLikeJsonData(data, tocUrlRule) && _isJsonRule(tocUrlRule)) {
      final jsonData = data is String ? jsonDecode(data) : data;
      tocUrl = _extractJsonValue(jsonData, tocUrlRule);
    } else {
      final document = parse(data.toString());
      final root = document.documentElement ?? document.body;
      if (root != null) tocUrl = _extractHtmlValue(root, tocUrlRule);
    }
    if (tocUrl.trim().isEmpty) return response;
    return _request(source, _resolveUrl(baseUrl, tocUrl));
  }

  static Future<Response<dynamic>> _followContentUrl(
    BookSource source,
    String baseUrl,
    Response<dynamic> response,
    Map<String, dynamic> rule,
  ) async {
    final contentUrlRule = _firstRule(rule, const [
      'contentUrl',
      'realContentUrl',
    ]);
    if (contentUrlRule == null) return response;
    final data = response.data;
    String contentUrl = '';
    if (_looksLikeJsonData(data, contentUrlRule) &&
        _isJsonRule(contentUrlRule)) {
      final jsonData = data is String ? jsonDecode(data) : data;
      contentUrl = _extractJsonValue(jsonData, contentUrlRule);
    } else {
      final document = parse(data.toString());
      final root = document.documentElement ?? document.body;
      if (root != null) contentUrl = _extractHtmlValue(root, contentUrlRule);
    }
    if (contentUrl.trim().isEmpty) return response;
    return _request(source, _resolveUrl(baseUrl, contentUrl));
  }

  static String? _extractNextContentUrl(
    String baseUrl,
    dynamic data,
    Map<String, dynamic> rule,
  ) {
    final nextRule = _firstRule(rule, const [
      'nextContentUrl',
      'nextUrl',
      'nextPageUrl',
    ]);
    if (nextRule == null) return null;
    String nextUrl = '';
    if (_looksLikeJsonData(data, nextRule) && _isJsonRule(nextRule)) {
      try {
        final jsonData = data is String ? jsonDecode(data) : data;
        nextUrl = _extractJsonValue(jsonData, nextRule);
      } catch (_) {
        nextUrl = '';
      }
    } else {
      final document = parse(data.toString());
      final root = document.documentElement ?? document.body;
      if (root != null) nextUrl = _extractHtmlValue(root, nextRule);
    }
    if (nextUrl.trim().isEmpty) return null;
    return _resolveUrl(baseUrl, nextUrl);
  }

  static Future<({dynamic data, String rule})> _prepareDataForRule(
    BookSource source,
    dynamic data,
    String rule, {
    String? baseUrl,
    String? keyword,
  }) async {
    final block = _leadingJsBlock(rule);
    if (block == null) return (data: data, rule: rule);

    final resultText = data is String ? data : jsonEncode(data);
    final variables = _jsVariables(
      source,
      result: resultText,
      baseUrl: baseUrl,
      keyword: keyword,
    );
    try {
      final output = await LegadoJsEngine().evaluateWithAjax(
        block.script,
        variables: variables,
        libraries: await _sourceLibraryCodes(source, baseUrl: baseUrl),
        ajax: (request) =>
            _ajaxForJs(source, request, baseUrl: baseUrl, keyword: keyword),
      );
      return (data: output, rule: block.suffix);
    } catch (_) {
      return (data: data, rule: block.suffix.isEmpty ? rule : block.suffix);
    }
  }

  static ({String script, String suffix})? _leadingJsBlock(String rule) {
    final text = rule.trimLeft();
    if (text.startsWith('<js>')) {
      final close = text.indexOf('</js>');
      if (close < 0) return (script: text, suffix: '');
      final end = close + '</js>'.length;
      return (
        script: text.substring(0, end),
        suffix: text.substring(end).trim(),
      );
    }
    if (text.startsWith('@js:')) {
      return (script: text, suffix: '');
    }
    return null;
  }

  static Map<String, dynamic> _jsVariables(
    BookSource source, {
    String result = '',
    String? baseUrl,
    String? keyword,
    int page = 1,
  }) {
    final sourceUrl = LegadoRequestBuilder.cleanBaseUrl(
      source.bookSourceUrl,
    ).replaceAll(RegExp(r'/+$'), '');
    final sourceUri = Uri.tryParse(
      sourceUrl.contains('://') ? sourceUrl : 'https://$sourceUrl',
    );
    final config = LegadoRequestBuilder.jsonConfig(source.customConfig);
    return {
      'result': result,
      'baseUrl': baseUrl ?? sourceUrl,
      'key': keyword ?? '',
      'keyword': keyword ?? '',
      'page': page,
      'cookieHeader': sourceUri == null
          ? ''
          : LegadoSessionStore.cookieHeaderFor(sourceUri) ?? '',
      'userAgent': sourceUri == null
          ? ''
          : LegadoSessionStore.userAgentFor(sourceUri) ?? '',
      'source': {
        'key': sourceUrl,
        'bookSourceUrl': sourceUrl,
        'bookSourceName': source.bookSourceName,
        'variable': config['variable'] ?? config['variableComment'] ?? '',
        'customConfig': config,
      },
    };
  }

  static Iterable<String> _sourceLibraries(BookSource source) {
    final config = LegadoRequestBuilder.jsonConfig(source.customConfig);
    final jsLib = config['jsLib'];
    if (jsLib == null) return const [];
    if (jsLib is List) {
      return jsLib.map((value) => value.toString());
    }
    return [jsLib.toString()];
  }

  static Future<List<String>> _sourceLibraryCodes(
    BookSource source, {
    String? baseUrl,
  }) async {
    final codes = <String>[];
    for (final raw in _sourceLibraries(source)) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      if (!_looksLikeJsLibraryUrl(value)) {
        codes.add(value);
        continue;
      }
      final url = _resolveUrl(baseUrl ?? source.bookSourceUrl, value);
      final cached = _jsLibraryCache[url];
      if (cached != null) {
        codes.add(cached);
        continue;
      }
      try {
        final response = await _request(source, url);
        final code = response.data?.toString() ?? '';
        if (code.trim().isNotEmpty) {
          _jsLibraryCache[url] = code;
          codes.add(code);
        }
      } catch (_) {
        // A missing jsLib should not stop the whole source; the main rule may
        // still work or the source test will show the later failing step.
      }
    }
    return codes;
  }

  static bool _looksLikeJsLibraryUrl(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('/') && lower.endsWith('.js') ||
        lower.endsWith('.js') && !lower.contains('\n');
  }

  static Future<String> _ajaxForJs(
    BookSource source,
    String request, {
    String? baseUrl,
    String? keyword,
  }) async {
    final resolved = _resolveRequestUrl(
      baseUrl ?? source.bookSourceUrl,
      request,
    );
    final response = await _request(source, resolved, keyword: keyword);
    return response.data?.toString() ?? '';
  }

  static String _resolveRequestUrl(String baseUrl, String request) {
    final embedded = LegadoRequestBuilder.splitEmbeddedConfig(request);
    final resolved = _resolveUrl(baseUrl, embedded.url);
    if (embedded.config.isEmpty) return resolved;
    return '$resolved,${jsonEncode(embedded.config)}';
  }

  static String _extractJsonValue(dynamic json, String jsonPath) {
    return LegadoRuleEvaluator.extractJsonValue(json, jsonPath);
  }

  static List<dynamic> _extractJsonNodes(dynamic json, String jsonPath) {
    return LegadoRuleEvaluator.extractJsonNodes(json, jsonPath);
  }

  static String _extractHtmlValue(Element node, String ruleStr) {
    return LegadoRuleEvaluator.extractHtmlValue(node, ruleStr);
  }

  static List<Element> _queryAll(Document document, String rule) {
    if (rule.trim().isEmpty) return [];
    final alternatives = rule.split(RegExp(r'\|\|'));
    for (final alt in alternatives) {
      final trimmed = alt.trim();
      if (trimmed.isEmpty) continue;
      final nodes = LegadoRuleEvaluator.queryAll(document, trimmed);
      if (nodes.isNotEmpty) return nodes;
    }
    return [];
  }

  static Element? _queryOne(dynamic node, String rule) {
    if (rule.trim().isEmpty) return null;
    final alternatives = rule.split(RegExp(r'\|\|'));
    for (final alt in alternatives) {
      final trimmed = alt.trim();
      if (trimmed.isEmpty) continue;
      final match = LegadoRuleEvaluator.queryOne(node, trimmed);
      if (match != null) return match;
    }
    return null;
  }

  static bool _hasWebViewConfig(BookSource source, String url) {
    try {
      final embedded = LegadoRequestBuilder.splitEmbeddedConfig(url);
      final config = <String, dynamic>{};
      config.addAll(LegadoRequestBuilder.jsonConfig(source.customConfig));
      config.addAll(embedded.config);
      
      final webViewVal = config['webView'] ?? config['webview'];
      if (webViewVal != null) {
        final str = webViewVal.toString().trim().toLowerCase();
        return str == 'true' || str == '1';
      }
    } catch (_) {}
    return false;
  }

  static Future<String> _requestViaHeadlessWebView(
    BookSource source,
    String targetUrl,
  ) async {
    targetUrl = targetUrl.replaceAll('\n', '').replaceAll('\r', '').replaceAll('%0A', '').replaceAll('%0D', '').replaceAll('%0a', '').replaceAll('%0d', '').trim();
    final embedded = LegadoRequestBuilder.splitEmbeddedConfig(targetUrl);
    final urlStr = embedded.url;
    final uri = Uri.parse(urlStr);
    
    final completer = Completer<String>();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
      
    final config = <String, dynamic>{};
    config.addAll(LegadoRequestBuilder.jsonConfig(source.customConfig));
    config.addAll(embedded.config);
    
    final rawHeaders = config['headers'] ?? config['header'] ?? config['bookSourceHeader'];
    Map<String, String> headersMap = {};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) => headersMap[k.toString()] = v.toString());
    } else if (rawHeaders is String) {
      final parsed = LegadoRequestBuilder.parseHeaderString(rawHeaders);
      parsed.forEach((k, v) => headersMap[k.toString()] = v.toString());
    }
    
    final ua = headersMap['User-Agent'] ?? headersMap['user-agent'] ?? config['userAgent'];
    if (ua != null && ua.toString().isNotEmpty) {
      await controller.setUserAgent(ua.toString());
      LegadoSessionStore.setUserAgent(uri, ua.toString());
    }
    
    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) async {
          try {
            await Future.delayed(const Duration(milliseconds: 1200));
            final cookieManager = wcm.WebviewCookieManager();
            final gotCookies = await cookieManager.getCookies(urlStr);
            if (gotCookies.isNotEmpty) {
              final cookieStr = gotCookies.map((c) => '${c.name}=${c.value}').join('; ');
              LegadoSessionStore.setCookieString(uri, cookieStr);
            }
            
            if (ua == null || ua.toString().isEmpty) {
              final extractedUa = await controller.runJavaScriptReturningResult('navigator.userAgent');
              final uaStr = extractedUa.toString().replaceAll('"', '').trim();
              if (uaStr.isNotEmpty) {
                LegadoSessionStore.setUserAgent(uri, uaStr);
              }
            }
            
            String html = '';
            int attempts = 0;
            while (attempts < 3) {
              final result = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
              html = result.toString();
              if (html.startsWith('"') && html.endsWith('"')) {
                try {
                  final decoded = jsonDecode(html);
                  if (decoded is String) html = decoded;
                } catch (_) {
                  html = html.substring(1, html.length - 1)
                    .replaceAll(r'\"', '"')
                    .replaceAll(r'\\', r'\');
                }
              }
              
              // 智能条件轮询，欺骗 WebKit 保证后台 Ajax 全速活跃并渲染出真正的骨架屏正文
              if (html.contains('href') || 
                  html.contains('chapter') || 
                  html.contains('<li') || 
                  html.contains('<p>') || 
                  html.contains('</p>') || 
                  html.length > 2000) {
                break;
              }
              attempts++;
              if (attempts < 3) {
                await Future.delayed(const Duration(milliseconds: 1000));
              }
            }
            
            if (!completer.isCompleted) {
              await LegadoSessionStore.persistHost(uri);
              completer.complete(html);
            }
          } catch (e) {
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
          }
        },
        onNavigationRequest: (request) {
          return NavigationDecision.navigate;
        },
        onWebResourceError: (error) {
          print("Headless WebView resource error: ${error.description}");
        },
      ),
    );
    
    final timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Headless WebView request timed out for $urlStr'));
      }
    });
    
    // 配合业务层物理边缘欺骗性挂载（以 1x1 物理挂载而非 Offstage），强行阻止 WebKit 将其挂起
    final overlayState = rootNavigatorKey.currentState?.overlay;
    OverlayEntry? overlayEntry;
    if (overlayState != null) {
      overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          bottom: -10,
          right: -10,
          width: 1,
          height: 1,
          child: Opacity(
            opacity: 0.01,
            child: WebViewWidget(controller: controller),
          ),
        ),
      );
      overlayState.insert(overlayEntry);
    }
    
    try {
      final optionsHeaders = <String, String>{};
      headersMap.forEach((k, v) {
        optionsHeaders[k] = v;
      });
      
      final storedCookie = LegadoSessionStore.cookieHeaderFor(uri);
      if (storedCookie != null && storedCookie.isNotEmpty) {
        optionsHeaders['Cookie'] = storedCookie;
        try {
          final cookieManager = wcm.WebviewCookieManager();
          final cookiesList = <Cookie>[];
          for (final c in storedCookie.split(';')) {
            final trimC = c.trim();
            if (trimC.isEmpty) continue;
            final eqIdx = trimC.indexOf('=');
            if (eqIdx > 0) {
              final name = trimC.substring(0, eqIdx).trim();
              final value = trimC.substring(eqIdx + 1).trim();
              if (name.isNotEmpty) {
                cookiesList.add(
                  Cookie(name, value)
                    ..domain = uri.host
                    ..path = '/',
                );
              }
            }
          }
          if (cookiesList.isNotEmpty) {
            await cookieManager.setCookies(cookiesList);
          }
        } catch (e) {
          print('Failed to set WebView cookies: $e');
        }
      }
      
      await controller.loadRequest(
        uri,
        headers: optionsHeaders,
      );
      
      final result = await completer.future;
      timeoutTimer.cancel();
      return result;
    } catch (e) {
      timeoutTimer.cancel();
      rethrow;
    } finally {
      overlayEntry?.remove();
    }
  }

  static Future<String> executeFetch(
    BookSource source,
    String targetUrl, {
    String? keyword,
  }) async {
    targetUrl = targetUrl.replaceAll('\n', '').replaceAll('\r', '').replaceAll('%0A', '').replaceAll('%0D', '').replaceAll('%0a', '').replaceAll('%0d', '').trim();
    
    // 漫画源前置降级与底层通用扩展预留
    if (source.bookSourceType > 0 || 
        source.ruleContent?.contains('@css:img') == true ||
        source.ruleContent?.contains('@js:return java.getElements') == true) {
      throw Exception('暂不支持漫画类书源解析（功能扩充预留中）');
    }

    final hasWebView = _hasWebViewConfig(source, targetUrl);
    if (hasWebView) {
      print('Url config specifies webView. Routing to Headless WebView.');
      return await _requestViaHeadlessWebView(source, targetUrl);
    }
    
    try {
      final request = _buildRequest(source, targetUrl, keyword: keyword);
      final headers = Map<String, dynamic>.from(request.headers ?? const {});
      LegadoSessionStore.apply(Uri.parse(request.url), headers);
      
      dynamic requestData = request.body;
      
      // 彻底修复 GBK POST 请求体二次编码污染（针对言情港等老页面的 POST 方式）
      if (request.method == 'POST' && 
          (request.charset?.toLowerCase() == 'gbk' || 
           source.customConfig?.toLowerCase().contains('gbk') == true)) {
        if (request.body != null && keyword != null && keyword.isNotEmpty) {
          // 将 keyword 字符串强制转换为原始的 GBK 字节流，并执行标准的十六进制 URL 编码
          final gbkBytes = gbk.encode(keyword);
          final gbkEncodedKeyword = gbkBytes.map((b) => '%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}').join();
          
          var bodyStr = request.body!;
          if (bodyStr.contains(keyword)) {
            bodyStr = bodyStr.replaceAll(keyword, gbkEncodedKeyword);
          }
          final utf8EncodedKeywordUpper = Uri.encodeComponent(keyword).toUpperCase();
          final utf8EncodedKeywordLower = Uri.encodeComponent(keyword).toLowerCase();
          if (bodyStr.contains(utf8EncodedKeywordUpper)) {
            bodyStr = bodyStr.replaceAll(utf8EncodedKeywordUpper, gbkEncodedKeyword);
          }
          if (bodyStr.contains(utf8EncodedKeywordLower)) {
            bodyStr = bodyStr.replaceAll(utf8EncodedKeywordLower, gbkEncodedKeyword);
          }
          
          // 转换为原始的 GBK 字节流，防止被 Dio 默认的 UTF-8 二次编码转义破坏
          requestData = Uint8List.fromList(gbk.encode(bodyStr));
        }
      }
      
      final response = await _dio.request<dynamic>(
        request.url,
        data: requestData,
        options: Options(
          method: request.method,
          headers: headers.isEmpty ? null : headers,
          responseType: ResponseType.bytes,
        ),
      );
      LegadoSessionStore.rememberResponse(response.realUri, response.headers);
      final bytes = response.data is List<int>
          ? response.data as List<int>
          : utf8.encode(response.data?.toString() ?? '');
      final responseData = decodeBytes(bytes, request.charset, headers: response.headers.map);
      
      if (_needsManualVerification(response.statusCode, responseData)) {
        print('Dio response triggers verification. Downgrading to Headless WebView.');
        return await _requestViaHeadlessWebView(source, targetUrl);
      }
      return responseData;
    } on DioException catch (e) {
      final isTlsOrConnectionError = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError ||
          (e.message?.toLowerCase().contains('handshake') ?? false) ||
          (e.message?.toLowerCase().contains('connection reset') ?? false);
          
      final isStatusCodeError = e.response != null &&
          (e.response!.statusCode == 403 || e.response!.statusCode == 503);
          
      if (isTlsOrConnectionError || isStatusCodeError) {
        print('Dio request failed (code: ${e.response?.statusCode}, err: ${e.message}). Falling back to Headless WebView.');
        return await _requestViaHeadlessWebView(source, targetUrl);
      } else {
        rethrow;
      }
    } catch (e) {
      print('Dio request generic error: $e. Falling back to Headless WebView.');
      return await _requestViaHeadlessWebView(source, targetUrl);
    }
  }

  static Future<Response<dynamic>> _request(
    BookSource source,
    String url, {
    String? keyword,
  }) async {
    url = url.replaceAll('\n', '').replaceAll('\r', '').replaceAll('%0A', '').replaceAll('%0D', '').replaceAll('%0a', '').replaceAll('%0d', '').trim();
    if (url.isEmpty) {
      throw Exception('请求 URL 为空 (可能是由于 JS 执行异常或书源未配置有效链接)');
    }
    final dataPayload = _decodeDataPayload(url);
    if (dataPayload != null) {
      return Response<dynamic>(
        data: dataPayload,
        statusCode: 200,
        requestOptions: RequestOptions(path: url),
      );
    }
    
    final responseData = await executeFetch(source, url, keyword: keyword);
    return Response<dynamic>(
      data: responseData,
      statusCode: 200,
      requestOptions: RequestOptions(path: url),
    );
  }

  static LegadoHttpRequest _buildRequest(
    BookSource source,
    String url, {
    String? keyword,
  }) {
    return LegadoRequestBuilder.buildRequest(source, url, keyword: keyword);
  }

  static bool _needsManualVerification(int? statusCode, dynamic data) {
    final text = data?.toString() ?? '';
    final lower = text.toLowerCase();
    if (lower.contains('/cdn-cgi/challenge-platform') ||
        lower.contains('just a moment') ||
        lower.contains('cf-browser-verification') ||
        lower.contains('challenge-form') ||
        lower.contains('enable javascript and cookies') ||
        lower.contains('百度安全验证') ||
        lower.contains('cloudflare') &&
            lower.contains('checking your browser')) {
      return true;
    }
    if ((statusCode == 401 ||
            statusCode == 403 ||
            statusCode == 429 ||
            statusCode == 503) &&
        _looksLikeHtmlPage(text)) {
      return true;
    }
    return false;
  }

  static bool _looksLikeHtmlPage(String text) {
    final sample = text.toLowerCase();
    return sample.contains('<!doctype html') ||
        sample.contains('<html') ||
        sample.contains('<title>') ||
        sample.contains('<body');
  }

  static Future<String> _buildSearchUrlAsync(
    BookSource source,
    String keyword, {
    int page = 1,
  }) async {
    final raw = source.searchUrl ?? '';
    var searchUrl = LegadoRequestBuilder.replaceVariables(
      raw,
      keyword: keyword,
      page: page,
      source: source,
    );
    if (_isWholeJsRule(searchUrl)) {
      final variables = _jsVariables(
        source,
        keyword: keyword,
        page: page,
        baseUrl: source.bookSourceUrl,
      );
      final output = await LegadoJsEngine().evaluateWithAjax(
        searchUrl,
        variables: variables,
        libraries: await _sourceLibraryCodes(
          source,
          baseUrl: source.bookSourceUrl,
        ),
        ajax: (request) => _ajaxForJs(
          source,
          request,
          baseUrl: source.bookSourceUrl,
          keyword: keyword,
        ),
      );
      if (output.trim().isNotEmpty) searchUrl = output.trim();
    }

    final embedded = LegadoRequestBuilder.splitEmbeddedConfig(searchUrl);
    final resolved = _resolveUrl(source.bookSourceUrl, embedded.url);
    if (embedded.config.isEmpty) return resolved;
    return '$resolved,${jsonEncode(embedded.config)}';
  }

  static bool _isWholeJsRule(String text) {
    final value = text.trimLeft();
    return value.startsWith('@js:') || value.startsWith('<js>');
  }

  static String _resolveUrl(String baseUrl, String url) {
    return LegadoRequestBuilder.resolveUrl(baseUrl, url);
  }

  static String _resolveBookUrl(String baseUrl, String url) {
    if (url.isEmpty) return baseUrl;
    if (RegExp(r'^\d+$').hasMatch(url)) {
      return _resolveUrl(baseUrl, url);
    }
    return _resolveUrl(baseUrl, url);
  }

  static bool _isJsonRule(String rule) {
    return LegadoRuleEvaluator.isJsonRule(rule);
  }

  static String _jsonPathRule(String rule) {
    return LegadoRuleEvaluator.jsonPathRule(rule);
  }

  static String _cleanRuleOutput(String value) {
    return LegadoRuleEvaluator.cleanRuleOutput(value);
  }

  static String _applyContentReplaceRegex(
    String value,
    Map<String, dynamic> rule,
  ) {
    final replaceRule = _firstRule(rule, const ['replaceRegex', 'replace']);
    if (replaceRule == null || replaceRule.isEmpty) {
      return _cleanRuleOutput(value);
    }
    return LegadoRuleEvaluator.applyPostProcessors(
      value,
      replaceRule.startsWith('##') ? replaceRule : '##$replaceRule',
    );
  }

  static bool _isJsOnlyRule(String rule) {
    return LegadoRuleEvaluator.isJsOnlyRule(rule);
  }

  static bool _containsJsRule(String? rule) {
    return LegadoRuleEvaluator.containsJsRule(rule);
  }

  static bool _looksLikeJsonData(dynamic data, String? rule) {
    return LegadoRuleEvaluator.looksLikeJsonData(data, rule);
  }

  static String _sample(dynamic data) {
    final text = data.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 220 ? '${text.substring(0, 220)}...' : text;
  }

  static List<Book> _parseBooksByJsonFallback(
    dynamic data,
    Map<String, dynamic> rule,
    BookSource source,
  ) {
    try {
      final jsonData = data is String ? jsonDecode(data) : data;
      final candidates = <dynamic>[
        if (jsonData is Map) jsonData['data'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['list'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['data'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['books'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['bookList'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['items'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['records'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['rows'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['result'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['results'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['searchList'],
        if (jsonData is Map) jsonData['list'],
        if (jsonData is Map) jsonData['books'],
        if (jsonData is Map) jsonData['bookList'],
        if (jsonData is Map) jsonData['items'],
        if (jsonData is Map) jsonData['records'],
        if (jsonData is Map) jsonData['rows'],
        if (jsonData is Map) jsonData['result'],
        if (jsonData is Map) jsonData['results'],
        if (jsonData is Map) jsonData['searchList'],
        if (jsonData is Map) jsonData['novels'],
        ..._findLikelyBookLists(jsonData),
        jsonData,
      ];
      final list = candidates.whereType<List>().firstWhere(
        (items) => items.whereType<Map>().any(_looksLikeBookMap),
        orElse: () => const [],
      );
      if (list.isEmpty) return [];
      return list
          .whereType<Map>()
          .map((item) => _parseBookFromJson(_stringKeyMap(item), rule, source))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static List<Chapter> _parseChaptersByJsonFallback(
    dynamic data,
    Map<String, dynamic> rule,
    BookSource source,
    Book book,
    String baseUrl, {
    int? limit,
  }) {
    try {
      final jsonData = data is String ? jsonDecode(data) : data;
      final candidates = <dynamic>[
        if (jsonData is Map) jsonData['data'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['chapters'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['chapterList'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['chapter_list'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['catalog'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['catalogList'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['volumeList'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['records'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['rows'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['items'],
        if (jsonData is Map && jsonData['data'] is Map)
          jsonData['data']['list'],
        if (jsonData is Map) jsonData['chapters'],
        if (jsonData is Map) jsonData['chapterList'],
        if (jsonData is Map) jsonData['chapter_list'],
        if (jsonData is Map) jsonData['catalog'],
        if (jsonData is Map) jsonData['catalogList'],
        if (jsonData is Map) jsonData['volumeList'],
        if (jsonData is Map) jsonData['records'],
        if (jsonData is Map) jsonData['rows'],
        if (jsonData is Map) jsonData['list'],
        if (jsonData is Map) jsonData['items'],
        ..._findLikelyChapterLists(jsonData),
        jsonData,
      ];
      final list = candidates.whereType<List>().firstWhere(
        (items) => items.whereType<Map>().any(_looksLikeChapterMap),
        orElse: () => const [],
      );
      if (list.isEmpty) return [];

      final chapters = <Chapter>[];
      var index = 0;
      for (final raw in list.whereType<Map>()) {
        if (limit != null && chapters.length >= limit) break;
        final item = _stringKeyMap(raw);
        final title = _firstText(item, const [
          'chapterName',
          'chapter_name',
          'name',
          'title',
          'chapterTitle',
          'chapter_title',
          'chapter_title_name',
          'volumeName',
        ]);
        final url = _chapterUrlFromFallbackItem(
          item,
          rule,
          source,
          book,
          baseUrl,
        );
        if (title.isEmpty && url.isEmpty) continue;
        final resolvedUrl = _resolveUrl(baseUrl, url);
        chapters.add(
          Chapter(
            bookId: book.id,
            title: title.isEmpty ? '第${index + 1}章' : title,
            index: index++,
            content: resolvedUrl,
            url: resolvedUrl,
            wordCount: 0,
            isDownloaded: false,
          ),
        );
      }
      return chapters;
    } catch (_) {
      return [];
    }
  }

  static String _chapterUrlFromFallbackItem(
    Map<String, dynamic> item,
    Map<String, dynamic> rule,
    BookSource source,
    Book book,
    String baseUrl,
  ) {
    final ruleValue = _firstRule(rule, const ['bookUrl', 'chapterUrl', 'url', 'link']);
    if (ruleValue != null && ruleValue.isNotEmpty) {
      final extracted = _extractJsonValue(
        item,
        _sourceScopedRule(ruleValue, source),
      );
      if (extracted.trim().isNotEmpty) return extracted.trim();
    }

    final direct = _firstText(item, const [
      'bookUrl',
      'chapterUrl',
      'url',
      'link',
      'path',
      'content',
      'contentUrl',
      'chapter_url',
      'chapter_url_full',
      'href',
    ]);
    if (direct.isNotEmpty) return direct;

    final id = _firstText(item, const ['chapterId', 'chapter_id', 'id', 'cid']);
    if (id.isEmpty) return '';
    final uri = Uri.tryParse(book.filePath);
    if (uri != null &&
        uri.hasScheme &&
        (uri.path.contains('findChapterList') ||
            uri.path.contains('chapterList') ||
            uri.path.contains('getchapter'))) {
      final bookId =
          uri.queryParameters['book_id'] ??
          uri.queryParameters['bookId'] ??
          uri.queryParameters['id'] ??
          _firstText(item, const ['bookId', 'book_id']);
      if (bookId.isNotEmpty) {
        final contentUrl = Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: '/chapterContent',
        );
        return '${contentUrl.toString()},${jsonEncode({
          'method': 'POST',
          'body': {'book_id': bookId, 'chapterIdList': '$id,'},
        })}';
      }
    }
    return id;
  }

  static String _firstText(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return '';
  }

  static Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> map) {
    return map.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<List<dynamic>> _findLikelyBookLists(dynamic value) {
    final result = <List<dynamic>>[];
    void visit(dynamic node, [int depth = 0]) {
      if (depth > 5) return;
      if (node is List) {
        if (node.whereType<Map>().any(_looksLikeBookMap)) {
          result.add(node);
        }
        for (final child in node.take(8)) {
          visit(child, depth + 1);
        }
      } else if (node is Map) {
        for (final child in node.values) {
          visit(child, depth + 1);
        }
      }
    }

    visit(value);
    return result;
  }

  static List<List<dynamic>> _findLikelyChapterLists(dynamic value) {
    final result = <List<dynamic>>[];
    void visit(dynamic node, [int depth = 0]) {
      if (depth > 6) return;
      if (node is List) {
        if (node.whereType<Map>().any(_looksLikeChapterMap)) {
          result.add(node);
        }
        for (final child in node.take(12)) {
          visit(child, depth + 1);
        }
      } else if (node is Map) {
        for (final child in node.values) {
          visit(child, depth + 1);
        }
      }
    }

    visit(value);
    return result;
  }

  static bool _looksLikeBookMap(Map<dynamic, dynamic> item) {
    return item.containsKey('title') ||
        item.containsKey('bookName') ||
        item.containsKey('book_name') ||
        item.containsKey('bookTitle') ||
        item.containsKey('articleName') ||
        item.containsKey('novelName') ||
        item.containsKey('name') ||
        item.containsKey('bookId') ||
        item.containsKey('book_id') ||
        item.containsKey('novelId') ||
        item.containsKey('cover') ||
        item.containsKey('summary') ||
        item.containsKey('intro') ||
        item.containsKey('author');
  }

  static bool _looksLikeChapterMap(Map<dynamic, dynamic> item) {
    return item.containsKey('chapterName') ||
        item.containsKey('chapter_name') ||
        item.containsKey('chapterTitle') ||
        item.containsKey('chapter_title') ||
        item.containsKey('chapterUrl') ||
        item.containsKey('chapter_url') ||
        item.containsKey('chapterId') ||
        item.containsKey('chapter_id') ||
        item.containsKey('cid') ||
        item.containsKey('path') ||
        item.containsKey('contentUrl') ||
        (item.containsKey('name') &&
            (item.containsKey('id') ||
                item.containsKey('cid') ||
                item.containsKey('chapterId'))) ||
        (item.containsKey('title') &&
            (item.containsKey('id') || item.containsKey('url')));
  }

  static String detectCharset(List<int> bytes, String? charset, Map<String, List<String>>? headers) {
    if (charset != null && charset.isNotEmpty) {
      return charset;
    }

    var sniffBytes = bytes;
    bool isGzip = false;
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      isGzip = true;
    } else if (headers != null) {
      final encoding = headers['content-encoding']?.join(',').toLowerCase() ?? '';
      if (encoding.contains('gzip')) isGzip = true;
    }

    // 在嗅探前利用 GzipCodec 解压，防止乱码穿透探测器
    if (isGzip) {
      try {
        sniffBytes = GZipCodec().decode(bytes);
      } catch (_) {}
    }

    if (headers != null) {
      final contentType = headers['content-type'] ?? headers['Content-Type'];
      if (contentType != null && contentType.isNotEmpty) {
        final ctStr = contentType.join(' ').toLowerCase();
        if (ctStr.contains('charset=gbk') || ctStr.contains('charset=gb2312')) {
          return 'gbk';
        }
        if (ctStr.contains('charset=utf-8') || ctStr.contains('charset=utf8')) {
          return 'utf-8';
        }
      }
    }

    if (sniffBytes.isEmpty) return 'utf-8';
    final sampleLength = sniffBytes.length < 4096 ? sniffBytes.length : 4096;
    final sampleBytes = sniffBytes.sublist(0, sampleLength);
    final sampleStr = ascii.decode(
      sampleBytes.map((b) => (b >= 0 && b <= 127) ? b : 63).toList(),
    ).toLowerCase();

    if (sampleStr.contains('charset=gbk') ||
        sampleStr.contains('charset="gbk"') ||
        sampleStr.contains("charset='gbk'") ||
        sampleStr.contains('charset=gb2312') ||
        sampleStr.contains('charset="gb2312"') ||
        sampleStr.contains("charset='gb2312'")) {
      return 'gbk';
    }

    return 'utf-8';
  }

  static String decodeBytes(List<int> bytes, String? charset, {Map<String, List<String>>? headers}) {
    if (bytes.isEmpty) return '';
    var contentBytes = bytes;
    
    // 强解 Gzip 逻辑：通过魔法头嗅探（1F 8B）
    bool isGzip = false;
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      isGzip = true;
    } else if (headers != null) {
      final encoding = headers['content-encoding']?.join(',').toLowerCase() ?? '';
      if (encoding.contains('gzip')) isGzip = true;
    }
    
    if (isGzip) {
      try {
        contentBytes = GZipCodec().decode(bytes);
      } catch (e) {
        print('Gzip decode error: $e');
      }
    }
    final detected = detectCharset(contentBytes, charset, headers).toLowerCase().trim();
    if (detected == 'gbk' || detected == 'gb2312') {
      try {
        return gbk.decode(contentBytes);
      } catch (_) {
        return utf8.decode(contentBytes, allowMalformed: true);
      }
    }
    return utf8.decode(contentBytes, allowMalformed: true);
  }

  static String? _decodeDataPayload(String url) {
    final trimmed = url.trim();
    if (!trimmed.startsWith('data:')) return null;
    final comma = trimmed.indexOf(',');
    if (comma < 0) return '';
    final meta = trimmed.substring(5, comma).toLowerCase();
    var payload = trimmed.substring(comma + 1);
    final nextComma = payload.indexOf(',');
    if (nextComma >= 0 &&
        payload.substring(nextComma + 1).trim().startsWith('{')) {
      payload = payload.substring(0, nextComma);
    }
    try {
      if (meta.contains('base64')) {
        return utf8.decode(base64Decode(payload), allowMalformed: true);
      }
      return Uri.decodeComponent(payload);
    } catch (_) {
      return payload;
    }
  }

  // --- RSS Parsing ---

  static Future<List<RssArticle>> parseRssArticles(RssSource source) async {
    final ruleArticles = source.ruleArticles;

    try {
      final response = await _dio.get(source.sourceUrl);
      final data = response.data;
      final articles = <RssArticle>[];

      if (ruleArticles == null || ruleArticles.isEmpty) {
        final standard = _parseStandardFeed(data.toString(), source.sourceUrl);
        if (standard.isNotEmpty) return standard;
        return _parseSourceRepositoryNotice(data, source);
      }

      if (_isJsonRule(ruleArticles) && _looksLikeJsonData(data, ruleArticles)) {
        final jsonData = data is String ? jsonDecode(data) : data;
        final matches = JsonPath(_jsonPathRule(ruleArticles)).read(jsonData);
        for (final match in matches) {
          if (match.value is Map<String, dynamic>) {
            articles.add(
              _parseRssArticleFromJson(
                match.value as Map<String, dynamic>,
                source,
              ),
            );
          }
        }
      } else {
        final document = parse(data.toString());
        final nodes = _queryAll(document, ruleArticles);
        for (final node in nodes) {
          articles.add(_parseRssArticleFromHtmlNode(node, source));
        }
      }
      return articles;
    } catch (e) {
      print('RSS parsing error: $e');
      return [];
    }
  }

  static Future<String> parseRssContent(
    RssSource source,
    String articleUrl,
  ) async {
    final ruleContent = source.ruleContent;
    if (ruleContent == null || ruleContent.isEmpty) {
      if (articleUrl.contains('shuyuan.yiove.com')) {
        return '这是 Yiove 书源仓库页面，不是普通 RSS/Atom 文章订阅。\n\n'
            '它主要用于展示和分发书源集合，所以不会像新闻订阅那样拉取文章列表。'
            '要真正搜索小说，请在“书源”里导入对应的书源集合 URL。';
      }
      try {
        final response = await _dio.get(articleUrl);
        final document = parse(response.data.toString());
        document
            .querySelectorAll('script, style, nav, footer')
            .forEach((element) => element.remove());
        final article = document.querySelector('article') ?? document.body;
        return article?.text.trim() ?? '正文为空';
      } catch (e) {
        return '拉取正文失败: $e';
      }
    }

    try {
      final response = await _dio.get(articleUrl);
      final data = response.data;

      if (_isJsonRule(ruleContent) && _looksLikeJsonData(data, ruleContent)) {
        final jsonData = data is String ? jsonDecode(data) : data;
        return _extractJsonValue(jsonData, ruleContent);
      }

      final document = parse(data.toString());
      final node = _queryOne(document, ruleContent);
      if (node != null) {
        node.querySelectorAll('script, style').forEach((e) => e.remove());
        return node.outerHtml;
      }
    } catch (e) {
      print('RSS Content parsing error: $e');
      return '拉取正文失败';
    }
    return '解析为空';
  }

  static RssArticle _parseRssArticleFromJson(
    Map<String, dynamic> item,
    RssSource source,
  ) {
    final title = _extractJsonValue(item, source.ruleTitle ?? '');
    final link = _extractJsonValue(item, source.ruleLink ?? '');
    final pubDate = _extractJsonValue(item, source.rulePubDate ?? '');
    final description = _extractJsonValue(item, source.ruleDescription ?? '');
    final image = _extractJsonValue(item, source.ruleImage ?? '');

    return RssArticle(
      title: title.isNotEmpty ? title : '无标题',
      link: _resolveUrl(source.sourceUrl, link),
      pubDate: pubDate,
      description: description,
      coverUrl: _resolveUrl(source.sourceUrl, image),
    );
  }

  static List<RssArticle> _parseSourceRepositoryNotice(
    dynamic data,
    RssSource source,
  ) {
    try {
      final jsonData = data is String ? jsonDecode(data) : data;
      final items = jsonData is List ? jsonData : [jsonData];
      final item = items.whereType<Map>().firstWhere(
        (item) =>
            item.containsKey('sourceName') && item.containsKey('sourceUrl'),
        orElse: () => const {},
      );
      if (item.isEmpty) return [];
      final sourceName = item['sourceName']?.toString() ?? source.sourceName;
      final sourceUrl = item['sourceUrl']?.toString() ?? source.sourceUrl;
      final comment = item['sourceComment']?.toString() ?? '';
      final group = item['sourceGroup']?.toString() ?? '';
      if (!sourceName.contains('书源') &&
          !sourceUrl.contains('shuyuan') &&
          group != '书源') {
        return [];
      }
      return [
        RssArticle(
          title: sourceName,
          link: sourceUrl,
          description: comment.isEmpty
              ? '这是书源仓库入口，不是普通文章订阅。'
              : '$comment\n这是书源仓库入口，不是普通文章订阅。',
          coverUrl: item['sourceIcon']?.toString(),
        ),
      ];
    } catch (_) {
      return [];
    }
  }

  static List<RssArticle> _parseStandardFeed(String data, String baseUrl) {
    try {
      final doc = xml.XmlDocument.parse(data);
      final rssItems = doc.findAllElements('item').toList();
      if (rssItems.isNotEmpty) {
        return rssItems.map((item) {
          final title = _xmlText(item, 'title');
          final link = _xmlText(item, 'link');
          final description = _xmlText(item, 'description');
          final pubDate = _xmlText(item, 'pubDate');
          return RssArticle(
            title: title.isEmpty ? '无标题' : title,
            link: _resolveUrl(baseUrl, link),
            description: description,
            pubDate: pubDate,
            coverUrl: _rssImage(item, baseUrl),
          );
        }).toList();
      }

      final entries = doc.findAllElements('entry').toList();
      return entries.map((entry) {
        final title = _xmlText(entry, 'title');
        final linkElement = entry.findElements('link').firstOrNull;
        final link =
            linkElement?.getAttribute('href') ?? _xmlText(entry, 'link');
        final description = _xmlText(entry, 'summary').isNotEmpty
            ? _xmlText(entry, 'summary')
            : _xmlText(entry, 'content');
        final pubDate = _xmlText(entry, 'updated').isNotEmpty
            ? _xmlText(entry, 'updated')
            : _xmlText(entry, 'published');
        return RssArticle(
          title: title.isEmpty ? '无标题' : title,
          link: _resolveUrl(baseUrl, link),
          description: description,
          pubDate: pubDate,
          coverUrl: _rssImage(entry, baseUrl),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static String _xmlText(xml.XmlElement element, String name) {
    return element.findElements(name).firstOrNull?.innerText.trim() ?? '';
  }

  static String? _rssImage(xml.XmlElement element, String baseUrl) {
    for (final media in element.descendants.whereType<xml.XmlElement>()) {
      final local = media.name.local;
      if (local == 'thumbnail' || local == 'content') {
        final url = media.getAttribute('url');
        if (url != null && url.isNotEmpty) return _resolveUrl(baseUrl, url);
      }
      if (local == 'enclosure' &&
          (media.getAttribute('type')?.startsWith('image/') ?? false)) {
        final url = media.getAttribute('url');
        if (url != null && url.isNotEmpty) return _resolveUrl(baseUrl, url);
      }
    }
    return null;
  }

  static RssArticle _parseRssArticleFromHtmlNode(
    Element node,
    RssSource source,
  ) {
    final title = _extractHtmlValue(node, source.ruleTitle ?? '');
    final link = _extractHtmlValue(node, source.ruleLink ?? '');
    final pubDate = _extractHtmlValue(node, source.rulePubDate ?? '');
    final description = _extractHtmlValue(node, source.ruleDescription ?? '');
    final image = _extractHtmlValue(node, source.ruleImage ?? '');

    return RssArticle(
      title: title.isNotEmpty ? title : '无标题',
      link: _resolveUrl(source.sourceUrl, link),
      pubDate: pubDate,
      description: description,
      coverUrl: _resolveUrl(source.sourceUrl, image),
    );
  }
}

class LegadoTestReport {
  final List<LegadoTestStep> steps;

  LegadoTestReport({required this.steps});

  bool get hasFailure =>
      steps.any((step) => step.status == LegadoStepStatus.fail);
}

class LegadoTestStep {
  final String title;
  final String message;
  final String? sample;
  final LegadoStepStatus status;

  const LegadoTestStep({
    required this.title,
    required this.message,
    this.sample,
    required this.status,
  });

  const LegadoTestStep.ok(String title, String message, {String? sample})
    : this(
        title: title,
        message: message,
        sample: sample,
        status: LegadoStepStatus.ok,
      );

  const LegadoTestStep.fail(String title, String message, {String? sample})
    : this(
        title: title,
        message: message,
        sample: sample,
        status: LegadoStepStatus.fail,
      );

  const LegadoTestStep.skip(String title, String message, {String? sample})
    : this(
        title: title,
        message: message,
        sample: sample,
        status: LegadoStepStatus.skip,
      );
}

enum LegadoStepStatus { ok, fail, skip }
