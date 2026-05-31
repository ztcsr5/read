import 'package:flutter/cupertino.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../data/models/book.dart';
import '../../../widgets/book_cover.dart';

class BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final double width;

  const BookCard({
    super.key,
    required this.book,
    required this.onTap,
    this.width = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        // TODO: 显示菜单（删除、分享、查看信息）
      },
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 书籍封面 (带投影圆角)
            AspectRatio(
              aspectRatio: 0.7,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildCover(context),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 书名
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            // 阅读进度 / 作者
            Text(
              book.readingProgress > 0
                  ? '已读 ${(book.readingProgress * 100).toInt()}%'
                  : book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    ).animate().scale(
      begin: const Offset(0.95, 0.95),
      end: const Offset(1, 1),
      curve: Curves.easeOutBack,
      duration: 300.ms,
    );
  }

  Widget _buildCover(BuildContext context) {
    return BookCover(book: book);
  }
}
