import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/book_repository.dart';
import '../viewmodels/reader_viewmodel.dart';
import '../models/reader_navigation_target.dart';
import 'reader_toc_page.dart';
import '../../../widgets/book_cover.dart';
import '../../bookshelf/viewmodels/bookshelf_viewmodel.dart';

class ReaderBookDetailsPage extends ConsumerStatefulWidget {
  final String bookId;

  const ReaderBookDetailsPage({super.key, required this.bookId});

  @override
  ConsumerState<ReaderBookDetailsPage> createState() =>
      _ReaderBookDetailsPageState();
}

class _ReaderBookDetailsPageState extends ConsumerState<ReaderBookDetailsPage> {
  bool _isAscending = true;
  bool _isIntroExpanded = false;
  bool? _isInBookshelf;

  @override
  void initState() {
    super.initState();
    _checkBookshelfStatus();
  }

  Future<void> _checkBookshelfStatus() async {
    final repo = ref.read(bookRepositoryProvider);
    final bookId = int.tryParse(widget.bookId);
    if (bookId != null) {
      final existing = await repo.getBookById(bookId);
      if (mounted) {
        setState(() {
          _isInBookshelf = existing != null && existing.isFavorite;
        });
      }
    }
  }

  Future<bool> _handlePopAttempt() async {
    if (_isInBookshelf == true) return true;
    final state = ref.read(readerViewModelProvider(widget.bookId));
    final book = state.book;
    if (book == null) return true;

    final result = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('加入书架'),
        content: const Text('是否将本书加入书架？'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('不加入'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('加入'),
          ),
        ],
      ),
    );

    if (result == true) {
      book.isFavorite = true;
      book.lastReadTime ??= DateTime.now();
      await ref.read(bookRepositoryProvider).saveBook(book);
      ref.read(bookshelfViewModelProvider.notifier).loadBooks();
      return true;
    } else if (result == false) {
      await ref.read(bookRepositoryProvider).deleteBook(book.id);
      ref.read(bookshelfViewModelProvider.notifier).loadBooks();
      if (mounted) {
        context.go('/bookshelf');
      }
      return false;
    }
    return true;
  }

  Future<void> _markAsRead() async {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    final book = state.book;
    if (book == null) return;

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('标记为已读'),
        content: const Text('确定要将本书标记为已读吗？这会将进度设置为 100%。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      book.currentChapter = book.totalChapters - 1;
      book.readingProgress = 1.0;
      await ref.read(bookRepositoryProvider).saveBook(book);
      ref.read(bookshelfViewModelProvider.notifier).loadBooks();
      setState(() {});
    }
  }

  Future<void> _toggleBookmark() async {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    final book = state.book;
    if (book == null) return;

    final repo = ref.read(bookRepositoryProvider);
    if (_isInBookshelf == true) {
      final confirm = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('确认移除'),
          content: const Text('确定要将本书从书架移除吗？'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('移除'),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        await repo.deleteBook(book.id);
        ref.read(bookshelfViewModelProvider.notifier).loadBooks();
        setState(() => _isInBookshelf = false);
      }
    } else {
      book.isFavorite = true;
      book.lastReadTime ??= DateTime.now();
      await repo.saveBook(book);
      ref.read(bookshelfViewModelProvider.notifier).loadBooks();
      setState(() => _isInBookshelf = true);
    }
  }

  Future<void> _startDownload() async {
    final vm = ref.read(readerViewModelProvider(widget.bookId).notifier);
    await vm.startDownloadChapters();
    if (mounted) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('下载开始'),
          content: const Text('已加入后台下载队列。'),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _refreshCatalog() async {
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const CupertinoAlertDialog(
        title: Text('正在刷新目录'),
        content: Padding(
          padding: EdgeInsets.only(top: 14),
          child: CupertinoActivityIndicator(),
        ),
      ),
    );

    try {
      final count = await ref
          .read(readerViewModelProvider(widget.bookId).notifier)
          .refreshCatalog();
      if (!mounted) return;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('刷新完成'),
          content: Text('已重新解析并缓存 $count 个章节。'),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('刷新失败'),
          content: Text(e.toString()),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _openFullToc() async {
    final target = await Navigator.of(context).push<ReaderNavigationTarget>(
      CupertinoPageRoute(
        builder: (context) => ReaderTocPage(bookId: widget.bookId),
        fullscreenDialog: true,
      ),
    );
    if (target != null && mounted) {
      Navigator.pop(context, target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerViewModelProvider(widget.bookId));
    final book = state.book;

    if (state.error != null) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('详情')),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_circle,
                    size: 48,
                    color: CupertinoColors.destructiveRed,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  CupertinoButton.filled(
                    child: const Text('重试'),
                    onPressed: () {
                      ref
                          .read(readerViewModelProvider(widget.bookId).notifier)
                          .loadBook(widget.bookId);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (book == null) {
      return const CupertinoPageScaffold(
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    final lastReadChapter = book.currentChapter;
    final lastReadTitle =
        state.chapters.isNotEmpty && lastReadChapter < state.chapters.length
        ? state.chapters[lastReadChapter].title
        : '';
    final lastReadText = lastReadTitle.isNotEmpty
        ? '上次读到：$lastReadTitle'
        : '未读';

    final displayChapters = _isAscending
        ? state.chapters.take(100).toList()
        : state.chapters.reversed.take(100).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _handlePopAttempt();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(CupertinoIcons.left_chevron, color: Colors.blue, size: 20),
                Text(
                  'Back',
                  style: TextStyle(color: Colors.blue, fontSize: 16),
                ),
              ],
            ),
            onPressed: () async {
              final shouldPop = await _handlePopAttempt();
              if (shouldPop && context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          leadingWidth: 80,
          actions: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _markAsRead,
              child: const Text(
                '已读',
                style: TextStyle(color: Colors.blue, fontSize: 16),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () {
                setState(() {
                  _isAscending = !_isAscending;
                });
              },
              child: Text(
                _isAscending ? '倒序' : '正序',
                style: const TextStyle(color: Colors.blue, fontSize: 16),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _refreshCatalog,
              child: const Icon(
                CupertinoIcons.refresh,
                color: Colors.blue,
                size: 22,
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.only(left: 8, right: 16),
              onPressed: _toggleBookmark,
              child: Icon(
                _isInBookshelf == true
                    ? CupertinoIcons.bookmark_fill
                    : CupertinoIcons.bookmark,
                color: Colors.blue,
                size: 24,
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // 元数据行 (Header Metadata Row)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 105,
                    height: 140,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.0),
                      child: BookCover(book: book, width: 105, height: 140),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          book.author.isEmpty ? '未知作者' : book.author,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '共 ${book.totalChapters} 章',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          lastReadText,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // 双核心按钮组
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: CupertinoButton(
                        color: Colors.blue[600],
                        borderRadius: BorderRadius.circular(24),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          final target = ReaderNavigationTarget(
                            chapterIndex: book.currentChapter,
                            charOffset: 0,
                          );
                          Navigator.pop(context, target);
                        },
                        child: const Text(
                          '继续阅读',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: CupertinoButton(
                        color: Colors.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(24),
                        padding: EdgeInsets.zero,
                        onPressed: _startDownload,
                        child: Text(
                          '全本下载',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 简介
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isIntroExpanded = !_isIntroExpanded;
                  });
                },
                child: Text(
                  '本书简介：${book.filePath.isEmpty ? "暂无简介" : book.filePath}',
                  maxLines: _isIntroExpanded ? null : 3,
                  overflow: _isIntroExpanded
                      ? TextOverflow.clip
                      : TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 32, thickness: 0.8, color: Colors.grey[200]),
              // 目录标题行
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _openFullToc,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '目录（共 ${book.totalChapters} 章，${_isAscending ? "正序" : "倒序"}）',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_right,
                        color: Colors.grey[400],
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 底部目录快照列表
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayChapters.length,
                itemBuilder: (context, i) {
                  final chapter = displayChapters[i];
                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.grey[200]!,
                          width: 0.8,
                        ),
                      ),
                    ),
                    child: CupertinoListTile(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 4,
                      ),
                      title: Text(
                        chapter.title,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      trailing: Icon(
                        CupertinoIcons.chevron_right,
                        color: Colors.grey[400],
                        size: 18,
                      ),
                      onTap: () {
                        final target = ReaderNavigationTarget(
                          chapterIndex: chapter.index,
                          charOffset: 0,
                        );
                        Navigator.pop(context, target);
                      },
                    ),
                  );
                },
              ),
              if (state.chapters.length > 100) ...[
                const SizedBox(height: 16),
                Center(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    color: Colors.blue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(22),
                    onPressed: _openFullToc,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          '查看全部章节',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          CupertinoIcons.chevron_right,
                          color: Colors.blue,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}
