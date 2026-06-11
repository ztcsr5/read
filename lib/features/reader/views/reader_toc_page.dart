import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/reader_navigation_target.dart';
import '../viewmodels/reader_viewmodel.dart';
import '../../../app/theme/colors.dart';

class ReaderTocPage extends ConsumerStatefulWidget {
  final String bookId;
  const ReaderTocPage({super.key, required this.bookId});

  @override
  ConsumerState<ReaderTocPage> createState() => _ReaderTocPageState();
}

class _ReaderTocPageState extends ConsumerState<ReaderTocPage> {
  int _tabIndex = 0; // 0 for TOC, 1 for Bookmarks
  bool _isReversed = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerViewModelProvider(widget.bookId));
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: CupertinoSlidingSegmentedControl<int>(
          groupValue: _tabIndex,
          children: const {
            0: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('目录'),
            ),
            1: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('书签'),
            ),
          },
          onValueChanged: (val) {
            if (val != null) {
              setState(() {
                _tabIndex = val;
              });
            }
          },
        ),
        trailing: _tabIndex == 0
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _refreshCatalog,
                    child: const Icon(CupertinoIcons.refresh, size: 22),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      _showDownloadOptions(context, state);
                    },
                    child: const Icon(CupertinoIcons.cloud_download, size: 22),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      setState(() {
                        _isReversed = !_isReversed;
                      });
                    },
                    child: Text(_isReversed ? '倒序' : '顺序'),
                  ),
                ],
              )
            : null,
      ),
      child: SafeArea(
        child: _tabIndex == 0
            ? _buildTocList(state, isDark)
            : _buildBookmarksList(state, isDark),
      ),
    );
  }

  Widget _buildTocList(ReaderState state, bool isDark) {
    if (state.chapters.isEmpty) {
      return const Center(child: Text('暂无目录'));
    }

    final query = _query.trim().toLowerCase();
    var entries = state.chapters.asMap().entries.where((entry) {
      if (query.isEmpty) return true;
      final indexText = '${entry.key + 1}';
      return indexText.contains(query) ||
          entry.value.title.toLowerCase().contains(query);
    }).toList();
    if (_isReversed) {
      entries = entries.reversed.toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: CupertinoSearchTextField(
            placeholder: '筛选章节名或序号',
            onChanged: (value) {
              setState(() {
                _query = value;
              });
            },
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    '没有匹配章节',
                    style: TextStyle(
                      color: isDark
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.systemGrey2,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, displayIndex) {
                    final entry = entries[displayIndex];
                    final index = entry.key;
                    final chapter = entry.value;
                    final isCurrent = index == state.currentChapterIndex;

                    return CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pop(ReaderNavigationTarget(chapterIndex: index));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : CupertinoColors.systemGrey5,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 42,
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isCurrent
                                      ? AppColors.primaryPurple
                                      : (isDark
                                            ? CupertinoColors.systemGrey
                                            : CupertinoColors.systemGrey2),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                chapter.title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isCurrent
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: isCurrent
                                      ? AppColors.primaryPurple
                                      : (isDark
                                            ? CupertinoColors.white
                                            : CupertinoColors.black),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (chapter.isDownloaded) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                CupertinoIcons.checkmark_seal_fill,
                                color: CupertinoColors.activeGreen,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBookmarksList(ReaderState state, bool isDark) {
    if (state.bookmarks.isEmpty) {
      return Center(
        child: Text(
          '暂无书签',
          style: TextStyle(
            color: isDark
                ? CupertinoColors.systemGrey
                : CupertinoColors.systemGrey2,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: state.bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = state.bookmarks[index];
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).pop(
              ReaderNavigationTarget(
                chapterIndex: bookmark.chapterIndex,
                charOffset: bookmark.position,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : CupertinoColors.systemGrey5,
                  width: 0.5,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bookmark.chapterTitle ?? '未知章节',
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark
                        ? CupertinoColors.white
                        : CupertinoColors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  bookmark.selectedText ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? CupertinoColors.systemGrey
                        : CupertinoColors.systemGrey2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  void _showDownloadOptions(BuildContext context, ReaderState state) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('下载缓存章节'),
        message: const Text('支持多线程离线下载，可在后台持续下载正文。'),
        actions: [
          CupertinoActionSheetAction(
            child: const Text('缓存后续 50 章'),
            onPressed: () {
              Navigator.pop(context);
              _startDownload(state, limit: 50);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('下载全本章节'),
            onPressed: () {
              Navigator.pop(context);
              _startDownload(state, limit: null);
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _startDownload(ReaderState state, {int? limit}) async {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('开始下载'),
        content: Text(limit != null ? '正在后台下载后续 $limit 章...' : '正在后台下载全本章节...'),
        actions: [
          CupertinoDialogAction(
            child: const Text('好的'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
    
    try {
      await ref
          .read(readerViewModelProvider(widget.bookId).notifier)
          .startDownloadChapters(limit: limit);
    } catch (e) {
      print('Download error: $e');
    }
  }

  Future<void> _refreshCatalog() async {
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CupertinoAlertDialog(
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
        builder: (context) => CupertinoAlertDialog(
          title: const Text('刷新完成'),
          content: Text('已重新解析 $count 个章节。'),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(context),
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
        builder: (context) => CupertinoAlertDialog(
          title: const Text('刷新失败'),
          content: Text(e.toString()),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }
}
