import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
  static const int _minTestContentLength = 120;

  /// 假红防护用的通用回退关键字：覆盖面极广的小说，几乎所有小说源都应有结果。
  /// 仅在书源未自带 checkKeyWord、且默认关键字搜索为空时才重试，避免“能用却测成坏”。
  static const List<String> _fallbackTestKeywords = [
    '剑来',
    '诡秘之主',
    '凡人修仙传',
    '完美世界',
  ];

  static bool get _headlessWebViewDisabled =>
      Platform.environment['LEGADO_DISABLE_HEADLESS_WEBVIEW'] == '1';

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

  static Future<String> buildSearchUrl(BookSource source, String keyword, {int page = 1}) =>
      _buildSearchUrlAsync(source, keyword, page: page);

  static Future<String> buildExploreUrl(BookSource source, {int page = 1}) =>
      _buildExploreUrlAsync(source, page: page);

  static Future<Response<dynamic>> fetchHtml(
    BookSource source,
    String url, {
    String? keyword,
  }) => _request(source, url, keyword: keyword);

  static String _testKeywordForSource(BookSource source, String fallback) {
    final rule = _ruleMap(source.ruleSearch);
    final value = _firstRule(rule, const ['checkKeyWord', 'checkKeyword']);
    final keyword = (value ?? '').trim();
    return keyword.isEmpty ? fallback : keyword;
  }

  /// 从搜索到正文逐步测试书源，方便定位是哪一段规则失效。
  static Future<LegadoTestReport> testSource(
    BookSource source,
    String keyword,
  ) async {
    final steps = <LegadoTestStep>[];
    final testKeyword = _testKeywordForSource(source, keyword);

    // 非小说源（bookSourceType != 0，例如有声书=1、漫画/图片源=2）当前应用仅支持小说，
    // 统一标记为「跳过」而非「失败」，避免一键测源把它们误判为坏源后被一键禁用。
    if (source.bookSourceType != 0) {
      final typeLabel = source.bookSourceType == 1
          ? '有声书源'
          : (source.bookSourceType == 2 ? '漫画/图片源' : '非小说源');
      return LegadoTestReport(
        steps: [
          LegadoTestStep.skip(
            '源类型',
            '$typeLabel（bookSourceType=${source.bookSourceType}）：当前仅支持小说源，已跳过测试。',
            logs: [
              'bookSourceType=${source.bookSourceType}',
              '测试关键字: $testKeyword',
            ],
          ),
        ],
      );
    }

    try {
      if (source.searchUrl == null || source.searchUrl!.isEmpty) {
        steps.add(const LegadoTestStep.fail('搜索 URL', 'searchUrl 为空'));
        return LegadoTestReport(steps: steps);
      }

      // 1. 搜索 URL
      final urlLogs = <String>[
        '配置的 searchUrl: ${source.searchUrl}',
        '输入关键字: $testKeyword',
      ];
      if (testKeyword != keyword) {
        urlLogs.add(
          '使用 ruleSearch.checkKeyWord 覆盖默认测试关键字: $keyword -> $testKeyword',
        );
      }
      late final String searchUrl;
      try {
        searchUrl = await _buildSearchUrlAsync(source, testKeyword);
      } catch (e, stackTrace) {
        steps.add(
          LegadoTestStep.fail(
            '搜索 URL',
            'searchUrl 构建异常：$e',
            logs: [...urlLogs, '构建调用栈:\n$stackTrace'],
          ),
        );
        return LegadoTestReport(steps: steps);
      }
      urlLogs.add('构建后的搜索 URL: $searchUrl');
      if (searchUrl.trim().isEmpty) {
        urlLogs.add('—— JS 引擎诊断（排查真机为何返回空）——');
        urlLogs.add('QuickJS 引擎可用(_runtime 已加载): ${LegadoJsEngine().isAvailable}');
        urlLogs.add('是否落到 Node 兜底: ${LegadoJsEngine().isUsingNodeFallback}');
        urlLogs.add('该 searchUrl 是否含 JS 规则: ${_containsJsRule(source.searchUrl)}');
        steps.add(
          LegadoTestStep.fail(
            '搜索 URL',
            'searchUrl 构建结果为空；通常是 @js/<js> 搜索 URL 执行失败、返回空字符串，或原始规则含未支持的动态占位符。',
            logs: urlLogs,
          ),
        );
        return LegadoTestReport(steps: steps);
      }
      steps.add(LegadoTestStep.ok('搜索 URL', searchUrl, logs: urlLogs));

      // 2. JS 引擎状态
      if (_containsJsRule(source.searchUrl) ||
          _containsJsRule(source.ruleSearch) ||
          _containsJsRule(source.ruleBookInfo) ||
          _containsJsRule(source.ruleToc) ||
          _containsJsRule(source.ruleContent)) {
        final jsLogs = <String>[
          '检查规则以判断是否使用 JS 运行环境:',
          '  searchUrl 包含 JS: ${_containsJsRule(source.searchUrl)}',
          '  ruleSearch 包含 JS: ${_containsJsRule(source.ruleSearch)}',
          '  ruleBookInfo 包含 JS: ${_containsJsRule(source.ruleBookInfo)}',
          '  ruleToc 包含 JS: ${_containsJsRule(source.ruleToc)}',
          '  ruleContent 包含 JS: ${_containsJsRule(source.ruleContent)}',
          '将开启 QuickJS 沙盒并在执行规则时自动注入上下文变量 (result, baseUrl, keyword, page 等)。',
        ];
        steps.add(
          LegadoTestStep.ok(
            'JS 引擎',
            '检测到 @js/<js>/java.* 规则，将使用 QuickJS 引擎执行。',
            logs: jsLogs,
          ),
        );
      }

      // 3. 请求搜索页
      final reqLogs = <String>[];
      reqLogs.add('正在发起 HTTP 请求...');
      reqLogs.add('目标 URL: $searchUrl');

      final reqObj = _buildRequest(source, searchUrl, keyword: testKeyword);
      reqLogs.add('请求方法: ${reqObj.method}');
      reqLogs.add('请求字符集: ${reqObj.charset}');
      reqLogs.add('请求 Headers: ${reqObj.headers}');
      if (reqObj.body != null) {
        reqLogs.add('请求 Body: ${reqObj.body}');
      }

      final searchResponse = await _request(
        source,
        searchUrl,
        keyword: testKeyword,
      );

      reqLogs.add('响应状态码: ${searchResponse.statusCode}');
      reqLogs.add('真实响应 URL: ${searchResponse.realUri}');
      reqLogs.add('响应 Headers:');
      searchResponse.headers.forEach((name, values) {
        reqLogs.add('  $name: ${values.join(", ")}');
      });

      final detectedCharset = detectCharset(
        searchResponse.data is List<int>
            ? searchResponse.data as List<int>
            : utf8.encode(searchResponse.data?.toString() ?? ''),
        reqObj.charset,
        searchResponse.headers.map,
      );
      reqLogs.add('嗅探/检测字符集: $detectedCharset');

      final sampleText = _sample(searchResponse.data);
      reqLogs.add('响应内容前缀采样: $sampleText');

      steps.add(
        LegadoTestStep.ok(
          '请求搜索页',
          'HTTP ${searchResponse.statusCode}',
          sample: sampleText,
          logs: reqLogs,
        ),
      );

      // 4. 搜索结果
      final searchResultLogs = <String>[];
      searchResultLogs.add('正在解析书籍列表...');
      final rule = _ruleMap(source.ruleSearch);
      searchResultLogs.add('搜索规则 ruleSearch: ${source.ruleSearch}');

      final bookListRule = _firstRule(rule, const ['bookList', 'list']);
      searchResultLogs.add('提取的书籍列表规则 (bookList): $bookListRule');
      searchResultLogs.add('搜索页真实响应 URL: ${searchResponse.realUri}');
      searchResultLogs.add('搜索页响应状态码: ${searchResponse.statusCode}');
      searchResultLogs.add('搜索页响应内容前缀采样: ${_sample(searchResponse.data)}');

      // 使用预获取的 Response，避免在数秒内请求同一搜索 URL 两次触发频率限制
      final books = await searchBooks(
        source,
        testKeyword,
        preFetchedResponse: searchResponse,
      );
      searchResultLogs.add('解析得到的书籍数量: ${books.length}');

      // 假红防护：搜索为空且书源未自带 checkKeyWord 时，改用通用关键字重试，
      // 避免“测试书恰好不在该源”被误判为坏源（能用却测成坏）。
      if (books.isEmpty && testKeyword == keyword) {
        for (final fallbackKeyword in _fallbackTestKeywords) {
          if (fallbackKeyword == testKeyword) continue;
          searchResultLogs.add('搜索结果为空，改用通用关键字重试: $fallbackKeyword');
          try {
            final retryUrl = await _buildSearchUrlAsync(source, fallbackKeyword);
            if (retryUrl.trim().isEmpty) {
              searchResultLogs.add('  关键字「$fallbackKeyword」构建搜索 URL 为空，跳过。');
              continue;
            }
            final retryResponse = await _request(
              source,
              retryUrl,
              keyword: fallbackKeyword,
            );
            final retryBooks = await searchBooks(
              source,
              fallbackKeyword,
              preFetchedResponse: retryResponse,
            );
            searchResultLogs.add('  关键字「$fallbackKeyword」解析到 ${retryBooks.length} 本。');
            if (retryBooks.isNotEmpty) {
              books.addAll(retryBooks);
              searchResultLogs.add('  重试成功，使用关键字「$fallbackKeyword」的结果继续后续测试。');
              break;
            }
          } catch (e) {
            searchResultLogs.add('  关键字「$fallbackKeyword」重试异常: $e');
          }
        }
      }

      if (books.isEmpty) {
        searchResultLogs.add(
          '警告：书籍列表解析为空！可能是 bookList 规则未匹配，或者服务器返回了错误页面/频控保护页面。',
        );
        steps.add(
          LegadoTestStep.fail(
            '搜索结果',
            '没有解析出书籍，请检查 ruleSearch.bookList/name/bookUrl',
            logs: searchResultLogs,
          ),
        );
        return LegadoTestReport(steps: steps);
      }

      final pickedBookIndex = _pickTestBookIndex(books, testKeyword);
      var firstBook = books[pickedBookIndex];
      if (pickedBookIndex > 0) {
        searchResultLogs.add(
          '首本与关键词不匹配，改用第 ${pickedBookIndex + 1} 本作为后续详情/目录/正文测试目标。',
        );
      }
      searchResultLogs.add('解析出测试目标书籍信息:');
      searchResultLogs.add('  书名 (title): ${firstBook.title}');
      searchResultLogs.add('  作者 (author): ${firstBook.author}');
      searchResultLogs.add('  链接 (filePath): ${firstBook.filePath}');
      searchResultLogs.add('  封面 (coverPath): ${firstBook.coverPath}');

      steps.add(
        LegadoTestStep.ok(
          '搜索结果',
          '解析到 ${books.length} 本，首本：${firstBook.title}',
          sample: '${firstBook.title}\n${firstBook.filePath}',
          logs: searchResultLogs,
        ),
      );

      // 5. 书籍详情
      Response<dynamic>? detailResponse;
      final detailLogs = <String>[];
      if (source.ruleBookInfo != null && source.ruleBookInfo!.isNotEmpty) {
        detailLogs.add('配置了 ruleBookInfo 详情页规则。开始发起详情页请求...');
        detailLogs.add('详情页 URL (filePath): ${firstBook.filePath}');

        detailResponse = await _request(source, firstBook.filePath);
        detailLogs.add('详情页响应状态: ${detailResponse.statusCode}');
        detailLogs.add('详情页真实 URL: ${detailResponse.realUri}');
        detailLogs.add('详情页响应 Headers: ${detailResponse.headers.map}');

        final detailBook = await parseBookInfo(
          source,
          firstBook,
          preFetchedResponse: detailResponse,
        );
        firstBook = detailBook;

        detailLogs.add('详情页规则解析完毕，合并后书籍信息:');
        detailLogs.add('  书名: ${firstBook.title}');
        detailLogs.add('  作者: ${firstBook.author}');
        detailLogs.add('  封面: ${firstBook.coverPath}');
        detailLogs.add('  链接: ${firstBook.filePath}');

        steps.add(
          LegadoTestStep.ok(
            '书籍详情',
            firstBook.title,
            sample: firstBook.coverPath ?? firstBook.filePath,
            logs: detailLogs,
          ),
        );
      } else {
        detailLogs.add('未配置 ruleBookInfo 详情页规则，跳过详情页网络请求，使用搜索结果中的链接。');
        steps.add(
          LegadoTestStep.skip(
            '书籍详情',
            '未配置 ruleBookInfo，使用搜索结果里的详情链接',
            logs: detailLogs,
          ),
        );
      }

      // 6. 目录列表
      final tocLogs = <String>[];
      tocLogs.add('开始获取目录章节列表...');
      tocLogs.add('目录页/详情页链接: ${firstBook.filePath}');
      tocLogs.add('目录规则 ruleToc: ${source.ruleToc}');

      // 复用详情页的 Response 缓存，大幅减少不必要的重复网络请求
      final chapters = await getChapterList(
        source,
        firstBook,
        preFetchedResponse: detailResponse,
      );

      tocLogs.add('目录解析成功，共解析到 ${chapters.length} 个章节。');

      if (chapters.isEmpty) {
        tocLogs.add('警告：目录章节列表为空！请检查 ruleToc.chapterList。');
        if (detailResponse != null) {
          final dataStr = detailResponse.data?.toString() ?? '';
          tocLogs.add('当前详情页 HTML 响应长度: ${dataStr.length}');
          final sampleLength = dataStr.length > 1000 ? 1000 : dataStr.length;
          if (sampleLength > 0) {
            tocLogs.add(
              '当前详情页 HTML 响应前缀取证 (前 1000 字符):\n${dataStr.substring(0, sampleLength)}',
            );
          }
        }
        steps.add(
          LegadoTestStep.fail(
            '目录',
            '没有解析出章节，请检查 ruleToc.chapterList/chapterName/chapterUrl',
            logs: tocLogs,
          ),
        );
        return LegadoTestReport(steps: steps);
      }

      final firstChapter = chapters.first;
      tocLogs.add('首章节解析结果:');
      tocLogs.add('  章节标题 (title): ${firstChapter.title}');
      tocLogs.add('  章节链接 (url): ${firstChapter.url}');
      tocLogs.add('  章节内部指向链接 (content): ${firstChapter.content}');

      final suspiciousChapter = _firstSuspiciousChapter(
        chapters.take(8),
        firstBook.filePath,
      );
      if (suspiciousChapter != null) {
        tocLogs.add(
          '警告：目录虽然解析出章节，但结果疑似无效：${suspiciousChapter.title} / ${suspiciousChapter.content ?? suspiciousChapter.url ?? ''}',
        );
        steps.add(
          LegadoTestStep.fail(
            '目录',
            '目录解析结果疑似 JS 残片、空链接或详情页重复链接，请检查 ruleToc.chapterName/chapterUrl',
            logs: tocLogs,
          ),
        );
        return LegadoTestReport(steps: steps);
      }

      steps.add(
        LegadoTestStep.ok(
          '目录',
          '解析到 ${chapters.length} 章，首章：${firstChapter.title}',
          sample:
              '${firstChapter.title}\n${firstChapter.content ?? firstChapter.url ?? ''}',
          logs: tocLogs,
        ),
      );

      // 7. 正文
      final contentLogs = <String>[];
      final contentCandidates = chapters
          .where((chapter) {
            final url = (chapter.content ?? chapter.url ?? '').trim();
            return url.isNotEmpty && !url.startsWith('volume://');
          })
          .take(5)
          .toList();
      if (contentCandidates.isEmpty) {
        contentLogs.add('错误：目录只有卷节点或空链接，没有可请求的正文章节。');
        steps.add(
          LegadoTestStep.fail(
            '正文',
            '没有可请求的正文章节，请检查 ruleToc.chapterUrl/isVolume',
            logs: contentLogs,
          ),
        );
        return LegadoTestReport(steps: steps);
      }
      final firstContentChapter = contentCandidates.first;
      final chapterUrl =
          firstContentChapter.content ?? firstContentChapter.url ?? '';
      contentLogs.add('开始获取章节正文内容...');
      contentLogs.add('首章链接: $chapterUrl');

      if (chapterUrl.trim().isEmpty) {
        contentLogs.add('错误：首章链接解析为空，无法发起正文请求。请检查 ruleToc.chapterUrl。');
        steps.add(
          LegadoTestStep.fail(
            '正文',
            '章节链接解析为空，请检查 ruleToc.chapterUrl',
            logs: contentLogs,
          ),
        );
        return LegadoTestReport(steps: steps);
      }

      contentLogs.add('正文规则 ruleContent: ${source.ruleContent}');
      String lastContent = '';
      Chapter? passedChapter;
      String passedContent = '';
      for (var i = 0; i < contentCandidates.length; i++) {
        final candidate = contentCandidates[i];
        final candidateUrl = candidate.content ?? candidate.url ?? '';
        contentLogs.add(
          '正文候选 ${i + 1}/${contentCandidates.length}: ${candidate.title} -> $candidateUrl',
        );
        if (candidateUrl.trim().isEmpty) {
          contentLogs.add('跳过：章节链接为空。');
          continue;
        }
        final content = await getChapterContent(
          source,
          candidateUrl,
          book: firstBook,
          chapter: candidate,
        );
        lastContent = content;
        if (content.isEmpty || content.startsWith('解析失败')) {
          contentLogs.add('候选失败：正文解析失败或为空。返回值: $content');
          continue;
        }
        if (content.trim().length < _minTestContentLength) {
          contentLogs.add('候选失败：正文过短 (${content.trim().length} 字)，继续尝试后续章节。');
          continue;
        }
        if (_looksLikeInvalidContent(content)) {
          contentLogs.add('候选失败：正文长度达标但质量校验未通过（疑似验证页/反爬页/未清洗整页HTML/JS残片），继续尝试后续章节。');
          continue;
        }
        passedChapter = candidate;
        passedContent = content;
        break;
      }

      if (passedChapter == null) {
        final message = lastContent.isEmpty
            ? '没有解析出正文内容'
            : lastContent.startsWith('解析失败')
            ? lastContent
            : lastContent.trim().length < _minTestContentLength
            ? '正文过短，仅 ${lastContent.trim().length} 字，疑似只解析到一小段'
            : '正文长度达标但质量校验未通过，疑似验证页/反爬页/未清洗整页HTML或JS残片，请检查 ruleContent';
        if (lastContent.isNotEmpty) {
          contentLogs.add('最后一次正文内容采样:');
          contentLogs.add(lastContent);
        }
        steps.add(
          LegadoTestStep.fail(
            '正文',
            message,
            sample: lastContent.isEmpty ? null : _sample(lastContent),
            logs: contentLogs,
          ),
        );
      } else {
        contentLogs.add(
          '正文解析成功！命中章节: ${passedChapter.title}，正文字数: ${passedContent.length}',
        );
        contentLogs.add('正文前 500 字符采样:');
        contentLogs.add(
          passedContent.substring(
            0,
            passedContent.length > 500 ? 500 : passedContent.length,
          ),
        );

        steps.add(
          LegadoTestStep.ok(
            '正文',
            '正文解析成功：${passedChapter.title}',
            sample: _sample(passedContent),
            logs: contentLogs,
          ),
        );
      }
    } on LegadoVerificationRequiredException catch (e, stackTrace) {
      steps.add(
        LegadoTestStep.fail(
          '站点验证',
          e.toString(),
          logs: [
            '站点返回验证码/安全验证页，需要在 App 内打开网页完成验证后复测。',
            '异常内容: $e',
            '异常调用栈:\n$stackTrace',
          ],
        ),
      );
    } catch (e, stackTrace) {
      steps.add(
        LegadoTestStep.fail(
          '异常',
          e.toString(),
          logs: ['书源测试过程中抛出未捕获的异常:', '异常内容: $e', '异常调用栈:\n$stackTrace'],
        ),
      );
    }

    return LegadoTestReport(steps: steps);
  }

  /// 搜索书籍。
  static Future<List<Book>> searchBooks(
    BookSource source,
    String keyword, {
    Response<dynamic>? preFetchedResponse,
    CancelToken? cancelToken,
  }) async {
    if (preFetchedResponse != null) {
      return _parseBooksFromResponse(
        source,
        keyword,
        preFetchedResponse,
        page: 1,
      );
    }
    final firstPage = await _searchBooksPage(
      source,
      keyword,
      page: 1,
      cancelToken: cancelToken,
    );
    if (firstPage.isNotEmpty ||
        !(source.searchUrl?.contains('page') ?? false)) {
      return firstPage;
    }
    return _searchBooksPage(source, keyword, page: 0, cancelToken: cancelToken);
  }

  /// 解析发现/分类页书籍。
  static Future<List<Book>> parseExploreBooks(
    BookSource source,
    String targetUrl, {
    required int page,
  }) async {
    final response = await _request(source, targetUrl);
    final html = response.data?.toString() ?? '';
    if (response.statusCode != 200 ||
        html.contains("Bad Gateway") ||
        html.contains("502 Error") ||
        html.contains("502 Bad Gateway") ||
        html.contains("503 Service Temporarily Unavailable") ||
        html.contains("Nginx Error") ||
        html.contains("Server Error") ||
        (html.contains("Cloudflare") &&
            html.contains("checking your browser"))) {
      throw Exception(
        "🚨 核心网络层提示：站点服务器高频反爬拦截或并发熔断 (Status: ${response.statusCode})",
      );
    }

    var data = response.data;

    final exploreRuleStr = source.ruleExplore ?? source.ruleSearch;
    if (exploreRuleStr == null) return [];

    final rule = _ruleMap(exploreRuleStr);
    var bookListRule = _firstRule(rule, const ['bookList', 'list']);
    bool reverseList = false;
    if (bookListRule != null) {
      final trimmed = bookListRule.trim();
      if (trimmed.startsWith('+')) {
        bookListRule = trimmed.substring(1).trim();
      } else if (trimmed.startsWith('-')) {
        bookListRule = trimmed.substring(1).trim();
        reverseList = true;
      }
    }

    if (bookListRule != null) {
      final prepared = await _prepareDataForRule(
        source,
        data,
        bookListRule,
        baseUrl: response.realUri.toString(),
      );
      data = prepared.data;
      bookListRule = prepared.rule;
    }

    final results = <Book>[];
    final regexListRule = bookListRule == null
        ? null
        : _regexListRule(bookListRule);
    if ((bookListRule == null || bookListRule.isEmpty) &&
        _looksLikeJsonData(data, null)) {
      results.addAll(
        await _parseBooksByJsonFallback(
          data,
          rule,
          source,
          baseUrl: response.realUri.toString(),
        ),
      );
    } else if (regexListRule != null) {
      final books = _parseBooksByRegexList(
        data,
        rule,
        source,
        baseUrl: response.realUri.toString(),
        regexRule: regexListRule,
      );
      results.addAll(reverseList ? books.reversed : books);
    } else if (bookListRule != null &&
        _isJsonListRuleForData(data, bookListRule) &&
        _looksLikeJsonData(data, bookListRule)) {
      try {
        final jsonData = data is String ? jsonDecode(data) : data;
        final variables = _jsVariables(
          source,
          result: data is String ? data : jsonEncode(data),
          baseUrl: response.realUri.toString(),
          page: page,
        );
        var nodes = _extractJsonNodes(
          jsonData,
          bookListRule,
          variables: variables,
        );
        if (reverseList) {
          nodes = nodes.reversed.toList();
        }
        for (final node in nodes) {
          if (node is Map<String, dynamic>) {
            results.add(
              await _parseBookFromJsonAsync(
                node,
                rule,
                source,
                baseUrl: response.realUri.toString(),
              ),
            );
          } else if (node is Map) {
            results.add(
              await _parseBookFromJsonAsync(
                node.map((key, value) => MapEntry(key.toString(), value)),
                rule,
                source,
                baseUrl: response.realUri.toString(),
              ),
            );
          }
        }
        if (results.isEmpty) {
          results.addAll(
            await _parseBooksByJsonFallback(
              data,
              rule,
              source,
              baseUrl: response.realUri.toString(),
            ),
          );
        }
      } catch (_) {
        results.addAll(
          await _parseBooksByJsonFallback(
            data,
            rule,
            source,
            baseUrl: response.realUri.toString(),
          ),
        );
      }
    } else if (bookListRule == null || _looksLikeJsonData(data, bookListRule)) {
      results.addAll(
        await _parseBooksByJsonFallback(
          data,
          rule,
          source,
          baseUrl: response.realUri.toString(),
        ),
      );
    } else {
      final document = parse(data.toString());
      var nodes = _queryAll(document, bookListRule);
      if (reverseList) {
        nodes = nodes.reversed.toList();
      }
      for (final node in nodes) {
        results.add(
          _parseBookFromHtmlNode(
            node,
            rule,
            source,
            baseUrl: response.realUri.toString(),
          ),
        );
      }
    }

    return results
        .where(
          (book) =>
              book.title.trim().isNotEmpty &&
              !_isNonNavigableHref(book.filePath),
        )
        .toList();
  }

  static Future<List<Book>> _searchBooksPage(
    BookSource source,
    String keyword, {
    required int page,
    CancelToken? cancelToken,
  }) async {
    if (source.searchUrl == null || source.ruleSearch == null) return [];
    final searchUrl = await _buildSearchUrlAsync(source, keyword, page: page);
    if (searchUrl.trim().isEmpty) {
      throw Exception(
        '搜索 URL 构建结果为空：${source.bookSourceName}。请单源测试查看 searchUrl/@js 规则。',
      );
    }

    final response = await _request(
      source,
      searchUrl,
      keyword: keyword,
      cancelToken: cancelToken,
    );
    return _parseBooksFromResponse(source, keyword, response, page: page);
  }

  static Future<List<Book>> _parseBooksFromResponse(
    BookSource source,
    String keyword,
    Response<dynamic> response, {
    required int page,
  }) async {
    final html = response.data?.toString() ?? '';
    if (response.statusCode != 200 ||
        html.contains("Bad Gateway") ||
        html.contains("502 Error") ||
        html.contains("502 Bad Gateway") ||
        html.contains("503 Service Temporarily Unavailable") ||
        html.contains("Nginx Error") ||
        html.contains("Server Error") ||
        (html.contains("Cloudflare") &&
            html.contains("checking your browser"))) {
      throw Exception(
        "🚨 核心网络层提示：站点服务器高频反爬拦截或并发熔断 (Status: ${response.statusCode})",
      );
    }

    var data = response.data;

    final rule = _ruleMap(source.ruleSearch);
    var bookListRule = _firstRule(rule, const ['bookList', 'list']);
    bool reverseList = false;
    if (bookListRule != null) {
      final trimmed = bookListRule.trim();
      if (trimmed.startsWith('+')) {
        bookListRule = trimmed.substring(1).trim();
      } else if (trimmed.startsWith('-')) {
        bookListRule = trimmed.substring(1).trim();
        reverseList = true;
      }
    }

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
    final regexListRule = bookListRule == null
        ? null
        : _regexListRule(bookListRule);
    if ((bookListRule == null || bookListRule.isEmpty) &&
        _looksLikeJsonData(data, null)) {
      results.addAll(
        await _parseBooksByJsonFallback(
          data,
          rule,
          source,
          baseUrl: response.realUri.toString(),
          keyword: keyword,
        ),
      );
    } else if (regexListRule != null) {
      final books = _parseBooksByRegexList(
        data,
        rule,
        source,
        baseUrl: response.realUri.toString(),
        regexRule: regexListRule,
      );
      results.addAll(reverseList ? books.reversed : books);
    } else if (bookListRule != null &&
        _isJsonListRuleForData(data, bookListRule) &&
        _looksLikeJsonData(data, bookListRule)) {
      try {
        final jsonData = data is String ? jsonDecode(data) : data;
        final variables = _jsVariables(
          source,
          result: data is String ? data : jsonEncode(data),
          baseUrl: response.realUri.toString(),
          keyword: keyword,
          page: page,
        );
        var nodes = _extractJsonNodes(
          jsonData,
          bookListRule,
          variables: variables,
        );
        if (reverseList) {
          nodes = nodes.reversed.toList();
        }
        for (final node in nodes) {
          if (node is Map<String, dynamic>) {
            results.add(
              await _parseBookFromJsonAsync(
                node,
                rule,
                source,
                baseUrl: response.realUri.toString(),
                keyword: keyword,
              ),
            );
          } else if (node is Map) {
            results.add(
              await _parseBookFromJsonAsync(
                node.map((key, value) => MapEntry(key.toString(), value)),
                rule,
                source,
                baseUrl: response.realUri.toString(),
                keyword: keyword,
              ),
            );
          }
        }
        if (results.isEmpty) {
          results.addAll(
            await _parseBooksByJsonFallback(
              data,
              rule,
              source,
              baseUrl: response.realUri.toString(),
              keyword: keyword,
            ),
          );
        }
      } catch (_) {
        results.addAll(
          await _parseBooksByJsonFallback(
            data,
            rule,
            source,
            baseUrl: response.realUri.toString(),
            keyword: keyword,
          ),
        );
      }
    } else if (bookListRule == null || _looksLikeJsonData(data, bookListRule)) {
      results.addAll(
        await _parseBooksByJsonFallback(
          data,
          rule,
          source,
          baseUrl: response.realUri.toString(),
          keyword: keyword,
        ),
      );
    } else {
      final document = parse(data.toString());
      var nodes = _queryAll(document, bookListRule);
      if (reverseList) {
        nodes = nodes.reversed.toList();
      }
      if (nodes.isEmpty) {
        results.addAll(
          _parseBooksByHtmlSearchFallback(
            data,
            source,
            baseUrl: response.realUri.toString(),
            keyword: keyword,
          ),
        );
      } else {
        for (final node in nodes) {
          results.add(
            _parseBookFromHtmlNode(
              node,
              rule,
              source,
              baseUrl: response.realUri.toString(),
            ),
          );
        }
      }
    }

    final filtered = results
        .where(
          (book) =>
              book.title.trim().isNotEmpty &&
              !_isNonNavigableHref(book.filePath),
        )
        .toList();
    if (filtered.isEmpty &&
        source.ruleBookInfo != null &&
        source.ruleBookInfo!.trim().isNotEmpty) {
      try {
        final dummyBook = Book(
          title: '',
          author: '',
          filePath: response.realUri.toString(),
          fileType: 'online',
          isFromSource: true,
          sourceUrl: source.id.toString(),
        );
        final parsedBook = await parseBookInfo(source, dummyBook);
        if (parsedBook.title.isNotEmpty && parsedBook.title != '未知') {
          filtered.add(parsedBook);
        }
      } catch (_) {}
    }

    return filtered;
  }

  /// 获取书籍详情信息。
  static Future<Book> parseBookInfo(
    BookSource source,
    Book book, {
    Response<dynamic>? preFetchedResponse,
  }) async {
    if (source.ruleBookInfo == null || source.ruleBookInfo!.isEmpty) {
      return book;
    }

    final rule = _ruleMap(source.ruleBookInfo);
    final response =
        preFetchedResponse ?? await _request(source, book.filePath);
    final html = response.data?.toString() ?? '';
    if (response.statusCode != 200 ||
        html.contains("Bad Gateway") ||
        html.contains("502 Error") ||
        html.contains("502 Bad Gateway") ||
        html.contains("503 Service Temporarily Unavailable") ||
        html.contains("Nginx Error") ||
        html.contains("Server Error") ||
        (html.contains("Cloudflare") &&
            html.contains("checking your browser"))) {
      throw Exception(
        "🚨 核心网络层提示：站点服务器高频反爬拦截或并发熔断 (Status: ${response.statusCode})",
      );
    }
    var data = response.data;
    final initRule = _firstRule(rule, const ['init']);
    final preparedInit = initRule == null
        ? null
        : await _prepareDataForRule(
            source,
            data,
            initRule,
            baseUrl: response.realUri.toString(),
            book: book,
          );
    if (preparedInit != null) {
      data = preparedInit.data;
    }
    final sampleRule = preparedInit?.rule.isNotEmpty == true
        ? preparedInit!.rule
        : initRule ?? rule.values.whereType<String>().firstOrNull ?? '';

    if (_isJsonRule(sampleRule) && _looksLikeJsonData(data, sampleRule)) {
      final jsonData = data is String ? jsonDecode(data) : data;
      final variables = _jsVariables(
        source,
        result: data is String ? data : jsonEncode(data),
        baseUrl: response.realUri.toString(),
        book: book,
      );
      final root = initRule == null || sampleRule.isEmpty
          ? jsonData
          : _extractJsonNodes(
                  jsonData,
                  sampleRule,
                  variables: variables,
                ).firstOrNull ??
                jsonData;
      if (root is Map<String, dynamic>) {
        return _mergeBookInfo(
          book,
          await _parseBookFromJsonAsync(
            root,
            rule,
            source,
            baseUrl: book.filePath,
            isBookInfo: true,
            contextBook: book,
          ),
        );
      } else if (root is Map) {
        return _mergeBookInfo(
          book,
          await _parseBookFromJsonAsync(
            _stringKeyMap(root),
            rule,
            source,
            baseUrl: book.filePath,
            isBookInfo: true,
            contextBook: book,
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
      _parseBookFromHtmlNode(
        root,
        rule,
        source,
        baseUrl: book.filePath,
        isBookInfo: true,
        contextBook: book,
      ),
    );
  }

  /// 获取目录。
  static Future<List<Chapter>> getChapterList(
    BookSource source,
    Book book, {
    int? limit,
    Response<dynamic>? preFetchedResponse,
  }) async {
    final ruleTocStr = source.ruleToc;
    if (ruleTocStr == null) return [];

    final rule = _ruleMap(ruleTocStr);
    var listRule = _firstRule(rule, const [
      'chapterList',
      'chapterListTOC',
      'chapterListToc',
      'list',
    ]);
    listRule ??= '';
    final reverseTocFromRule = listRule.startsWith('-');
    if (listRule.startsWith('-') || listRule.startsWith('+')) {
      listRule = listRule.substring(1);
    }

    final chapters = <Chapter>[];
    final visitedUrls = <String>{};
    final pendingTocUrls = <String>[];

    var currentResponse =
        preFetchedResponse != null &&
            _responseMatchesUrl(preFetchedResponse, book.filePath)
        ? preFetchedResponse
        : await _request(source, book.filePath);
    currentResponse = await _followTocUrl(
      source,
      book.filePath,
      currentResponse,
      rule,
      book: book,
    );
    currentResponse = await _retryShortenedDuplicatePathIfMissing(
      source,
      currentResponse,
    );

    final html = currentResponse.data?.toString() ?? '';
    if (currentResponse.statusCode != 200 ||
        html.contains("Bad Gateway") ||
        html.contains("502 Error") ||
        html.contains("502 Bad Gateway") ||
        html.contains("503 Service Temporarily Unavailable") ||
        html.contains("Nginx Error") ||
        html.contains("Server Error") ||
        (html.contains("Cloudflare") &&
            html.contains("checking your browser"))) {
      throw Exception(
        "🚨 核心网络层提示：站点服务器高频反爬拦截或并发熔断 (Status: ${currentResponse.statusCode})",
      );
    }

    var currentUrlStr = _responseUrl(
      currentResponse,
      fallback: book.filePath,
    );
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
      final currentBaseUrl = _responseBaseUrl(source, currentUrlStr);

      final prepared = await _prepareDataForRule(
        source,
        data,
        listRule,
        baseUrl: currentBaseUrl,
        book: book,
      );
      final pageData = prepared.data;
      final pageListRule = prepared.rule;

      final pageChapters = <Chapter>[];
      final isVolumeRule = _firstRule(rule, const ['isVolume']);
      final formatJsRule = _firstRule(rule, const ['formatJs']);

      final regexListRule = _regexListRule(pageListRule);
      if (_isJsOnlyRule(pageListRule)) {
        pageChapters.addAll(
          await _parseChaptersByJsListRule(
            source,
            book,
            rule,
            pageData,
            pageListRule,
            currentBaseUrl,
            startIndex: chapters.length,
            limit: limit,
          ),
        );
        if (pageChapters.isEmpty &&
            _looksLikeJsonData(pageData, pageListRule)) {
          pageChapters.addAll(
            _parseChaptersByJsonFallback(
              pageData,
              rule,
              source,
              book,
              currentBaseUrl,
              limit: limit,
            ),
          );
        }
      } else if (regexListRule != null) {
        pageChapters.addAll(
          _parseChaptersByRegexList(
            pageData,
            rule,
            book,
            currentBaseUrl,
            regexListRule,
            startIndex: chapters.length,
            limit: limit,
          ),
        );
      } else if (pageListRule.isEmpty && _looksLikeJsonData(pageData, '')) {
        pageChapters.addAll(
          _parseChaptersByJsonFallback(
            pageData,
            rule,
            source,
            book,
            currentBaseUrl,
            limit: limit,
          ),
        );
      } else if (_isJsonRule(pageListRule) &&
          _looksLikeJsonData(pageData, pageListRule)) {
        try {
          final jsonData = pageData is String ? jsonDecode(pageData) : pageData;
          final variables = _jsVariables(
            source,
            result: pageData is String ? pageData : jsonEncode(pageData),
            baseUrl: currentBaseUrl,
            book: book,
          );
          var index = chapters.length;
          for (final node in _extractJsonNodes(
            jsonData,
            pageListRule,
            variables: variables,
          )) {
            if (limit != null &&
                (chapters.length + pageChapters.length) >= limit) {
              break;
            }
            if (node is! Map) continue;
            final item = node.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            _primeJsonRuleSideEffects(item, rule, source);

            var titleRule =
                _firstRule(rule, const [
                  'chapterName',
                  'chapterNameTOC',
                  'chapterNameToc',
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
              variables: variables,
            );

            var urlRule =
                _firstRule(rule, const [
                  'chapterUrl',
                  'chapterUrlTOC',
                  'chapterUrlToc',
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
              variables: variables,
            );

            bool isVolume = false;
            if (isVolumeRule != null && isVolumeRule.isNotEmpty) {
              final val = _extractJsonValue(
                item,
                _sourceScopedRule(isVolumeRule, source),
                variables: variables,
              );
              isVolume = _isLegadoTrue(val);
            }

            var fullUrl = '';
            if (url.trim().isEmpty) {
              if (isVolume) {
                fullUrl = 'volume://$currentBaseUrl#$index';
              } else {
                fullUrl = currentBaseUrl;
              }
            } else {
              fullUrl = _resolveUrl(currentBaseUrl, url);
            }

            var finalTitle = title.isEmpty ? '第${index + 1}章' : title;
            if (formatJsRule != null && formatJsRule.isNotEmpty) {
              finalTitle = _applyFormatJsSync(
                formatJsRule,
                index: index,
                title: finalTitle,
                url: fullUrl,
              );
            }

            pageChapters.add(
              Chapter(
                bookId: book.id,
                title: finalTitle,
                index: index++,
                content: fullUrl,
                url: fullUrl,
                wordCount: 0,
                isDownloaded: false,
              ),
            );
          }
          if (pageChapters.isEmpty) {
            pageChapters.addAll(
              _parseChaptersByJsonFallback(
                pageData,
                rule,
                source,
                book,
                currentBaseUrl,
                limit: limit,
              ),
            );
          }
        } catch (_) {
          pageChapters.addAll(
            _parseChaptersByJsonFallback(
              pageData,
              rule,
              source,
              book,
              currentBaseUrl,
              limit: limit,
            ),
          );
        }
      } else {
        final document = parse(pageData.toString());
        final nodes = _queryAll(document, pageListRule);
        if (nodes.isEmpty) {
          pageChapters.addAll(
            _parseChaptersByHtmlFallback(
              pageData,
              rule,
              source,
              book,
              currentBaseUrl,
              startIndex: chapters.length,
              limit: limit,
            ),
          );
        }
        var index = chapters.length;
        for (final node in nodes) {
          if (limit != null &&
              (chapters.length + pageChapters.length) >= limit) {
            break;
          }
          _primeHtmlRuleSideEffects(node, rule, source);

          var titleRule =
              _firstRule(rule, const [
                'chapterName',
                'chapterNameTOC',
                'chapterNameToc',
                'name',
                'title',
              ]) ??
              '';
          if (titleRule.trim().isEmpty) titleRule = 'text'; // 默认脑补 'text'
          final title = _extractHtmlValue(
            node,
            _sourceScopedRule(titleRule, source),
          );

          var urlRule =
              _firstRule(rule, const [
                'chapterUrl',
                'chapterUrlTOC',
                'chapterUrlToc',
                'url',
                'link',
              ]) ??
              '';
          if (urlRule.trim().isEmpty) urlRule = 'href'; // 默认脑补 'href'
          final url = _extractHtmlValue(
            node,
            _sourceScopedRule(urlRule, source),
          );

          bool isVolume = false;
          if (isVolumeRule != null && isVolumeRule.isNotEmpty) {
            final val = _extractHtmlValue(
              node,
              _sourceScopedRule(isVolumeRule, source),
            );
            isVolume = _isLegadoTrue(val);
          }

          var fullUrl = '';
          if (url.trim().isEmpty) {
            if (isVolume) {
              fullUrl = 'volume://$currentBaseUrl#$index';
            } else {
              fullUrl = currentBaseUrl;
            }
          } else {
            fullUrl = _resolveUrl(currentBaseUrl, url);
          }

          if (title.trim().isEmpty && url.trim().isEmpty) continue;

          var finalTitle = title.isEmpty ? '第${index + 1}章' : title;
          if (formatJsRule != null && formatJsRule.isNotEmpty) {
            finalTitle = _applyFormatJsSync(
              formatJsRule,
              index: index,
              title: finalTitle,
              url: fullUrl,
            );
          }

          pageChapters.add(
            Chapter(
              bookId: book.id,
              title: finalTitle,
              index: index++,
              content: fullUrl,
              url: fullUrl,
              wordCount: 0,
              isDownloaded: false,
            ),
          );
        }
        if (pageChapters.isEmpty) {
          pageChapters.addAll(
            _parseChaptersByJsonFallback(
              pageData,
              rule,
              source,
              book,
              currentBaseUrl,
              limit: limit,
            ),
          );
          if (pageChapters.isEmpty) {
            pageChapters.addAll(
              _parseChaptersByHtmlFallback(
                pageData,
                rule,
                source,
                book,
                currentBaseUrl,
                startIndex: chapters.length,
                limit: limit,
              ),
            );
          }
        }
        if (pageChapters.isEmpty) {
          for (final fallbackTocUrl in _extractFallbackTocUrls(
            currentBaseUrl,
            pageData.toString(),
          )) {
            if (fallbackTocUrl != currentUrlStr &&
                !visitedUrls.contains(fallbackTocUrl) &&
                !pendingTocUrls.contains(fallbackTocUrl)) {
              pendingTocUrls.add(fallbackTocUrl);
            }
          }
        }
      }

      chapters.addAll(pageChapters);

      if (limit != null && chapters.length >= limit) {
        break;
      }

      // 提取下一页目录 URL
      final nextRule = _firstRule(rule, const [
        'nextTocUrl',
        'nextTocUrlTOC',
        'nextTocUrlToc',
        'nextPageUrl',
        'nextUrl',
      ]);
      if (nextRule != null && nextRule.isNotEmpty) {
        for (final nextUrl in _extractUrlListFromRule(
          currentBaseUrl,
          pageData,
          nextRule,
          source: source,
          book: book,
        )) {
          if (nextUrl != currentUrlStr &&
              !visitedUrls.contains(nextUrl) &&
              !pendingTocUrls.contains(nextUrl)) {
            pendingTocUrls.add(nextUrl);
          }
        }
      }
      if (pendingTocUrls.isEmpty) {
        break;
      }

      Response<dynamic>? nextResponse;
      String? nextUrlResolved;
      while (pendingTocUrls.isNotEmpty) {
        final candidateUrl = pendingTocUrls.removeAt(0);
        try {
          final response = await _request(source, candidateUrl);
          final nextHtml = response.data?.toString() ?? '';
          if (response.statusCode != 200 ||
              nextHtml.contains("Bad Gateway") ||
              nextHtml.contains("502 Error") ||
              nextHtml.contains("502 Bad Gateway") ||
              nextHtml.contains("503 Service Temporarily Unavailable") ||
              nextHtml.contains("Nginx Error") ||
              nextHtml.contains("Server Error") ||
              (nextHtml.contains("Cloudflare") &&
                  nextHtml.contains("checking your browser"))) {
            throw Exception(
              "🚨 核心网络层提示：站点服务器高频反爬拦截或并发熔断 (Status: ${response.statusCode})",
            );
          }
          nextUrlResolved = candidateUrl;
          nextResponse = response;
          break;
        } catch (innerError) {
          debugPrint('Error processing chapter list page: $innerError');
        }
      }

      if (nextResponse == null || nextUrlResolved == null) {
        break;
      }
      currentUrlStr = nextUrlResolved;
      data = nextResponse.data;
    }

    final uniqueChapters = <String, Chapter>{};
    for (final c in chapters) {
      final urlKey = c.url ?? '';
      final titleKey = c.title.trim();
      if (urlKey.isNotEmpty || titleKey.isNotEmpty) {
        uniqueChapters.putIfAbsent('$urlKey\x00$titleKey', () => c);
      } else {
        uniqueChapters['empty_url_${c.title}_${c.index}'] = c;
      }
    }
    var resultList = uniqueChapters.values.toList();
    if (reverseTocFromRule) {
      resultList = resultList.reversed.toList();
    }
    for (int i = 0; i < resultList.length; i++) {
      resultList[i].index = i;
    }
    return resultList;
  }

  static Future<String> getChapterContent(
    BookSource source,
    String chapterUrl, {
    Book? book,
    Chapter? chapter,
  }) async {
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
      final pendingContentUrls = <String>[];

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
          final pageContentRule = _sourceScopedRule(
            contentRule,
            source,
            book: book,
            chapter: chapter,
            contextBaseUrl: currentUrl,
          );

          var response = await _request(source, currentUrl);
          final html = response.data?.toString() ?? '';
          if (response.statusCode != 200 ||
              html.contains("Bad Gateway") ||
              html.contains("502 Error") ||
              html.contains("502 Bad Gateway") ||
              html.contains("503 Service Temporarily Unavailable") ||
              html.contains("Nginx Error") ||
              html.contains("Server Error") ||
              (html.contains("Cloudflare") &&
                  html.contains("checking your browser"))) {
            throw Exception(
              "🚨 核心网络层提示：站点服务器高频反爬拦截或并发熔断 (Status: ${response.statusCode})",
            );
          }
          response = await _followContentUrl(
            source,
            currentUrl,
            response,
            rule,
            book: book,
            chapter: chapter,
          );

          var rawData = response.data.toString();

          // 1. sourceRegex
          final sourceRegexRule = _firstRule(rule, const ['sourceRegex']);
          if (sourceRegexRule != null && sourceRegexRule.isNotEmpty) {
            final scopedSourceRegexRule = _sourceScopedRule(
              sourceRegexRule,
              source,
              book: book,
              chapter: chapter,
              contextBaseUrl: currentUrl,
            );
            final ruleText = scopedSourceRegexRule.startsWith('##')
                ? scopedSourceRegexRule
                : '##$scopedSourceRegexRule';
            rawData = LegadoRuleEvaluator.applyPostProcessors(
              rawData,
              ruleText,
            );
          }

          // 2. webJs
          final webJsRule = _firstRule(rule, const ['webJs']);
          if (webJsRule != null && webJsRule.isNotEmpty) {
            try {
              final variables = _jsVariables(
                source,
                result: rawData,
                baseUrl: currentUrl,
                book: book,
                chapter: chapter,
              );
              final output = await LegadoJsEngine().evaluateWithAjax(
                webJsRule,
                variables: variables,
                libraries: await _sourceLibraryCodes(
                  source,
                  baseUrl: currentUrl,
                ),
                ajax: (request) =>
                    _ajaxForJs(source, request, baseUrl: currentUrl),
                ajaxBytes: (request) =>
                    _ajaxBytesForJs(source, request, baseUrl: currentUrl),
              );
              if (output.trim().isNotEmpty) {
                rawData = output.trim();
              }
            } catch (e) {
              debugPrint('webJs execution failed: $e');
            }
          }

          // 3. content extraction
          final prepared = await _prepareDataForRule(
            source,
            rawData,
            pageContentRule,
            baseUrl: currentUrl,
            book: book,
            chapter: chapter,
          );
          final contentText = await _extractContentFromResponseAsync(
            source,
            prepared.data,
            prepared.rule,
            baseUrl: currentUrl,
            book: book,
            chapter: chapter,
          );
          parts.add(contentText);

          final nextUrls = [
            ..._extractNextContentUrls(
              source,
              response.realUri.toString(),
              rawData,
              rule,
              book: book,
              chapter: chapter,
            ),
          ];
          if (nextUrls.isEmpty) {
            nextUrls.addAll(
              _extractFallbackNextContentUrls(
                response.realUri.toString(),
                response.data?.toString() ?? '',
              ),
            );
          }
          for (final nextUrl in nextUrls) {
            if (nextUrl != currentUrl &&
                !visitedUrls.contains(nextUrl) &&
                !pendingContentUrls.contains(nextUrl)) {
              pendingContentUrls.add(nextUrl);
            }
          }
          if (pendingContentUrls.isEmpty) {
            break;
          }

          currentUrl = pendingContentUrls.removeAt(0);
        } catch (innerError) {
          // 某个正文分页失败时跳过该分页，继续解析已发现的其他分页，避免正文只剩前一小段。
          debugPrint('Error processing chapter content page: $innerError');
          if (pendingContentUrls.isEmpty) break;
          currentUrl = pendingContentUrls.removeAt(0);
        }
      }

      final content = parts
          .map(
            (part) => _applyContentReplaceRegex(
              part,
              rule,
              source: source,
              book: book,
              chapter: chapter,
            ),
          )
          .where((part) => part.trim().isNotEmpty)
          .join('\n');

      var finalContent = content.trim();
      if (finalContent.isEmpty && !_headlessWebViewDisabled) {
        try {
          debugPrint('正文解析为空，尝试 Headless WebView 二次抓取...');
          final fallbackHtml = await _requestViaHeadlessWebView(
            source,
            chapterUrl,
          );
          final prepared = await _prepareDataForRule(
            source,
            fallbackHtml,
            _sourceScopedRule(
              contentRule,
              source,
              book: book,
              chapter: chapter,
              contextBaseUrl: chapterUrl,
            ),
            baseUrl: chapterUrl,
            book: book,
            chapter: chapter,
          );
          final fallbackText = await _extractContentFromResponseAsync(
            source,
            prepared.data,
            prepared.rule,
            baseUrl: chapterUrl,
            book: book,
            chapter: chapter,
          );
          finalContent = _applyContentReplaceRegex(
            fallbackText,
            rule,
            source: source,
            book: book,
            chapter: chapter,
          ).trim();
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
    content = content.replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'), (
      match,
    ) {
      try {
        final code = int.parse(match.group(1)!, radix: 16);
        return String.fromCharCode(code);
      } catch (_) {
        return match.group(0)!;
      }
    });

    return content.trim();
  }

  static Future<String> _extractContentFromResponseAsync(
    BookSource source,
    dynamic data,
    String contentRule, {
    required String baseUrl,
    Book? book,
    Chapter? chapter,
  }) async {
    if (!contentRule.contains('java.ajax')) {
      return _extractContentFromResponse(
        data,
        contentRule,
        source: source,
        baseUrl: baseUrl,
        book: book,
        chapter: chapter,
      );
    }
    final block = _inlineJsPostProcessor(contentRule);
    if (block == null || block.prefix.trim().isEmpty) {
      return _extractContentFromResponse(
        data,
        contentRule,
        source: source,
        baseUrl: baseUrl,
        book: book,
        chapter: chapter,
      );
    }

    final input = _extractContentFromResponse(
      data,
      block.prefix,
      source: source,
      baseUrl: baseUrl,
      book: book,
      chapter: chapter,
    );
    if (input.trim().isEmpty || input.startsWith('解析失败')) {
      return _extractContentFromResponse(
        data,
        contentRule,
        source: source,
        baseUrl: baseUrl,
        book: book,
        chapter: chapter,
      );
    }

    try {
      final output = await LegadoJsEngine().evaluateWithAjax(
        block.script,
        variables: _jsVariables(
          source,
          result: input,
          baseUrl: baseUrl,
          book: book,
          chapter: chapter,
        ),
        libraries: await _sourceLibraryCodes(source, baseUrl: baseUrl),
        ajax: (request) => _ajaxForJs(source, request, baseUrl: baseUrl),
        ajaxBytes: (request) =>
            _ajaxBytesForJs(source, request, baseUrl: baseUrl),
      );
      final suffix = block.suffix.trim();
      if (suffix.isEmpty) return _contentHtmlToText(output);
      return _extractContentFromResponse(
        output,
        suffix,
        source: source,
        baseUrl: baseUrl,
        book: book,
        chapter: chapter,
      );
    } catch (_) {
      return _extractContentFromResponse(
        data,
        contentRule,
        source: source,
        baseUrl: baseUrl,
        book: book,
        chapter: chapter,
      );
    }
  }

  static String _extractContentFromResponse(
    dynamic data,
    String contentRule, {
    BookSource? source,
    String? baseUrl,
    Book? book,
    Chapter? chapter,
  }) {
    if (contentRule.trim().isEmpty) return data.toString().trim();
    final variables = source == null
        ? null
        : _jsVariables(
            source,
            result: data is String ? data : jsonEncode(data),
            baseUrl: baseUrl,
            book: book,
            chapter: chapter,
          );
    if (_isJsonRule(contentRule) && _looksLikeJsonData(data, contentRule)) {
      final jsonData = data is String ? jsonDecode(data) : data;
      return _extractJsonValue(jsonData, contentRule, variables: variables);
    }

    final document = parse(data.toString());
    final root = document.documentElement ?? document.body;
    if (root != null) {
      final evaluated = _extractHtmlValue(
        root,
        contentRule,
        variables: variables,
      );
      if (evaluated.trim().isNotEmpty) {
        return _contentHtmlToText(evaluated);
      }
    }

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
    return _contentHtmlToText(html);
  }

  static String _contentHtmlToText(String html) {
    final document = parse(html);
    final root = document.body ?? document.documentElement;
    root
        ?.querySelectorAll('script, style, noscript, iframe')
        .forEach((element) => element.remove());
    html = root?.innerHtml ?? html;
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
    Book? contextBook,
  }) {
    _primeJsonRuleSideEffects(item, rule, source);
    final fieldVariables = _jsVariables(
      source,
      result: jsonEncode(item),
      baseUrl: baseUrl ?? source.bookSourceUrl,
      book: contextBook,
    );
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
          book: contextBook,
        ),
        variables: fieldVariables,
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
          book: contextBook,
        ),
        variables: fieldVariables,
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
          book: contextBook,
        ),
        variables: fieldVariables,
      ),
    );
    final bookUrlRule = isBookInfo
        ? (rule['tocUrl'] ?? rule['catalogUrl'] ?? rule['bookUrl'])
        : (rule['bookUrl'] ?? rule['tocUrl'] ?? rule['catalogUrl']);
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
          book: contextBook,
        ),
        variables: fieldVariables,
      ),
    );
    final base = baseUrl ?? source.bookSourceUrl;

    // 提取 wordCount
    final wordCountStr = _cleanRuleOutput(
      _extractJsonValue(
        item,
        _sourceScopedRule(
          _ruleOrKey(rule['wordCount'], item, [
            'wordCount',
            'WordCount',
            'word_count',
            'words',
            'Words',
            'size',
            'Size',
          ]),
          source,
          book: contextBook,
        ),
        variables: fieldVariables,
      ),
    );

    // 提取 lastChapter
    final lastChapter = _cleanRuleOutput(
      _extractJsonValue(
        item,
        _sourceScopedRule(
          _ruleOrKey(rule['lastChapter'], item, [
            'lastChapter',
            'LastChapter',
            'last_chapter',
            'lastChapterName',
            'latestChapter',
          ]),
          source,
          book: contextBook,
        ),
        variables: fieldVariables,
      ),
    );

    int totalChapters = 0;
    final chMatch = RegExp(r'第\s*(\d+)\s*[章|回]').firstMatch(lastChapter);
    if (chMatch != null) {
      totalChapters = int.tryParse(chMatch.group(1) ?? '') ?? 0;
    } else {
      final chMatch2 = RegExp(r'(\d+)\s*章').firstMatch(lastChapter);
      if (chMatch2 != null) {
        totalChapters = int.tryParse(chMatch2.group(1) ?? '') ?? 0;
      }
    }

    int wordCount = 0;
    if (wordCountStr.isNotEmpty) {
      if (wordCountStr.contains('万')) {
        final numPart =
            double.tryParse(wordCountStr.split('万').first.trim()) ?? 0;
        wordCount = (numPart * 10000).toInt();
      } else {
        wordCount =
            int.tryParse(wordCountStr.replaceAll(RegExp(r'\D'), '')) ?? 0;
      }
    }

    return Book(
      title: name.isNotEmpty ? name : '未知',
      author: author,
      filePath: _resolveBookUrl(base, bookUrl),
      fileType: 'online',
      coverPath: _resolveUrl(base, coverUrl),
      isFromSource: true,
      sourceUrl: source.id.toString(),
      totalChapters: totalChapters,
      fileSize: wordCount,
    );
  }

  static Future<Book> _parseBookFromJsonAsync(
    Map<String, dynamic> item,
    Map<String, dynamic> rule,
    BookSource source, {
    String? baseUrl,
    bool isBookInfo = false,
    String? keyword,
    Book? contextBook,
  }) async {
    final baseBook = _parseBookFromJson(
      item,
      rule,
      source,
      baseUrl: baseUrl,
      isBookInfo: isBookInfo,
      contextBook: contextBook,
    );
    final base = baseUrl ?? source.bookSourceUrl;

    try {
      final coverUrl = await _resolveJsonAjaxFieldValue(
        source,
        item,
        _sourceScopedRule(
          _ruleOrKey(rule['coverUrl'], item, const [
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
          book: contextBook,
        ),
        baseUrl: base,
        keyword: keyword,
        book: contextBook,
      );
      final bookUrlRule = isBookInfo
          ? (rule['tocUrl'] ?? rule['catalogUrl'] ?? rule['bookUrl'])
          : (rule['bookUrl'] ?? rule['tocUrl'] ?? rule['catalogUrl']);
      final bookUrl = await _resolveJsonAjaxFieldValue(
        source,
        item,
        _sourceScopedRule(
          _ruleOrKey(bookUrlRule, item, const [
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
          book: contextBook,
        ),
        baseUrl: base,
        keyword: keyword,
        book: contextBook,
      );
      final wordCountStr = await _resolveJsonAjaxFieldValue(
        source,
        item,
        _sourceScopedRule(
          _ruleOrKey(rule['wordCount'], item, const [
            'wordCount',
            'WordCount',
            'word_count',
            'words',
            'Words',
            'size',
            'Size',
          ]),
          source,
          book: contextBook,
        ),
        baseUrl: base,
        keyword: keyword,
        book: contextBook,
      );
      final lastChapter = await _resolveJsonAjaxFieldValue(
        source,
        item,
        _sourceScopedRule(
          _ruleOrKey(rule['lastChapter'], item, const [
            'lastChapter',
            'LastChapter',
            'last_chapter',
            'lastChapterName',
            'latestChapter',
          ]),
          source,
          book: contextBook,
        ),
        baseUrl: base,
        keyword: keyword,
        book: contextBook,
      );

      final asyncWordCount = _parseWordCount(wordCountStr ?? '');
      final asyncTotalChapters = _parseChapterCount(lastChapter ?? '');
      return baseBook.copyWith(
        coverPath: coverUrl == null || coverUrl.isEmpty
            ? null
            : _resolveUrl(base, coverUrl),
        filePath: bookUrl == null || bookUrl.isEmpty
            ? null
            : _resolveBookUrl(base, bookUrl),
        fileSize: asyncWordCount > 0 ? asyncWordCount : null,
        totalChapters: asyncTotalChapters > 0 ? asyncTotalChapters : null,
      );
    } catch (_) {
      return baseBook;
    }
  }

  static Future<String?> _resolveJsonAjaxFieldValue(
    BookSource source,
    Map<String, dynamic> item,
    String rawRule, {
    required String baseUrl,
    String? keyword,
    Book? book,
  }) async {
    final rule = _sourceScopedRule(rawRule, source).trim();
    if (!rule.contains('java.ajax')) return null;
    final block = _inlineJsPostProcessor(rule);
    if (block == null || block.prefix.trim().isEmpty) return null;

    final input = _cleanRuleOutput(_extractJsonValue(item, block.prefix));
    if (input.trim().isEmpty) return null;

    final output = await LegadoJsEngine().evaluateWithAjax(
      block.script,
      variables: _jsVariables(
        source,
        result: input,
        baseUrl: baseUrl,
        keyword: keyword,
        book: book,
      ),
      libraries: await _sourceLibraryCodes(source, baseUrl: baseUrl),
      ajax: (request) =>
          _ajaxForJs(source, request, baseUrl: baseUrl, keyword: keyword),
      ajaxBytes: (request) =>
          _ajaxBytesForJs(source, request, baseUrl: baseUrl, keyword: keyword),
    );
    final value = _applyAjaxFieldSuffix(output, block.suffix);
    return value.trim().isEmpty ? null : value;
  }

  static ({String prefix, String script, String suffix})?
  _inlineJsPostProcessor(String rule) {
    final tagStart = rule.indexOf('<js>');
    final atStart = rule.indexOf('@js:');
    final useTag = tagStart >= 0 && (atStart < 0 || tagStart < atStart);
    if (useTag) {
      final close = rule.indexOf('</js>', tagStart);
      if (close < 0) return null;
      final end = close + '</js>'.length;
      return (
        prefix: rule.substring(0, tagStart),
        script: rule.substring(tagStart, end),
        suffix: rule.substring(end),
      );
    }
    if (atStart >= 0) {
      final regexStart = rule.indexOf('##', atStart + 4);
      final end = regexStart < 0 ? rule.length : regexStart;
      return (
        prefix: rule.substring(0, atStart),
        script: rule.substring(atStart, end),
        suffix: regexStart < 0 ? '' : rule.substring(regexStart),
      );
    }
    return null;
  }

  static String _applyAjaxFieldSuffix(String output, String suffix) {
    final text = output.trim();
    final rule = suffix.trim();
    if (text.isEmpty || rule.isEmpty) return text;
    try {
      if (_isJsonRule(rule) && _looksLikeJsonData(text, rule)) {
        final jsonData = jsonDecode(text);
        return _cleanRuleOutput(_extractJsonValue(jsonData, rule));
      }
    } catch (_) {}
    return _cleanRuleOutput(
      LegadoRuleEvaluator.applyPostProcessors(text, rule),
    );
  }

  static int _parseChapterCount(String value) {
    for (final pattern in const [
      r'chapter\s*(\d+)',
      r'\u7b2c\s*(\d+)\s*(?:\u7ae0|\u8282|\u5377|\u56de|\u96c6)?',
      r'(\d+)\s*(?:\u7ae0|\u8282|\u5377|\u56de|\u96c6)',
      r'(\d+)\s*(?:chapter|chapters)',
    ]) {
      final match = RegExp(pattern, caseSensitive: false).firstMatch(value);
      if (match != null) return int.tryParse(match.group(1) ?? '') ?? 0;
    }
    return 0;
  }

  static int _parseWordCount(String value) {
    if (value.isEmpty) return 0;
    if (value.contains('\u4e07')) {
      final numPart = double.tryParse(value.split('\u4e07').first.trim()) ?? 0;
      return (numPart * 10000).toInt();
    }
    return int.tryParse(value.replaceAll(RegExp(r'\D'), '')) ?? 0;
  }

  static Book _parseBookFromHtmlNode(
    Element node,
    Map<String, dynamic> rule,
    BookSource source, {
    String? baseUrl,
    bool isBookInfo = false,
    Book? contextBook,
  }) {
    _primeHtmlRuleSideEffects(node, rule, source);
    final fieldVariables = _jsVariables(
      source,
      result: node.outerHtml,
      baseUrl: baseUrl ?? source.bookSourceUrl,
      book: contextBook,
    );
    final name = _extractHtmlValue(
      node,
      _sourceScopedRule(
        _firstRule(rule, const ['name']) ?? '',
        source,
        book: contextBook,
      ),
      variables: fieldVariables,
    );
    final author = _extractHtmlValue(
      node,
      _sourceScopedRule(
        _firstRule(rule, const ['author']) ?? '',
        source,
        book: contextBook,
      ),
      variables: fieldVariables,
    );
    final coverUrl = _extractHtmlValue(
      node,
      _sourceScopedRule(
        _firstRule(rule, const ['coverUrl', 'cover']) ?? '',
        source,
        book: contextBook,
      ),
      variables: fieldVariables,
    );
    final bookUrlKeys = isBookInfo
        ? const ['tocUrl', 'catalogUrl']
        : const ['bookUrl', 'tocUrl', 'catalogUrl', 'url'];
    final rawBookUrlRule = _firstRule(rule, bookUrlKeys);
    final bookUrl = rawBookUrlRule == null || rawBookUrlRule.trim().isEmpty
        ? ''
        : _extractHtmlValue(
            node,
            _sourceScopedRule(rawBookUrlRule, source, book: contextBook),
            variables: fieldVariables,
          );
    final base = baseUrl ?? source.bookSourceUrl;
    var filePath = bookUrl.trim().isEmpty && !isBookInfo
        ? ''
        : _resolveBookUrl(base, bookUrl);
    if (!isBookInfo &&
        (_isNonNavigableHref(bookUrl) ||
            _isNonNavigableHref(filePath) ||
            _hasMultipleUrlCandidates(bookUrl) ||
            _looksSuspiciousResolvedBookUrl(filePath))) {
      final fallbackBookUrl = _fallbackBookUrlFromHtmlNode(node, base);
      if (fallbackBookUrl.isNotEmpty) {
        filePath = fallbackBookUrl;
      }
    }
    filePath = _normalizeSuspiciousBookUrl(filePath);

    final wordCountStr = _extractHtmlValue(
      node,
      _sourceScopedRule(
        _firstRule(rule, const ['wordCount']) ?? '',
        source,
        book: contextBook,
      ),
      variables: fieldVariables,
    );
    final lastChapter = _extractHtmlValue(
      node,
      _sourceScopedRule(
        _firstRule(rule, const ['lastChapter']) ?? '',
        source,
        book: contextBook,
      ),
      variables: fieldVariables,
    );

    int totalChapters = 0;
    final chMatch = RegExp(r'第\s*(\d+)\s*[章|回]').firstMatch(lastChapter);
    if (chMatch != null) {
      totalChapters = int.tryParse(chMatch.group(1) ?? '') ?? 0;
    } else {
      final chMatch2 = RegExp(r'(\d+)\s*章').firstMatch(lastChapter);
      if (chMatch2 != null) {
        totalChapters = int.tryParse(chMatch2.group(1) ?? '') ?? 0;
      }
    }

    int wordCount = 0;
    if (wordCountStr.isNotEmpty) {
      if (wordCountStr.contains('万')) {
        final numPart =
            double.tryParse(wordCountStr.split('万').first.trim()) ?? 0;
        wordCount = (numPart * 10000).toInt();
      } else {
        wordCount =
            int.tryParse(wordCountStr.replaceAll(RegExp(r'\D'), '')) ?? 0;
      }
    }

    return Book(
      title: name.isNotEmpty ? name : '未知',
      author: author,
      filePath: filePath,
      fileType: 'online',
      coverPath: _resolveUrl(base, coverUrl),
      isFromSource: true,
      sourceUrl: source.id.toString(),
      totalChapters: totalChapters,
      fileSize: wordCount,
    );
  }

  static String _fallbackBookUrlFromHtmlNode(Element node, String baseUrl) {
    final anchors = <Element>[];
    if (node.localName?.toLowerCase() == 'a' &&
        node.attributes.containsKey('href')) {
      anchors.add(node);
    }
    anchors.addAll(node.querySelectorAll('a[href]'));

    for (final anchor in anchors) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (_isNonNavigableHref(href)) continue;
      final resolved = _resolveBookUrl(baseUrl, href);
      if (_isNonNavigableHref(resolved)) continue;
      if (!_looksLikeBookDetailHref(href) &&
          !_looksLikeBookDetailHref(resolved)) {
        continue;
      }
      return resolved;
    }
    return '';
  }

  static Book _mergeBookInfo(Book origin, Book detail) {
    return origin.copyWith(
      title: detail.title == '未知' ? origin.title : detail.title,
      author: detail.author.isEmpty ? origin.author : detail.author,
      coverPath: detail.coverPath?.isEmpty ?? true
          ? origin.coverPath
          : detail.coverPath,
      filePath: _selectBetterBookPath(origin.filePath, detail.filePath),
      totalChapters: detail.totalChapters > 0
          ? detail.totalChapters
          : origin.totalChapters,
      fileSize: detail.fileSize > 0 ? detail.fileSize : origin.fileSize,
    );
  }

  static String _selectBetterBookPath(String originPath, String detailPath) {
    if (detailPath.isEmpty) return originPath;
    if (originPath.isEmpty) return detailPath;
    if (detailPath.toLowerCase().contains('javascript:')) return originPath;
    if (_looksLikeUnresolvedDataPath(detailPath)) {
      return _repairBookDataPathFromOriginId(originPath, detailPath) ??
          originPath;
    }
    if (_looksLikeBookDetailHref(originPath) &&
        _looksLikeCollectionPageUrl(detailPath)) {
      return originPath;
    }

    try {
      final origin = Uri.parse(originPath);
      final detail = Uri.parse(detailPath);
      if (origin.hasScheme &&
          detail.hasScheme &&
          origin.host.toLowerCase() == detail.host.toLowerCase()) {
        final originSegments = origin.pathSegments
            .where((segment) => segment.trim().isNotEmpty)
            .toList();
        final detailSegments = detail.pathSegments
            .where((segment) => segment.trim().isNotEmpty)
            .toList();

        if (originSegments.isNotEmpty &&
            detailSegments.length == originSegments.length + 1 &&
            _listStartsWith(detailSegments, originSegments) &&
            detailSegments.last == originSegments.last) {
          return originPath;
        }
      }
    } catch (_) {
      return detailPath;
    }

    return detailPath;
  }

  static bool _looksLikeUnresolvedDataPath(String path) {
    final text = path.trim();
    if (!text.toLowerCase().startsWith('data:')) return false;
    final decoded = _decodeDataPayload(text);
    if (_isPlaceholderDataPayload(decoded)) return true;
    final trailingPayload = RegExp(
      r'\}([A-Za-z0-9+/_=-]+)$',
    ).firstMatch(text)?.group(1);
    if (trailingPayload == null || trailingPayload.isEmpty) return false;
    try {
      final normalized = trailingPayload
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      final padded = normalized.padRight(
        normalized.length + (4 - normalized.length % 4) % 4,
        '=',
      );
      final trailingDecoded = utf8.decode(
        base64Decode(padded),
        allowMalformed: true,
      );
      return _isPlaceholderDataPayload(trailingDecoded);
    } catch (_) {
      return false;
    }
  }

  static String? _repairBookDataPathFromOriginId(
    String originPath,
    String dataPath,
  ) {
    final lower = dataPath.trimLeft().toLowerCase();
    if (!lower.startsWith('data:bookid') &&
        !lower.startsWith('data:book_id')) {
      return null;
    }
    var id = _extractRequestBodyBookId(originPath);
    if (id.isEmpty) {
      final uri = Uri.tryParse(originPath);
      if (uri != null) {
        for (final segment in uri.pathSegments.reversed) {
          final match = RegExp(r'\d{2,}').firstMatch(segment);
          if (match != null) {
            id = match.group(0) ?? '';
            break;
          }
        }
      }
    }
    if (id.isEmpty) return null;
    final comma = dataPath.indexOf(',');
    if (comma < 0) return null;
    final prefix = dataPath.substring(0, comma + 1);
    final tail = dataPath.substring(comma + 1);
    final metadata = RegExp(r',(\s*\{[^{}]*\})').firstMatch(tail)?.group(1);
    final payload = base64Encode(utf8.encode(id));
    return metadata == null ? '$prefix$payload' : '$prefix$payload,$metadata';
  }

  static bool _isPlaceholderDataPayload(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    return const {
      'bookid',
      'book_id',
      'chapterid',
      'chapter_id',
      'result',
      'id',
      'url',
    }.contains(text);
  }

  static bool _looksLikeCollectionPageUrl(String url) {
    final uri = Uri.tryParse(url.trim().toLowerCase());
    if (uri == null) return false;
    final path = uri.path;
    if (path.isEmpty || path == '/') return true;
    return RegExp(
      r'/(cat|category|class|sort|list|rank|top|tag|search|fenlei|leibie)(/|_|\.|$)',
    ).hasMatch(path);
  }

  static bool _listStartsWith(List<String> list, List<String> prefix) {
    if (prefix.length > list.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (list[i] != prefix[i]) return false;
    }
    return true;
  }

  static bool _listEquals(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static bool _responseMatchesUrl(Response<dynamic> response, String url) {
    try {
      final actual = response.realUri;
      final expected = Uri.parse(url);
      if (actual.scheme.toLowerCase() != expected.scheme.toLowerCase()) {
        return false;
      }
      if (actual.host.toLowerCase() != expected.host.toLowerCase()) {
        return false;
      }
      final actualPath = _normalizedComparePath(actual);
      final expectedPath = _normalizedComparePath(expected);
      if (actualPath != expectedPath) return false;
      return actual.query == expected.query;
    } catch (_) {
      return _responseUrl(response) == url;
    }
  }

  static String _responseUrl(Response<dynamic> response, {String? fallback}) {
    try {
      return response.realUri.toString();
    } catch (_) {
      final path = response.requestOptions.path;
      if (path.isNotEmpty) return path;
      return fallback ?? '';
    }
  }

  static String _responseBaseUrl(BookSource source, String responseUrl) {
    final lower = responseUrl.trimLeft().toLowerCase();
    if (lower.startsWith('data:') || lower.startsWith('javascript:')) {
      return LegadoRequestBuilder.cleanBaseUrl(source.bookSourceUrl);
    }
    return responseUrl;
  }

  static String _normalizedComparePath(Uri uri) {
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    return path.isEmpty ? '/' : path;
  }

  static Future<Response<dynamic>> _retryShortenedDuplicatePathIfMissing(
    BookSource source,
    Response<dynamic> response,
  ) async {
    if (!_looksLikeMissingPage(response.data?.toString() ?? '')) {
      return response;
    }

    final fixedUrl = _trimRepeatedLastPathSegment(response.realUri.toString());
    if (fixedUrl == null || fixedUrl == response.realUri.toString()) {
      return response;
    }

    try {
      final retry = await _request(source, fixedUrl);
      if (!_looksLikeMissingPage(retry.data?.toString() ?? '')) {
        return retry;
      }
    } catch (_) {
      return response;
    }

    return response;
  }

  static String? _trimRepeatedLastPathSegment(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments
          .where((segment) => segment.trim().isNotEmpty)
          .toList();
      if (segments.length < 2) return null;
      if (segments.last != segments[segments.length - 2]) return null;

      final shortened = segments.take(segments.length - 1).toList();
      return uri.replace(pathSegments: shortened).toString();
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeMissingPage(String html) {
    final lower = html.toLowerCase();
    return lower.contains('<title>not found</title>') ||
        lower.contains('<h1>not found</h1>') ||
        lower.contains('404 not found') ||
        lower.contains('页面不存在') ||
        lower.contains('访问的页面不存在') ||
        lower.contains('您访问的页面不存在');
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

  static void _primeJsonRuleSideEffects(
    Map<String, dynamic> item,
    Map<String, dynamic> rule,
    BookSource source,
  ) {
    for (final value in rule.values) {
      final text = value?.toString() ?? '';
      if (!text.toLowerCase().contains('@put:')) continue;
      try {
        _extractJsonValue(item, _sourceScopedRule(text, source));
      } catch (_) {
        // @put side effects are best-effort; the field parser will still run.
      }
    }
  }

  static void _primeHtmlRuleSideEffects(
    Element node,
    Map<String, dynamic> rule,
    BookSource source,
  ) {
    for (final value in rule.values) {
      final text = value?.toString() ?? '';
      if (!text.toLowerCase().contains('@put:')) continue;
      try {
        _extractHtmlValue(node, _sourceScopedRule(text, source));
      } catch (_) {
        // @put side effects are best-effort; the field parser will still run.
      }
    }
  }

  static String _sourceScopedRule(
    String rule,
    BookSource source, {
    Book? book,
    Chapter? chapter,
    String? contextBaseUrl,
  }) {
    if (rule.isEmpty) return '';
    final baseUrl = LegadoRequestBuilder.cleanBaseUrl(
      contextBaseUrl ?? source.bookSourceUrl,
    ).replaceAll(RegExp(r'/+$'), '');
    var output = rule
        .replaceAll('{{source.bookSourceUrl}}', baseUrl)
        .replaceAll('{source.bookSourceUrl}', baseUrl)
        .replaceAll('{{source.key}}', baseUrl)
        .replaceAll('{source.key}', baseUrl)
        .replaceAll('{{source.getKey()}}', baseUrl)
        .replaceAll('{source.getKey()}', baseUrl)
        .replaceAll('{{baseUrl}}', baseUrl)
        .replaceAll('{baseUrl}', baseUrl);
    String replaceToken(String text, String name, String value) {
      return text.replaceAll('{{$name}}', value).replaceAll('{$name}', value);
    }

    output = replaceToken(
      output,
      'book.origin',
      LegadoRequestBuilder.cleanBaseUrl(source.bookSourceUrl),
    );
    output = replaceToken(
      output,
      'book.bookSourceUrl',
      LegadoRequestBuilder.cleanBaseUrl(source.bookSourceUrl),
    );

    if (book != null) {
      output = replaceToken(output, 'book.name', book.title);
      output = replaceToken(output, 'book.title', book.title);
      output = replaceToken(output, 'book.author', book.author);
      output = replaceToken(output, 'book.bookUrl', book.filePath);
      output = replaceToken(output, 'book.url', book.filePath);
      output = replaceToken(
        output,
        'book.origin',
        LegadoRequestBuilder.cleanBaseUrl(source.bookSourceUrl),
      );
      output = replaceToken(output, 'book.tocUrl', book.filePath);
      output = replaceToken(output, 'book.coverUrl', book.coverPath ?? '');
      output = replaceToken(output, 'book.coverPath', book.coverPath ?? '');
    }
    if (chapter != null) {
      final chapterUrl = chapter.url ?? chapter.content ?? '';
      output = replaceToken(output, 'chapter.title', chapter.title);
      output = replaceToken(output, 'chapter.name', chapter.title);
      output = replaceToken(output, 'chapter.url', chapterUrl);
      output = replaceToken(output, 'chapter.index', chapter.index.toString());
    }
    return output;
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
    Map<String, dynamic> rule, {
    Book? book,
  }) async {
    final tocUrlRule = _firstRule(rule, const [
      'tocUrl',
      'catalogUrl',
      'chapterListUrl',
      'chapterListUrlTOC',
    ]);
    if (tocUrlRule == null) return response;
    final data = response.data;
    String tocUrl = '';
    final scopedRule = _sourceScopedRule(
      tocUrlRule,
      source,
      book: book,
      contextBaseUrl: baseUrl,
    );
    final variables = _jsVariables(
      source,
      result: data is String ? data : jsonEncode(data),
      baseUrl: baseUrl,
      book: book,
    );
    if (_looksLikeJsonData(data, scopedRule) && _isJsonRule(scopedRule)) {
      final jsonData = data is String ? jsonDecode(data) : data;
      tocUrl = _extractJsonValue(jsonData, scopedRule, variables: variables);
    } else {
      final document = parse(data.toString());
      final root = document.documentElement ?? document.body;
      if (root != null) {
        tocUrl = _extractHtmlValue(root, scopedRule, variables: variables);
      }
    }
    tocUrl = _fillStoredBookIdInRequestBody(tocUrl, book: book);
    if (tocUrl.trim().isEmpty) return response;
    return _request(source, _resolveUrl(baseUrl, tocUrl));
  }

  static String _fillStoredBookIdInRequestBody(String url, {Book? book}) {
    var saved = LegadoJsEngine().getStoredString('savebid').trim();
    if (saved.isEmpty) {
      saved = _extractRequestBodyBookId(book?.filePath ?? '');
    }
    if (saved.isEmpty) return url;
    return url.replaceAllMapped(
      RegExp(
        r'''((?:bID|bid|bookId|book_id)=)(?=(&|["'}\]]|$))''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}$saved',
    );
  }

  static String _extractRequestBodyBookId(String value) {
    final match = RegExp(
      r'''(?:bID|bid|bookId|book_id)=([^&"'}\]\s]+)''',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1)?.trim() ?? '';
  }

  static Future<Response<dynamic>> _followContentUrl(
    BookSource source,
    String baseUrl,
    Response<dynamic> response,
    Map<String, dynamic> rule, {
    Book? book,
    Chapter? chapter,
  }) async {
    final contentUrlRule = _firstRule(rule, const [
      'contentUrl',
      'realContentUrl',
    ]);
    if (contentUrlRule == null) return response;
    final data = response.data;
    String contentUrl = '';
    final scopedRule = _sourceScopedRule(
      contentUrlRule,
      source,
      book: book,
      chapter: chapter,
      contextBaseUrl: baseUrl,
    );
    final variables = _jsVariables(
      source,
      result: data is String ? data : jsonEncode(data),
      baseUrl: baseUrl,
      book: book,
      chapter: chapter,
    );
    if (_looksLikeJsonData(data, scopedRule) && _isJsonRule(scopedRule)) {
      final jsonData = data is String ? jsonDecode(data) : data;
      contentUrl = _extractJsonValue(
        jsonData,
        scopedRule,
        variables: variables,
      );
    } else {
      final document = parse(data.toString());
      final root = document.documentElement ?? document.body;
      if (root != null) {
        contentUrl = _extractHtmlValue(root, scopedRule, variables: variables);
      }
    }
    if (contentUrl.trim().isEmpty) return response;
    return _request(source, _resolveUrl(baseUrl, contentUrl));
  }

  static List<String> _extractNextContentUrls(
    BookSource source,
    String baseUrl,
    dynamic data,
    Map<String, dynamic> rule, {
    Book? book,
    Chapter? chapter,
  }) {
    final nextRule = _firstRule(rule, const [
      'nextContentUrl',
      'nextUrl',
      'nextPageUrl',
    ]);
    if (nextRule == null) return const [];
    return _extractUrlListFromRule(
      baseUrl,
      data,
      nextRule,
      source: source,
      book: book,
      chapter: chapter,
    );
  }

  static List<String> _extractUrlListFromRule(
    String baseUrl,
    dynamic data,
    String rule, {
    BookSource? source,
    Book? book,
    Chapter? chapter,
  }) {
    if (source != null) {
      rule = _sourceScopedRule(
        rule,
        source,
        book: book,
        chapter: chapter,
        contextBaseUrl: baseUrl,
      );
    }
    final rawValues = <String>[];
    if (_isJsOnlyRule(rule)) {
      try {
        final output = LegadoJsEngine().evaluate(
          rule,
          variables: {
            'result': data is String ? data : jsonEncode(data),
            'baseUrl': baseUrl,
            'url': baseUrl,
            'book': _bookJsObject(
              book,
              origin: source == null
                  ? ''
                  : LegadoRequestBuilder.cleanBaseUrl(source.bookSourceUrl),
            ),
            'chapter': _chapterJsObject(chapter, fallbackUrl: baseUrl),
          },
        );
        try {
          final decoded = jsonDecode(output);
          if (decoded is List) {
            rawValues.addAll(decoded.map((value) => value?.toString() ?? ''));
          } else {
            rawValues.add(decoded?.toString() ?? '');
          }
        } catch (_) {
          rawValues.add(output);
        }
      } catch (_) {
        // Fall through to normal rule handling.
      }
    } else if (_looksLikeJsonData(data, rule) && _isJsonRule(rule)) {
      try {
        final jsonData = data is String ? jsonDecode(data) : data;
        final variables = source == null
            ? <String, dynamic>{
                'result': data is String ? data : jsonEncode(data),
                'baseUrl': baseUrl,
                'url': baseUrl,
                'book': _bookJsObject(book),
                'chapter': _chapterJsObject(chapter, fallbackUrl: baseUrl),
              }
            : _jsVariables(
                source,
                result: data is String ? data : jsonEncode(data),
                baseUrl: baseUrl,
                book: book,
                chapter: chapter,
              );
        rawValues.addAll(
          _extractJsonNodes(jsonData, rule, variables: variables)
              .map((value) => value?.toString() ?? '')
              .where((value) => value.trim().isNotEmpty),
        );
        if (rawValues.isEmpty) {
          rawValues.add(_extractJsonValue(jsonData, rule));
        }
      } catch (_) {
        // Fall through to an empty list.
      }
    } else {
      final document = parse(data.toString());
      final root = document.documentElement ?? document.body;
      if (root != null) rawValues.add(_extractHtmlValue(root, rule));
    }

    final urls = <String>[];
    final seen = <String>{};
    for (final raw in rawValues.expand(_splitExtractedUrlValues)) {
      final cleaned = _cleanInlineUrl(raw);
      if (cleaned.isEmpty) continue;
      final resolved = _resolveUrl(baseUrl, cleaned);
      if (_isNonNavigableHref(resolved) || !seen.add(resolved)) continue;
      urls.add(resolved);
    }
    return urls;
  }

  static Iterable<String> _splitExtractedUrlValues(String value) {
    return value
        .split(RegExp(r'[\r\n]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
  }

  static String _cleanInlineUrl(String value) {
    return value
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll('%0A', '')
        .replaceAll('%0D', '')
        .replaceAll('%0a', '')
        .replaceAll('%0d', '')
        .trim();
  }

  static Future<({dynamic data, String rule})> _prepareDataForRule(
    BookSource source,
    dynamic data,
    String rule, {
    String? baseUrl,
    String? keyword,
    Book? book,
    Chapter? chapter,
  }) async {
    final block = _leadingJsBlock(rule);
    if (block == null) return (data: data, rule: rule);

    final resultText = data is String ? data : jsonEncode(data);
    final variables = _jsVariables(
      source,
      result: resultText,
      baseUrl: baseUrl,
      keyword: keyword,
      book: book,
      chapter: chapter,
    );
    try {
      final output = await LegadoJsEngine().evaluateWithAjax(
        block.script,
        variables: variables,
        libraries: await _sourceLibraryCodes(source, baseUrl: baseUrl),
        ajax: (request) =>
            _ajaxForJs(source, request, baseUrl: baseUrl, keyword: keyword),
        ajaxBytes: (request) => _ajaxBytesForJs(
          source,
          request,
          baseUrl: baseUrl,
          keyword: keyword,
        ),
      );
      final resolvedRule = _resolvePreparedRuleSuffix(block.suffix, variables);
      if (resolvedRule.trim().isEmpty && _looksLikeJsonData(output, '')) {
        try {
          final decoded = jsonDecode(output);
          return (data: output, rule: decoded is List ? r'$[*]' : r'$');
        } catch (_) {
          // Keep the historical empty suffix behavior for non-JSON JS output.
        }
      }
      return (
        data: output.trim().isEmpty ? data : output,
        rule: resolvedRule.trim().isEmpty ? block.suffix : resolvedRule,
      );
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

  static String _resolvePreparedRuleSuffix(
    String suffix,
    Map<String, dynamic> variables,
  ) {
    final text = suffix.trim();
    if (!_looksLikeJsRuleReference(text)) return suffix;
    try {
      final evaluated = LegadoJsEngine().evaluate(text, variables: variables);
      final resolved = evaluated.trim();
      return resolved.isEmpty ? suffix : resolved;
    } catch (_) {
      return suffix;
    }
  }

  static bool _looksLikeJsRuleReference(String text) {
    if (text.isEmpty || text.contains('\n') || text.contains('@')) {
      return false;
    }
    if (text.startsWith('.') ||
        text.startsWith('#') ||
        text.startsWith('class.') ||
        text.startsWith('id.') ||
        text.startsWith('tag.') ||
        text.startsWith('xpath:') ||
        text.startsWith('@xpath:')) {
      return false;
    }
    return RegExp(
      r'^[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)+$',
    ).hasMatch(text);
  }

  static Map<String, dynamic> _jsVariables(
    BookSource source, {
    String result = '',
    String? baseUrl,
    String? keyword,
    int page = 1,
    Book? book,
    Chapter? chapter,
  }) {
    final sourceUrl = LegadoRequestBuilder.cleanBaseUrl(
      source.bookSourceUrl,
    ).replaceAll(RegExp(r'/+$'), '');
    final sourceUri = Uri.tryParse(
      sourceUrl.contains('://') ? sourceUrl : 'https://$sourceUrl',
    );
    final config = LegadoRequestBuilder.jsonConfig(source.customConfig);
    final comment =
        (config['bookSourceComment'] ??
                config['sourceComment'] ??
                config['comment'] ??
                '')
            .toString();
    final header = config['bookSourceHeader'] ?? config['header'] ?? '';
    final loginUrl = _prepareEmbeddedJsVariable(
      (config['loginUrl'] ?? '').toString(),
    );
    final loginUi = config['loginUi'] ?? '';
    final jsLib = config['jsLib'] ?? config['js'] ?? '';
    return {
      'result': result,
      'baseUrl': baseUrl ?? sourceUrl,
      'key': keyword ?? '',
      'keyword': keyword ?? '',
      'page': page,
      'params': {
        'pageIndex': page,
        'tabIndex': 0,
        'filters': <String, dynamic>{},
      },
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
        'bookSourceGroup': source.bookSourceGroup ?? '',
        'bookSourceType': source.bookSourceType,
        'bookSourceComment': comment,
        'bookSourceHeader': header,
        'header': header,
        'loginUrl': loginUrl,
        'loginUi': loginUi,
        'jsLib': jsLib,
        'enabled': source.enabled,
        'enabledCookieJar': config['enabledCookieJar'] ?? false,
        'enabledExplore': config['enabledExplore'] ?? true,
        'variable': config['variable'] ?? config['variableComment'] ?? '',
        'variableComment': config['variableComment'] ?? '',
        'customConfig': config,
      },
      'book': _bookJsObject(
        book,
        origin: LegadoRequestBuilder.cleanBaseUrl(source.bookSourceUrl),
      ),
      'chapter': _chapterJsObject(chapter, fallbackUrl: baseUrl),
    };
  }

  static String _prepareEmbeddedJsVariable(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return value;
    if (!RegExp(r'java\.(ajax|post|connect|startBrowser)\b').hasMatch(value)) {
      return value;
    }
    return JsCompatibilityTransformer.transform(value, wrapScript: false);
  }

  static Map<String, dynamic> _bookJsObject(Book? book, {String? origin}) {
    if (book == null) {
      return <String, dynamic>{
        'origin': origin ?? '',
        'bookSourceUrl': origin ?? '',
        'variable': '',
      };
    }
    return <String, dynamic>{
      'name': book.title,
      'title': book.title,
      'author': book.author,
      'bookUrl': book.filePath,
      'url': book.filePath,
      'origin': origin ?? '',
      'bookSourceUrl': origin ?? '',
      'coverUrl': book.coverPath ?? '',
      'coverPath': book.coverPath ?? '',
      'tocUrl': book.filePath,
      'index': book.currentChapter,
      'variable': '',
    };
  }

  static Map<String, dynamic> _chapterJsObject(
    Chapter? chapter, {
    String? fallbackUrl,
  }) {
    return <String, dynamic>{
      'title': chapter?.title ?? '',
      'name': chapter?.title ?? '',
      'url': chapter?.url ?? chapter?.content ?? fallbackUrl ?? '',
      'index': chapter?.index ?? 0,
      'content': chapter?.content ?? '',
      'variable': '',
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

  static Future<Uint8List> _ajaxBytesForJs(
    BookSource source,
    String request, {
    String? baseUrl,
    String? keyword,
  }) async {
    final decoded = _decodeAjaxBytesRequest(request);
    final requestUrl = decoded['url']?.toString() ?? request;
    final resolved = _resolveRequestUrl(
      baseUrl ?? source.bookSourceUrl,
      requestUrl,
    );
    final req = _buildRequest(source, resolved, keyword: keyword);
    final headers = Map<String, dynamic>.from(req.headers ?? const {});
    final uri = Uri.parse(req.url);
    LegadoSessionStore.apply(uri, headers);
    final extraHeaders = decoded['headers'];
    if (extraHeaders is Map) {
      extraHeaders.forEach((key, value) {
        final name = key?.toString() ?? '';
        if (name.isNotEmpty && value != null) headers[name] = value.toString();
      });
    }
    final referer = decoded['referer']?.toString();
    if (referer != null && referer.isNotEmpty) {
      headers[HttpHeaders.refererHeader] = referer;
    }

    final response = await _dio
        .request<dynamic>(
          req.url,
          data: req.body,
          options: Options(
            method: req.method,
            headers: headers.isEmpty ? null : headers,
            responseType: ResponseType.bytes,
            followRedirects: true,
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        )
        .timeout(const Duration(seconds: 15));
    LegadoSessionStore.rememberResponse(response.realUri, response.headers);
    final bytes = response.data is List<int>
        ? Uint8List.fromList(response.data as List<int>)
        : Uint8List.fromList(utf8.encode(response.data?.toString() ?? ''));
    if (bytes.isEmpty) {
      throw Exception('Font response is empty: ${req.url}');
    }
    if (bytes.length > 5 * 1024 * 1024) {
      throw Exception('Font response is too large: ${bytes.length}');
    }
    return bytes;
  }

  static Map<String, dynamic> _decodeAjaxBytesRequest(String rawRequest) {
    final text = rawRequest.trim();
    if (text.startsWith('{') && text.endsWith('}')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        // Fall through and treat it as a URL.
      }
    }
    return <String, dynamic>{'url': text};
  }

  static String _resolveRequestUrl(String baseUrl, String request) {
    final embedded = LegadoRequestBuilder.splitEmbeddedConfig(request);
    final resolved = _resolveUrl(baseUrl, embedded.url);
    if (embedded.config.isEmpty) return resolved;
    return '$resolved,${jsonEncode(embedded.config)}';
  }

  static Future<String> _applyEmbeddedUrlOptionJs(
    BookSource source,
    String targetUrl, {
    String? keyword,
  }) async {
    final embedded = LegadoRequestBuilder.splitEmbeddedConfig(targetUrl);
    final jsRule = embedded.config['js']?.toString().trim();
    if (jsRule == null || jsRule.isEmpty) return targetUrl;

    final resolvedInput = _resolveUrl(source.bookSourceUrl, embedded.url);
    if (resolvedInput.isEmpty) return targetUrl;

    try {
      final output = await LegadoJsEngine().evaluateWithAjax(
        jsRule,
        variables: _jsVariables(
          source,
          result: resolvedInput,
          baseUrl: resolvedInput,
          keyword: keyword,
        ),
        libraries: await _sourceLibraryCodes(source, baseUrl: resolvedInput),
        ajax: (request) => _ajaxForJs(
          source,
          request,
          baseUrl: resolvedInput,
          keyword: keyword,
        ),
        ajaxBytes: (request) => _ajaxBytesForJs(
          source,
          request,
          baseUrl: resolvedInput,
          keyword: keyword,
        ),
      );
      final rewritten = output.trim();
      if (rewritten.isEmpty) return targetUrl;

      final resolvedOutput = _resolveUrl(resolvedInput, rewritten);
      if (resolvedOutput.isEmpty) return targetUrl;

      final nextConfig = Map<String, dynamic>.from(embedded.config)
        ..remove('js');
      if (nextConfig.isEmpty) return resolvedOutput;
      return '$resolvedOutput,${jsonEncode(nextConfig)}';
    } catch (e) {
      debugPrint('URL option js execution failed: $e');
      return targetUrl;
    }
  }

  static Future<String> _applyResponseBodyJs(
    BookSource source,
    String targetUrl,
    String body, {
    String? keyword,
  }) async {
    final embedded = LegadoRequestBuilder.splitEmbeddedConfig(targetUrl);
    final config = <String, dynamic>{};
    config.addAll(LegadoRequestBuilder.jsonConfig(source.customConfig));
    config.addAll(embedded.config);
    final jsRule = (config['bodyJs'] ?? config['bodyjs'])?.toString().trim();
    if (jsRule == null || jsRule.isEmpty) return body;

    final resolvedUrl = _resolveUrl(source.bookSourceUrl, embedded.url);
    final baseUrl = resolvedUrl.isEmpty ? source.bookSourceUrl : resolvedUrl;
    try {
      final output = await LegadoJsEngine().evaluateWithAjax(
        jsRule,
        variables: _jsVariables(
          source,
          result: body,
          baseUrl: baseUrl,
          keyword: keyword,
        ),
        libraries: await _sourceLibraryCodes(source, baseUrl: baseUrl),
        ajax: (request) =>
            _ajaxForJs(source, request, baseUrl: baseUrl, keyword: keyword),
        ajaxBytes: (request) => _ajaxBytesForJs(
          source,
          request,
          baseUrl: baseUrl,
          keyword: keyword,
        ),
      );
      return output.trim().isEmpty ? body : output;
    } catch (e) {
      debugPrint('bodyJs execution failed: $e');
      return body;
    }
  }

  static String _applyFormatJsSync(
    String formatJsRule, {
    required int index,
    required String title,
    required String url,
  }) {
    if (formatJsRule.trim().isEmpty) return title;
    try {
      final variables = {
        'index': index,
        'title': title,
        'chapter': {'title': title, 'url': url, 'index': index},
      };
      final output = LegadoJsEngine().evaluate(
        formatJsRule,
        variables: variables,
      );
      if (output.trim().isNotEmpty) return output.trim();
    } catch (e) {
      debugPrint('formatJsSync execution failed: $e');
    }
    return title;
  }

  static String _extractJsonValue(
    dynamic json,
    String jsonPath, {
    Map<String, dynamic>? variables,
  }) {
    return LegadoRuleEvaluator.extractJsonValue(
      json,
      jsonPath,
      variables: variables,
    );
  }

  static List<dynamic> _extractJsonNodes(
    dynamic json,
    String jsonPath, {
    Map<String, dynamic>? variables,
  }) {
    return LegadoRuleEvaluator.extractJsonNodes(
      json,
      jsonPath,
      variables: variables,
    );
  }

  static String _extractHtmlValue(
    Element node,
    String ruleStr, {
    Map<String, dynamic>? variables,
  }) {
    return LegadoRuleEvaluator.extractHtmlValue(
      node,
      ruleStr,
      variables: variables,
    );
  }

  static List<Element> _queryAll(Document document, String rule) {
    if (rule.trim().isEmpty) return [];
    return LegadoRuleEvaluator.queryAll(document, rule);
  }

  static Element? _queryOne(dynamic node, String rule) {
    if (rule.trim().isEmpty) return null;
    return LegadoRuleEvaluator.queryOne(node, rule);
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
    String targetUrl, {
    CancelToken? cancelToken,
  }) async {
    targetUrl = targetUrl
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll('%0A', '')
        .replaceAll('%0D', '')
        .replaceAll('%0a', '')
        .replaceAll('%0d', '')
        .trim();
    final embedded = LegadoRequestBuilder.splitEmbeddedConfig(targetUrl);
    final urlStr = embedded.url;
    final uri = Uri.parse(urlStr);

    final completer = Completer<String>();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);

    final config = <String, dynamic>{};
    config.addAll(LegadoRequestBuilder.jsonConfig(source.customConfig));
    config.addAll(embedded.config);

    final rawHeaders =
        config['headers'] ?? config['header'] ?? config['bookSourceHeader'];
    Map<String, String> headersMap = {};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) => headersMap[k.toString()] = v.toString());
    } else if (rawHeaders is String) {
      final parsed = LegadoRequestBuilder.parseHeaderString(rawHeaders);
      parsed.forEach((k, v) => headersMap[k.toString()] = v.toString());
    }

    final ua =
        headersMap['User-Agent'] ??
        headersMap['user-agent'] ??
        config['userAgent'];
    var uaStr = ua?.toString();
    if (uaStr == null ||
        uaStr.isEmpty ||
        uaStr.contains('Flutter') ||
        uaStr.contains('Headless') ||
        uaStr.contains('Kite') ||
        uaStr.contains('flutter') ||
        uaStr.contains('headless') ||
        uaStr.contains('kite')) {
      uaStr =
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
    }

    await controller.setUserAgent(uaStr);
    LegadoSessionStore.setUserAgent(uri, uaStr);

    final webViewDelay =
        int.tryParse(
          (config['webViewDelayTime'] ?? config['webviewDelayTime'] ?? '')
              .toString(),
        ) ??
        1200;
    final webJsRule = (config['webJs'] ?? config['webjs'])?.toString().trim();

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) async {
          try {
            await controller.runJavaScript(
              "Object.defineProperty(navigator, 'webdriver', { get: () => undefined });",
            );
          } catch (_) {}
        },
        onPageFinished: (url) async {
          try {
            await Future.delayed(
              Duration(milliseconds: webViewDelay.clamp(0, 10000).toInt()),
            );
            try {
              await controller.runJavaScript(
                "Object.defineProperty(navigator, 'webdriver', { get: () => undefined });",
              );
            } catch (_) {}

            final cookieManager = wcm.WebviewCookieManager();
            final gotCookies = await cookieManager.getCookies(urlStr);
            if (gotCookies.isNotEmpty) {
              final cookieStr = gotCookies
                  .map((c) => '${c.name}=${c.value}')
                  .join('; ');
              LegadoSessionStore.setCookieString(uri, cookieStr);
            }

            if (ua == null || ua.toString().isEmpty) {
              final extractedUa = await controller.runJavaScriptReturningResult(
                'navigator.userAgent',
              );
              final extractedUaStr = extractedUa
                  .toString()
                  .replaceAll('"', '')
                  .trim();
              if (extractedUaStr.isNotEmpty) {
                LegadoSessionStore.setUserAgent(uri, extractedUaStr);
              }
            }

            String html = '';
            int attempts = 0;
            int lastLength = 0;
            int stableCount = 0;

            final searchRule = _ruleMap(source.ruleSearch);
            final searchSelector = _extractCssSelector(
              _firstRule(searchRule, const ['bookList', 'list']),
            );

            final tocRule = _ruleMap(source.ruleToc);
            final tocSelector = _extractCssSelector(
              _firstRule(tocRule, const ['chapterList', 'list']),
            );

            final contentRule = _ruleMap(source.ruleContent);
            final contentSelector = _extractCssSelector(
              _firstRule(contentRule, const ['content', 'text']),
            );

            final bookInfoRule = _ruleMap(source.ruleBookInfo);
            final tocUrlRule = _firstRule(bookInfoRule, const [
              'tocUrl',
              'catalogUrl',
            ]);
            final isTocSameAsDetail =
                tocUrlRule == null || tocUrlRule.toString().trim().isEmpty;

            while (attempts < 25) {
              if (cancelToken?.isCancelled == true) {
                if (!completer.isCompleted) {
                  completer.completeError(
                    DioException(
                      requestOptions: RequestOptions(path: targetUrl),
                      error: 'User interrupted source switching',
                      type: DioExceptionType.cancel,
                    ),
                  );
                }
                break;
              }
              final result = await controller.runJavaScriptReturningResult(
                'document.documentElement.outerHTML',
              );
              html = result.toString();
              if (html.startsWith('"') && html.endsWith('"')) {
                try {
                  final decoded = jsonDecode(html);
                  if (decoded is String) html = decoded;
                } catch (_) {
                  html = html
                      .substring(1, html.length - 1)
                      .replaceAll(r'\"', '"')
                      .replaceAll(r'\\', r'\');
                }
              }

              final currentLength = html.length;
              bool isSelectorMatch = false;

              if (tocSelector != null &&
                  (targetUrl.contains('toc') ||
                      targetUrl.contains('chapter') ||
                      isTocSameAsDetail ||
                      targetUrl.contains('/50045/'))) {
                try {
                  final evalResult = await controller
                      .runJavaScriptReturningResult(
                        "document.querySelectorAll('$tocSelector').length",
                      );
                  final count = int.tryParse(evalResult.toString()) ?? 0;
                  if (count > 0) {
                    isSelectorMatch = true;
                  }
                } catch (_) {}
              }

              if (!isSelectorMatch &&
                  searchSelector != null &&
                  targetUrl.contains('search')) {
                try {
                  final evalResult = await controller
                      .runJavaScriptReturningResult(
                        "document.querySelectorAll('$searchSelector').length",
                      );
                  final count = int.tryParse(evalResult.toString()) ?? 0;
                  if (count > 0) {
                    isSelectorMatch = true;
                  }
                } catch (_) {}
              }

              if (!isSelectorMatch && contentSelector != null) {
                try {
                  final evalResult = await controller
                      .runJavaScriptReturningResult(
                        "document.querySelectorAll('$contentSelector').length",
                      );
                  final count = int.tryParse(evalResult.toString()) ?? 0;
                  if (count > 0) {
                    isSelectorMatch = true;
                  }
                } catch (_) {}
              }

              bool isStable = false;
              if (lastLength > 0) {
                final diff = (currentLength - lastLength).abs();
                final changeRate = diff / lastLength;
                if (changeRate <= 0.001) {
                  stableCount++;
                } else {
                  stableCount = 0;
                }
                if (stableCount >= 2) {
                  isStable = true;
                }
              }
              lastLength = currentLength;

              bool isFeatureMatch = false;
              final isSearch = targetUrl.contains('search');
              final isToc =
                  targetUrl.contains('toc') ||
                  targetUrl.contains('chapter') ||
                  isTocSameAsDetail;
              if (isSearch || isToc) {
                final linkCount = RegExp(
                  r'''href\s*=\s*["\'][^"\']+["\']''',
                ).allMatches(html).length;
                if (linkCount > 10) {
                  isFeatureMatch = true;
                }
              } else {
                if (html.contains('</p>') || html.contains('<br')) {
                  isFeatureMatch = true;
                }
              }

              if (isSelectorMatch || (isFeatureMatch && isStable)) {
                break;
              }

              attempts++;
              await Future.delayed(const Duration(milliseconds: 400));
            }

            if (cancelToken?.isCancelled == true) {
              return;
            }
            if (webJsRule != null && webJsRule.isNotEmpty) {
              try {
                var script = webJsRule;
                if (script.startsWith('@js:')) {
                  script = script.substring(4);
                } else if (script.startsWith('<js>') &&
                    script.endsWith('</js>')) {
                  script = script.substring(4, script.length - 5);
                }
                if (RegExp(r'\breturn\b').hasMatch(script) &&
                    !script.trimLeft().startsWith('(function') &&
                    !script.trimLeft().startsWith('(()')) {
                  script = '(function(){ $script })()';
                }
                final jsResult = await controller.runJavaScriptReturningResult(
                  script,
                );
                final jsText = _decodeWebViewStringResult(jsResult);
                if (jsText.trim().isNotEmpty) {
                  html = jsText;
                }
              } catch (e) {
                debugPrint('Headless WebView webJs failed: $e');
              }
            }
            if (!completer.isCompleted) {
              if (_looksLikeBlankWebViewHtml(html)) {
                completer.completeError(
                  TimeoutException(
                    'Headless WebView returned an empty document for $urlStr',
                  ),
                );
                return;
              }
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
          debugPrint('Headless WebView resource error: ${error.description}');
        },
      ),
    );

    final timeoutTimer = Timer(const Duration(seconds: 20), () async {
      if (!completer.isCompleted) {
        String htmlSnapshot = '';
        try {
          final result = await controller.runJavaScriptReturningResult(
            'document.documentElement.outerHTML',
          );
          htmlSnapshot = result.toString();
          if (htmlSnapshot.startsWith('"') && htmlSnapshot.endsWith('"')) {
            try {
              final decoded = jsonDecode(htmlSnapshot);
              if (decoded is String) htmlSnapshot = decoded;
            } catch (_) {
              htmlSnapshot = htmlSnapshot
                  .substring(1, htmlSnapshot.length - 1)
                  .replaceAll(r'\"', '"')
                  .replaceAll(r'\\', r'\');
            }
          }
        } catch (e) {
          htmlSnapshot = 'Failed to capture HTML snapshot: $e';
        }

        final logMsg =
            '🚨 [Headless WebView 超时临终绝密取证] 目标 URL: $urlStr\n'
            '🚨 [临终残页片段] (前1000字符):\n'
            '${htmlSnapshot.substring(0, htmlSnapshot.length > 1000 ? 1000 : htmlSnapshot.length)}';
        debugPrint(logMsg);

        completer.completeError(
          TimeoutException(
            'Headless WebView request timed out for $urlStr\n$logMsg',
          ),
        );
      }
    });

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
          debugPrint('Failed to set WebView cookies: $e');
        }
      }

      await controller.loadRequest(uri, headers: optionsHeaders);

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

  /// 从 Legado 规则中清洗出纯净的 CSS 选择器（去除 @css:, @text, ## 等后缀）
  static String? _extractCssSelector(String? rule) {
    if (rule == null || rule.isEmpty) return null;
    var css = rule.trim();
    if (css.startsWith('@css:')) {
      css = css.substring(5);
    }
    final atIndex = css.indexOf('@');
    if (atIndex != -1) {
      css = css.substring(0, atIndex);
    }
    final hashIndex = css.indexOf('##');
    if (hashIndex != -1) {
      css = css.substring(0, hashIndex);
    }
    css = css.trim();
    return css.isEmpty ? null : css;
  }

  static Future<String> executeFetch(
    BookSource source,
    String targetUrl, {
    String? keyword,
    CancelToken? cancelToken,
  }) async {
    targetUrl = targetUrl
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll('%0A', '')
        .replaceAll('%0D', '')
        .replaceAll('%0a', '')
        .replaceAll('%0d', '')
        .trim();

    // 漫画源前置降级与底层通用扩展预留。java.getElements 也会被小说源用来取正文节点，
    // 不能仅凭该 JS 桥判断为漫画源。
    if (source.bookSourceType > 0 ||
        source.ruleContent?.contains('@css:img') == true) {
      throw Exception('暂不支持漫画类书源解析（功能扩充预留中）');
    }

    targetUrl = await _applyEmbeddedUrlOptionJs(
      source,
      targetUrl,
      keyword: keyword,
    );
    final hasWebView = _hasWebViewConfig(source, targetUrl);
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
          final gbkEncodedKeyword = gbkBytes
              .map(
                (b) => '%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}',
              )
              .join();

          var bodyStr = request.body!;
          if (bodyStr.contains(keyword)) {
            bodyStr = bodyStr.replaceAll(keyword, gbkEncodedKeyword);
          }
          final utf8EncodedKeywordUpper = Uri.encodeComponent(
            keyword,
          ).toUpperCase();
          final utf8EncodedKeywordLower = Uri.encodeComponent(
            keyword,
          ).toLowerCase();
          if (bodyStr.contains(utf8EncodedKeywordUpper)) {
            bodyStr = bodyStr.replaceAll(
              utf8EncodedKeywordUpper,
              gbkEncodedKeyword,
            );
          }
          if (bodyStr.contains(utf8EncodedKeywordLower)) {
            bodyStr = bodyStr.replaceAll(
              utf8EncodedKeywordLower,
              gbkEncodedKeyword,
            );
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
        cancelToken: cancelToken,
      );
      LegadoSessionStore.rememberResponse(response.realUri, response.headers);
      final bytes = response.data is List<int>
          ? response.data as List<int>
          : utf8.encode(response.data?.toString() ?? '');
      var responseData = decodeBytes(
        bytes,
        request.charset,
        headers: response.headers.map,
      );
      responseData = await _applyResponseBodyJs(
        source,
        targetUrl,
        responseData,
        keyword: keyword,
      );

      if (_needsManualVerification(response.statusCode, responseData)) {
        if (_headlessWebViewDisabled) {
          debugPrint(
            'Dio response requires manual verification; Headless WebView is disabled.',
          );
          throw LegadoVerificationRequiredException(
            sourceName: source.bookSourceName,
            url: targetUrl,
            statusCode: response.statusCode,
            message: '当前运行环境禁用了 Headless WebView，请在 App 内跳验证后复测。',
          );
        }
        debugPrint(
          'Dio response triggers verification. Downgrading to Headless WebView.',
        );
        return await _requestViaHeadlessWebView(
          source,
          targetUrl,
          cancelToken: cancelToken,
        );
      }
      if (hasWebView && _shouldTryWebViewAfterDio(responseData)) {
        if (_headlessWebViewDisabled) {
          throw Exception('当前运行环境禁用了 Headless WebView，无法执行 webView 规则');
        }
        debugPrint(
          'Dio response is blank or incomplete while webView is enabled. Trying Headless WebView.',
        );
        return await _requestViaHeadlessWebView(
          source,
          targetUrl,
          cancelToken: cancelToken,
        );
      }
      return responseData;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        rethrow;
      }
      final isTlsOrConnectionError =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError ||
          (e.message?.toLowerCase().contains('handshake') ?? false) ||
          (e.message?.toLowerCase().contains('connection reset') ?? false);

      final isStatusCodeError =
          e.response != null &&
          (e.response!.statusCode == 403 || e.response!.statusCode == 503);

      if (isTlsOrConnectionError || isStatusCodeError) {
        if (_headlessWebViewDisabled) {
          debugPrint(
            'Dio request failed (code: ${e.response?.statusCode}, err: ${e.message}); Headless WebView is disabled.',
          );
          rethrow;
        }
        debugPrint(
          'Dio request failed (code: ${e.response?.statusCode}, err: ${e.message}). Falling back to Headless WebView.',
        );
        return await _requestViaHeadlessWebView(
          source,
          targetUrl,
          cancelToken: cancelToken,
        );
      } else {
        rethrow;
      }
    } on LegadoVerificationRequiredException {
      rethrow;
    } catch (e) {
      if (_headlessWebViewDisabled) {
        debugPrint(
          'Dio request generic error: $e; Headless WebView is disabled.',
        );
        rethrow;
      }
      debugPrint(
        'Dio request generic error: $e. Falling back to Headless WebView.',
      );
      return await _requestViaHeadlessWebView(
        source,
        targetUrl,
        cancelToken: cancelToken,
      );
    }
  }

  static Future<Response<dynamic>> _request(
    BookSource source,
    String url, {
    String? keyword,
    CancelToken? cancelToken,
  }) async {
    url = url
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll('%0A', '')
        .replaceAll('%0D', '')
        .replaceAll('%0a', '')
        .replaceAll('%0d', '')
        .trim();
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

    final responseData = await executeFetch(
      source,
      url,
      keyword: keyword,
      cancelToken: cancelToken,
    );
    return Response<dynamic>(
      data: responseData,
      statusCode: 200,
      requestOptions: RequestOptions(path: _displayRequestUrl(source, url)),
    );
  }

  static String _displayRequestUrl(BookSource source, String url) {
    final embedded = LegadoRequestBuilder.splitEmbeddedConfig(url);
    if (embedded.url.trim().isEmpty) return url;
    final resolved = _resolveUrl(source.bookSourceUrl, embedded.url);
    return resolved.isEmpty ? embedded.url : resolved;
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

  static bool _shouldTryWebViewAfterDio(dynamic data) {
    final text = data?.toString().trim() ?? '';
    if (text.isEmpty) return true;
    if (_looksLikeBlankWebViewHtml(text)) return true;
    if (text.length < 120 && !_looksLikeJsonPayload(text)) return true;
    return false;
  }

  static String _decodeWebViewStringResult(Object? result) {
    var text = result?.toString() ?? '';
    if (text.startsWith('"') && text.endsWith('"')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is String) return decoded;
      } catch (_) {
        text = text
            .substring(1, text.length - 1)
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', r'\');
      }
    }
    return text;
  }

  static bool _looksLikeBlankWebViewHtml(String html) {
    final normalized = html
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
        .toLowerCase();
    if (normalized.isEmpty) return true;
    return normalized == '<html><head></head><body></body></html>' ||
        normalized == '<html><head></head><body></body></html>undefined' ||
        normalized == '<html><head></head><body></body></html>null' ||
        normalized == '<html><head></head><body></body></html>""' ||
        normalized == '<html><head></head><body></body></html>"';
  }

  static bool _looksLikeJsonPayload(String text) {
    final value = text.trimLeft();
    return value.startsWith('{') || value.startsWith('[');
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
    var searchUrl = raw;
    if (_isWholeJsRule(raw)) {
      Object? jsError;
      final variables = _jsVariables(
        source,
        keyword: keyword,
        page: page,
        baseUrl: source.bookSourceUrl,
      );
      var output = '';
      try {
        output = await LegadoJsEngine().evaluateWithAjax(
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
          ajaxBytes: (request) => _ajaxBytesForJs(
            source,
            request,
            baseUrl: source.bookSourceUrl,
            keyword: keyword,
          ),
        );
      } catch (e) {
        jsError = e;
      }
      searchUrl = output.trim();
      if (searchUrl.isEmpty) {
        searchUrl =
            _evaluateCommonJsSearchUrlFallback(raw, source, keyword, page) ??
            '';
      }
      if (searchUrl.isEmpty && jsError != null) {
        throw Exception('JS 搜索 URL 执行失败: $jsError');
      }
      if (searchUrl.isEmpty) return '';
    } else {
      searchUrl =
          await _evaluateMixedSearchUrlJs(source, raw, keyword, page) ??
          LegadoRequestBuilder.replaceVariables(
            raw,
            keyword: keyword,
            page: page,
            source: source,
          );
      if (_isWholeJsRule(searchUrl)) {
        Object? jsError;
        final variables = _jsVariables(
          source,
          keyword: keyword,
          page: page,
          baseUrl: source.bookSourceUrl,
        );
        final jsRule = searchUrl;
        var output = '';
        try {
          output = await LegadoJsEngine().evaluateWithAjax(
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
            ajaxBytes: (request) => _ajaxBytesForJs(
              source,
              request,
              baseUrl: source.bookSourceUrl,
              keyword: keyword,
            ),
          );
        } catch (e) {
          jsError = e;
        }
        searchUrl = output.trim();
        if (searchUrl.isEmpty) {
          searchUrl =
              _evaluateCommonJsSearchUrlFallback(
                jsRule,
                source,
                keyword,
                page,
              ) ??
              '';
        }
        if (searchUrl.isEmpty && jsError != null) {
          throw Exception('JS 搜索 URL 执行失败: $jsError');
        }
        if (searchUrl.isEmpty) return '';
      }
    }

    final embedded = LegadoRequestBuilder.splitEmbeddedConfig(searchUrl);
    final resolved = _resolveUrl(source.bookSourceUrl, embedded.url);
    if (embedded.config.isEmpty) return resolved;
    return '$resolved,${jsonEncode(embedded.config)}';
  }

  static Future<String> _buildExploreUrlAsync(
    BookSource source, {
    int page = 1,
  }) async {
    final raw = source.exploreUrl ?? '';
    if (raw.trim().isEmpty) return '';

    var exploreUrl = raw;
    if (_isWholeJsRule(raw)) {
      final variables = _jsVariables(
        source,
        keyword: '',
        page: page,
        baseUrl: source.bookSourceUrl,
      );
      try {
        final output = await LegadoJsEngine().evaluateWithAjax(
          raw,
          variables: variables,
          libraries: await _sourceLibraryCodes(
            source,
            baseUrl: source.bookSourceUrl,
          ),
          ajax: (request) =>
              _ajaxForJs(source, request, baseUrl: source.bookSourceUrl),
        );
        if (output.trim().isNotEmpty) {
          exploreUrl = output.trim();
        }
      } catch (_) {
        return '';
      }
    } else if (_containsJsRule(raw)) {
      exploreUrl =
          await _evaluateMixedSearchUrlJs(source, raw, '', page) ?? raw;
    }

    return LegadoRequestBuilder.replaceVariables(
      exploreUrl,
      keyword: '',
      page: page,
      source: source,
    ).trim();
  }

  static Future<String?> _evaluateMixedSearchUrlJs(
    BookSource source,
    String raw,
    String keyword,
    int page,
  ) async {
    final matches = RegExp(
      r'<js>([\s\S]*?)</js>|@js:([\s\S]*)',
      caseSensitive: false,
    ).allMatches(raw).toList();
    if (matches.isEmpty) return null;

    var start = 0;
    var result = raw;
    for (final match in matches) {
      if (match.start > start) {
        final prefix = raw.substring(start, match.start).trim();
        if (prefix.isNotEmpty) result = prefix.replaceAll('@result', result);
      }

      final js = match.group(1) ?? match.group(2) ?? '';
      final variables = _jsVariables(
        source,
        keyword: keyword,
        page: page,
        baseUrl: source.bookSourceUrl,
        result: result,
      );
      try {
        result = await LegadoJsEngine().evaluateWithAjax(
          js,
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
          ajaxBytes: (request) => _ajaxBytesForJs(
            source,
            request,
            baseUrl: source.bookSourceUrl,
            keyword: keyword,
          ),
        );
      } catch (e) {
        final fallbackVal = _evaluateSimpleJsExpression(
          js,
          source,
          keyword,
          page,
          result,
        );
        if (fallbackVal != null && fallbackVal.isNotEmpty) {
          result = fallbackVal;
        } else {
          rethrow;
        }
      }
      start = match.end;
    }

    if (raw.length > start) {
      final suffix = raw.substring(start).trim();
      if (suffix.isNotEmpty) result = suffix.replaceAll('@result', result);
    }
    return result.trim();
  }

  static bool _isWholeJsRule(String text) {
    final value = text.trimLeft();
    return value.startsWith('@js:') || value.startsWith('<js>');
  }

  static String? _evaluateCommonJsSearchUrlFallback(
    String jsRule,
    BookSource source,
    String keyword,
    int page,
  ) {
    var code = jsRule.trim();
    if (code.startsWith('@js:')) {
      code = code.substring(4);
    } else if (code.startsWith('<js>') && code.endsWith('</js>')) {
      code = code.substring(4, code.length - 5);
    }
    code = code.trim();

    if (code.contains('java.put') &&
        code.contains('params') &&
        code.contains('headers')) {
      final headersObject = _extractJsAssignedObject(code, 'headers');
      final paramsObject = _extractJsAssignedObject(code, 'params');
      if (headersObject != null && paramsObject != null) {
        final pathMatch = RegExp(
          r'''(["'])([^"']*\?[^"']*)\1\s*\+\s*body''',
          dotAll: true,
        ).firstMatch(code);
        final path = pathMatch?.group(2);
        if (path != null && path.trim().isNotEmpty) {
          final headers = _parseSimpleJsObject(
            headersObject,
            keyword: keyword,
            page: page,
          );
          final params = _parseSimpleJsObject(
            paramsObject,
            keyword: keyword,
            page: page,
          );
          if (params.isNotEmpty) {
            final signKey = RegExp(
              r'''sign_key\s*=\s*(["'])([\s\S]*?)\1''',
              dotAll: true,
            ).firstMatch(code)?.group(2);
            if (signKey != null && signKey.isNotEmpty) {
              if (code.contains("headers['sign']") ||
                  code.contains('headers["sign"]') ||
                  code.contains('headers.sign')) {
                headers['sign'] = _signedParamString(headers, signKey);
              }
              if (code.contains("params['sign']") ||
                  code.contains('params["sign"]') ||
                  code.contains('params.sign')) {
                params['sign'] = _signedParamString(params, signKey);
              }
            }

            final body = _buildLegacyUrlEncodedBody(params);
            final url = _resolveUrl(source.bookSourceUrl, '$path$body');
            if (!code.contains('java.put("headers"') &&
                !code.contains("java.put('headers'")) {
              return url;
            }
            return '$url,${jsonEncode({'headers': headers})}';
          }
        }
      }
    }

    try {
      final result = _evaluateSimpleJsExpression(code, source, keyword, page);
      if (result != null && result.isNotEmpty) {
        return result;
      }
    } catch (e) {
      debugPrint('Simple JS fallback evaluation failed: $e');
    }

    return null;
  }

  static String? _evaluateSimpleJsExpression(
    String code,
    BookSource source,
    String keyword,
    int page, [
    String resultVar = '',
  ]) {
    code = code.trim();

    final variables = <String, dynamic>{
      'key': keyword,
      'keyword': keyword,
      'page': page,
      'pageIndex': page,
      'baseUrl': source.bookSourceUrl,
      'result': resultVar,
    };

    try {
      final statements = _splitSimpleJsStatements(code);
      dynamic lastVal;
      for (final stmt in statements) {
        lastVal = _evaluateSimpleJsStatement(stmt, variables);
      }
      return lastVal?.toString();
    } catch (_) {
      return null;
    }
  }

  static List<String> _splitSimpleJsStatements(String code) {
    final statements = <String>[];
    var current = StringBuffer();
    var braceDepth = 0;
    var parenDepth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < code.length; i++) {
      final char = code.codeUnitAt(i);
      if (escaped) {
        current.writeCharCode(char);
        escaped = false;
        continue;
      }
      if (char == 0x5c) {
        current.writeCharCode(char);
        escaped = true;
        continue;
      }
      if (quote != 0) {
        current.writeCharCode(char);
        if (char == quote) quote = 0;
        continue;
      }
      if (char == 0x22 || char == 0x27 || char == 0x60) {
        quote = char;
        current.writeCharCode(char);
        continue;
      }

      // Comment stripping
      if (char == 0x2f && i + 1 < code.length) {
        final nextChar = code.codeUnitAt(i + 1);
        if (nextChar == 0x2f) {
          // Skip until newline or end of code
          while (i < code.length && code.codeUnitAt(i) != 0x0a && code.codeUnitAt(i) != 0x0d) {
            i++;
          }
          continue;
        } else if (nextChar == 0x2a) {
          // Skip until */
          i += 2;
          while (i < code.length - 1 && !(code.codeUnitAt(i) == 0x2a && code.codeUnitAt(i + 1) == 0x2f)) {
            i++;
          }
          i++; // Skip the '/' of */
          continue;
        }
      }

      if (char == 0x7b) {
        braceDepth++;
      } else if (char == 0x7d) {
        braceDepth--;
      } else if (char == 0x28) {
        parenDepth++;
      } else if (char == 0x29) {
        parenDepth--;
      }

      if ((char == 0x3b || char == 0x0a || char == 0x0d) &&
          braceDepth == 0 &&
          parenDepth == 0) {
        final stmt = current.toString().trim();
        if (stmt.isNotEmpty) statements.add(stmt);
        current = StringBuffer();
      } else {
        current.writeCharCode(char);
      }
    }
    final stmt = current.toString().trim();
    if (stmt.isNotEmpty) statements.add(stmt);
    return statements;
  }

  static dynamic _evaluateSimpleJsStatement(
    String stmt,
    Map<String, dynamic> variables,
  ) {
    var s = stmt.trim();
    if (s.isEmpty) return null;

    if (s.startsWith('return ')) {
      s = s.substring(7).trim();
    }

    if (s.startsWith('if') && s.contains('(')) {
      final openParen = s.indexOf('(');
      var closeParen = -1;
      var depth = 0;
      for (var i = openParen; i < s.length; i++) {
        final c = s.codeUnitAt(i);
        if (c == 0x28) depth++;
        if (c == 0x29) {
          depth--;
          if (depth == 0) {
            closeParen = i;
            break;
          }
        }
      }
      if (closeParen != -1) {
        final condStr = s.substring(openParen + 1, closeParen).trim();
        var bodyStr = s.substring(closeParen + 1).trim();
        if (bodyStr.startsWith('{') && bodyStr.endsWith('}')) {
          bodyStr = bodyStr.substring(1, bodyStr.length - 1).trim();
        }

        final condVal = _evaluateSimpleJsExpressionPart(condStr, variables);
        final isTrue = condVal == true ||
            condVal == 'true' ||
            (condVal is num && condVal != 0) ||
            (condVal is String && condVal.isNotEmpty && condVal != 'false');
        if (isTrue) {
          final subStmts = _splitSimpleJsStatements(bodyStr);
          dynamic subResult;
          for (final subStmt in subStmts) {
            subResult = _evaluateSimpleJsStatement(subStmt, variables);
          }
          return subResult;
        }
        return null;
      }
    }

    final assignment = _parseSimpleJsAssignment(s);
    if (assignment != null) {
      final name = assignment[0];
      final expr = assignment[1];
      final val = _evaluateSimpleJsExpressionPart(expr, variables);
      variables[name] = val;
      return val;
    }

    return _evaluateSimpleJsExpressionPart(s, variables);
  }

  static List<String>? _parseSimpleJsAssignment(String stmt) {
    var quote = 0;
    var parenDepth = 0;
    var braceDepth = 0;
    var escaped = false;
    for (var i = 0; i < stmt.length; i++) {
      final char = stmt.codeUnitAt(i);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == 0x5c) {
        escaped = true;
        continue;
      }
      if (quote != 0) {
        if (char == quote) quote = 0;
        continue;
      }
      if (char == 0x22 || char == 0x27 || char == 0x60) {
        quote = char;
        continue;
      }
      if (char == 0x28) parenDepth++;
      if (char == 0x29) parenDepth--;
      if (char == 0x7b) braceDepth++;
      if (char == 0x7d) braceDepth--;
      if (char == 0x3d && parenDepth == 0 && braceDepth == 0) {
        final left = stmt.substring(0, i).trim();
        final right = stmt.substring(i + 1).trim();
        final leftClean = left
            .replaceFirst(RegExp(r'^(var|let|const)\s+'), '')
            .trim();
        return [leftClean, right];
      }
    }
    return null;
  }

  static dynamic _evaluateSimpleJsExpressionPart(
    String expr,
    Map<String, dynamic> variables,
  ) {
    var e = expr.trim();
    if (e.isEmpty) return '';

    if (e.startsWith('"') && e.endsWith('"') && e.length >= 2) {
      return e.substring(1, e.length - 1);
    }
    if (e.startsWith("'") && e.endsWith("'") && e.length >= 2) {
      return e.substring(1, e.length - 1);
    }
    if (e.startsWith('`') && e.endsWith('`') && e.length >= 2) {
      var template = e.substring(1, e.length - 1);
      final matches = RegExp(r'\$\{([\s\S]*?)\}').allMatches(template).toList();
      var offset = 0;
      final sb = StringBuffer();
      for (final m in matches) {
        sb.write(template.substring(offset, m.start));
        final innerExpr = m.group(1)!;
        sb.write(_evaluateSimpleJsExpressionPart(innerExpr, variables));
        offset = m.end;
      }
      sb.write(template.substring(offset));
      return sb.toString();
    }

    if (RegExp(r'^\d+$').hasMatch(e)) {
      return int.parse(e);
    }

    if (e == 'true') return true;
    if (e == 'false') return false;

    if (variables.containsKey(e)) {
      return variables[e];
    }

    final funcMatch = RegExp(r'^([a-zA-Z0-9_\.]+)\((.*)\)$').firstMatch(e);
    if (funcMatch != null) {
      final funcName = funcMatch.group(1)!;
      final argsStr = funcMatch.group(2)!;
      final args = _splitSimpleJsArguments(argsStr);
      final argValues = args
          .map((arg) => _evaluateSimpleJsExpressionPart(arg, variables))
          .toList();
      return _callSimpleJsFunction(funcName, argValues, variables);
    }

    if (e.startsWith('(') && e.endsWith(')')) {
      if (_hasMatchingSimpleJsOuterParens(e)) {
        return _evaluateSimpleJsExpressionPart(
          e.substring(1, e.length - 1),
          variables,
        );
      }
    }

    final parts = _splitSimpleJsByOperator(e, '+');
    if (parts.length > 1) {
      dynamic result;
      for (final part in parts) {
        final val = _evaluateSimpleJsExpressionPart(part, variables);
        if (result == null) {
          result = val;
        } else {
          if (result is String || val is String) {
            result = result.toString() + val.toString();
          } else if (result is num && val is num) {
            result = result + val;
          } else {
            result = result.toString() + val.toString();
          }
        }
      }
      return result;
    }

    final subParts = _splitSimpleJsByOperator(e, '-');
    if (subParts.length > 1) {
      final left = _evaluateSimpleJsExpressionPart(subParts[0], variables);
      final right = _evaluateSimpleJsExpressionPart(subParts[1], variables);
      if (left is num && right is num) {
        return left - right;
      }
      return (double.tryParse(left.toString()) ?? 0) -
          (double.tryParse(right.toString()) ?? 0);
    }

    final mulParts = _splitSimpleJsByOperator(e, '*');
    if (mulParts.length > 1) {
      final left = _evaluateSimpleJsExpressionPart(mulParts[0], variables);
      final right = _evaluateSimpleJsExpressionPart(mulParts[1], variables);
      if (left is num && right is num) {
        return left * right;
      }
      return (double.tryParse(left.toString()) ?? 0) *
          (double.tryParse(right.toString()) ?? 0);
    }

    return e;
  }

  static List<String> _splitSimpleJsByOperator(String expr, String op) {
    final parts = <String>[];
    var current = StringBuffer();
    var parenDepth = 0;
    var braceDepth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < expr.length; i++) {
      final char = expr.codeUnitAt(i);
      if (escaped) {
        current.writeCharCode(char);
        escaped = false;
        continue;
      }
      if (char == 0x5c) {
        current.writeCharCode(char);
        escaped = true;
        continue;
      }
      if (quote != 0) {
        current.writeCharCode(char);
        if (char == quote) quote = 0;
        continue;
      }
      if (char == 0x22 || char == 0x27 || char == 0x60) {
        quote = char;
        current.writeCharCode(char);
        continue;
      }
      if (char == 0x28) parenDepth++;
      if (char == 0x29) parenDepth--;
      if (char == 0x7b) braceDepth++;
      if (char == 0x7d) braceDepth--;

      if (parenDepth == 0 &&
          braceDepth == 0 &&
          expr.substring(i).startsWith(op)) {
        parts.add(current.toString().trim());
        current = StringBuffer();
        i += op.length - 1;
      } else {
        current.writeCharCode(char);
      }
    }
    parts.add(current.toString().trim());
    return parts;
  }

  static List<String> _splitSimpleJsArguments(String argsStr) {
    final args = <String>[];
    var current = StringBuffer();
    var parenDepth = 0;
    var braceDepth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < argsStr.length; i++) {
      final char = argsStr.codeUnitAt(i);
      if (escaped) {
        current.writeCharCode(char);
        escaped = false;
        continue;
      }
      if (char == 0x5c) {
        current.writeCharCode(char);
        escaped = true;
        continue;
      }
      if (quote != 0) {
        current.writeCharCode(char);
        if (char == quote) quote = 0;
        continue;
      }
      if (char == 0x22 || char == 0x27 || char == 0x60) {
        quote = char;
        current.writeCharCode(char);
        continue;
      }
      if (char == 0x28) parenDepth++;
      if (char == 0x29) parenDepth--;
      if (char == 0x7b) braceDepth++;
      if (char == 0x7d) braceDepth--;

      if (char == 0x2c && parenDepth == 0 && braceDepth == 0) {
        args.add(current.toString().trim());
        current = StringBuffer();
      } else {
        current.writeCharCode(char);
      }
    }
    final last = current.toString().trim();
    if (last.isNotEmpty) args.add(last);
    return args;
  }

  static bool _hasMatchingSimpleJsOuterParens(String expr) {
    if (!expr.startsWith('(') || !expr.endsWith(')')) return false;
    var depth = 0;
    for (var i = 0; i < expr.length - 1; i++) {
      final char = expr.codeUnitAt(i);
      if (char == 0x28) depth++;
      if (char == 0x29) depth--;
      if (depth == 0) return false;
    }
    return true;
  }

  static dynamic _callSimpleJsFunction(
    String funcName,
    List<dynamic> args,
    Map<String, dynamic> variables,
  ) {
    if (funcName == 'encodeURIComponent' || funcName == 'encodeURI') {
      if (args.isEmpty) return '';
      return Uri.encodeComponent(args[0].toString());
    }
    if (funcName == 'java.encodeURI' || funcName == 'java.encode') {
      if (args.isEmpty) return '';
      final str = args[0].toString();
      final charset = args.length > 1
          ? args[1].toString().replaceAll(RegExp("[\"']"), '')
          : 'utf-8';
      if (charset.toLowerCase() == 'gbk' || charset.toLowerCase() == 'gb2312') {
        final bytes = gbk.encode(str);
        return bytes
            .map((b) => '%' + b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join();
      }
      return Uri.encodeComponent(str);
    }
    if (funcName == 'java.md5Encode') {
      if (args.isEmpty) return '';
      final str = args[0].toString();
      final bytes = utf8.encode(str);
      final digest = md5.convert(bytes);
      return digest.toString();
    }
    if (funcName == 'java.base64Encode') {
      if (args.isEmpty) return '';
      final str = args[0].toString();
      return base64.encode(utf8.encode(str));
    }
    if (funcName == 'java.get') {
      if (args.isEmpty) return '';
      return variables[args[0].toString()] ?? '';
    }
    if (funcName == 'java.put') {
      if (args.length >= 2) {
        variables[args[0].toString()] = args[1];
        return args[1];
      }
      return '';
    }
    return args.isNotEmpty ? args[0] : '';
  }

  static String? _extractJsAssignedObject(String code, String name) {
    final match = RegExp('$name\\s*=\\s*\\{', multiLine: true).firstMatch(code);
    if (match == null) return null;
    final openIndex = code.indexOf('{', match.start);
    if (openIndex < 0) return null;
    var depth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = openIndex; i < code.length; i++) {
      final unit = code.codeUnitAt(i);
      if (quote != 0) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == quote) {
          quote = 0;
        }
        continue;
      }
      if (unit == 0x22 || unit == 0x27 || unit == 0x60) {
        quote = unit;
        continue;
      }
      if (unit == 0x7b) {
        depth++;
      } else if (unit == 0x7d) {
        depth--;
        if (depth == 0) return code.substring(openIndex, i + 1);
      }
    }
    return null;
  }

  static Map<String, String> _parseSimpleJsObject(
    String objectLiteral, {
    required String keyword,
    required int page,
  }) {
    final inner = objectLiteral.trim().replaceFirst('{', '');
    final text = inner.endsWith('}')
        ? inner.substring(0, inner.length - 1)
        : inner;
    final result = <String, String>{};
    for (final entry in _splitTopLevelCommas(text)) {
      final colon = _firstTopLevelColon(entry);
      if (colon <= 0) continue;
      final key = _unquoteJsString(entry.substring(0, colon).trim());
      final value = _evaluateSimpleJsValue(
        entry.substring(colon + 1).trim(),
        keyword: keyword,
        page: page,
      );
      if (key.isNotEmpty) result[key] = value;
    }
    return result;
  }

  static List<String> _splitTopLevelCommas(String text) {
    final parts = <String>[];
    var start = 0;
    var depth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (quote != 0) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == quote) {
          quote = 0;
        }
        continue;
      }
      if (unit == 0x22 || unit == 0x27 || unit == 0x60) {
        quote = unit;
        continue;
      }
      if (unit == 0x28 || unit == 0x5b || unit == 0x7b) depth++;
      if (unit == 0x29 || unit == 0x5d || unit == 0x7d) depth--;
      if (depth == 0 && unit == 0x2c) {
        parts.add(text.substring(start, i).trim());
        start = i + 1;
      }
    }
    final tail = text.substring(start).trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts;
  }

  static int _firstTopLevelColon(String text) {
    var depth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (quote != 0) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == quote) {
          quote = 0;
        }
        continue;
      }
      if (unit == 0x22 || unit == 0x27 || unit == 0x60) {
        quote = unit;
        continue;
      }
      if (unit == 0x28 || unit == 0x5b || unit == 0x7b) depth++;
      if (unit == 0x29 || unit == 0x5d || unit == 0x7d) depth--;
      if (depth == 0 && unit == 0x3a) return i;
    }
    return -1;
  }

  static String _evaluateSimpleJsValue(
    String expression, {
    required String keyword,
    required int page,
  }) {
    final value = expression.trim().replaceAll(RegExp(r';+$'), '').trim();
    if (value == 'key' || value == 'keyword') return keyword;
    if (value == 'page' || value == 'params.pageIndex') return page.toString();
    if (value == 'true' || value == 'false') return value;
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) return value;
    return _unquoteJsString(value);
  }

  static String _unquoteJsString(String value) {
    final text = value.trim();
    if (text.length >= 2) {
      final first = text.codeUnitAt(0);
      final last = text.codeUnitAt(text.length - 1);
      if ((first == 0x22 || first == 0x27 || first == 0x60) && first == last) {
        return text
            .substring(1, text.length - 1)
            .replaceAll(r'\"', '"')
            .replaceAll(r"\'", "'")
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\r', '\r')
            .replaceAll(r'\t', '\t');
      }
    }
    return text;
  }

  static String _signedParamString(Map<String, String> values, String signKey) {
    final keys = values.keys.toList()..sort();
    final payload = keys.map((key) => '$key=${values[key] ?? ''}').join();
    return md5.convert(utf8.encode(payload + signKey)).toString();
  }

  static String _buildLegacyUrlEncodedBody(Map<String, String> params) {
    final buffer = StringBuffer();
    params.forEach((key, value) {
      buffer
        ..write('&')
        ..write(key)
        ..write('=')
        ..write(Uri.encodeComponent(value));
    });
    return buffer.toString();
  }

  static String _resolveUrl(String baseUrl, String url) {
    return LegadoRequestBuilder.resolveUrl(baseUrl, url);
  }

  static String resolveUrl(String baseUrl, String url) {
    return _resolveUrl(baseUrl, url);
  }

  static String _resolveBookUrl(String baseUrl, String url) {
    if (url.isEmpty) return baseUrl;
    final candidate = _bestUrlCandidate(url);
    if (candidate.isEmpty) return '';
    if (RegExp(r'^\d+$').hasMatch(candidate)) {
      return _normalizeSuspiciousBookUrl(_resolveUrl(baseUrl, candidate));
    }
    return _normalizeSuspiciousBookUrl(_resolveUrl(baseUrl, candidate));
  }

  static String _bestUrlCandidate(String value) {
    final candidates = _splitUrlCandidates(value);
    if (candidates.isEmpty) return value.trim();
    if (candidates.length == 1) return candidates.first;

    String best = '';
    var bestScore = -1 << 30;
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      if (_isNonNavigableHref(candidate)) continue;
      final score = _scoreBookUrlCandidate(candidate) - i;
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best.isEmpty ? candidates.first : best;
  }

  static List<String> _splitUrlCandidates(String value) {
    final text = value.trim();
    if (text.isEmpty) return const [];
    if (LegadoRequestBuilder.splitEmbeddedConfig(text).config.isNotEmpty) {
      return [text];
    }
    final parts = text
        .split(RegExp(r'[\r\n]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= 1) return parts;
    final seen = <String>{};
    return [
      for (final part in parts)
        if (seen.add(part)) part,
    ];
  }

  static bool _hasMultipleUrlCandidates(String value) {
    return _splitUrlCandidates(value).length > 1;
  }

  static int _scoreBookUrlCandidate(String value) {
    final lower = value.toLowerCase();
    var score = 0;
    if (RegExp(
      r'/(?:book|novel|info|detail|article|shu|xiaoshuo|txt|mh)/',
    ).hasMatch(lower)) {
      score += 12;
    }
    if (RegExp(r'/(?:read|chapter|chap|content)/').hasMatch(lower)) {
      score += 4;
    }
    if (RegExp(r'\d{2,}').hasMatch(lower)) score += 2;
    if (lower.contains('/search') ||
        lower.contains('/sort') ||
        lower.contains('/class') ||
        lower.contains('/category') ||
        lower.contains('/cat/') ||
        lower.contains('/top/') ||
        lower.contains('/rank') ||
        lower.contains('/tag/')) {
      score -= 20;
    }
    final slashCount = '/'.allMatches(lower).length;
    score -= slashCount;
    if (lower.endsWith('.html') || lower.endsWith('.htm')) score -= 1;
    return score;
  }

  static bool _looksSuspiciousResolvedBookUrl(String url) {
    final text = url.trim();
    if (text.isEmpty) return false;
    if (RegExp(
      r'https?://[^ \r\n]+https?://',
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }
    try {
      final uri = Uri.parse(text);
      final segments = uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (_hasRepeatedPathPrefix(segments)) return true;
    } catch (_) {}
    return false;
  }

  static String _normalizeSuspiciousBookUrl(String url) {
    var text = url.trim();
    if (text.isEmpty) return text;
    text = _removeEmbeddedAbsoluteUrl(text);
    try {
      final uri = Uri.parse(text);
      final segments = uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
      final collapsed = _collapseRepeatedPathPrefix(segments);
      if (collapsed.length != segments.length) {
        final normalizedPath =
            '/${collapsed.map(Uri.encodeComponent).join('/')}';
        text = uri.replace(path: normalizedPath).toString();
      }
    } catch (_) {}
    return text;
  }

  static String _removeEmbeddedAbsoluteUrl(String url) {
    final match = RegExp(
      r'^((?:https?:)?//[^/]+/.*?)https?://',
      caseSensitive: false,
    ).firstMatch(url);
    if (match == null) return url;
    final prefix = match.group(1)?.trim() ?? '';
    if (prefix.isEmpty) return url;
    return prefix;
  }

  static bool _hasRepeatedPathPrefix(List<String> segments) {
    return _collapseRepeatedPathPrefix(segments).length != segments.length;
  }

  static List<String> _collapseRepeatedPathPrefix(List<String> segments) {
    if (segments.length < 2) return segments;
    for (var groupSize = 1; groupSize <= segments.length ~/ 2; groupSize++) {
      final group = segments.take(groupSize).toList();
      var cursor = groupSize;
      var repeats = 1;
      while (cursor + groupSize <= segments.length &&
          _listEquals(segments.sublist(cursor, cursor + groupSize), group)) {
        repeats++;
        cursor += groupSize;
      }
      if (repeats >= 2) {
        return [...group, ...segments.skip(cursor)];
      }
    }
    return segments;
  }

  static bool _isJsonRule(String rule) {
    return LegadoRuleEvaluator.isJsonRule(rule);
  }

  static bool _isJsonListRuleForData(dynamic data, String rule) {
    if (_isJsonRule(rule)) return true;
    if (!_looksLikeJsonData(data, rule)) return false;
    final cleaned = LegadoRuleEvaluator.stripPostProcessors(rule).trim();
    return cleaned.startsWith('.') &&
        RegExp(r'(^|[|&%]\s*)\.[A-Za-z_]').hasMatch(cleaned);
  }

  static String _jsonPathRule(String rule) {
    return LegadoRuleEvaluator.jsonPathRule(rule);
  }

  static String _cleanRuleOutput(String value) {
    return LegadoRuleEvaluator.cleanRuleOutput(value);
  }

  static String _applyContentReplaceRegex(
    String value,
    Map<String, dynamic> rule, {
    BookSource? source,
    Book? book,
    Chapter? chapter,
  }) {
    final replaceRule = _firstRule(rule, const ['replaceRegex', 'replace']);
    if (replaceRule == null || replaceRule.isEmpty) {
      return _cleanRuleOutput(value);
    }
    final scopedReplaceRule = source == null
        ? replaceRule
        : _sourceScopedRule(replaceRule, source, book: book, chapter: chapter);
    return LegadoRuleEvaluator.applyPostProcessors(
      value,
      scopedReplaceRule.startsWith('##')
          ? scopedReplaceRule
          : '##$scopedReplaceRule',
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

  static bool _isLegadoTrue(String? value) {
    if (value == null) return false;
    final text = value.trim();
    if (text.isEmpty || text == 'null') return false;
    return !RegExp(
      r'^(?:false|no|not|0|0\.0)$',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static String _sample(dynamic data) {
    final text = data.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 220 ? '${text.substring(0, 220)}...' : text;
  }

  static int _pickTestBookIndex(List<Book> books, String keyword) {
    if (books.isEmpty) return 0;
    final q = _normalizeSearchComparable(keyword);
    if (q.isEmpty) return 0;
    for (var i = 0; i < books.length; i++) {
      final title = _normalizeSearchComparable(books[i].title);
      if (title.isEmpty) continue;
      if (title == q || title.contains(q) || q.contains(title)) return i;
    }
    return 0;
  }

  static String _normalizeSearchComparable(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '')
        .trim();
  }

  static Chapter? _firstSuspiciousChapter(
    Iterable<Chapter> chapters,
    String bookUrl,
  ) {
    final normalizedBookUrl = bookUrl.trim();
    for (final chapter in chapters) {
      final title = chapter.title.trim();
      final target = (chapter.content ?? chapter.url ?? '').trim();
      if (title.isEmpty || target.isEmpty) return chapter;
      if (_looksLikeJsFragment(title)) return chapter;
      if (target == normalizedBookUrl && !target.startsWith('volume://')) {
        return chapter;
      }
    }
    return null;
  }

  static bool _looksLikeJsFragment(String text) {
    final value = text.trim();
    if (value.contains('result.match') ||
        value.contains('}else{') ||
        value.contains('@js:') ||
        value.contains('function(') ||
        value.contains('=>') ||
        value.contains('java.ajax') ||
        value.contains('java.connect')) {
      return true;
    }
    return value.length > 120 &&
        (value.contains('{') || value.contains('}') || value.contains(';'));
  }

  /// 正文质量校验：长度达标也可能是“假绿”——验证页/反爬页/未清洗整页HTML/JS残片。
  /// 命中任一特征即视为无效正文，避免一键测源把打不开的源误判为可用。
  static bool _looksLikeInvalidContent(String content) {
    final value = content.trim();
    if (value.isEmpty) return true;
    if (_looksLikeJsFragment(value)) return true;
    final lower = value.toLowerCase();
    if (lower.contains('<script') ||
        lower.contains('</html>') ||
        lower.contains('<!doctype')) {
      return true;
    }
    const markers = [
      '请开启javascript',
      'enable javascript',
      '人机验证',
      '滑动验证',
      '安全验证',
      '验证码',
      'captcha',
      'cloudflare',
      'attention required',
      'access denied',
      '访问受限',
      'just a moment',
      'checking your browser',
      '404 not found',
      '页面不存在',
      '请求过于频繁',
      '访问频繁',
    ];
    for (final marker in markers) {
      if (lower.contains(marker)) return true;
    }
    final structuralTags = RegExp(
      r'<(div|a|li|span|form|input|button|ul|table|tr|td|nav|header|footer)[\s>]',
      caseSensitive: false,
    ).allMatches(value).length;
    if (structuralTags >= 6) return true;
    final stripped = value
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), '');
    if (stripped.length < _minTestContentLength) return true;
    return false;
  }

  static Future<List<Book>> _parseBooksByJsonFallback(
    dynamic data,
    Map<String, dynamic> rule,
    BookSource source, {
    String? baseUrl,
    String? keyword,
  }) async {
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
      final books = <Book>[];
      for (final item in list.whereType<Map>()) {
        books.add(
          await _parseBookFromJsonAsync(
            _stringKeyMap(item),
            rule,
            source,
            baseUrl: baseUrl,
            keyword: keyword,
          ),
        );
      }
      return books;
    } catch (_) {
      return [];
    }
  }

  static List<Book> _parseBooksByHtmlSearchFallback(
    dynamic data,
    BookSource source, {
    required String baseUrl,
    required String keyword,
  }) {
    final query = _normalizeSearchComparable(keyword);
    if (query.isEmpty) return const [];
    try {
      final document = parse(data.toString());
      document
          .querySelectorAll('script, style, noscript, iframe, header, footer')
          .forEach((element) => element.remove());

      final books = <Book>[];
      final seen = <String>{};
      for (final anchor in document.querySelectorAll('a[href]')) {
        final title = anchor.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        final href = anchor.attributes['href']?.trim() ?? '';
        if (title.length < 2 || title.length > 80 || href.isEmpty) continue;
        if (_looksLikeNavigationLink(title, href)) continue;

        final normalizedTitle = _normalizeSearchComparable(title);
        var score = 0;
        if (normalizedTitle == query) score += 16;
        if (normalizedTitle.contains(query) ||
            query.contains(normalizedTitle)) {
          score += 10;
        }
        if (_looksLikeBookDetailHref(href)) score += 4;
        var cursor = anchor.parent;
        for (var depth = 0; cursor != null && depth < 3; depth++) {
          final marker =
              '${cursor.localName ?? ''} ${cursor.id} ${cursor.className}'
                  .toLowerCase();
          if (marker.contains('book') ||
              marker.contains('novel') ||
              marker.contains('result') ||
              marker.contains('search') ||
              marker.contains('item') ||
              marker.contains('list')) {
            score += 3;
            break;
          }
          cursor = cursor.parent;
        }
        if (score < 10) continue;

        final resolved = _resolveBookUrl(baseUrl, href);
        if (_isNonNavigableHref(resolved) || !seen.add('$title|$resolved')) {
          continue;
        }
        books.add(
          Book(
            title: title,
            author: '',
            filePath: resolved,
            fileType: 'online',
            isFromSource: true,
            sourceUrl: source.id.toString(),
          ),
        );
        if (books.length >= 20) break;
      }
      return books;
    } catch (_) {
      return const [];
    }
  }

  static bool _looksLikeBookDetailHref(String href) {
    final value = href.toLowerCase();
    if (value.startsWith('javascript:') ||
        value.startsWith('#') ||
        value.startsWith('mailto:')) {
      return false;
    }
    return RegExp(
      r'(book|novel|info|detail|read|article|txt|xiaoshuo|shu|mh|chapter|/\d{2,}/)',
    ).hasMatch(value);
  }

  static List<String> _extractFallbackTocUrls(String baseUrl, String html) {
    if (html.trim().isEmpty) return const [];
    try {
      final document = parse(html);
      final urls = <String>[];
      final seen = <String>{};
      for (final anchor in document.querySelectorAll('a[href]')) {
        final href = anchor.attributes['href']?.trim() ?? '';
        if (_isNonNavigableHref(href)) continue;
        final text = anchor.text.trim().replaceAll(RegExp(r'\s+'), '');
        final lowerText = text.toLowerCase();
        final lowerHref = href.toLowerCase();
        final looksLikeToc =
            text.contains('目录') ||
            text.contains('章节') ||
            text.contains('点击阅读') ||
            text.contains('开始阅读') ||
            lowerText == 'read' ||
            lowerHref.contains('/mainindex') ||
            lowerHref.contains('catalog') ||
            lowerHref.contains('chapterlist') ||
            lowerHref.contains('chapters');
        if (!looksLikeToc) continue;
        if (_looksLikeCollectionPageUrl(href)) continue;
        final resolved = _resolveUrl(baseUrl, href);
        if (_isNonNavigableHref(resolved) || !seen.add(resolved)) continue;
        urls.add(resolved);
        if (urls.length >= 3) break;
      }
      return urls;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<Chapter>> _parseChaptersByJsListRule(
    BookSource source,
    Book book,
    Map<String, dynamic> rule,
    dynamic data,
    String listRule,
    String baseUrl, {
    int startIndex = 0,
    int? limit,
  }) async {
    try {
      final dataText = data is String ? data : jsonEncode(data);
      final variables = _jsVariables(
        source,
        result: dataText,
        baseUrl: baseUrl,
        book: book,
      );
      final output = await LegadoJsEngine().evaluateWithAjax(
        listRule,
        variables: variables,
        libraries: await _sourceLibraryCodes(source, baseUrl: baseUrl),
        ajax: (request) => _ajaxForJs(source, request, baseUrl: baseUrl),
      );
      final trimmed = output.trim();
      if (trimmed.isEmpty) return const [];
      final decoded = jsonDecode(trimmed);
      final nodes = decoded is List ? decoded : <dynamic>[decoded];
      if (nodes.isEmpty) return const [];

      final isVolumeRule = _firstRule(rule, const ['isVolume']);
      final formatJsRule = _firstRule(rule, const ['formatJs']);
      final titleRule =
          _firstRule(rule, const [
            'chapterName',
            'chapterNameTOC',
            'chapterNameToc',
            'name',
            'title',
            'ChapterName',
            'N',
          ]) ??
          'title';
      final urlRule =
          _firstRule(rule, const [
            'chapterUrl',
            'chapterUrlTOC',
            'chapterUrlToc',
            'url',
            'link',
            'ChapterUrl',
            'C',
          ]) ??
          'url';

      final chapters = <Chapter>[];
      var index = startIndex;
      for (final node in nodes) {
        if (limit != null && chapters.length >= limit) break;
        if (node is! Map) continue;
        final item = node.map((key, value) => MapEntry(key.toString(), value));
        final title = _extractJsonValue(
          item,
          _sourceScopedRule(titleRule, source),
          variables: variables,
        );
        final url = _extractJsonValue(
          item,
          _sourceScopedRule(urlRule, source),
          variables: variables,
        );
        bool isVolume = false;
        if (isVolumeRule != null && isVolumeRule.isNotEmpty) {
          final val = _extractJsonValue(
            item,
            _sourceScopedRule(isVolumeRule, source),
            variables: variables,
          );
          isVolume = _isLegadoTrue(val);
        }

        final fullUrl = url.trim().isEmpty
            ? (isVolume ? 'volume://$baseUrl#$index' : baseUrl)
            : _resolveUrl(baseUrl, url);
        if (title.trim().isEmpty && url.trim().isEmpty) continue;

        var finalTitle = title.isEmpty ? '第${index + 1}章' : title;
        if (formatJsRule != null && formatJsRule.isNotEmpty) {
          finalTitle = _applyFormatJsSync(
            formatJsRule,
            index: index,
            title: finalTitle,
            url: fullUrl,
          );
        }

        chapters.add(
          Chapter(
            bookId: book.id,
            title: finalTitle,
            index: index++,
            content: fullUrl,
            url: fullUrl,
            wordCount: 0,
            isDownloaded: false,
          ),
        );
      }
      return chapters;
    } catch (e) {
      debugPrint('JS chapterList execution failed: $e');
      return const [];
    }
  }

  static List<Chapter> _parseChaptersByHtmlFallback(
    dynamic data,
    Map<String, dynamic> rule,
    BookSource source,
    Book book,
    String baseUrl, {
    int startIndex = 0,
    int? limit,
  }) {
    try {
      final document = parse(data.toString());
      document
          .querySelectorAll('script, style, noscript, iframe, header, footer')
          .forEach((element) => element.remove());

      final anchors = document.querySelectorAll('a[href]');
      final candidates = <({String title, String url, int score})>[];
      for (final anchor in anchors) {
        final title = anchor.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        final href = anchor.attributes['href']?.trim() ?? '';
        if (title.isEmpty || href.isEmpty) continue;
        if (title.length > 80) continue;
        if (_looksLikeNavigationLink(title, href)) continue;

        var score = 0;
        if (_looksLikeChapterTitle(title)) score += 8;
        if (RegExp(r'\d+').hasMatch(href)) score += 2;
        if (href.endsWith('.html') || href.endsWith('.htm')) score += 2;
        final parentClass = anchor.parent?.className.toLowerCase() ?? '';
        final parentId = anchor.parent?.id.toLowerCase() ?? '';
        if (parentClass.contains('chapter') ||
            parentClass.contains('catalog') ||
            parentClass.contains('list') ||
            parentClass.contains('mulu') ||
            parentId.contains('chapter') ||
            parentId.contains('catalog') ||
            parentId.contains('list') ||
            parentId.contains('mulu')) {
          score += 4;
        }
        if (score < 8) continue;

        final resolved = _resolveUrl(baseUrl, href);
        if (_isNonNavigableHref(resolved)) continue;
        candidates.add((title: title, url: resolved, score: score));
      }

      if (candidates.length < 2) return [];
      final seen = <String>{};
      final chapters = <Chapter>[];
      var index = startIndex;
      final formatJsRule = _firstRule(rule, const ['formatJs']);
      for (final candidate in candidates) {
        if (limit != null && chapters.length >= limit) break;
        final key = '${candidate.title}|${candidate.url}';
        if (!seen.add(key)) continue;
        var title = candidate.title;
        if (formatJsRule != null && formatJsRule.isNotEmpty) {
          title = _applyFormatJsSync(
            formatJsRule,
            index: index,
            title: title,
            url: candidate.url,
          );
        }
        chapters.add(
          Chapter(
            bookId: book.id,
            title: title,
            index: index++,
            content: candidate.url,
            url: candidate.url,
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

  static List<Book> _parseBooksByRegexList(
    dynamic data,
    Map<String, dynamic> rule,
    BookSource source, {
    required String baseUrl,
    required String regexRule,
  }) {
    final matches = _extractRegexGroupRows(data.toString(), regexRule);
    if (matches.isEmpty) return const [];

    final explicitNameRule = _firstRule(rule, const [
      'name',
      'title',
      'bookName',
    ]);
    final explicitUrlRule = _firstRule(rule, const [
      'bookUrl',
      'tocUrl',
      'catalogUrl',
      'url',
      'link',
    ]);
    final authorRule = _firstRule(rule, const ['author', 'writer']);
    final coverRule = _firstRule(rule, const ['coverUrl', 'cover']);
    final kindRule = _firstRule(rule, const ['kind', 'category', 'tags']);
    final wordCountRule = _firstRule(rule, const ['wordCount']);
    final lastChapterRule = _firstRule(rule, const ['lastChapter']);

    String value(List<String> groups, String? rawRule, String fallbackRule) {
      final selected = (rawRule == null || rawRule.trim().isEmpty)
          ? fallbackRule
          : rawRule;
      if (selected.trim().isEmpty) return '';
      return _cleanRuleOutput(
        _valueFromRegexGroups(groups, _sourceScopedRule(selected, source)),
      );
    }

    final books = <Book>[];
    final seen = <String>{};
    for (final groups in matches) {
      final name = value(groups, explicitNameRule, r'$1').trim();
      final urlFallback = groups.length > 2 ? r'$2' : '';
      final bookUrl = value(groups, explicitUrlRule, urlFallback).trim();
      if (name.isEmpty && bookUrl.isEmpty) continue;

      final author = value(groups, authorRule, '').trim();
      final coverUrl = value(groups, coverRule, '').trim();
      final kind = value(groups, kindRule, '').trim();
      final wordCount = _parseWordCount(value(groups, wordCountRule, ''));
      final totalChapters = _parseChapterCount(
        value(groups, lastChapterRule, ''),
      );
      final resolvedBookUrl = bookUrl.isEmpty
          ? baseUrl
          : _resolveBookUrl(baseUrl, bookUrl);
      final dedupeKey = '$name|$resolvedBookUrl';
      if (!seen.add(dedupeKey)) continue;

      books.add(
        Book(
          title: name.isEmpty ? 'Unknown' : name,
          author: author,
          filePath: resolvedBookUrl,
          fileType: 'online',
          coverPath: coverUrl.isEmpty ? null : _resolveUrl(baseUrl, coverUrl),
          tags: _splitBookTags(kind),
          isFromSource: true,
          sourceUrl: source.id.toString(),
          totalChapters: totalChapters,
          fileSize: wordCount,
        ),
      );
    }
    return books;
  }

  static List<String> _splitBookTags(String value) {
    if (value.trim().isEmpty) return const [];
    final seen = <String>{};
    return value
        .split(RegExp(r'[,，/|;；\s]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && seen.add(item))
        .toList();
  }

  static List<Chapter> _parseChaptersByRegexList(
    dynamic data,
    Map<String, dynamic> rule,
    Book book,
    String baseUrl,
    String regexRule, {
    int startIndex = 0,
    int? limit,
  }) {
    final matches = _extractRegexGroupRows(data.toString(), regexRule);
    if (matches.isEmpty) return [];

    var titleRule =
        _firstRule(rule, const [
          'chapterName',
          'chapterNameTOC',
          'chapterNameToc',
          'name',
          'title',
          'ChapterName',
          'N',
        ]) ??
        '';
    if (titleRule.trim().isEmpty) titleRule = r'$1';

    final urlRule =
        _firstRule(rule, const [
          'chapterUrl',
          'chapterUrlTOC',
          'chapterUrlToc',
          'url',
          'link',
          'ChapterUrl',
          'C',
        ]) ??
        '';
    final isVolumeRule = _firstRule(rule, const ['isVolume']);
    final formatJsRule = _firstRule(rule, const ['formatJs']);

    final chapters = <Chapter>[];
    var index = startIndex;
    for (final groups in matches) {
      if (limit != null && chapters.length >= limit) break;

      final title = _valueFromRegexGroups(groups, titleRule).trim();
      final url = _valueFromRegexGroups(groups, urlRule).trim();
      final isVolume = isVolumeRule == null || isVolumeRule.isEmpty
          ? false
          : _isLegadoTrue(_valueFromRegexGroups(groups, isVolumeRule));

      final fullUrl = url.isEmpty
          ? (isVolume ? 'volume://$baseUrl#$index' : baseUrl)
          : _resolveUrl(baseUrl, url);

      if (title.isEmpty && url.isEmpty) continue;

      var finalTitle = title.isEmpty ? 'Chapter ${index + 1}' : title;
      if (formatJsRule != null && formatJsRule.isNotEmpty) {
        finalTitle = _applyFormatJsSync(
          formatJsRule,
          index: index,
          title: finalTitle,
          url: fullUrl,
        );
      }

      chapters.add(
        Chapter(
          bookId: book.id,
          title: finalTitle,
          index: index++,
          content: fullUrl,
          url: fullUrl,
          wordCount: 0,
          isDownloaded: false,
        ),
      );
    }
    return chapters;
  }

  static String? _regexListRule(String rule) {
    final trimmed = rule.trimLeft();
    if (trimmed.startsWith(':')) {
      final body = trimmed.substring(1).trim();
      return body.isEmpty ? null : body;
    }
    if (trimmed.toLowerCase().startsWith('@regex:')) {
      final body = trimmed.substring('@regex:'.length).trim();
      return body.isEmpty ? null : body;
    }
    return null;
  }

  static List<List<String>> _extractRegexGroupRows(String input, String rule) {
    var text = input;
    final parts = rule
        .split('&&')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return const [];

    for (var i = 0; i < parts.length; i++) {
      final List<RegExpMatch> matches;
      try {
        final regex = _compileLegadoRegex(parts[i]);
        matches = regex.allMatches(text).toList();
      } catch (_) {
        return const [];
      }
      if (matches.isEmpty) return const [];
      final isLast = i == parts.length - 1;
      if (!isLast) {
        text = matches.map((match) => match.group(0) ?? '').join();
        continue;
      }
      return matches.map(_regexGroups).toList();
    }
    return const [];
  }

  static List<String> _regexGroups(RegExpMatch match) {
    return [for (var i = 0; i <= match.groupCount; i++) match.group(i) ?? ''];
  }

  static RegExp _compileLegadoRegex(String pattern) {
    var caseSensitive = true;
    var dotAll = false;
    var multiLine = false;
    for (final match in RegExp(r'\(\?([ismxuU]+)\)').allMatches(pattern)) {
      final flags = match.group(1) ?? '';
      if (flags.contains('i')) caseSensitive = false;
      if (flags.contains('s')) dotAll = true;
      if (flags.contains('m')) multiLine = true;
    }
    final normalized = pattern
        .replaceAll(RegExp(r'\(\?[ismxuU]+\)'), '')
        .replaceAll(r'\h', r'[\t \u00A0]');
    return RegExp(
      normalized,
      caseSensitive: caseSensitive,
      multiLine: multiLine,
      dotAll: dotAll,
    );
  }

  static String _valueFromRegexGroups(List<String> groups, String rule) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return '';
    final raw = groups.isEmpty ? '' : groups[0];
    if (trimmed.startsWith('##')) {
      return LegadoRuleEvaluator.applyPostProcessors(raw, trimmed);
    }
    final expanded = _expandRegexGroupTemplate(trimmed, groups);
    if (!expanded.contains('##')) return expanded;

    final marker = expanded.indexOf('##');
    final base = expanded.substring(0, marker);
    final processors = expanded.substring(marker);
    return LegadoRuleEvaluator.applyPostProcessors(base, processors);
  }

  static String _expandRegexGroupTemplate(
    String template,
    List<String> groups,
  ) {
    return template.replaceAllMapped(RegExp(r'\\([\\$])|\$(\d+)'), (match) {
      final escaped = match.group(1);
      if (escaped != null) return escaped;
      final index = int.tryParse(match.group(2) ?? '');
      if (index == null || index < 0 || index >= groups.length) return '';
      return groups[index];
    });
  }

  static bool _looksLikeChapterTitle(String title) {
    final normalized = title.trim();
    if (RegExp(
      r'^(第?\s*[0-9零一二三四五六七八九十百千万两〇]+[\s\.、_-]*(章|节|回|话|卷|集|部)|chapter\s*\d+)',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(r'^\d{1,5}[\s\.、_-]+.{1,60}$').hasMatch(normalized)) {
      return true;
    }
    return RegExp(
      r'^(序章|楔子|引子|前言|后记|终章|番外|正文|卷\s*[0-9零一二三四五六七八九十百千万两〇]+)',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  static bool _looksLikeNavigationLink(String title, String href) {
    if (_isNonNavigableHref(href)) return true;
    final text = title.toLowerCase();
    final url = href.toLowerCase();
    const words = [
      '首页',
      '上一页',
      '下一页',
      '上一章',
      '下一章',
      '末页',
      '返回',
      '目录',
      '书架',
      '登录',
      '注册',
      '更多',
      'home',
      'next',
      'prev',
      'previous',
      'last',
      'back',
    ];
    return words.any((word) => text == word || url.endsWith('/$word'));
  }

  static bool _isNonNavigableHref(String href) {
    final value = href.trim().toLowerCase();
    if (value.isEmpty) return true;
    return value == '#' ||
        value.startsWith('#') ||
        value.startsWith('javascript:') ||
        value.startsWith('mailto:') ||
        value.startsWith('tel:') ||
        value == 'about:blank';
  }

  static List<String> _extractFallbackNextContentUrls(
    String baseUrl,
    String html,
  ) {
    if (html.trim().isEmpty) return const [];
    try {
      final document = parse(html);
      final urls = <String>[];
      final seen = <String>{};
      for (final anchor in document.querySelectorAll('a[href]')) {
        final text = anchor.text.trim().replaceAll(RegExp(r'\s+'), '');
        final href = anchor.attributes['href']?.trim() ?? '';
        if (_isNonNavigableHref(href)) continue;
        final rel = (anchor.attributes['rel'] ?? '').toLowerCase();
        final lowerText = text.toLowerCase();
        final isNextPage =
            text == '下一页' ||
            text == '下一頁' ||
            text == '下页' ||
            text == '下頁' ||
            lowerText == 'next' ||
            lowerText == 'nextpage' ||
            lowerText == 'next>';
        final relNextPage =
            rel.split(RegExp(r'\s+')).contains('next') &&
            !RegExp(r'章|节|回|chapter', caseSensitive: false).hasMatch(text);
        if (!isNextPage && !relNextPage) continue;
        final resolved = _resolveUrl(baseUrl, _cleanInlineUrl(href));
        if (_isNonNavigableHref(resolved) ||
            resolved == baseUrl ||
            !seen.add(resolved)) {
          continue;
        }
        urls.add(resolved);
        if (urls.length >= 2) break;
      }
      return urls;
    } catch (_) {
      return const [];
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
      final list = _collectLikelyChapterMaps(jsonData);
      if (list.isEmpty) return [];

      final isVolumeRule = _firstRule(rule, const ['isVolume']);
      final formatJsRule = _firstRule(rule, const ['formatJs']);

      final chapters = <Chapter>[];
      var index = 0;
      for (final raw in list) {
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
          'text',
          'volumeName',
        ]);
        final url = _chapterUrlFromFallbackItem(
          item,
          rule,
          source,
          book,
          baseUrl,
        );

        bool isVolume = false;
        if (isVolumeRule != null && isVolumeRule.isNotEmpty) {
          final val = _extractJsonValue(
            item,
            _sourceScopedRule(isVolumeRule, source),
          );
          isVolume = _isLegadoTrue(val);
        }

        var fullUrl = '';
        if (url.trim().isEmpty) {
          if (isVolume) {
            fullUrl = 'volume://$baseUrl#$index';
          } else {
            fullUrl = baseUrl;
          }
        } else {
          fullUrl = _resolveUrl(baseUrl, url);
        }

        if (title.isEmpty && url.isEmpty) continue;

        var finalTitle = title.isEmpty ? '第${index + 1}章' : title;
        if (formatJsRule != null && formatJsRule.isNotEmpty) {
          finalTitle = _applyFormatJsSync(
            formatJsRule,
            index: index,
            title: finalTitle,
            url: fullUrl,
          );
        }

        chapters.add(
          Chapter(
            bookId: book.id,
            title: finalTitle,
            index: index++,
            content: fullUrl,
            url: fullUrl,
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
    final ruleValue = _firstRule(rule, const [
      'bookUrl',
      'chapterUrl',
      'url',
      'link',
    ]);
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
      'readUrl',
      'read_url',
      'jumpUrl',
      'jump_url',
      'uri',
      'filePath',
      'content',
      'contentUrl',
      'chapter_url',
      'chapter_url_full',
      'href',
      'src',
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
      final exact = item[key];
      final exactText = exact?.toString().trim();
      if (exactText != null && exactText.isNotEmpty) return exactText;

      final keyLower = key.toLowerCase();
      for (final entry in item.entries) {
        if (entry.key.toLowerCase() != keyLower) continue;
        final text = entry.value?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
    }
    return '';
  }

  static Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> map) {
    return map.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<Map<dynamic, dynamic>> _collectLikelyChapterMaps(dynamic value) {
    final result = <Map<dynamic, dynamic>>[];
    final seen = <Map<dynamic, dynamic>>{};

    void visit(dynamic node, [int depth = 0]) {
      if (depth > 8) return;
      if (node is List) {
        for (final child in node) {
          visit(child, depth + 1);
        }
        return;
      }
      if (node is! Map) return;

      if (_looksLikeChapterMap(node) && seen.add(node)) {
        result.add(node);
      }
      for (final child in node.values) {
        if (child is List || child is Map) {
          visit(child, depth + 1);
        }
      }
    }

    visit(value);
    return result;
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
    final lowerKeys = item.keys
        .map((key) => key.toString().toLowerCase())
        .toSet();
    bool has(String key) => lowerKeys.contains(key.toLowerCase());

    return has('chapterName') ||
        has('chapter_name') ||
        has('chapterTitle') ||
        has('chapter_title') ||
        has('chapterUrl') ||
        has('chapter_url') ||
        has('chapterId') ||
        has('chapter_id') ||
        has('cid') ||
        has('path') ||
        has('href') ||
        has('readUrl') ||
        has('read_url') ||
        has('page') ||
        has('contentUrl') ||
        (has('name') &&
            (has('id') ||
                has('cid') ||
                has('chapterId') ||
                has('url') ||
                has('href') ||
                has('path') ||
                has('page'))) ||
        (has('title') &&
            (has('id') ||
                has('url') ||
                has('href') ||
                has('path') ||
                has('page'))) ||
        (has('text') && (has('url') || has('href') || has('path')));
  }

  static bool _isLegacyChineseCharset(String value) {
    final normalized = value.toLowerCase();
    return normalized == 'gbk' ||
        normalized == 'gb2312' ||
        normalized == 'gb18030' ||
        RegExp(
          r'''charset\s*=\s*["']?(gbk|gb2312|gb18030)''',
          caseSensitive: false,
        ).hasMatch(value);
  }

  static bool _isUtf8Charset(String value) {
    final normalized = value.toLowerCase();
    return normalized == 'utf-8' ||
        normalized == 'utf8' ||
        RegExp(
          r'''charset\s*=\s*["']?(utf-8|utf8)''',
          caseSensitive: false,
        ).hasMatch(value);
  }

  static String _headerValue(Map<String, List<String>>? headers, String name) {
    if (headers == null || headers.isEmpty) return '';
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) {
        return entry.value.join(' ');
      }
    }
    return '';
  }

  static bool _looksLikeBrokenUtf8(String text) {
    if (text.isEmpty) return false;
    final replacementCount =
        '\uFFFD'.allMatches(text).length + '锟'.allMatches(text).length;
    return replacementCount >= 2 &&
        replacementCount / text.length.clamp(1, 1 << 30) > 0.003;
  }

  static String detectCharset(
    List<int> bytes,
    String? charset,
    Map<String, List<String>>? headers,
  ) {
    if (charset != null && charset.isNotEmpty) {
      if (_isLegacyChineseCharset(charset)) {
        return 'gbk';
      }
      if (_isUtf8Charset(charset)) return 'utf-8';
      return charset;
    }

    var sniffBytes = bytes;
    final isGzip = bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B;

    // 在嗅探前利用 GzipCodec 解压，防止乱码穿透探测器
    if (isGzip) {
      try {
        sniffBytes = GZipCodec().decode(bytes);
      } catch (_) {}
    }

    final contentType = _headerValue(headers, 'content-type');
    if (contentType.isNotEmpty) {
      if (_isLegacyChineseCharset(contentType)) return 'gbk';
      if (_isUtf8Charset(contentType)) return 'utf-8';
    }

    if (sniffBytes.isEmpty) return 'utf-8';
    final sampleLength = sniffBytes.length < 4096 ? sniffBytes.length : 4096;
    final sampleBytes = sniffBytes.sublist(0, sampleLength);
    final sampleStr = ascii
        .decode(sampleBytes.map((b) => (b >= 0 && b <= 127) ? b : 63).toList())
        .toLowerCase();

    if (_isLegacyChineseCharset(sampleStr)) return 'gbk';
    if (_isUtf8Charset(sampleStr)) return 'utf-8';

    return 'utf-8';
  }

  static String decodeBytes(
    List<int> bytes,
    String? charset, {
    Map<String, List<String>>? headers,
  }) {
    if (bytes.isEmpty) return '';
    var contentBytes = bytes;

    // 只按魔法头解 gzip。Dart HttpClient 可能已自动解压但保留
    // content-encoding: gzip，按响应头重复解压会制造大量假错误日志。
    final isGzip = bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B;

    if (isGzip) {
      try {
        contentBytes = GZipCodec().decode(bytes);
      } catch (_) {}
    }
    final detected = detectCharset(
      contentBytes,
      charset,
      headers,
    ).toLowerCase().trim();
    if (_isLegacyChineseCharset(detected)) {
      try {
        return gbk.decode(contentBytes);
      } catch (_) {
        return utf8.decode(contentBytes, allowMalformed: true);
      }
    }
    final utf8Text = utf8.decode(contentBytes, allowMalformed: true);
    if (_looksLikeBrokenUtf8(utf8Text)) {
      try {
        final gbkText = gbk.decode(contentBytes);
        if (!_looksLikeBrokenUtf8(gbkText)) return gbkText;
      } catch (_) {
        // Keep UTF-8 fallback.
      }
    }
    return utf8Text;
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
      debugPrint('RSS parsing error: $e');
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
      debugPrint('RSS Content parsing error: $e');
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
  final List<String> logs;

  const LegadoTestStep({
    required this.title,
    required this.message,
    this.sample,
    required this.status,
    this.logs = const [],
  });

  const LegadoTestStep.ok(
    String title,
    String message, {
    String? sample,
    List<String> logs = const [],
  }) : this(
         title: title,
         message: message,
         sample: sample,
         status: LegadoStepStatus.ok,
         logs: logs,
       );

  const LegadoTestStep.fail(
    String title,
    String message, {
    String? sample,
    List<String> logs = const [],
  }) : this(
         title: title,
         message: message,
         sample: sample,
         status: LegadoStepStatus.fail,
         logs: logs,
       );

  const LegadoTestStep.skip(
    String title,
    String message, {
    String? sample,
    List<String> logs = const [],
  }) : this(
         title: title,
         message: message,
         sample: sample,
         status: LegadoStepStatus.skip,
         logs: logs,
       );
}

enum LegadoStepStatus { ok, fail, skip }
