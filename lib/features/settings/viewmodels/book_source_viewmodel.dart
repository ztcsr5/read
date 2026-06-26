import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../data/models/book_source.dart';
import '../../../data/models/rss_source.dart';
import '../../../data/models/source_catalog.dart';
import '../../../data/parsers/source_import_link_parser.dart';
import '../../../data/repositories/book_repository.dart';

typedef SourceTextFetcher =
    Future<String> Function(String url, {bool withoutUserAgent});

class BookSourceState {
  final List<BookSource> sources;
  final List<RssSource> rssSources;
  final List<SourceCatalog> catalogs;
  final bool isLoading;
  final String? error;
  final String? message;

  BookSourceState({
    this.sources = const [],
    this.rssSources = const [],
    this.catalogs = const [],
    this.isLoading = false,
    this.error,
    this.message,
  });

  BookSourceState copyWith({
    List<BookSource>? sources,
    List<RssSource>? rssSources,
    List<SourceCatalog>? catalogs,
    bool? isLoading,
    String? error,
    String? message,
  }) {
    return BookSourceState(
      sources: sources ?? this.sources,
      rssSources: rssSources ?? this.rssSources,
      catalogs: catalogs ?? this.catalogs,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      message: message,
    );
  }
}

class BookSourceViewModel extends StateNotifier<BookSourceState> {
  final BookRepository _repository;
  final SourceTextFetcher _fetchText;

  BookSourceViewModel(this._repository, {SourceTextFetcher? fetchText})
    : _fetchText = fetchText ?? _defaultFetchText,
      super(BookSourceState()) {
    loadSources();
  }

