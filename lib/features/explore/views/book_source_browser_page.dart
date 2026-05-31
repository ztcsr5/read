import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/book.dart';
import '../../../data/models/book_source.dart';
import '../../../data/parsers/legado_parser.dart';
import '../../../data/repositories/book_repository.dart';
import '../../../widgets/book_cover.dart';

class BookSourceBrowserPage extends ConsumerStatefulWidget {
  final BookSource source;

  const BookSourceBrowserPage({super.key, required this.source});

  @override
  ConsumerState<BookSourceBrowserPage> createState() =>
      _BookSourceBrowserPageState();
}

class _BookSourceBrowserPageState extends ConsumerState<BookSourceBrowserPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  String _message = '输入书名或作者，在当前书源内搜索。';
  List<Book> _books = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.source.bookSourceName),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isLoading ? null : _search,
          child: _isLoading
              ? const CupertinoActivityIndicator()
              : const Icon(CupertinoIcons.search),
        ),
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: CupertinoSearchTextField(
                  controller: _controller,
                  placeholder: '搜索当前书源',
                  onSubmitted: (_) => _search(),
                ),
              ),
            ),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CupertinoActivityIndicator(radius: 14)),
                ),
              )
            else if (_books.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(36),
                  child: Center(
                    child: Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: CupertinoColors.secondaryLabel,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: _books.length,
                itemBuilder: (context, index) => _bookRow(_books[index]),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty || _isLoading) return;
    setState(() {
      _isLoading = true;
      _books = const [];
      _message = '';
    });
    try {
      final books = await LegadoParser.searchBooks(widget.source, keyword);
      if (!mounted) return;
      setState(() {
        _books = books;
        _message = books.isEmpty ? '当前书源没有搜到结果，可以用“书源测试”看具体失败位置。' : '';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = '搜索失败：$e';
        _isLoading = false;
      });
    }
  }

  Widget _bookRow(Book book) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () async {
        setState(() {
          _isLoading = true;
          _message = '姝ｅ湪鎷夊彇涔︾睄璇︽儏...';
        });
        var target = book;
        try {
          target = await LegadoParser.parseBookInfo(widget.source, book);
        } catch (_) {
          target = book;
        }
        final id = await ref.read(bookRepositoryProvider).saveBook(target);
        if (!mounted) return;
        setState(() => _isLoading = false);
        context.push('/reader/$id');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: BookCover(book: book, width: 58, height: 78, iconSize: 26),
            ),
            const SizedBox(width: 12),
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
                    book.author.isEmpty ? '未知作者' : book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book.filePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.tertiaryLabel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
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
