import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/book.dart';
import '../../../data/models/book_source.dart';
import '../../../data/parsers/legado_parser.dart';
import '../viewmodels/reader_viewmodel.dart';

class SourceSelectionBottomSheet extends ConsumerStatefulWidget {
  final Book book;

  const SourceSelectionBottomSheet({super.key, required this.book});

  @override
  ConsumerState<SourceSelectionBottomSheet> createState() =>
      _SourceSelectionBottomSheetState();
}

class _SourceSelectionBottomSheetState
    extends ConsumerState<SourceSelectionBottomSheet> {
  bool _isLoading = true;
  List<_SourceCandidate> _candidates = [];

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    final vm = ref.read(readerViewModelProvider(widget.book.id.toString()).notifier);
    final sources = await vm.getEnabledSwitchSources();
    final results = <_SourceCandidate>[];

    await Future.wait(
      sources.map((source) async {
        try {
          final books = await LegadoParser.searchBooks(
            source,
            widget.book.title,
          ).timeout(const Duration(seconds: 8));

          for (final b in books) {
            if (b.title.trim().toLowerCase() == widget.book.title.trim().toLowerCase()) {
              results.add(_SourceCandidate(source: source, book: b));
              break;
            }
          }
        } catch (_) {}
      }),
    );

    if (mounted) {
      setState(() {
        _candidates = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectSource(_SourceCandidate candidate) async {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CupertinoActivityIndicator()),
    );

    try {
      final vm = ref.read(readerViewModelProvider(widget.book.id.toString()).notifier);
      await vm.switchBookSource(candidate.source, candidate.book);
      if (mounted) {
        Navigator.pop(context); // Close loading spinner
        Navigator.pop(context); // Close bottom sheet
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('换源成功'),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading spinner
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('换源失败'),
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

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    
    return Container(
      height: 480,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1C1E)
            : CupertinoColors.systemBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey3,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  const Text(
                    '更换书源',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CupertinoActivityIndicator())
                  : _candidates.isEmpty
                      ? const Center(child: Text('未找到其他可用书源'))
                      : ListView.builder(
                          itemCount: _candidates.length,
                          itemBuilder: (context, index) {
                            final candidate = _candidates[index];
                            final totalCh = candidate.book.totalChapters;
                            final size = candidate.book.fileSize;
                            final infoText = [
                              if (totalCh > 0) '$totalCh章',
                              if (size > 0) '${(size / 10000).toStringAsFixed(1)}万字',
                            ].join(' / ');
                            
                            return CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => _selectSource(candidate),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: isDark
                                          ? const Color(0xFF2C2C2E)
                                          : CupertinoColors.systemGrey6,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            candidate.source.bookSourceName,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? CupertinoColors.white
                                                  : CupertinoColors.black,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            candidate.book.filePath,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: CupertinoColors.secondaryLabel,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (infoText.isNotEmpty)
                                      Text(
                                        infoText,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: CupertinoColors.secondaryLabel,
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      CupertinoIcons.chevron_right,
                                      size: 16,
                                      color: CupertinoColors.systemGrey4,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceCandidate {
  final BookSource source;
  final Book book;

  _SourceCandidate({required this.source, required this.book});
}
