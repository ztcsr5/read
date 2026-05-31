import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/book.dart';
import '../../../data/repositories/book_repository.dart';
import '../viewmodels/reader_viewmodel.dart';
import '../models/reader_navigation_target.dart';
import 'reader_toc_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../widgets/book_cover.dart';

class ReaderBookDetailsPage extends ConsumerStatefulWidget {
  final String bookId;

  const ReaderBookDetailsPage({super.key, required this.bookId});

  @override
  ConsumerState<ReaderBookDetailsPage> createState() =>
      _ReaderBookDetailsPageState();
}

class _ReaderBookDetailsPageState extends ConsumerState<ReaderBookDetailsPage> {
  bool _allowUpdate = true;
  bool _showCustom = true;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerViewModelProvider(widget.bookId));
    final book = state.book;
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final separator = isDark
        ? const Color(0xFF2C2C2E)
        : CupertinoColors.systemGrey6;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('详情'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {},
          child: const Icon(CupertinoIcons.ellipsis),
        ),
      ),
      child: SafeArea(
        child: book == null
            ? const Center(child: CupertinoActivityIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        _buildHeader(context, book),
                        _sectionText(
                          '本书来自当前书架。简介、作者和来源信息会随着后续书源详情解析逐步补齐；本地文件则优先展示文件本身信息。',
                        ),
                        _divider(separator),
                        _buildSourceSection(book),
                        _divider(separator),
                        _buildTocSection(context, state),
                        _divider(separator),
                        _switchRow('允许更新', _allowUpdate, (value) {
                          setState(() => _allowUpdate = value);
                        }),
                        _switchRow('显示自定义', _showCustom, (value) {
                          setState(() => _showCustom = value);
                        }),
                        _valueRow('书籍类型', book.fileType.toUpperCase()),
                        _valueRow(
                          '所属分组',
                          book.groupId == null ? '未分组' : '${book.groupId}',
                        ),
                      ],
                    ),
                  ),
                  _buildBottomActions(book),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Book book) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BookCover(book: book, width: 92, height: 126),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                Text(
                  book.author,
                  style: const TextStyle(
                    fontSize: 17,
                    color: CupertinoColors.activeBlue,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _formatSize(book.fileSize),
                  style: TextStyle(
                    fontSize: 16,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceSection(Book book) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '来源',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                book.isFromSource ? '网络书源' : '本地文件',
                style: const TextStyle(
                  color: CupertinoColors.secondaryLabel,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            book.isFromSource
                ? '当前来源：${book.sourceUrl ?? '未知书源'}'
                : '当前来源：${book.filePath}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
          const SizedBox(height: 14),
          const Center(
            child: Text(
              '查看全部',
              style: TextStyle(color: CupertinoColors.activeBlue, fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTocSection(BuildContext context, ReaderState state) {
    final currentTitle =
        state.currentChapterIndex >= 0 &&
            state.currentChapterIndex < state.chapters.length
        ? state.chapters[state.currentChapterIndex].title
        : '未开始';
    final latestTitle = state.chapters.isNotEmpty
        ? state.chapters.last.title
        : '暂无目录';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '目录',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            '最新章节： $latestTitle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '阅读章节： $currentTitle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                final target = await Navigator.of(context)
                    .push<ReaderNavigationTarget>(
                      CupertinoPageRoute(
                        builder: (context) =>
                            ReaderTocPage(bookId: widget.bookId),
                        fullscreenDialog: true,
                      ),
                    );
                if (target != null && context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('查看全部'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String title, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 19)),
          const Spacer(),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _valueRow(String title, String value) {
    return CupertinoListTile(
      title: Text(title, style: const TextStyle(fontSize: 18)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(CupertinoIcons.chevron_right, size: 18),
        ],
      ),
    );
  }

  Widget _buildBottomActions(Book book) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CupertinoColors.separator)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: CupertinoButton(
                onPressed: () async {
                  await ref.read(bookRepositoryProvider).deleteBook(book.id);
                  if (mounted) context.go('/bookshelf');
                },
                child: const Text('从书架移除'),
              ),
            ),
            Expanded(
              child: CupertinoButton(
                color: CupertinoColors.activeBlue,
                borderRadius: BorderRadius.zero,
                onPressed: () => Navigator.pop(context),
                child: const Text('开始阅读'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionText(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          height: 1.45,
          color: CupertinoColors.secondaryLabel,
        ),
      ),
    );
  }

  Widget _divider(Color color) => Container(height: 10, color: color);

  String _formatSize(int bytes) {
    if (bytes <= 0) return '未知大小';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
