import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'web_browser_page.dart';

import '../../../data/models/book.dart';
import '../../../data/models/rss_source.dart';
import '../../../widgets/book_cover.dart';
import '../../../widgets/ios_navigation_bar.dart';
import '../viewmodels/explore_viewmodel.dart';

class ExplorePage extends ConsumerWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exploreViewModelProvider);
    final viewModel = ref.read(exploreViewModelProvider.notifier);

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          const IosNavigationBar(title: '发现'),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: state.selectedTab,
                children: const {0: Text('找书'), 1: Text('订阅'), 2: Text('写源')},
                onValueChanged: (value) {
                  if (value != null) viewModel.setTab(value);
                },
              ),
            ),
          ),
          if (state.selectedTab == 0)
            ..._buildSearchTab(context, ref, state, viewModel)
          else if (state.selectedTab == 1)
            ..._buildRssTab(context, state.rssSources)
          else
            SliverToBoxAdapter(child: _buildWebSourceCard(context)),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  List<Widget> _buildSearchTab(
    BuildContext context,
    WidgetRef ref,
    ExploreState state,
    ExploreViewModel viewModel,
  ) {
    final visibleResults = viewModel.filterVisibleResults(
      state.searchResults,
      state.resultFilter,
      state.resultFilterScope,
    );
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CupertinoSearchTextField(
                placeholder: '搜索书名或作者',
                onSubmitted: viewModel.search,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: CupertinoColors.activeBlue.withValues(alpha: 0.1),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.globe,
                        size: 20,
                        color: CupertinoColors.activeBlue,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '智能网页小说模式',
                        style: TextStyle(
                          color: CupertinoColors.activeBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (context) => const WebBrowserPage(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              _buildSourceCard(context),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: CupertinoSlidingSegmentedControl<SearchMatchMode>(
                  groupValue: state.searchMatchMode,
                  children: const {
                    SearchMatchMode.fuzzy: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('模糊'),
                    ),
                    SearchMatchMode.precise: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('精准'),
                    ),
                  },
                  onValueChanged: (mode) {
                    if (mode != null) viewModel.setSearchMatchMode(mode);
                  },
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                '搜索结果',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              _buildSearchSummary(context, state, visibleResults.length),
              if (state.searchResults.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child:
                      CupertinoSlidingSegmentedControl<SearchResultFilterScope>(
                        groupValue: state.resultFilterScope,
                        children: const {
                          SearchResultFilterScope.all: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('全部'),
                          ),
                          SearchResultFilterScope.title: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('书名'),
                          ),
                          SearchResultFilterScope.author: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('作者'),
                          ),
                          SearchResultFilterScope.source: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('来源'),
                          ),
                        },
                        onValueChanged: (scope) {
                          if (scope != null) {
                            viewModel.setResultFilterScope(scope);
                          }
                        },
                      ),
                ),
                const SizedBox(height: 10),
                CupertinoSearchTextField(
                  placeholder: _filterPlaceholder(state.resultFilterScope),
                  onChanged: viewModel.setResultFilter,
                ),
                const SizedBox(height: 8),
                Text(
                  '显示 ${visibleResults.length} / ${state.searchResults.length} 条',
                  style: const TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ],
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
      if (state.isSearching)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                const CupertinoActivityIndicator(radius: 14),
                const SizedBox(height: 12),
                if (state.searchTotalSources > 0) ...[
                  Text(
                    '已检测 ${state.searchedSources}/${state.searchTotalSources} 个书源'
                    ' · 命中 ${state.matchedSources} 个源'
                    ' · 当前 ${state.searchResults.length} 条',
                    style: const TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                ],
                CupertinoButton(
                  child: const Text('取消搜索'),
                  onPressed: () {
                    viewModel.cancelSearch();
                  },
                ),
              ],
            ),
          ),
        )
      else if (!state.isSearching && state.error.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                Text(
                  state.error,
                  style: const TextStyle(color: CupertinoColors.destructiveRed),
                  textAlign: TextAlign.center,
                ),
                if (state.verificationSource != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    '可能需要先完成 ${state.verificationSource!.bookSourceName} 的站点验证',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                  const SizedBox(height: 10),
                  CupertinoButton.filled(
                    onPressed: () async {
                      final result = await context.push<bool>(
                        '/source_verify',
                        extra: {
                          'source': state.verificationSource!,
                          'url': state.verificationUrl.isEmpty
                              ? null
                              : state.verificationUrl,
                        },
                      );
                      if (result == true && context.mounted) {
                        viewModel.search(state.lastQuery);
                      }
                    },
                    child: const Text('跳验证后重试'),
                  ),
                ],
              ],
            ),
          ),
        )
      else if (!state.isSearching && state.searchResults.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                state.lastQuery.isEmpty
                    ? '输入书名后，会从启用的小说书源里搜索'
                    : '没有搜索结果，可切换精准/模糊、筛选可用书源或跳验证后重试',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        )
      else if (state.searchResults.isNotEmpty && visibleResults.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: Text('没有符合当前筛选的结果')),
          ),
        )
      else if (state.searchResults.isNotEmpty)
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final book = visibleResults[index];
            return _buildSearchResultItem(context, book, ref);
          }, childCount: visibleResults.length),
        ),
    ];
  }

  Widget _buildSourceCard(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/sources'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CupertinoTheme.of(context).primaryColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.cube_box,
              color: CupertinoColors.white,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '书源管理',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '导入、测试、验证和管理网络书源',
                    style: TextStyle(
                      color: CupertinoColors.white.withValues(alpha: 0.82),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              color: CupertinoColors.white,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRssTab(BuildContext context, List<RssSource> rssSources) {
    if (rssSources.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  const Icon(
                    CupertinoIcons.news,
                    size: 48,
                    color: CupertinoColors.systemGrey,
                  ),
                  const SizedBox(height: 16),
                  const Text('暂无订阅源，请在书源管理中导入'),
                  const SizedBox(height: 16),
                  CupertinoButton.filled(
                    child: const Text('前往管理'),
                    onPressed: () => context.push('/sources'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final source = rssSources[index];
          return _buildRssItem(context, source);
        }, childCount: rssSources.length),
      ),
    ];
  }

  Widget _buildSearchSummary(
    BuildContext context,
    ExploreState state,
    int visibleCount,
  ) {
    final pieces = <String>[];
    if (state.searchTotalSources > 0) {
      pieces.add('已检测 ${state.searchedSources}/${state.searchTotalSources} 个源');
    }
    if (state.matchedSources > 0) {
      pieces.add('命中 ${state.matchedSources} 个源');
    }
    if (state.searchResults.isNotEmpty) {
      pieces.add('结果 ${state.searchResults.length} 条');
    }
    if (state.resultFilter.isNotEmpty) {
      pieces.add('筛选后 $visibleCount 条');
    }
    if (pieces.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        pieces.join(' · '),
        style: TextStyle(
          fontSize: 12,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }

  String _filterPlaceholder(SearchResultFilterScope scope) {
    return switch (scope) {
      SearchResultFilterScope.title => '筛选书名',
      SearchResultFilterScope.author => '筛选作者',
      SearchResultFilterScope.source => '筛选来源/分组/地址',
      SearchResultFilterScope.all => '筛选结果：书名、作者、来源、地址',
    };
  }

  Widget _buildRssItem(BuildContext context, RssSource source) {
    return GestureDetector(
      onTap: () => context.push('/rss_articles', extra: source),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.systemGrey.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: CupertinoTheme.of(
                  context,
                ).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                CupertinoIcons.text_quote,
                color: CupertinoTheme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.sourceName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    source.sourceGroup ?? '未分组',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              color: CupertinoColors.systemGrey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebSourceCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: GestureDetector(
        onTap: () => context.push('/web_source'),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: CupertinoTheme.of(context).primaryColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            children: [
              Icon(
                CupertinoIcons.globe,
                color: CupertinoColors.white,
                size: 32,
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Web 写源',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '用表单快速创建一个可搜索的网页书源',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right, color: CupertinoColors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultItem(
    BuildContext context,
    Book book,
    WidgetRef ref,
  ) {
    return GestureDetector(
      onTap: () async {
        final id = await ref
            .read(exploreViewModelProvider.notifier)
            .addToBookshelf(book);
        if (context.mounted) context.push('/reader/$id');
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.systemGrey.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: BookCover(book: book, width: 60, height: 80, iconSize: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author.isEmpty ? '未知作者' : book.author,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                  if (_sourceLabel(book).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _sourceLabel(book),
                      style: const TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.activeBlue,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    book.filePath.isEmpty ? '暂无简介' : book.filePath,
                    style: TextStyle(
                      fontSize: 14,
                      color:
                          CupertinoTheme.of(context).brightness ==
                              Brightness.dark
                          ? CupertinoColors.systemGrey3
                          : CupertinoColors.systemGrey,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                final id = await ref
                    .read(exploreViewModelProvider.notifier)
                    .addToBookshelf(book);
                if (!context.mounted) return;
                showCupertinoDialog(
                  context: context,
                  builder: (dialogContext) => CupertinoAlertDialog(
                    title: const Text('已加入书架'),
                    actions: [
                      CupertinoDialogAction(
                        child: const Text('去阅读'),
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          context.push('/reader/$id');
                        },
                      ),
                    ],
                  ),
                );
              },
              child: const Icon(CupertinoIcons.add_circled),
            ),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(Book book) {
    String? source;
    String? group;
    for (final tag in book.tags) {
      if (source == null && tag.startsWith('source:')) {
        final value = tag.substring('source:'.length).trim();
        if (value.isNotEmpty) source = value;
      } else if (group == null && tag.startsWith('group:')) {
        final value = tag.substring('group:'.length).trim();
        if (value.isNotEmpty) group = value;
      }
    }
    if (source == null && group == null) return '';
    if (source == null) return group!;
    if (group == null) return source;
    return '$source · $group';
  }
}