  Future<void> loadSources() async {
    state = state.copyWith(isLoading: true, error: null, message: null);
    try {
      final sources = await _repository.getAllBookSources();
      final rssSources = await _repository.getAllRssSources();
      final catalogs = await _repository.getAllSourceCatalogs();
      state = state.copyWith(
        sources: sources,
        rssSources: rssSources,
        catalogs: catalogs,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> importSmartInput(String input) async {
    final parsed = SourceImportLinkParser.parse(input);
    switch (parsed.kind) {
      case SourceImportInputKind.empty:
        return;
      case SourceImportInputKind.json:
        await importFromJson(parsed.value);
        break;
      case SourceImportInputKind.url:
        await importFromUrl(parsed.value);
        break;
      case SourceImportInputKind.unsupportedScheme:
        state = state.copyWith(
          isLoading: false,
          error: '识别到了阅读类导入链接，但没有找到 src/url 参数。请复制完整链接，或用内置浏览器打开分享页后导入。',
        );
        break;
      case SourceImportInputKind.unknown:
        if (_looksLikeJsSource(parsed.value)) {
          await importFromJs(parsed.value);
          break;
        }
        state = state.copyWith(
          isLoading: false,
          error: '没有识别到 JSON、HTTP 链接或阅读导入链接。请检查复制内容。',
        );
        break;
    }
  }

  Future<void> importFromUrl(String url) async {
    final normalizedUrl = _normalizeImportUrl(url);
    state = state.copyWith(isLoading: true, error: null, message: null);
    try {
      final body = await _fetchText(normalizedUrl);
      if (_looksLikeJson(body)) {
        await importFromJson(body, originalUrl: normalizedUrl);
        return;
      }
      if (_looksLikeCloudflareChallenge(body)) {
        throw Exception(
          '内容是 Cloudflare/JS 验证页，不是书源 JSON。请用内置浏览器验证后下载 JSON，或选择本地 JSON 文件导入。',
        );
      }
      if (!_looksLikeJson(body)) {
        throw Exception('返回内容不是 JSON，可能是网页仓库入口、验证码或站点拒绝访问。可尝试内置浏览器导入。');
      }
      await importFromJson(body, originalUrl: normalizedUrl);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '网络导入失败: $e');
    }
  }

  Future<void> importFromJson(String jsonString, {String? originalUrl}) async {
    state = state.copyWith(isLoading: true, error: null, message: null);
    try {
      if (!_looksLikeJson(_normalizeImportJsonText(jsonString)) &&
          _looksLikeCloudflareChallenge(jsonString)) {
        throw Exception('内容是 Cloudflare 验证页，不是书源 JSON。请在浏览器下载 JSON 后导入。');
      }

      final parsed = jsonDecode(_normalizeImportJsonText(jsonString));
      final counts = await _importDecoded(
        parsed,
        originalUrl: originalUrl,
        visitedUrls: <String>{},
      );

      final summary = [
        if (counts.bookCount > 0) '书源 ${counts.bookCount} 个',
        if (counts.catalogCount > 0) '仓库 ${counts.catalogCount} 个',
        if (counts.rssCount > 0) 'RSS ${counts.rssCount} 个',
      ].join('，');

      await loadSources();
      if (summary.isNotEmpty) {
        state = state.copyWith(message: '导入成功：$summary');
      } else {
        state = state.copyWith(error: '未识别到有效的书源、书源仓库或 RSS 订阅格式');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '导入失败: $e');
    }
  }

  Future<void> importFromJs(String jsCode) async {
    state = state.copyWith(isLoading: true, error: null, message: null);
    try {
      final source = _bookSourceFromJs(jsCode);
      await _repository.saveBookSource(source);
      await loadSources();
      state = state.copyWith(message: '导入成功：JS 书源 1 个');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'JS 书源导入失败: $e');
    }
  }

  Future<_ImportSummary> _importDecoded(
    dynamic parsed, {
    String? originalUrl,
    required Set<String> visitedUrls,
  }) async {
    final sourceUrls = parsed is Map ? parsed['sourceUrls'] : null;
    if (sourceUrls is List) {
      final total = _ImportSummary();
      for (final value in sourceUrls) {
        final url = value?.toString().trim() ?? '';
        if (url.isEmpty) continue;
        total.add(await _importFromSourceUrl(url, visitedUrls: visitedUrls));
      }
      return total;
    }

    final total = _ImportSummary();
    final list = _normalizeImportItems(parsed);
    for (final item in list) {
      if (item is String && _isHttpUrl(item)) {
        total.add(await _importFromSourceUrl(item, visitedUrls: visitedUrls));
        continue;
      }
      if (item is! Map) continue;
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      switch (_detectImportKind(map)) {
        case _ImportKind.bookSource:
          await _repository.saveBookSource(BookSource.fromJson(map));
          total.bookCount++;
          break;
        case _ImportKind.sourceCatalog:
          await _repository.saveSourceCatalog(
            SourceCatalog.fromJson(map, originalUrl: originalUrl),
          );
          total.catalogCount++;
          break;
        case _ImportKind.rssSource:
          await _repository.saveRssSource(RssSource.fromJson(map));
          total.rssCount++;
          break;
        case _ImportKind.unknown:
          break;
      }
    }
    return total;
  }

  Future<_ImportSummary> _importFromSourceUrl(
    String rawUrl, {
    required Set<String> visitedUrls,
  }) async {
    final withoutUserAgent = rawUrl.endsWith('#requestWithoutUA');
    final url = withoutUserAgent
        ? rawUrl.substring(0, rawUrl.length - '#requestWithoutUA'.length)
        : rawUrl;
    final normalizedUrl = _normalizeImportUrl(url);
    if (!visitedUrls.add(normalizedUrl)) return _ImportSummary();

    final text = await _fetchText(
      normalizedUrl,
      withoutUserAgent: withoutUserAgent,
    );
    final parsed = jsonDecode(_normalizeImportJsonText(text));
    return _importDecoded(
      parsed,
      originalUrl: normalizedUrl,
      visitedUrls: visitedUrls,
    );
  }

  Future<void> importFromFilePath(String filePath) async {
    state = state.copyWith(isLoading: true, error: null, message: null);
    try {
      final bytes = await File(filePath).readAsBytes();
      await importFromBytes(bytes, originalUrl: filePath);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '文件导入失败: $e');
    }
  }

