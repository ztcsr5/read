import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/book.dart';
import '../../models/book_source.dart';
import '../../routes/app_routes.dart';
import '../../services/cover_config_service.dart';
import '../../utils/design_tokens.dart';

class SearchPage extends StatefulWidget {
  final String? initialKeyword;
  final String? sourceUrl;

  const SearchPage({super.key, this.initialKeyword, this.sourceUrl});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isGridView = false;
  bool _precisionSearch = false;
  bool _showSearchProgress = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<SearchProvider>();
      // 清空上次搜索结果
      provider.clearResults();
      await provider.loadBookSources();
      // 限定单书源搜索（来自发现页/书源编辑页的"搜索书籍"入口）
      if (widget.sourceUrl != null && widget.sourceUrl!.isNotEmpty) {
        provider.selectSingleSource(widget.sourceUrl!);
      }
      await provider.loadSearchHistory();
      if (!mounted) return;
      if (_searchController.text.trim().isNotEmpty) {
        _performSearch();
      }
    });

    if (widget.initialKeyword != null) {
      _searchController.text = widget.initialKeyword!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final searchRadius = appProvider.currentSearchFollow
        ? 10 * appProvider.currentCornerScale
        : DesignTokens.searchRadius;
    return Scaffold(
      body: Consumer<SearchProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              // TitleBar + 搜索框（参考原版）
              Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                ),
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    // 顶部栏：返回按钮 + 搜索框 + 搜索按钮
                    SizedBox(
                      height: DesignTokens.topBarHeight,
                      child: Row(
                        children: [
                          // 返回按钮
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.pop(context),
                          ),
                          // 搜索框（参考原版：高度32dp）
                          Expanded(
                            child: SizedBox(
                              height: 32,
                              child: TextField(
                                controller: _searchController,
                                focusNode: _focusNode,
                                decoration: InputDecoration(
                                  hintText: '搜索书籍、漫画、视频...',
                                  hintStyle: const TextStyle(fontSize: 13),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: DesignTokens.listItemIconSize * 0.67,
                                  ),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.clear,
                                            size: DesignTokens.listItemIconSize * 0.67,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            _searchController.clear();
                                            provider.clearResults();
                                          },
                                        )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      searchRadius,
                                    ),
                                  ),
                                  filled: appProvider.currentSearchFollow,
                                  fillColor: appProvider.currentSearchFollow
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.surface.withValues(
                                          alpha:
                                              appProvider.currentLayoutAlpha /
                                              100,
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: DesignTokens.spacingSm,
                                    vertical: 0,
                                  ),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 13),
                                onSubmitted: (_) => _performSearch(),
                              ),
                            ),
                          ),
                          const SizedBox(width: DesignTokens.spacingXs),
                          // 更多菜单（参考原版）
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            tooltip: '更多选项',
                            offset: const Offset(0, 48),
                            onSelected: (value) =>
                                _handleMenuSelection(value, provider),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'precision_search',
                                height: 40,
                                child: Row(
                                  children: [
                                    const Text('精准搜索'),
                                    const Spacer(),
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: Checkbox(
                                        value: _precisionSearch,
                                        onChanged: null,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'show_search_progress',
                                height: 40,
                                child: Row(
                                  children: [
                                    const Text('显示搜索进度'),
                                    const Spacer(),
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: Checkbox(
                                        value: _showSearchProgress,
                                        onChanged: null,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'grid_view',
                                height: 40,
                                child: Row(
                                  children: [
                                    const Text('网格视图'),
                                    const Spacer(),
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: Checkbox(
                                        value: _isGridView,
                                        onChanged: null,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'source_manage',
                                height: 40,
                                child: Text('书源管理'),
                              ),
                              const PopupMenuItem(
                                value: 'search_scope',
                                height: 40,
                                child: Text('书源精选'),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'log',
                                height: 40,
                                child: Text('日志'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 搜索进度条
              if (provider.isLoading) _buildSearchStatusBar(provider),
              // 内容区域
              if (provider.sourceGroupNames.isNotEmpty)
                _buildGroupSearchBar(provider),
              Expanded(
                child: provider.error != null
                    ? _buildErrorState(provider)
                    : provider.searchResults.isNotEmpty
                    ? _buildResultsView(provider)
                    : provider.isLoading
                    ? _buildLoadingState()
                    : _buildEmptyState(provider),
              ),
            ],
          );
        },
      ),
      // 停止搜索按钮（参考原版 FloatingActionButton）
      floatingActionButton: Consumer<SearchProvider>(
        builder: (context, provider, child) {
          if (!provider.isLoading) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.small(
            onPressed: () => provider.stopSearch(),
            child: const Icon(Icons.stop),
          );
        },
      ),
    );
  }

  Widget _buildResultsView(SearchProvider provider) {
    return Column(
      children: [
        // 过滤器栏
        _buildFilters(provider),
        // 结果列表
        Expanded(
          child: _isGridView
              ? _buildGridView(provider)
              : _buildListView(provider),
        ),
      ],
    );
  }

  Widget _buildFilters(SearchProvider provider) {
    // 过滤器栏已移除，功能整合到更多菜单
    return const SizedBox.shrink();
  }

  Widget _buildLoadingState() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildSearchStatusBar(SearchProvider provider) {
    if (!_showSearchProgress) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    final scheme = Theme.of(context).colorScheme;
    final total = provider.searchTotalSources;
    final progress = total > 0
        ? (provider.searchCompletedSources / total).clamp(0.0, 1.0).toDouble()
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacingSm,
          DesignTokens.spacingXs,
          DesignTokens.spacingSm,
          DesignTokens.spacingXs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.manage_search,
                  size: DesignTokens.listItemIconSize * 0.72,
                  color: scheme.primary,
                ),
                const SizedBox(width: DesignTokens.spacingXs),
                Expanded(
                  child: Text(
                    _searchProgressText(provider),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: DesignTokens.fontSummary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.actionRadius),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSearchBar(SearchProvider provider) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingSm,
          ),
          children: [
            Center(
              child: Icon(
                Icons.tune,
                size: DesignTokens.listItemIconSize * 0.72,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: DesignTokens.spacingXs),
            _buildSourceScopeChip(
              label: '全部 ${provider.bookSources.length}',
              selected: provider.isAllSourcesSelected,
              onTap: () {
                provider.selectAllSources();
                _searchWithCurrentKeyword(provider);
              },
            ),
            ...provider.sourceGroupNames.map((group) {
              final selected = provider.selectedGroupName == group;
              return _buildSourceScopeChip(
                label: '$group ${provider.sourceCountForGroup(group)}',
                selected: selected,
                onTap: () {
                  provider.selectGroupSources(group);
                  _searchWithCurrentKeyword(provider);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceScopeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    final border = selected ? scheme.primary : scheme.outlineVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: DesignTokens.spacingXs),
        child: Tooltip(
          message: label,
          child: ChoiceChip(
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 128),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            selected: selected,
            showCheckmark: false,
            avatar: selected
                ? Icon(
                    Icons.check,
                    size: DesignTokens.fontCaption + 2,
                    color: foreground,
                  )
                : null,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelStyle: TextStyle(
              color: foreground,
              fontSize: DesignTokens.fontCaption,
            ),
            backgroundColor: scheme.surface,
            selectedColor: scheme.primary,
            side: BorderSide(color: border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.actionRadius),
            ),
            onSelected: (_) => onTap(),
          ),
        ),
      ),
    );
  }

  String _searchProgressText(SearchProvider provider) {
    final total = provider.searchTotalSources;
    final done = provider.searchCompletedSources;
    final workers = provider.searchConcurrentWorkers;
    final results = provider.searchResults.length;
    if (total <= 0) {
      return '结果 $results';
    }
    return '书源 $done/$total · 并发 $workers · 结果 $results';
  }

  Widget _buildErrorState(SearchProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: DesignTokens.emptyIconSize,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: DesignTokens.spacingLg),
          Text(
            provider.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: DesignTokens.spacingLg),
          ElevatedButton(
            onPressed: () => _showSourceFilter(provider),
            child: const Text('选择书源'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(SearchProvider provider) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (provider.searchHistory.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingLg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('搜索历史', style: Theme.of(context).textTheme.titleMedium),
                  TextButton(
                    onPressed: () => provider.clearHistory(),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingLg,
              ),
              child: Wrap(
                spacing: DesignTokens.spacingSm,
                runSpacing: DesignTokens.spacingSm,
                children: provider.searchHistory.map((keyword) {
                  return InputChip(
                    label: Text(keyword),
                    onPressed: () {
                      _searchController.text = keyword;
                      _performSearch();
                    },
                    onDeleted: () => provider.removeFromHistory(keyword),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: DesignTokens.spacingXxl),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.search,
                  size: DesignTokens.emptyIconSize,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: DesignTokens.spacingLg),
                Text(
                  '输入关键词搜索',
                  style: TextStyle(
                    fontSize: DesignTokens.fontTitle,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (provider.bookSources.isEmpty) ...[
                  const SizedBox(height: DesignTokens.spacingLg),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, AppRoutes.profile);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('导入书源'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(SearchProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final result = provider.searchResults[index];
        return _buildListResultItem(result);
      },
    );
  }

  Widget _buildListResultItem(Map<String, dynamic> result) {
    // 参考原版布局：封面 80x110，书名16sp，作者/最新/简介12sp
    final coverUrl = result['coverUrl']?.toString() ?? '';
    final intro = result['intro']?.toString().trim() ?? '';
    final lastChapter = result['lastChapter']?.toString().trim() ?? '';
    final author = result['author']?.toString().trim() ?? '未知作者';
    final sourceName = result['sourceName']?.toString().trim() ?? '';
    final scheme = Theme.of(context).colorScheme;
    final tags = _resultTags(result);

    return RepaintBoundary(
      child: InkWell(
        onTap: () => _openDetail(result),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingSm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面（参考原版：80x110）
              ClipRRect(
                borderRadius: BorderRadius.circular(DesignTokens.actionRadius),
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: DesignTokens.emptyIconSize,
                  height: 110.0,
                  child: _buildSearchCoverImage(
                    coverUrl,
                    bookName: result['name']?.toString(),
                    bookAuthor: author,
                  ),
                ),
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              // 右侧信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result['name']?.toString() ?? '未知书名',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSubtitle,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(
                      '作者：$author',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesignTokens.fontCaption,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(
                      lastChapter.isEmpty ? '暂无章节' : lastChapter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesignTokens.fontCaption,
                        color: scheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(
                      intro.isEmpty ? '暂无简介' : intro,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesignTokens.fontCaption,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacingXs),
                    Wrap(
                      spacing: DesignTokens.spacingXs,
                      runSpacing: 2,
                      children: [
                        if (sourceName.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.spacingXs,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(
                                DesignTokens.actionRadius,
                              ),
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(
                                sourceName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: DesignTokens.fontCaption,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ...tags.take(2).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.spacingXs,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: 0.35,
                              ),
                              borderRadius: BorderRadius.circular(
                                DesignTokens.actionRadius,
                              ),
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 96),
                              child: Text(
                                tag,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: DesignTokens.fontCaption,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridView(SearchProvider provider) {
    return GridView.builder(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.58,
        crossAxisSpacing: DesignTokens.spacingMd,
        mainAxisSpacing: DesignTokens.spacingMd,
      ),
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final result = provider.searchResults[index];
        return RepaintBoundary(child: _buildGridResultItem(result));
      },
    );
  }

  Widget _buildGridResultItem(Map<String, dynamic> result) {
    // 参考原版布局优化
    final coverUrl = result['coverUrl']?.toString() ?? '';
    final lastChapter = result['lastChapter']?.toString().trim() ?? '';
    final author = result['author']?.toString().trim() ?? '未知作者';
    final sourceName = result['sourceName']?.toString().trim() ?? '';
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _openDetail(result),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.panelRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 封面
            Expanded(
              child: _buildSearchCoverImage(
                coverUrl,
                bookName: result['name']?.toString(),
                bookAuthor: author,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingXs + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 书名
                  Text(
                    result['name'] ?? '未知书名',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: DesignTokens.fontCaption,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 作者
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DesignTokens.fontCaption,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 最新章节
                  Text(
                    lastChapter.isEmpty ? '暂无章节' : lastChapter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DesignTokens.fontCaption,
                      color: scheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  // 书源
                  if (sourceName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingXs,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(
                            DesignTokens.actionRadius,
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: Text(
                            sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: DesignTokens.fontCaption,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder({String? bookName, String? bookAuthor}) {
    final coverConfig = CoverConfigService.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (bookName != null && bookName.isNotEmpty) {
      return coverConfig.buildDefaultCoverPlaceholder(
        bookName: bookName,
        bookAuthor: bookAuthor,
        isDark: isDark,
      );
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.book, size: 36)),
    );
  }

  /// 构建搜索结果封面 - 接入封面配置
  Widget _buildSearchCoverImage(
    String coverUrl, {
    String? bookName,
    String? bookAuthor,
  }) {
    final coverConfig = CoverConfigService.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (coverConfig.useDefaultCover) {
      return coverConfig.buildDefaultCoverPlaceholder(
        bookName: bookName ?? '',
        bookAuthor: bookAuthor,
        isDark: isDark,
      );
    }

    if (coverUrl.isNotEmpty) {
      final memCacheWidth = coverConfig.loadCoverHighQuality ? null : 240;
      final maxWidthDiskCache = coverConfig.loadCoverHighQuality ? null : 320;
      return CachedNetworkImage(
        imageUrl: coverUrl,
        fit: BoxFit.cover,
        memCacheWidth: memCacheWidth,
        maxWidthDiskCache: maxWidthDiskCache,
        placeholder: (_, __) =>
            _coverPlaceholder(bookName: bookName, bookAuthor: bookAuthor),
        errorWidget: (_, __, ___) =>
            _coverPlaceholder(bookName: bookName, bookAuthor: bookAuthor),
      );
    }

    return _coverPlaceholder(bookName: bookName, bookAuthor: bookAuthor);
  }

  List<String> _resultTags(Map<String, dynamic> result) {
    final rawTags = result['tags'];
    if (rawTags is List) {
      return rawTags
          .map((tag) => tag.toString().trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
    }
    final kind = result['kind']?.toString() ?? '';
    return kind
        .split(RegExp(r'[,，/|·\s]+'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  void _openDetail(Map<String, dynamic> result) {
    final bookData = <String, dynamic>{
      ...result,
      'mediaType': result['mediaType'] ?? _mediaTypeForResult(result).index,
      'originType': result['originType'] ?? BookOriginType.online.index,
      'addedTime': DateTime.now().toIso8601String(),
    };
    Navigator.pushNamed(
      context,
      AppRoutes.detail,
      arguments: {'bookUrl': result['bookUrl'], 'bookData': bookData},
    );
  }

  MediaType _mediaTypeForResult(Map<String, dynamic> result) {
    final sourceUrl = result['sourceUrl']?.toString();
    final source = context
        .read<SearchProvider>()
        .bookSources
        .where((item) => item.bookSourceUrl == sourceUrl)
        .firstOrNull;
    switch (source?.bookSourceType) {
      case BookSourceType.image:
        return MediaType.comic;
      case BookSourceType.video:
        return MediaType.video;
      case BookSourceType.audio:
        return MediaType.audio;
      default:
        return MediaType.novel;
    }
  }

  void _performSearch() {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    // 收起键盘
    FocusScope.of(context).unfocus();
    context.read<SearchProvider>().search(
      keyword,
      precisionSearch: _precisionSearch,
    );
  }

  void _searchWithCurrentKeyword(SearchProvider provider) {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    FocusScope.of(context).unfocus();
    provider.search(keyword, precisionSearch: _precisionSearch);
  }

  void _handleMenuSelection(String value, SearchProvider provider) {
    switch (value) {
      case 'precision_search':
        setState(() {
          _precisionSearch = !_precisionSearch;
        });
        break;
      case 'show_search_progress':
        setState(() {
          _showSearchProgress = !_showSearchProgress;
        });
        break;
      case 'grid_view':
        setState(() {
          _isGridView = !_isGridView;
        });
        break;
      case 'source_manage':
        Navigator.pushNamed(context, AppRoutes.bookSourceManage);
        break;
      case 'search_scope':
        _showSearchScopeDialog(provider);
        break;
      case 'log':
        _showLogDialog();
        break;
    }
  }

  void _showSearchScopeDialog(SearchProvider provider) {
    // 按分组聚合书源
    final Map<String, List<BookSource>> groupedSources = {};
    for (final source in provider.bookSources) {
      final group = source.bookSourceGroup ?? '默认分组';
      groupedSources.putIfAbsent(group, () => []).add(source);
    }

    // 记录展开状态
    final expandedGroups = <String>{};

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final allSelected = provider.selectedSourceUrls.length ==
                provider.bookSources.length;
            final scheme = Theme.of(context).colorScheme;
            return AlertDialog(
              title: Row(
                children: [
                  const Text('书源精选'),
                  const Spacer(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.actionRadius,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacingSm,
                        vertical: DesignTokens.spacingXs,
                      ),
                      child: Text(
                        '${provider.selectedSourceUrls.length}/${provider.bookSources.length}',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSummary,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: ListView(
                  children: [
                    // 全部书源
                    ListTile(
                      leading: Icon(
                        allSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: allSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: const Text('全部书源'),
                      onTap: () {
                        if (allSelected) {
                          provider.deselectAllSources();
                        } else {
                          provider.selectAllSources();
                        }
                        setDialogState(() {});
                      },
                    ),
                    const Divider(),
                    // 按分组展示
                    ...groupedSources.entries.map((entry) {
                      final group = entry.key;
                      final sources = entry.value;
                      final selectedInGroup = sources
                          .where((s) =>
                              provider.selectedSourceUrls.contains(s.bookSourceUrl))
                          .length;
                      final allInGroupSelected = selectedInGroup == sources.length;
                      final isExpanded = expandedGroups.contains(group);

                      return Column(
                        children: [
                          InkWell(
                            onTap: () {
                              setDialogState(() {
                                if (isExpanded) {
                                  expandedGroups.remove(group);
                                } else {
                                  expandedGroups.add(group);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: DesignTokens.spacingSm,
                                vertical: DesignTokens.spacingXs,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isExpanded
                                        ? Icons.expand_less
                                        : Icons.chevron_right,
                                    size: DesignTokens.listItemIconSize,
                                  ),
                                  const SizedBox(width: DesignTokens.spacingXs),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          group,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '已选 $selectedInGroup/${sources.length}',
                                          style: TextStyle(
                                            fontSize: DesignTokens.fontCaption,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(44, 32),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: DesignTokens.spacingSm,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () {
                                      provider.selectGroupSources(group);
                                      setDialogState(() {});
                                    },
                                    child: const Text(
                                      '仅搜',
                                      style: TextStyle(
                                        fontSize: DesignTokens.fontCaption,
                                      ),
                                    ),
                                  ),
                                  Checkbox(
                                    value: allInGroupSelected,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    onChanged: (checked) {
                                      provider.toggleGroupSelection(group);
                                      setDialogState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isExpanded)
                            ...sources.map((source) {
                              final isSelected = provider.selectedSourceUrls
                                  .contains(source.bookSourceUrl);
                              return InkWell(
                                onTap: () {
                                  provider.toggleSourceSelection(
                                      source.bookSourceUrl);
                                  setDialogState(() {});
                                },
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    DesignTokens.spacingXxxl,
                                    DesignTokens.spacingXs,
                                    DesignTokens.spacingSm,
                                    DesignTokens.spacingXs,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _buildSourceTypeIcon(source).icon,
                                        size:
                                            DesignTokens.listItemIconSize * 0.67,
                                        color: isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                      ),
                                      const SizedBox(
                                        width: DesignTokens.spacingSm,
                                      ),
                                      Expanded(
                                        child: Text(
                                          source.bookSourceName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: DesignTokens.fontBody,
                                            color: isSelected
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        isSelected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size:
                                            DesignTokens.listItemIconSize * 0.72,
                                        color: isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : Theme.of(context)
                                                .colorScheme
                                                .outline,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    provider.deselectAllSources();
                    setDialogState(() {});
                  },
                  child: const Text('清空'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (provider.selectedSourceUrls.isNotEmpty) {
                      _searchWithCurrentKeyword(provider);
                    }
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLogDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('搜索日志'),
          content: const SizedBox(
            width: double.maxFinite,
            height: 300,
            child: Center(child: Text('暂无日志')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  void _showSourceFilter(SearchProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingLg),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '选择书源 (${provider.bookSources.length})',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => provider.selectAllSources(),
                            child: const Text('全选'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: provider.bookSources.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('暂无可用书源'),
                              const SizedBox(height: DesignTokens.spacingLg),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  Navigator.pushNamed(
                                    context,
                                    AppRoutes.profile,
                                  );
                                },
                                child: const Text('导入书源'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: provider.bookSources.length,
                          itemBuilder: (context, index) {
                            final source = provider.bookSources[index];
                            final isSelected = provider.selectedSourceUrls
                                .contains(source.bookSourceUrl);
                            return CheckboxListTile(
                              value: isSelected,
                              onChanged: (checked) {
                                provider.toggleSourceSelection(
                                  source.bookSourceUrl,
                                );
                              },
                              title: Text(source.bookSourceName),
                              subtitle: Text(
                                source.bookSourceGroup ?? '默认分组',
                                style: TextStyle(
                                  fontSize: DesignTokens.fontCaption,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              secondary: _buildSourceTypeIcon(source),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSourceTypeIcon(BookSource source) {
    IconData icon;
    switch (source.bookSourceType) {
      case BookSourceType.text:
        icon = Icons.book;
        break;
      case BookSourceType.audio:
        icon = Icons.headphones;
        break;
      case BookSourceType.image:
        icon = Icons.image;
        break;
      case BookSourceType.video:
        icon = Icons.video_library;
        break;
      case BookSourceType.file:
        icon = Icons.folder;
        break;
    }
    return Icon(icon, size: DesignTokens.listItemIconSize);
  }
}

extension on Widget {
  IconData? get icon => null;
}
