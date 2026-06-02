import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/book.dart';
import '../../../data/repositories/book_repository.dart';
import '../../../widgets/book_cover.dart';

final readingHistoryProvider = FutureProvider.autoDispose<List<Book>>((
  ref,
) async {
  final books = await ref.watch(bookRepositoryProvider).getAllBooks();
  final history =
      books
          .where(
            (book) => book.lastReadTime != null || book.readingProgress > 0,
          )
          .toList()
        ..sort((a, b) {
          final aTime = a.lastReadTime ?? a.dateAdded;
          final bTime = b.lastReadTime ?? b.dateAdded;
          return bTime.compareTo(aTime);
        });
  return history;
});

class ReadingHistoryPage extends ConsumerWidget {
  const ReadingHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(readingHistoryProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('阅读历史')),
      child: SafeArea(
        child: history.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (error, _) => Center(child: Text('加载失败: $error')),
          data: (books) {
            if (books.isEmpty) {
              return const Center(
                child: Text(
                  '还没有阅读记录',
                  style: TextStyle(color: CupertinoColors.secondaryLabel),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: books.length,
              separatorBuilder: (_, _) => Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 86),
                color: CupertinoColors.separator,
              ),
              itemBuilder: (context, index) => _HistoryRow(book: books[index]),
            );
          },
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Book book;

  const _HistoryRow({required this.book});

  @override
  Widget build(BuildContext context) {
    final progress = (book.readingProgress * 100).clamp(0, 100).round();
    final chapter = book.currentChapter + 1;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => context.push('/reader/${book.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: BookCover(book: book, width: 54, height: 74, iconSize: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.label,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '第 $chapter 章 · $progress%',
                    style: const TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.tertiaryLabel,
                    ),
                  ),
                ],
              ),
            ),
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
}
