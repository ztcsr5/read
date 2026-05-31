import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reader_navigation_target.dart';
import '../viewmodels/reader_viewmodel.dart';

class ReaderBookmarksPage extends ConsumerWidget {
  final String bookId;

  const ReaderBookmarksPage({super.key, required this.bookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(readerViewModelProvider(bookId));
    final viewModel = ref.read(readerViewModelProvider(bookId).notifier);
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('书签')),
      child: SafeArea(
        child: state.bookmarks.isEmpty
            ? Center(
                child: Text(
                  '暂无书签',
                  style: TextStyle(
                    color: isDark
                        ? CupertinoColors.systemGrey
                        : CupertinoColors.systemGrey2,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: state.bookmarks.length,
                separatorBuilder: (context, index) => Container(
                  height: 0.5,
                  margin: const EdgeInsets.only(left: 20),
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : CupertinoColors.systemGrey5,
                ),
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bookmark.chapterTitle ?? '未知章节',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? CupertinoColors.white
                                        : CupertinoColors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  bookmark.selectedText?.isNotEmpty == true
                                      ? bookmark.selectedText!
                                      : '位置 ${bookmark.position}',
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
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minSize: 32,
                            onPressed: () {
                              viewModel.removeBookmark(bookmark.id);
                            },
                            child: const Icon(
                              CupertinoIcons.delete,
                              color: CupertinoColors.systemRed,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
