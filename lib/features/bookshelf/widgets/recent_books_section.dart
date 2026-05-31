import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import 'book_card.dart';
import '../../../data/models/book.dart';
import '../../../app/theme/colors.dart';

class RecentBooksSection extends StatelessWidget {
  const RecentBooksSection({super.key});

  @override
  Widget build(BuildContext context) {
    // 模拟最近阅读数据
    final recentBooks = List.generate(
      5,
      (i) => Book(
        title: '正在阅读的书籍 $i',
        author: '作者 $i',
        filePath: '',
        fileType: 'epub',
        readingProgress: 0.15 + (i * 0.1),
      ),
    );

    if (recentBooks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题和查看全部
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '最近阅读',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                child: Text(
                  '查看全部 >',
                  style: TextStyle(fontSize: 15, color: AppColors.primaryBlue),
                ),
                onPressed: () {
                  // TODO: 跳转最近阅读列表
                },
              ),
            ],
          ),
        ),

        // 横向滚动列表
        SizedBox(
          height: 130,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: recentBooks.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final book = recentBooks[index];
              return BookCard(
                width: 80, // 横向滚动中卡片固定宽度
                book: book,
                onTap: () => context.push('/reader/${book.id}'),
              );
            },
          ),
        ),

        // 底部留白和分隔线
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 1,
            color: CupertinoColors.separator.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
