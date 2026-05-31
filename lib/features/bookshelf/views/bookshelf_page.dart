import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../viewmodels/bookshelf_viewmodel.dart';
import '../../../data/models/book.dart';
import '../../../widgets/book_cover.dart';

class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({super.key});

  @override
  ConsumerState<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends ConsumerState<BookshelfPage> {
  bool _handledInitialPendingImport = false;

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final bgColor = CupertinoTheme.of(context).scaffoldBackgroundColor;

    final state = ref.watch(bookshelfViewModelProvider);
    final viewModel = ref.read(bookshelfViewModelProvider.notifier);

    // 监听错误并在界面上弹出
    ref.listen<BookshelfState>(bookshelfViewModelProvider, (previous, next) {
      if (next.error != null &&
          (previous == null || previous.error != next.error)) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('提示'),
            content: Text(next.error!),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    });

    ref.listen<String?>(pendingImportFilePathProvider, (previous, next) {
      if (next == null || next.isEmpty) return;
      ref.read(pendingImportFilePathProvider.notifier).state = null;
      _importExternalFile(next);
    });

    if (!_handledInitialPendingImport) {
      _handledInitialPendingImport = true;
      final pendingPath = ref.read(pendingImportFilePathProvider);
      if (pendingPath != null && pendingPath.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(pendingImportFilePathProvider.notifier).state = null;
          _importExternalFile(pendingPath);
        });
      }
    }

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // 顶部导航栏 (带超大标题和右侧头像)
          CupertinoSliverNavigationBar(
            largeTitle: const Text(
              '主页',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
            border: null, // 去掉底边框
            backgroundColor: bgColor.withOpacity(0.8),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Icon(CupertinoIcons.folder_badge_plus, size: 28),
                  onPressed: () {
                    viewModel.importLocalBook();
                  },
                ),
                GestureDetector(
                  onTap: () {
                    // TODO: 打开个人中心
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 4, left: 16),
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: CupertinoColors.systemGrey5,
                    ),
                    child: const Icon(
                      CupertinoIcons.person_crop_circle,
                      size: 32,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 待播清单 (横向沉浸式大卡片)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 区块标题
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 8.0,
                    ),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {},
                      child: Row(
                        children: [
                          Text(
                            '正在阅读',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? CupertinoColors.white
                                  : CupertinoColors.black,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            CupertinoIcons.chevron_right,
                            size: 20,
                            color: isDark
                                ? CupertinoColors.systemGrey3
                                : CupertinoColors.systemGrey,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 横向大卡片列表
                  if (state.isLoading && state.recentBooks.isEmpty)
                    const SizedBox(
                      height: 260,
                      child: Center(child: CupertinoActivityIndicator()),
                    )
                  else if (state.recentBooks.isEmpty)
                    const SizedBox(
                      height: 220,
                      child: Center(
                        child: Text(
                          '暂无阅读记录',
                          style: TextStyle(color: CupertinoColors.systemGrey),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 260,
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: state.recentBooks.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: _buildHeroCard(
                                context,
                                state.recentBooks[index],
                                index,
                                isDark,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 你的最爱节目 (双列网格)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 32.0, bottom: 12.0),
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                onPressed: () {},
                child: Row(
                  children: [
                    Text(
                      '最新更新',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 20,
                      color: isDark
                          ? CupertinoColors.systemGrey3
                          : CupertinoColors.systemGrey,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 列表视图 (封面在左，信息在右)
          if (state.allBooks.isEmpty && !state.isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Text(
                    '书库空空如也\n点击右上角按钮导入书籍',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CupertinoColors.systemGrey,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                return Padding(
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: 20,
                  ),
                  child: _buildFavoriteCard(
                    context,
                    state.allBooks[index],
                    index,
                    isDark,
                  ),
                );
              }, childCount: state.allBooks.length),
            ),

          // 书架标签
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 32.0, bottom: 12.0),
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                onPressed: () {
                  context.push('/library');
                },
                child: Row(
                  children: [
                    Text(
                      '书架',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 20,
                      color: isDark
                          ? CupertinoColors.systemGrey3
                          : CupertinoColors.systemGrey,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 底部留白以防被迷你播放器遮挡
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Future<void> _importExternalFile(String filePath) async {
    final bookId = await ref
        .read(bookshelfViewModelProvider.notifier)
        .importBookFromPath(filePath);
    if (!mounted || bookId == null) return;
    context.push('/reader/$bookId');
  }

  void _showBookDeleteSheet(BuildContext context, Book book) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(book.title),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              ref.read(bookshelfViewModelProvider.notifier).deleteBook(book.id);
              Navigator.pop(context);
            },
            child: const Text('从书架删除'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// 构建横向超大卡片 (类似 Podcasts 待播清单)
  Widget _buildHeroCard(
    BuildContext context,
    Book book,
    int index,
    bool isDark,
  ) {
    // 模拟不同颜色背景和封面
    final colors = [
      const Color(0xFF1E261D), // 墨绿色
      const Color(0xFF382F2D), // 深棕色
      const Color(0xFF222C3C), // 藏青色
    ];

    return GestureDetector(
      onTap: () => context.push('/reader/${book.id}'),
      onLongPress: () => _showBookDeleteSheet(context, book),
      child:
          Container(
                width: MediaQuery.of(context).size.width * 0.78,
                decoration: BoxDecoration(
                  color: colors[index % colors.length],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 封面与文本信息区 (横向排列)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 左侧封面图
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 20.0,
                              top: 20.0,
                              right: 16.0,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: BookCover(
                                book: book,
                                width: 72,
                                height: 96,
                                iconSize: 32,
                              ),
                            ),
                          ),
                          // 右侧文本区
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: 20.0,
                                right: 20.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '已读 ${(book.readingProgress * 100).toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: CupertinoColors.white.withOpacity(
                                        0.6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    book.title,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: CupertinoColors.white,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    book.author ?? '未知作者',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: CupertinoColors.white.withOpacity(
                                        0.6,
                                      ),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 底部操作区
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 胶囊按钮
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: CupertinoColors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  CupertinoIcons.play_arrow_solid,
                                  size: 16,
                                  color: CupertinoColors.black,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  '继续阅读',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: CupertinoColors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              ref
                                  .read(bookshelfViewModelProvider.notifier)
                                  .deleteBook(book.id);
                            },
                            child: Icon(
                              CupertinoIcons.trash,
                              color: CupertinoColors.white.withOpacity(0.6),
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms)
              .slideX(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
    );
  }

  /// 构建列表卡片 (封面在左)
  Widget _buildFavoriteCard(
    BuildContext context,
    Book book,
    int index,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: () => context.push('/reader/${book.id}'),
      onLongPress: () => _showBookDeleteSheet(context, book),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧封面 (固定大小，圆角)
          Container(
            width: 70,
            height: 100,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                BookCover(book: book, width: 70, height: 100, iconSize: 30),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 右侧信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  book.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? CupertinoColors.white
                        : CupertinoColors.black,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  book.author ?? '未知作者',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? CupertinoColors.systemGrey3
                        : CupertinoColors.systemGrey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '共 ${book.totalChapters} 章',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? CupertinoColors.systemGrey2
                        : CupertinoColors.systemGrey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ).animate().fadeIn(delay: (index * 50).ms, duration: 400.ms),
    );
  }
}
