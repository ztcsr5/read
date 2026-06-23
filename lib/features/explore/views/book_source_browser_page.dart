import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
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
  bool _needsVerification = false;
  String _verificationUrl = '';
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.source.exploreUrl != null &&
                widget.source.exploreUrl!.trim().isNotEmpty) ...[
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  context.push('/source_explore', extra: widget.source);
                },
                child: const Icon(CupertinoIcons.compass),
              ),
              const SizedBox(width: 8),
            ],
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _openSourceWeb,
              child: const Icon(CupertinoIcons.globe),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _isLoading ? null : _search,
              child: _isLoading
                  ? const CupertinoActivityIndicator()
                  : const Icon(CupertinoIcons.search),
            ),
          ],
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
                    child: Column(
                      children: [
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CupertinoColors.secondaryLabel,
                            height: 1.45,
                          ),
                        ),
                        if (_needsVerification) ...[
                          const SizedBox(height: 14),
                          CupertinoButton.filled(
                            onPressed: _openVerification,
                            child: const Text('跳验证后重试'),
                          ),
                        ],
                        if (!_needsVerification) ...[
                          const SizedBox(height: 14),
                          CupertinoButton(
                            onPressed: _openSourceWeb,
                            child: const Text('打开网页/跳验证'),
                          ),
                        ],
                      ],
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
    if ((widget.source.searchUrl?.trim().isEmpty ?? true) ||
        (widget.source.ruleSearch?.trim().isEmpty ?? true)) {
      setState(() {
        _books = const [];
        _needsVerification = false;
        _message = '当前书源没有配置搜索 URL 或搜索规则，可以进入 JSON 编辑补全，或直接打开网页。';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _books = const [];
      _message = '';
      _needsVerification = false;
      _verificationUrl = '';
    });
    try {
      final books = await LegadoParser.searchBooks(widget.source, keyword);
      if (!mounted) return;
      setState(() {
        _books = books;
        _message = books.isEmpty ? '当前书源没有搜到结果，可以用“书源测试”查看具体失败位置。' : '';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is LegadoVerificationRequiredException) {
          _needsVerification = true;
          _verificationUrl = e.url;
          _message = '当前书源返回验证页，请先完成站点验证。';
        } else if (e is LegadoLoginRequiredException) {
          _needsVerification = true;
          _verificationUrl = e.loginUrl;
          _message = '当前书源需要登录，请先完成登录。';
        } else {
          _message = '搜索失败：$e';
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _openVerification() async {
    final result = await context.push<bool>(
      '/source_verify',
      extra: {
        'source': widget.source,
        'url': _verificationUrl.isEmpty ? null : _verificationUrl,
      },
    );
    if (result == true && mounted) {
      await _search();
    }
  }

  void _openSourceWeb() {
    final url = _sourceHomeUrl();
    context.push(
      '/source_verify',
      extra: {'source': widget.source, 'url': url},
    );
  }

  String _sourceHomeUrl() {
    final raw = widget.source.bookSourceUrl.split(RegExp(r'[#\s]')).first;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.isEmpty) return 'https://example.com';
    return 'https://$raw';
  }

  Widget _bookRow(Book book) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => _openBook(book),
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

  Future<void> _openBook(Book book) async {
    HapticFeedback.lightImpact();
    setState(() {
      _isLoading = true;
      _message = '正在打开...';
    });
    var target = book;
    target
      ..isFromSource = true
      ..sourceUrl = widget.source.id.toString()
      ..isFavorite = false
      ..lastReadTime = null;
    final repo = ref.read(bookRepositoryProvider);
    final id = await repo.saveBook(target);
    target.id = id;
    if (!mounted) return;
    setState(() => _isLoading = false);
    context.push('/reader/$id');
  }
}