  Future<void> importFromBytes(List<int> bytes, {String? originalUrl}) async {
    try {
      final text = _decodeJsonBytes(bytes);
      if (_looksLikeJsSource(text)) {
        await importFromJs(text);
        return;
      }
      if (!_looksLikeJson(text)) {
        throw Exception('文件内容不是 JSON，请选择 .json 书源文件。');
      }
      await importFromJson(text, originalUrl: originalUrl);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '文件导入失败: $e');
    }
  }

  Future<void> importCatalog(SourceCatalog catalog) async {
    await importFromUrl(catalog.importUrl ?? catalog.url);
  }

  Future<void> deleteSource(int id) async {
    await _repository.deleteBookSource(id);
    await loadSources();
  }

  Future<void> saveSource(BookSource source) async {
    state = state.copyWith(isLoading: true, error: null, message: null);
    try {
      await _repository.saveBookSource(source);
      await loadSources();
      state = state.copyWith(message: '书源 JSON 已保存');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '保存书源失败: $e');
    }
  }

  Future<void> deleteSources(Iterable<int> ids) async {
    state = state.copyWith(isLoading: true, error: null, message: null);
    try {
      for (final id in ids.toList()) {
        await _repository.deleteBookSource(id);
      }
      await loadSources();
      state = state.copyWith(message: '已删除选中书源');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '删除书源失败: $e');
    }
  }

  Future<void> setSourcesEnabled(Iterable<int> ids, bool enabled) async {
    state = state.copyWith(isLoading: true, error: null, message: null);
    try {
      for (final id in ids.toList()) {
        await _repository.setBookSourceEnabled(id, enabled);
      }
      await loadSources();
      state = state.copyWith(message: enabled ? '已启用选中书源' : '已停用选中书源');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '更新书源状态失败: $e');
    }
  }

  Future<void> deleteRssSource(int id) async {
    await _repository.deleteRssSource(id);
    await loadSources();
  }

  Future<void> deleteRssSources(Iterable<int> ids) async {
    state = state.copyWith(isLoading: true, error: null, message: null);
    try {
      for (final id in ids.toList()) {
        await _repository.deleteRssSource(id);
      }
      await loadSources();
      state = state.copyWith(message: '已删除选中 RSS');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '删除 RSS 失败: $e');
    }
  }

  Future<void> deleteCatalog(int id) async {
    await _repository.deleteSourceCatalog(id);
    await loadSources();
  }

  Future<void> deleteCatalogs(Iterable<int> ids) async {
    state = state.copyWith(isLoading: true, error: null, message: null);
    try {
      for (final id in ids.toList()) {
        await _repository.deleteSourceCatalog(id);
      }
      await loadSources();
      state = state.copyWith(message: '已删除选中仓库');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '删除仓库失败: $e');
    }
  }

  Future<void> setCatalogsEnabled(Iterable<int> ids, bool enabled) async {
    state = state.copyWith(isLoading: true, error: null, message: null);
    try {
      for (final id in ids.toList()) {
        await _repository.setSourceCatalogEnabled(id, enabled);
      }
      await loadSources();
      state = state.copyWith(message: enabled ? '已启用选中仓库' : '已停用选中仓库');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '更新仓库状态失败: $e');
    }
  }

  void reportImportError(String message) {
    state = state.copyWith(isLoading: false, error: message);
  }

  String _normalizeImportUrl(String url) {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;
    if (uri.host == 'github.com' && uri.path.contains('/blob/')) {
      final parts = uri.pathSegments;
      final blobIndex = parts.indexOf('blob');
      if (blobIndex >= 2 && blobIndex + 2 < parts.length) {
        final owner = parts[0];
        final repo = parts[1];
        final branch = parts[blobIndex + 1];
        final rest = parts.skip(blobIndex + 2).join('/');
        return 'https://raw.githubusercontent.com/$owner/$repo/$branch/$rest';
      }
    }
    return trimmed;
  }

  bool _looksLikeCloudflareChallenge(String text) {
    final normalized = _normalizeImportJsonText(text);
    if (_looksLikeJson(normalized)) {
      try {
        jsonDecode(normalized);
        return false;
      } on FormatException {
        // Fall through and check whether the failed payload is actually a
        // challenge page. Some source rules legitimately contain CF words.
      }
    }
    return text.contains('/cdn-cgi/challenge-platform') ||
        text.contains('Just a moment') ||
        text.contains('Enable JavaScript and cookies to continue') ||
        text.contains('cf-browser-verification') ||
        text.contains('challenge-form');
  }

  bool _looksLikeJson(String text) {
    final trimmed = _stripBom(text).trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  String _normalizeImportJsonText(String text) {
    var normalized = _stripBom(text).trim();
    if (normalized.length >= 2 &&
        normalized.startsWith('"') &&
        normalized.endsWith('"')) {
      try {
        final decoded = jsonDecode(normalized);
        if (decoded is String) normalized = _stripBom(decoded).trim();
      } catch (_) {
        // Keep the original text if this was not a JSON-encoded string.
      }
    }
    return _extractFirstJsonValue(normalized) ?? normalized;
  }

  String _stripBom(String text) {
    return text.startsWith('\ufeff') ? text.substring(1) : text;
  }

  String? _extractFirstJsonValue(String text) {
    final src = _stripBom(text).trim();
    final start = src.indexOf(RegExp(r'[\[{]'));
    if (start < 0) return null;

    final stack = <int>[];
    var inString = false;
    var escaping = false;

    for (var i = start; i < src.length; i++) {
      final code = src.codeUnitAt(i);
      if (inString) {
        if (escaping) {
          escaping = false;
        } else if (code == 0x5c) {
          escaping = true;
        } else if (code == 0x22) {
          inString = false;
        }
        continue;
      }

      if (code == 0x22) {
        inString = true;
      } else if (code == 0x5b) {
        stack.add(0x5d);
      } else if (code == 0x7b) {
        stack.add(0x7d);
      } else if (code == 0x5d || code == 0x7d) {
        if (stack.isEmpty || stack.last != code) return null;
        stack.removeLast();
        if (stack.isEmpty) return src.substring(start, i + 1);
      }
    }
    return null;
  }

  String _decodeJsonBytes(List<int> bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\ufeff')) {
      text = text.substring(1);
    }
    return text;
  }

  List<dynamic> _normalizeImportItems(dynamic parsed) {
    if (parsed is List) return parsed;
    if (parsed is Map) {
      final data = parsed['data'];
      if (data is List) return data;
      if (data is Map && data['list'] is List) return data['list'] as List;
      if (parsed['list'] is List) return parsed['list'] as List;
      if (parsed['items'] is List) return parsed['items'] as List;
      if (parsed['bookSources'] is List) return parsed['bookSources'] as List;
      if (parsed['sources'] is List) return parsed['sources'] as List;
      if (parsed['bookSource'] is List) return parsed['bookSource'] as List;
      return [parsed];
    }
    return [];
  }

  _ImportKind _detectImportKind(Map<String, dynamic> item) {
    final hasBookRules =
        item.containsKey('bookSourceName') ||
        item.containsKey('bookSourceUrl') ||
        item.containsKey('searchUrl') ||
        item.containsKey('ruleSearch') ||
        item.containsKey('rulesSearch') ||
        item.containsKey('ruleBookInfo') ||
        item.containsKey('rulesBookInfo') ||
        item.containsKey('ruleToc') ||
        item.containsKey('rulesToc') ||
        item.containsKey('ruleContent') ||
        item.containsKey('rulesContent') ||
        item.containsKey('ruleBookContent');
    if (hasBookRules) return _ImportKind.bookSource;

    final name = item['sourceName']?.toString() ?? item['name']?.toString();
    final url = item['sourceUrl']?.toString() ?? item['url']?.toString() ?? '';
    if (name == null && url.isEmpty) return _ImportKind.unknown;

    final hasRssRules =
        item.containsKey('ruleArticles') ||
        item.containsKey('ruleTitle') ||
        item.containsKey('rulePubDate') ||
        item.containsKey('sortUrl');
    final looksLikeFeed =
        url.endsWith('.xml') ||
        url.endsWith('.rss') ||
        url.contains('/rss') ||
        url.contains('feed');
    if (hasRssRules || looksLikeFeed) return _ImportKind.rssSource;

    final group = item['sourceGroup']?.toString() ?? '';
    if (group.contains('书源') ||
        url.contains('shuyuan') ||
        url.endsWith('.json') ||
        item.containsKey('singleUrl') ||
        item.containsKey('importUrl')) {
      return _ImportKind.sourceCatalog;
    }
    return _ImportKind.rssSource;
  }

  BookSource _bookSourceFromJs(String jsCode) {
    final code = jsCode.trim();
    if (code.isEmpty) {
      throw const FormatException('JS 书源内容为空');
    }

    final name =
        _extractJsMeta(code, 'name') ??
        _extractJsStringVar(code, 'bookSourceName') ??
        _extractJsStringVar(code, 'sourceName') ??
        _extractJsStringVar(code, 'name') ??
        'JS书源_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final url =
        _extractJsMeta(code, 'url') ??
        _extractJsMeta(code, 'bookSourceUrl') ??
        _extractJsStringVar(code, 'bookSourceUrl') ??
        _extractJsStringVar(code, 'sourceUrl') ??
        _extractJsStringVar(code, 'url') ??
        'js_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final group =
        _extractJsMeta(code, 'group') ??
        _extractJsStringVar(code, 'bookSourceGroup') ??
        _extractJsStringVar(code, 'sourceGroup') ??
        'JS书源';
    final searchUrl =
        _extractJsMeta(code, 'searchUrl') ?? _extractJsVar(code, 'searchUrl');
    final exploreUrl =
        _extractJsMeta(code, 'exploreUrl') ?? _extractJsVar(code, 'exploreUrl');
    final header =
        _extractJsMeta(code, 'header') ?? _extractJsVar(code, 'header');

    final hasSearch = _hasJsFunctionLike(code, 'search');
    final hasExplore = _hasJsFunctionLike(code, 'explore');
    final hasBookInfo = _hasJsFunctionLike(code, 'bookInfo');
    final hasToc = _hasJsFunctionLike(code, 'toc');
    final hasContent = _hasJsFunctionLike(code, 'content');
    final hasNextTocUrl = _hasJsFunctionLike(code, 'nextTocUrl');
    final hasNextContentUrl = _hasJsFunctionLike(code, 'nextContentUrl');

    final source = BookSource.fromJson({
      'bookSourceName': name,
      'bookSourceUrl': url,
      'bookSourceGroup': group,
      'jsLib': code,
      'engine': 'quickjs',
      'sourceFormat': 'js',
      if (header != null) 'header': header,
      if (searchUrl != null) 'searchUrl': searchUrl,
      if (exploreUrl != null) 'exploreUrl': exploreUrl,
      if (hasSearch)
        'ruleSearch': {
          'bookList': '<js>search(key, page, result)</js>',
          'name': r'$.name',
          'author': r'$.author',
          'bookUrl': r'$.bookUrl',
          'coverUrl': r'$.coverUrl',
          'kind': r'$.kind',
          'lastChapter': r'$.lastChapter',
          'intro': r'$.intro',
        },
      if (hasExplore)
        'ruleExplore': {
          'bookList': '<js>explore(baseUrl, result)</js>',
          'name': r'$.name',
          'author': r'$.author',
          'bookUrl': r'$.bookUrl',
          'coverUrl': r'$.coverUrl',
          'kind': r'$.kind',
          'lastChapter': r'$.lastChapter',
          'intro': r'$.intro',
        },
      if (hasBookInfo)
        'ruleBookInfo': {
          'init': '<js>bookInfo(result)</js>',
          'name': r'$.name',
          'author': r'$.author',
          'coverUrl': r'$.coverUrl',
          'intro': r'$.intro',
          'kind': r'$.kind',
          'lastChapter': r'$.lastChapter',
          'tocUrl': r'$.tocUrl',
          'wordCount': r'$.wordCount',
        },
      if (hasToc)
        'ruleToc': {
          'chapterList': '<js>toc(result)</js>',
          'chapterName': r'$.name',
          'chapterUrl': r'$.url',
          'isVolume': r'$.isVolume',
          if (hasNextTocUrl) 'nextTocUrl': '<js>nextTocUrl(result)</js>',
        },
      if (hasContent)
        'ruleContent': {
          'content': '<js>content(result)</js>',
          if (hasNextContentUrl)
            'nextContentUrl': '<js>nextContentUrl(result)</js>',
        },
    });
    return source;
  }

  bool _looksLikeJsSource(String text) {
    final code = text.trim();
    if (code.isEmpty || _looksLikeJson(code)) return false;
    return RegExp(
          r'(^|\n)\s*//\s*@(?:name|url|group|searchUrl|exploreUrl)\b',
        ).hasMatch(code) ||
        RegExp(
          r'(?:(?:async\s+)?function\s+(?:search|explore|bookInfo|toc|content)\s*\(|(?:var|let|const)\s+(?:search|explore|bookInfo|toc|content)\s*=)',
        ).hasMatch(code);
  }

  bool _hasJsFunctionLike(String code, String name) {
    final escaped = RegExp.escape(name);
    return RegExp(
          '(?:^|[\\n;])\\s*(?:async\\s+)?function\\s+$escaped\\s*\\(',
        ).hasMatch(code) ||
        RegExp(
          '(?:^|[\\n;])\\s*(?:var|let|const)\\s+$escaped\\s*=\\s*(?:async\\s*)?(?:function\\s*)?\\(',
        ).hasMatch(code) ||
        RegExp(
          '(?:^|[\\n;])\\s*(?:var|let|const)\\s+$escaped\\s*=\\s*async\\s+function\\s*\\(',
        ).hasMatch(code);
  }

  String? _extractJsMeta(String code, String key) {
    final lines = code.split('\n');
    final buffer = StringBuffer();
    var collecting = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (!collecting) {
        final match = RegExp(
          '^//\\s*@${RegExp.escape(key)}\\s+(.+)\$',
          caseSensitive: false,
        ).firstMatch(trimmed);
        if (match == null) continue;
        collecting = true;
        buffer.write(match.group(1)?.trim() ?? '');
        continue;
      }
      if (!trimmed.startsWith('//')) break;
      final content = trimmed.substring(2).trim();
      if (RegExp(r'^@\w+').hasMatch(content)) break;
      buffer
        ..writeln()
        ..write(content);
    }
    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }

  String? _extractJsStringVar(String code, String key) {
    final match = RegExp(
      '''(?:var|let|const)\\s+${RegExp.escape(key)}\\s*=\\s*["']([^"']+)["']''',
    ).firstMatch(code);
    return match?.group(1);
  }

  String? _extractJsVar(String code, String key) {
    final simple = _extractJsStringVar(code, key);
    if (simple != null) return simple;
    final match = RegExp(
      '(?:var|let|const)\\s+${RegExp.escape(key)}\\s*=\\s*(.*?)(?=\\nvar\\s|\\nlet\\s|\\nconst\\s|\\nfunction\\s|\\n//\\s*@)',
      dotAll: true,
    ).firstMatch(code);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return '@js:$value';
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static Future<String> _defaultFetchText(
    String url, {
    bool withoutUserAgent = false,
  }) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': withoutUserAgent
            ? ''
            : 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        'Accept': 'application/json,text/plain,*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}

enum _ImportKind { bookSource, sourceCatalog, rssSource, unknown }

class _ImportSummary {
  int bookCount = 0;
  int catalogCount = 0;
  int rssCount = 0;

  void add(_ImportSummary other) {
    bookCount += other.bookCount;
    catalogCount += other.catalogCount;
    rssCount += other.rssCount;
  }
}

final bookSourceViewModelProvider =
    StateNotifierProvider<BookSourceViewModel, BookSourceState>((ref) {
      final repo = ref.watch(bookRepositoryProvider);
      return BookSourceViewModel(repo);
    });
