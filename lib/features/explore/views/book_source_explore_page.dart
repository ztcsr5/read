import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart'
    show TabBar, TabBarView, Tab, TabController, Material, Colors;

import '../../../data/models/book.dart';
import '../../../data/models/book_source.dart';
import '../../../data/parsers/legado/legado_request_builder.dart';
import '../../../data/parsers/legado_parser.dart';
import '../../../data/repositories/book_repository.dart';
import '../../../widgets/book_cover.dart';

class BookSourceExplorePage extends ConsumerStatefulWidget {
  final BookSource source;

  const BookSourceExplorePage({super.key, required this.source});

  @override
  ConsumerState<BookSourceExplorePage> createState() =>
      _BookSourceExplorePageState();
}

class _BookSourceExplorePageState extends ConsumerState<BookSourceExplorePage>
    with TickerProviderStateMixin {
  List<ExploreCategoryGroup> _groups = [];
  TabController? _tabController;

  // Track selected subcategory and loaded books per category group index
  final Map<int, ExploreSubCategory?> _selectedSub = {};
  final Map<int, List<Book>> _books = {};
  final Map<int, int> _currentPage = {};
  final Map<int, bool> _isLoading = {};
  final Map<int, bool> _hasMore = {};
  final Map<int, String> _errorMessage = {};
  bool _isPreparingExplore = true;
  String _prepareError = '';

  @override
  void initState() {
    super.initState();
    _prepareExploreUrl();
  }

  Future<void> _prepareExploreUrl() async {
    var urlStr = widget.source.exploreUrl ?? '';
    var error = '';
    try {
      urlStr = await LegadoParser.buildExploreUrl(
        widget.source,
      ).timeout(const Duration(seconds: 18));
    } catch (e) {
      error = '分类生成失败：$e';
    }

    final groups = parseExploreUrl(urlStr);
    if (!mounted) return;

    _tabController?.dispose();
    _selectedSub.clear();
    _books.clear();
    _currentPage.clear();
    _isLoading.clear();
    _hasMore.clear();
    _errorMessage.clear();

    setState(() {
      _groups = groups;
      _prepareError = groups.isEmpty && error.isEmpty
          ? _emptyExploreReason(widget.source.exploreUrl ?? '')
          : error;
      _isPreparingExplore = false;
      _tabController = groups.isEmpty
          ? null
          : TabController(length: groups.length, vsync: this);
      for (var i = 0; i < groups.length; i++) {
        _selectedSub[i] = groups[i].subCategories.first;
        _books[i] = [];
        _currentPage[i] = 1;
        _isLoading[i] = false;
        _hasMore[i] = true;
        _errorMessage[i] = '';
      }
    });

    if (groups.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadBooks(0);
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadBooks(int groupIndex, {bool loadMore = false}) async {
    final sub = _selectedSub[groupIndex];
    if (sub == null || _isLoading[groupIndex] == true) return;
    if (sub.url.trim().isEmpty) return;

    setState(() {
      _isLoading[groupIndex] = true;
      _errorMessage[groupIndex] = '';
      if (!loadMore) {
        _books[groupIndex] = [];
        _currentPage[groupIndex] = 1;
        _hasMore[groupIndex] = true;
      }
    });

    final page = _currentPage[groupIndex] ?? 1;

    final relativeUrl = LegadoRequestBuilder.replaceVariables(
      sub.url,
      keyword: '',
      page: page,
      source: widget.source,
    );

    // Resolve absolute URL
    final absoluteUrl = LegadoParser.resolveUrl(
      widget.source.bookSourceUrl,
      relativeUrl,
    );

    try {
      final newBooks = await LegadoParser.parseExploreBooks(
        widget.source,
        absoluteUrl,
        page: page,
      );

      if (!mounted) return;

      setState(() {
        if (loadMore) {
          _books[groupIndex]?.addAll(newBooks);
        } else {
          _books[groupIndex] = newBooks;
        }
        _isLoading[groupIndex] = false;
        if (newBooks.isEmpty || newBooks.length < 10) {
          _hasMore[groupIndex] = false;
        } else {
          _currentPage[groupIndex] = page + 1;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading[groupIndex] = false;
        _errorMessage[groupIndex] = '加载失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isPreparingExplore) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(widget.source.bookSourceName),
        ),
        child: const Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }

    if (_groups.isEmpty) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(widget.source.bookSourceName),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  context.push('/book_source', extra: widget.source);
                },
                child: const Icon(CupertinoIcons.search, size: 22),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _openSourceWeb,
                child: const Icon(CupertinoIcons.globe, size: 22),
              ),
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '当前书源没有生成可用分类。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: CupertinoColors.secondaryLabel),
                ),
                if (_prepareError.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _prepareError,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                CupertinoButton.filled(
                  onPressed: () =>
                      context.push('/book_source', extra: widget.source),
                  child: const Text('搜索当前书源'),
                ),
                const SizedBox(height: 8),
                CupertinoButton(
                  onPressed: _openSourceWeb,
                  child: const Text('打开网页/跳验证'),
                ),
                const SizedBox(height: 8),
                CupertinoButton(
                  onPressed: () =>
                      context.push('/source_test', extra: widget.source),
                  child: const Text('测试书源'),
                ),
                const SizedBox(height: 8),
                CupertinoButton(
                  onPressed: () =>
                      context.push('/source_json_editor', extra: widget.source),
                  child: const Text('编辑 JSON'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.source.bookSourceName),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                context.push('/book_source', extra: widget.source);
              },
              child: const Icon(CupertinoIcons.search, size: 22),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _openSourceWeb,
              child: const Icon(CupertinoIcons.globe, size: 22),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_groups.length > 1)
              Container(
                color: isDark
                    ? const Color(0xFF1C1C1E)
                    : CupertinoColors.systemGrey6,
                width: double.infinity,
                child: Material(
                  color: Colors.transparent,
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    indicatorColor: CupertinoColors.activeBlue,
                    labelColor: CupertinoColors.activeBlue,
                    unselectedLabelColor: CupertinoColors.secondaryLabel,
                    tabs: _groups.map((g) => Tab(text: g.name)).toList(),
                    onTap: (index) {
                      if (_books[index]?.isEmpty ?? true) {
                        _loadBooks(index);
                      }
                    },
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: List.generate(
                  _groups.length,
                  (index) => _buildCategoryTab(index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSourceWeb() {
    final url = _sourceHomeUrl();
    context.push(
      '/source_verify',
      extra: {'source': widget.source, 'url': url},
    );
  }

  String _sourceHomeUrl() {
    final raw = widget.source.bookSourceUrl.split(RegExp(r'[#\s]')).first;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.isEmpty) return 'https://example.com';
    return 'https://$raw';
  }

  Widget _buildCategoryTab(int groupIndex) {
    final group = _groups[groupIndex];
    final selected = _selectedSub[groupIndex];
    final booksList = _books[groupIndex] ?? [];
    final loading = _isLoading[groupIndex] ?? false;
    final hasMoreBooks = _hasMore[groupIndex] ?? true;
    final error = _errorMessage[groupIndex] ?? '';
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Grid of subcategories
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: const BoxConstraints(maxHeight: 180),
          width: double.infinity,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Wrap(
              spacing: 4,
              runSpacing: 10,
              children: group.subCategories.map((sub) {
                final isSelected = sub == selected;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (isSelected) return;
                    setState(() {
                      _selectedSub[groupIndex] = sub;
                    });
                    _loadBooks(groupIndex);
                  },
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: sub.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? (isDark
                                      ? CupertinoColors.activeBlue
                                      : const Color(0xFF1E88E5))
                                : (isDark
                                      ? CupertinoColors.systemGrey
                                      : CupertinoColors.label.resolveFrom(
                                          context,
                                        )),
                          ),
                        ),
                        TextSpan(
                          text: '  ·  ',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? CupertinoColors.systemGrey3
                                : CupertinoColors.systemGrey4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Books list
        Expanded(
          child: error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CupertinoColors.destructiveRed,
                          ),
                        ),
                        const SizedBox(height: 12),
                        CupertinoButton(
                          child: const Text('重试'),
                          onPressed: () => _loadBooks(groupIndex),
                        ),
                      ],
                    ),
                  ),
                )
              : booksList.isEmpty && !loading
              ? const Center(
                  child: Text(
                    '暂无书籍结果',
                    style: TextStyle(color: CupertinoColors.secondaryLabel),
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      sliver: SliverList.builder(
                        itemCount: booksList.length,
                        itemBuilder: (context, i) => _bookRow(booksList[i]),
                      ),
                    ),
                    if (loading)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CupertinoActivityIndicator()),
                        ),
                      )
                    else if (hasMoreBooks && booksList.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          child: CupertinoButton(
                            color: CupertinoColors.activeBlue.withValues(
                              alpha: 0.1,
                            ),
                            onPressed: () =>
                                _loadBooks(groupIndex, loadMore: true),
                            child: const Text(
                              '加载更多',
                              style: TextStyle(
                                color: CupertinoColors.activeBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (booksList.isNotEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              '没有更多内容了',
                              style: TextStyle(
                                fontSize: 13,
                                color: CupertinoColors.secondaryLabel,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _bookRow(Book book) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    // Clean up description if it is raw URL or empty
    final String description;
    if (book.filePath.isEmpty ||
        book.filePath.startsWith('/') ||
        book.filePath.startsWith('http') ||
        book.filePath.contains('.')) {
      description = '暂无简介，点击查看详情';
    } else {
      description = book.filePath;
    }

    final authorText = book.author.isEmpty ? '未知作者' : book.author;
    final tagsText = book.tags.isNotEmpty ? book.tags.join(',') : '';
    final infoText = tagsText.isNotEmpty
        ? '$authorText · $tagsText'
        : authorText;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => _openBook(book),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BookCover(book: book, width: 64, height: 86, iconSize: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    infoText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? CupertinoColors.systemGrey3
                          : CupertinoColors.secondaryLabel.resolveFrom(context),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              CupertinoIcons.chevron_right,
              color: CupertinoColors.systemGrey,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBook(Book book) async {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CupertinoActivityIndicator(radius: 14)),
    );

    var target = book;
    try {
      target = await LegadoParser.parseBookInfo(widget.source, book);
    } catch (_) {
      target = book;
    }

    target
      ..isFromSource = true
      ..sourceUrl = widget.source.id.toString()
      ..isFavorite = true
      ..lastReadTime = DateTime.now();

    final repo = ref.read(bookRepositoryProvider);
    final id = await repo.saveBook(target);
    target.id = id;

    try {
      final chapters = await LegadoParser.getChapterList(
        widget.source,
        target,
      ).timeout(const Duration(seconds: 12));
      if (chapters.isNotEmpty) {
        for (final chapter in chapters) {
          chapter.bookId = id;
        }
        await repo.deleteChaptersForBook(id);
        await repo.saveChapters(chapters);
        target.totalChapters = chapters.length;
        await repo.saveBook(target);
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.pop(context); // Close loading indicator
    context.push('/reader/$id');
  }
}

// Model and helper classes:
class ExploreCategoryGroup {
  final String name;
  final List<ExploreSubCategory> subCategories;
  ExploreCategoryGroup({required this.name, required this.subCategories});
}

class ExploreSubCategory {
  final String name;
  final String url;
  ExploreSubCategory({required this.name, required this.url});
}

List<ExploreCategoryGroup> parseExploreUrl(String exploreUrl) {
  final groups = <ExploreCategoryGroup>[];
  final trimmedInput = exploreUrl.trim();
  if (trimmedInput.isEmpty) return groups;

  // Try parsing as JSON first
  if (trimmedInput.startsWith('[') && trimmedInput.endsWith(']')) {
    try {
      final decoded = json.decode(trimmedInput);
      if (decoded is List) {
        final subCategories = <ExploreSubCategory>[];
        for (final item in decoded) {
          if (item is Map) {
            final title = (item['title'] ?? item['name'] ?? '')
                .toString()
                .trim();
            final url = (item['url'] ?? '').toString().trim();
            if (title.isNotEmpty && url.isNotEmpty) {
              subCategories.add(ExploreSubCategory(name: title, url: url));
            }
          }
        }
        if (subCategories.isNotEmpty) {
          groups.add(
            ExploreCategoryGroup(name: '全部', subCategories: subCategories),
          );
          return groups;
        }
      }
    } catch (_) {
      // Fallback to text parsing
    }
  }

  final lines = trimmedInput.split(RegExp(r'[\r\n]+'));
  var defaultSubCategories = <ExploreSubCategory>[];
  void flushDefaultGroup() {
    if (defaultSubCategories.isEmpty) return;
    groups.add(
      ExploreCategoryGroup(name: '全部', subCategories: defaultSubCategories),
    );
    defaultSubCategories = <ExploreSubCategory>[];
  }

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    final firstItem = trimmed.split('&&').first;
    final colonCount = '::'.allMatches(firstItem).length;

    if (colonCount >= 2) {
      flushDefaultGroup();
      final firstDoubleColon = trimmed.indexOf('::');
      final categoryName = trimmed.substring(0, firstDoubleColon).trim();
      final subcategoriesPart = trimmed.substring(firstDoubleColon + 2).trim();

      final subCategories = <ExploreSubCategory>[];
      for (final item in subcategoriesPart.split('&&')) {
        final subCategory = _parseExploreTextItem(item);
        if (subCategory != null) subCategories.add(subCategory);
      }
      if (subCategories.isNotEmpty) {
        groups.add(
          ExploreCategoryGroup(
            name: categoryName,
            subCategories: subCategories,
          ),
        );
      }
    } else {
      for (final item in trimmed.split('&&')) {
        final subCategory = _parseExploreTextItem(item);
        if (subCategory != null) defaultSubCategories.add(subCategory);
      }
    }
  }
  flushDefaultGroup();
  return groups;
}

ExploreSubCategory? _parseExploreTextItem(String item) {
  final parts = item.split('::');
  if (parts.length < 2) return null;
  final title = parts[0].trim();
  final url = parts[1].trim();
  if (title.isEmpty || url.isEmpty) return null;
  return ExploreSubCategory(name: title, url: url);
}

String _emptyExploreReason(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '该源没有填写 exploreUrl，可以直接搜索或打开网页。';
  if (value.startsWith('@js:') || value.startsWith('<js>')) {
    return '该源的分类由 JS 动态生成，但当前运行结果为空；通常需要登录、Cookie、远端接口或更完整 JS 桥。';
  }
  return 'exploreUrl 存在，但未解析出 title/url 分类项。';
}
