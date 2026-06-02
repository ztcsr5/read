import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator, Divider, Colors;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/book_source.dart';
import '../../../data/models/chapter.dart';
import '../../../data/parsers/legado_parser.dart';
import '../../../data/repositories/book_repository.dart';
import '../../../widgets/ios_navigation_bar.dart';
import '../viewmodels/book_source_viewmodel.dart';

class SourceCheckResult {
  final BookSource source;
  final bool isSuccess;
  final int booksCount;
  final String? errorMessage;
  final int durationInMs;

  SourceCheckResult({
    required this.source,
    required this.isSuccess,
    this.booksCount = 0,
    this.errorMessage,
    required this.durationInMs,
  });
}

class SourceBatchCheckPage extends ConsumerStatefulWidget {
  final List<BookSource> sources;

  const SourceBatchCheckPage({super.key, required this.sources});

  @override
  ConsumerState<SourceBatchCheckPage> createState() =>
      _SourceBatchCheckPageState();
}

class _SourceBatchCheckPageState extends ConsumerState<SourceBatchCheckPage> {
  int _currentIndex = 0;
  int _successCount = 0;
  int _failCount = 0;
  bool _isChecking = true;
  bool _isDisabling = false;
  final List<SourceCheckResult> _results = [];
  final ScrollController _scrollController = ScrollController();
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _startChecking();
  }

  @override
  void dispose() {
    _cancelled = true;
    _scrollController.dispose();
    super.dispose();
  }

  void _startChecking() async {
    const maxConcurrent = 5;
    final workers = <Future<void>>[];

    for (var i = 0; i < maxConcurrent; i++) {
      workers.add(_worker());
    }

    await Future.wait(workers);
    if (mounted) {
      setState(() {
        _isChecking = false;
      });
    }
  }

  Future<void> _worker() async {
    while (!_cancelled) {
      int index;
      if (_currentIndex >= widget.sources.length) return;
      index = _currentIndex++;

      final source = widget.sources[index];
      final watch = Stopwatch()..start();
      var success = false;
      var booksCount = 0;
      String? errorMessage;

      try {
        // 搜索通用字进行验证
        final books = await LegadoParser.searchBooks(source, '天')
            .timeout(const Duration(seconds: 15));
        if (books.isNotEmpty) {
          final book = books.first;
          List<Chapter> chapters = [];
          try {
            // 限制获取前 1~5 个章节以提高检测性能，同时触发目录解析逻辑
            chapters = await LegadoParser.getChapterList(source, book, limit: 5)
                .timeout(const Duration(seconds: 15));
          } catch (_) {
            // 目录获取异常，视为结果为空或失败
          }

          if (chapters.isNotEmpty) {
            final firstChapter = chapters.first;
            final chapterUrl = firstChapter.url ?? firstChapter.content ?? '';
            if (chapterUrl.trim().isNotEmpty) {
              success = true;
              booksCount = books.length;
            } else {
              errorMessage = '解析成功但结果为空';
            }
          } else {
            errorMessage = '解析成功但结果为空';
          }
        } else {
          errorMessage = '解析成功但结果为空';
        }
      } catch (e) {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      }

      watch.stop();

      if (mounted) {
        setState(() {
          _results.add(
            SourceCheckResult(
              source: source,
              isSuccess: success,
              booksCount: booksCount,
              errorMessage: errorMessage,
              durationInMs: watch.elapsedMilliseconds,
            ),
          );
          if (success) {
            _successCount++;
          } else {
            _failCount++;
          }
        });
        
        // 自动滚动到最底部
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 60,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    }
  }

  Future<void> _disableFailedSources() async {
    setState(() {
      _isDisabling = true;
    });

    final failedSources = _results
        .where((r) => !r.isSuccess)
        .map((r) => r.source)
        .toList();

    final repo = ref.read(bookRepositoryProvider);
    for (final source in failedSources) {
      if (source.enabled) {
        source.enabled = false;
        await repo.saveBookSource(source);
      }
    }

    // 刷新书源列表状态
    await ref.read(bookSourceViewModelProvider.notifier).loadSources();

    if (mounted) {
      setState(() {
        _isDisabling = false;
      });
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('禁用完成'),
          content: Text('已成功禁用 ${failedSources.length} 个失效书源。'),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = CupertinoTheme.of(context).scaffoldBackgroundColor;
    final total = widget.sources.length;
    final checked = _successCount + _failCount;
    final progress = total == 0 ? 0.0 : checked / total;

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('一键测源'),
        backgroundColor: CupertinoTheme.of(context).barBackgroundColor.withOpacity(0.9),
        border: null,
        trailing: _isChecking
            ? const CupertinoActivityIndicator()
            : null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildProgressHeader(progress, checked, total),
            const Divider(height: 1, color: CupertinoColors.systemGrey5),
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  color: CupertinoColors.systemGrey5,
                ),
                itemBuilder: (context, index) {
                  final result = _results[index];
                  return _buildResultItem(result);
                },
              ),
            ),
            if (!_isChecking && _failCount > 0)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: _isDisabling ? null : _disableFailedSources,
                    child: _isDisabling
                        ? const CupertinoActivityIndicator()
                        : const Text('一键禁用失效书源'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHeader(double progress, int checked, int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isChecking ? '正在检测中...' : '检测完成',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$checked / $total',
                style: const TextStyle(
                  color: CupertinoColors.systemGrey,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: CupertinoColors.systemGrey5,
              valueColor: const AlwaysStoppedAnimation<Color>(
                CupertinoColors.activeBlue,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard('有效', _successCount, CupertinoColors.activeGreen),
              _buildStatCard('失效', _failCount, CupertinoColors.destructiveRed),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: CupertinoColors.systemGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildResultItem(SourceCheckResult result) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.isSuccess
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.clear_circled_solid,
            color: result.isSuccess
                ? CupertinoColors.activeGreen
                : CupertinoColors.destructiveRed,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        result.source.bookSourceName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      "${result.durationInMs}ms",
                      style: const TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.systemGrey2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  result.isSuccess
                      ? "成功搜索到 ${result.booksCount} 本书"
                      : result.errorMessage != null && result.errorMessage!.length > 50
                          ? "${result.errorMessage!.substring(0, 50)}..."
                          : "${result.errorMessage}",
                  style: TextStyle(
                    fontSize: 13,
                    color: result.isSuccess
                        ? CupertinoColors.systemGrey
                        : CupertinoColors.destructiveRed.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
