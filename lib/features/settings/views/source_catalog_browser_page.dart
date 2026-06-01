import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../data/models/source_catalog.dart';
import '../viewmodels/book_source_viewmodel.dart';

class SourceCatalogBrowserPage extends ConsumerStatefulWidget {
  final SourceCatalog catalog;

  const SourceCatalogBrowserPage({super.key, required this.catalog});

  @override
  ConsumerState<SourceCatalogBrowserPage> createState() =>
      _SourceCatalogBrowserPageState();
}

class _SourceCatalogBrowserPageState
    extends ConsumerState<SourceCatalogBrowserPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedIndexes = {};
  bool _isLoading = false;
  bool _isImporting = false;
  String? _error;
  List<_CatalogPreviewItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookSourceViewModelProvider);
    final filteredItems = _filteredItems;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.catalog.name),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isLoading ? null : _load,
          child: _isLoading
              ? const CupertinoActivityIndicator()
              : const Icon(CupertinoIcons.refresh),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: '搜索仓库内书源',
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '共 ${_items.length} 个，已选 ${_selectedIndexes.length} 个',
                        style: const TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onPressed: () => setState(_selectVisible),
                      child: const Text('全选'),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onPressed: () => setState(_invertVisible),
                      child: const Text('反选'),
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildBody(filteredItems, state)),
            if (_items.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: CupertinoColors.separator),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        onPressed: _isImporting ? null : _importSelected,
                        child: Text(_isImporting ? '导入中...' : '导入选中'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton.filled(
                        onPressed: _isImporting ? null : _importAll,
                        child: const Text('全部导入'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    List<_CatalogPreviewItem> filteredItems,
    BookSourceState state,
  ) {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CupertinoColors.destructiveRed,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              CupertinoButton.filled(
                onPressed: () => context.push(
                  '/webview_import',
                  extra: widget.catalog.importUrl ?? widget.catalog.url,
                ),
                child: const Text('用内置浏览器打开'),
              ),
            ],
          ),
        ),
      );
    }
    if (filteredItems.isEmpty) {
      return const Center(
        child: Text(
          '没有拉取到可导入项目',
          style: TextStyle(color: CupertinoColors.secondaryLabel),
        ),
      );
    }
    return ListView.builder(
      itemCount: filteredItems.length,
      itemBuilder: (context, index) {
        final item = filteredItems[index];
        final selected = _selectedIndexes.contains(item.index);
        final imported = _isImported(item, state);
        return CupertinoListTile(
          onTap: () => setState(() => _toggle(item.index)),
          leading: Icon(
            selected
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.circle,
            color: selected
                ? CupertinoColors.activeBlue
                : CupertinoColors.systemGrey3,
          ),
          title: Text(item.name),
          subtitle: Text(
            '${item.kindLabel} · ${item.url}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: imported
              ? const Text(
                  '已导入',
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel,
                  ),
                )
              : null,
        );
      },
    );
  }

  bool _isImported(_CatalogPreviewItem item, BookSourceState state) {
    return switch (item.kind) {
      _CatalogPreviewKind.bookSource => state.sources.any(
        (source) =>
            source.bookSourceUrl == item.url ||
            source.bookSourceName == item.name,
      ),
      _CatalogPreviewKind.catalog => state.catalogs.any(
        (catalog) =>
            catalog.url == item.url ||
            catalog.importUrl == item.url ||
            catalog.name == item.name,
      ),
      _CatalogPreviewKind.rss => state.rssSources.any(
        (source) =>
            source.sourceUrl == item.url || source.sourceName == item.name,
      ),
    };
  }

  List<_CatalogPreviewItem> get _filteredItems {
    final keyword = _searchController.text.trim().toLowerCase();
    if (keyword.isEmpty) return _items;
    return _items.where((item) {
      return item.name.toLowerCase().contains(keyword) ||
          item.url.toLowerCase().contains(keyword) ||
          item.kindLabel.toLowerCase().contains(keyword);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _items = const [];
      _selectedIndexes.clear();
    });
    try {
      final response = await http.get(
        Uri.parse(widget.catalog.importUrl ?? widget.catalog.url),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
          'Accept': 'application/json,text/plain,*/*',
        },
      );
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (!_looksLikeJson(text) && _looksLikeCloudflareChallenge(text)) {
        throw Exception(
          '目标站启用了 Cloudflare/JS 验证，App 不能直接拉取。请在浏览器下载 JSON 后用本地文件导入。',
        );
      }
      if (!_looksLikeJson(text)) {
        final webItems = await _loadWebRepository(
          text,
          Uri.parse(widget.catalog.importUrl ?? widget.catalog.url),
        );
        if (webItems.isEmpty) {
          throw Exception('返回内容不是 JSON，且没有从网页仓库中发现可导入项目');
        }
        setState(() {
          _items = webItems;
          _isLoading = false;
        });
        return;
      }
      final parsed = jsonDecode(text);
      final maps = _normalizeItems(parsed);
      final items = <_CatalogPreviewItem>[];
      for (var i = 0; i < maps.length; i++) {
        final map = maps[i];
        final item = _CatalogPreviewItem.fromMap(i, map);
        if (item != null) items.add(item);
      }
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = '拉取仓库失败：$e';
        _isLoading = false;
      });
    }
  }

  Future<List<_CatalogPreviewItem>> _loadWebRepository(
    String html,
    Uri pageUri,
  ) async {
    final apiBase =
        await _discoverApiBase(html, pageUri) ?? _guessApiBase(pageUri);
    if (apiBase == null) return const [];

    final items = <_CatalogPreviewItem>[];
    final collectionJson = await _tryFetchJson(
      '$apiBase/shuyuan/book-source-collections?page=1&page_size=100',
    );
    for (final map in _normalizeItems(collectionJson)) {
      final id = map['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final name = map['name']?.toString() ?? '未命名仓库';
      final importUrl = '$apiBase/import/book-source-collection/$id';
      final raw = <String, dynamic>{
        'sourceName': name,
        'sourceUrl': map['url']?.toString() ?? importUrl,
        'importUrl': importUrl,
        'sourceGroup': '书源仓库',
        'sourceComment': map['description']?.toString(),
      };
      items.add(
        _CatalogPreviewItem(
          index: items.length,
          name: name,
          url: raw['sourceUrl']!.toString(),
          importUrl: importUrl,
          kind: _CatalogPreviewKind.catalog,
          raw: raw,
        ),
      );
    }

    final sourceJson = await _tryFetchJson(
      '$apiBase/shuyuan/book-sources?page=1&page_size=100',
    );
    for (final map in _normalizeItems(sourceJson)) {
      final id = map['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final name = map['name']?.toString() ?? '未命名书源';
      final sourceUrl = map['url']?.toString() ?? '';
      final importUrl = '$apiBase/import/book-source/$id';
      items.add(
        _CatalogPreviewItem(
          index: items.length,
          name: name,
          url: sourceUrl.isNotEmpty ? sourceUrl : importUrl,
          importUrl: importUrl,
          kind: _CatalogPreviewKind.bookSource,
          raw: <String, dynamic>{
            'bookSourceName': name,
            'bookSourceUrl': sourceUrl,
            'importUrl': importUrl,
            'bookSourceGroup': '网页仓库',
          },
        ),
      );
    }

    return items;
  }

  Future<String?> _discoverApiBase(String html, Uri pageUri) async {
    final inline = RegExp(
      r'VITE_API_BASE_URL["'
      ']?\s*[:=]\s*["'
      ']([^"'
      ']+)["'
      ']',
    ).firstMatch(html);
    if (inline != null) return inline.group(1);

    final scripts =
        RegExp(
              r'<script[^>]+src=["'
              ']([^"'
              ']+\.js)["'
              ']',
            )
            .allMatches(html)
            .map((match) => match.group(1))
            .whereType<String>()
            .take(8);
    for (final src in scripts) {
      final scriptUri = pageUri.resolve(src);
      try {
        final response = await http.get(scriptUri);
        if (response.statusCode != 200) continue;
        final script = utf8.decode(response.bodyBytes, allowMalformed: true);
        final match = RegExp(
          r'VITE_API_BASE_URL["'
          ']?\s*[:=]\s*["'
          ']([^"'
          ']+)["'
          ']',
        ).firstMatch(script);
        if (match != null) return match.group(1);

        final configFiles = RegExp(
          r'["'
          ']\.\/([^"'
          ']*config[^"'
          ']*\.js)["'
          ']',
        ).allMatches(script).map((match) => match.group(1)).whereType<String>();
        for (final configSrc in configFiles) {
          final configUri = scriptUri.resolve(configSrc);
          final configResponse = await http.get(configUri);
          if (configResponse.statusCode != 200) continue;
          final configText = utf8.decode(
            configResponse.bodyBytes,
            allowMalformed: true,
          );
          final configMatch = RegExp(
            r'VITE_API_BASE_URL["'
            ']?\s*[:=]\s*["'
            ']([^"'
            ']+)["'
            ']',
          ).firstMatch(configText);
          if (configMatch != null) return configMatch.group(1);
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String? _guessApiBase(Uri pageUri) {
    if (!pageUri.host.contains('shuyuan')) return null;
    return '${pageUri.scheme}://shuyuan-api.${pageUri.host.replaceFirst('shuyuan.', '')}';
  }

  Future<dynamic> _tryFetchJson(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: const {'Accept': 'application/json,text/plain,*/*'},
      );
      if (response.statusCode != 200) return null;
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (!_looksLikeJson(text)) return null;
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeJson(String text) {
    final trimmed = text.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  bool _looksLikeCloudflareChallenge(String text) {
    if (_looksLikeJson(text)) {
      try {
        jsonDecode(text);
        return false;
      } on FormatException {
        // Continue with the lightweight challenge-page checks below.
      }
    }
    return text.contains('/cdn-cgi/challenge-platform') ||
        text.contains('Just a moment') ||
        text.contains('Enable JavaScript and cookies to continue');
  }

  List<Map<String, dynamic>> _normalizeItems(dynamic parsed) {
    final rawItems = <dynamic>[];
    if (parsed is List) {
      rawItems.addAll(parsed);
    } else if (parsed is Map) {
      final data = parsed['data'];
      if (data is List) {
        rawItems.addAll(data);
      } else if (data is Map && data['list'] is List) {
        rawItems.addAll(data['list'] as List);
      } else if (parsed['list'] is List) {
        rawItems.addAll(parsed['list'] as List);
      } else if (parsed['items'] is List) {
        rawItems.addAll(parsed['items'] as List);
      } else if (parsed['sources'] is List) {
        rawItems.addAll(parsed['sources'] as List);
      } else if (parsed['bookSources'] is List) {
        rawItems.addAll(parsed['bookSources'] as List);
      } else {
        rawItems.add(parsed);
      }
    }

    return rawItems.whereType<Map>().map((item) {
      return item.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }

  void _toggle(int index) {
    if (!_selectedIndexes.add(index)) _selectedIndexes.remove(index);
  }

  void _selectVisible() {
    _selectedIndexes
      ..clear()
      ..addAll(_filteredItems.map((item) => item.index));
  }

  void _invertVisible() {
    final visible = _filteredItems.map((item) => item.index).toSet();
    final next = visible.difference(_selectedIndexes);
    _selectedIndexes
      ..removeAll(visible)
      ..addAll(next);
  }

  Future<void> _importSelected() async {
    final selected = _items
        .where((item) => _selectedIndexes.contains(item.index))
        .toList();
    await _importItems(selected);
  }

  Future<void> _importAll() async {
    await _importItems(_items);
  }

  Future<void> _importItems(List<_CatalogPreviewItem> items) async {
    if (items.isEmpty || _isImporting) return;
    setState(() => _isImporting = true);
    final notifier = ref.read(bookSourceViewModelProvider.notifier);
    final rawItems = items.where((item) => item.importUrl == null).toList();
    if (rawItems.isNotEmpty) {
      await notifier.importFromJson(
        jsonEncode(rawItems.map((item) => item.raw).toList()),
        originalUrl: widget.catalog.url,
      );
    }
    for (final item in items.where((item) => item.importUrl != null)) {
      await notifier.importFromUrl(item.importUrl!);
    }
    if (!mounted) return;
    setState(() => _isImporting = false);
  }
}

class _CatalogPreviewItem {
  final int index;
  final String name;
  final String url;
  final String? importUrl;
  final _CatalogPreviewKind kind;
  final Map<String, dynamic> raw;

  const _CatalogPreviewItem({
    required this.index,
    required this.name,
    required this.url,
    this.importUrl,
    required this.kind,
    required this.raw,
  });

  String get kindLabel {
    return switch (kind) {
      _CatalogPreviewKind.bookSource => '书源',
      _CatalogPreviewKind.catalog => '仓库',
      _CatalogPreviewKind.rss => 'RSS',
    };
  }

  static _CatalogPreviewItem? fromMap(int index, Map<String, dynamic> map) {
    final kind = _detectKind(map);
    if (kind == null) return null;
    final name =
        map['bookSourceName']?.toString() ??
        map['sourceName']?.toString() ??
        map['name']?.toString() ??
        '未命名';
    final url =
        map['bookSourceUrl']?.toString() ??
        map['sourceUrl']?.toString() ??
        map['url']?.toString() ??
        map['importUrl']?.toString() ??
        '';
    return _CatalogPreviewItem(
      index: index,
      name: name,
      url: url,
      importUrl: map['importUrl']?.toString(),
      kind: kind,
      raw: map,
    );
  }

  static _CatalogPreviewKind? _detectKind(Map<String, dynamic> map) {
    if (map.containsKey('bookSourceName') ||
        map.containsKey('searchUrl') ||
        map.containsKey('ruleSearch') ||
        map.containsKey('rulesSearch') ||
        map.containsKey('ruleBookInfo') ||
        map.containsKey('rulesBookInfo') ||
        map.containsKey('ruleToc') ||
        map.containsKey('rulesToc') ||
        map.containsKey('ruleContent') ||
        map.containsKey('rulesContent') ||
        map.containsKey('ruleBookContent')) {
      return _CatalogPreviewKind.bookSource;
    }
    final url = map['sourceUrl']?.toString() ?? map['url']?.toString() ?? '';
    final hasRssRules =
        map.containsKey('ruleArticles') ||
        map.containsKey('ruleTitle') ||
        map.containsKey('sortUrl');
    if (hasRssRules || url.contains('/rss') || url.contains('feed')) {
      return _CatalogPreviewKind.rss;
    }
    if (map.containsKey('sourceName') ||
        map.containsKey('importUrl') ||
        url.endsWith('.json') ||
        url.contains('shuyuan')) {
      return _CatalogPreviewKind.catalog;
    }
    return null;
  }
}

enum _CatalogPreviewKind { bookSource, catalog, rss }
