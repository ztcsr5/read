import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../widgets/ios_navigation_bar.dart';
import '../viewmodels/explore_viewmodel.dart';
import '../../../data/models/book.dart';
import 'package:go_router/go_router.dart';
import '../../../widgets/book_cover.dart';

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
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: state.selectedTab,
                children: const {0: Text('找书'), 1: Text('订阅'), 2: Text('写源')},
                onValueChanged: (value) {
                  if (value != null) viewModel.setTab(value);
                },
              ),
            ),
          ),

          if (state.selectedTab == 0) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 搜索栏
                    CupertinoSearchTextField(
                      placeholder: '搜索书名或作者',
                      onSubmitted: (value) {
                        viewModel.search(value);
                      },
                    ),
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
                    const SizedBox(height: 20),

                    // 书源管理入口
                    GestureDetector(
                      onTap: () {
                        context.push('/sources');
                      },
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
                                    '导入/更新网络书源',
                                    style: TextStyle(
                                      color: CupertinoColors.white.withOpacity(
                                        0.8,
                                      ),
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
                    ),

                    const SizedBox(height: 32),
                    const Text(
                      '搜索结果',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // 搜索结果列表
            if (state.isSearching)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CupertinoActivityIndicator(radius: 14),
                ),
              )
            else if (state.error.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Text(
                    state.error,
                    style: const TextStyle(
                      color: CupertinoColors.destructiveRed,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (state.searchResults.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Center(child: Text('没有搜索结果，请导入书源后尝试搜索')),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final book = state.searchResults[index];
                  return _buildSearchResultItem(context, book, ref);
                }, childCount: state.searchResults.length),
              ),
          ] else if (state.selectedTab == 1) ...[
            if (state.rssSources.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          CupertinoIcons.news,
                          size: 48,
                          color: CupertinoColors.systemGrey,
                        ),
                        const SizedBox(height: 16),
                        const Text('暂无订阅源，请在“书源管理”中导入'),
                        const SizedBox(height: 16),
                        CupertinoButton.filled(
                          child: const Text('前往管理'),
                          onPressed: () => context.push('/sources'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final source = state.rssSources[index];
                  return GestureDetector(
                    onTap: () {
                      context.push('/rss_articles', extra: source);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBackground.resolveFrom(
                          context,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: CupertinoColors.systemGrey.withOpacity(0.1),
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
                              ).primaryColor.withOpacity(0.1),
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
                                    color: CupertinoColors.secondaryLabel
                                        .resolveFrom(context),
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
                }, childCount: state.rssSources.length),
              ),
          ] else ...[
            SliverToBoxAdapter(
              child: Padding(
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
                        Icon(
                          CupertinoIcons.chevron_right,
                          color: CupertinoColors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 100)), // 底部留白
        ],
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
        if (context.mounted) {
          context.push('/reader/$id');
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.systemGrey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: BookCover(book: book, width: 60, height: 80, iconSize: 28),
            ),
            const SizedBox(width: 12),
            // 信息
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
                    book.author,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '暂无简介',
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
            // 添加按钮
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                final id = await ref
                    .read(exploreViewModelProvider.notifier)
                    .addToBookshelf(book);
                if (context.mounted) {
                  showCupertinoDialog(
                    context: context,
                    builder: (context) => CupertinoAlertDialog(
                      title: const Text('已加入书架'),
                      actions: [
                        CupertinoDialogAction(
                          child: const Text('去阅读'),
                          onPressed: () {
                            context.pop();
                            context.push('/reader/$id');
                          },
                        ),
                      ],
                    ),
                  );
                }
              },
              child: const Icon(CupertinoIcons.add_circled),
            ),
          ],
        ),
      ),
    );
  }
}
