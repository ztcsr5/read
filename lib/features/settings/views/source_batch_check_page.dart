import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator, Divider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../data/models/book_source.dart';
import '../../../data/parsers/legado_parser.dart';
import '../../../data/repositories/book_repository.dart';
import '../services/source_check_classifier.dart';
import '../viewmodels/book_source_viewmodel.dart';

class SourceCheckResult {
  final BookSource source;
  final bool isSuccess;
  final bool isBlocked;
  final bool isSkipped;
  final int booksCount;
  final String? errorMessage;
  final String? failStep;
  final String? failSample;
  final List<String> failLogs;
  final String? stageTrail;
  final int durationInMs;

  SourceCheckResult({
    required this.source,
    required this.isSuccess,
    this.isBlocked = false,
    this.isSkipped = false,
    this.booksCount = 0,
    this.errorMessage,
    this.failStep,
    this.failSample,
    this.failLogs = const [],
    this.stageTrail,
    required this.durationInMs,
  });

  bool get canDisable => !isSuccess && !isBlocked && !isSkipped;
}

enum SourceCheckFilter { all, success, failed, blocked, skipped }

class SourceBatchCheckPage extends ConsumerStatefulWidget {
  final List<BookSource> sources;

  const SourceBatchCheckPage({super.key, required this.sources});

  @override
  ConsumerState<SourceBatchCheckPage> createState() =>
      _SourceBatchCheckPageState();
}

class _SourceBatchCheckPageState extends ConsumerState<SourceBatchCheckPage> {
  static const _batchKeyword = '斗破苍穹';

  int _currentIndex = 0;
  int _successCount = 0;
  int _failCount = 0;
  int _blockedCount = 0;
  int _skippedCount = 0;
  bool _isChecking = true;
  bool _isDisabling = false;
  final List<SourceCheckResult> _results = [];
  final ScrollController _scrollController = ScrollController();
  bool _cancelled = false;
  SourceCheckFilter _filter = SourceCheckFilter.all;

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
    const maxConcurrent = 2;
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
      var skipped = false;
      var booksCount = 0;
      String? errorMessage;
      String? failStepTitle;
      String? failSample;
      List<String> failLogs = const [];
      String? stageTrail;
      var blocked = false;

      try {
        // 统一测源：复用单源测试的 testSource，确保「一键测源」与单源测试判定标准一致，
        // 并继承其虚假成功(假绿)拦截逻辑，降低测源误差。
        final report = await LegadoParser.testSource(
          source,
          _batchKeyword,
        ).timeout(const Duration(seconds: 45));
        skipped = report.steps.isNotEmpty &&
            report.steps.every((s) => s.status == LegadoStepStatus.skip);
        success = !report.hasFailure && !skipped;
        if (success) {
          // 从「搜索结果」步骤提取书籍数量用于展示
          for (final step in report.steps) {
            final match = RegExp(r'解析到 (\d+) 本').firstMatch(step.message);
            if (match != null) {
              booksCount = int.tryParse(match.group(1)!) ?? 0;
              break;
            }
          }
        } else {
          final failStep = report.steps.firstWhere(
            (s) => s.status == LegadoStepStatus.fail,
            orElse: () => report.steps.isNotEmpty
                ? report.steps.last
                : const LegadoTestStep.fail('测试', '未知错误'),
          );
          failStepTitle = failStep.title;
          errorMessage = '${failStep.title}：${failStep.message}';
          failSample = failStep.sample;
          failLogs = failStep.logs;
          stageTrail = report.steps.map((s) {
            final mark = s.status == LegadoStepStatus.ok
                ? '✓'
                : s.status == LegadoStepStatus.fail
                ? '✗'
                : '–';
            return '$mark${s.title}';
          }).join(' · ');
          blocked = sourceCheckFailureIsBlocked(
            source,
            failStep: failStepTitle,
            message: errorMessage,
          );
        }
      } catch (e) {
        failStepTitle = '异常';
        errorMessage = e.toString().replaceFirst('Exception: ', '');
        blocked = sourceCheckFailureIsBlocked(
          source,
          failStep: failStepTitle,
          message: errorMessage,
        );
      }

      watch.stop();

      if (mounted) {
        setState(() {
          _results.add(
            SourceCheckResult(
              source: source,
              isSuccess: success,
              isBlocked: blocked,
              isSkipped: skipped,
              booksCount: booksCount,
              errorMessage: errorMessage,
              failStep: failStepTitle,
              failSample: failSample,
              failLogs: failLogs,
              stageTrail: stageTrail,
              durationInMs: watch.elapsedMilliseconds,
            ),
          );
          if (skipped) {
            _skippedCount++;
          } else if (success) {
            _successCount++;
          } else if (blocked) {
            _blockedCount++;
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

  Future<void> _copyReport() async {
    final buffer = StringBuffer()
      ..writeln('# 书源批量检测报告')
      ..writeln()
      ..writeln('- 总数: ${_results.length}')
      ..writeln('- 成功: $_successCount')
      ..writeln('- 失败: $_failCount')
      ..writeln('- 待复测/需处理: $_blockedCount')
      ..writeln('- 跳过(非小说源): $_skippedCount')
      ..writeln('- 默认关键词: $_batchKeyword')
      ..writeln('- 说明: 单源规则配置了 checkKeyWord 时会自动覆盖默认关键词')
      ..writeln()
      ..writeln('## 失败阶段统计');
    final counts = _failureStepCounts();
    if (counts.isEmpty) {
      buffer.writeln('_无_');
    } else {
      counts.forEach((step, count) => buffer.writeln('- $step: $count'));
    }
    buffer
      ..writeln()
      ..writeln('## 明细');
    for (final result in _results) {
      final status = result.isSuccess
          ? 'OK'
          : result.isSkipped
          ? 'SKIP'
          : result.isBlocked
          ? 'BLOCKED'
          : 'FAIL';
      buffer.writeln(
        '- $status '
        '${result.source.bookSourceName} '
        '[${result.durationInMs}ms]'
        '${result.failStep == null ? "" : " ${result.failStep}"}'
        '${result.errorMessage == null ? "" : " - ${result.errorMessage}"}',
      );
      if (!result.isSuccess && !result.isSkipped) {
        if (result.stageTrail != null && result.stageTrail!.isNotEmpty) {
          buffer.writeln('    阶段轨迹: ${result.stageTrail}');
        }
        if (result.failSample != null && result.failSample!.trim().isNotEmpty) {
          final sample = result.failSample!.trim().replaceAll('\n', ' ');
          final clipped =
              sample.length > 200 ? '${sample.substring(0, 200)}…' : sample;
          buffer.writeln('    抓到的内容样本: $clipped');
        }
        if (result.failLogs.isNotEmpty) {
          for (final log in result.failLogs) {
            buffer.writeln('    · ${log.replaceAll('\n', ' / ')}');
          }
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('已复制'),
        content: const Text('检测报告已复制到剪贴板。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Map<String, int> _failureStepCounts() {
    final counts = <String, int>{};
    for (final result in _results) {
      if (result.isSuccess || result.isSkipped) continue;
      final key = result.failStep ?? '未知';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  Future<void> _disableFailedSources() async {
    setState(() {
      _isDisabling = true;
    });

    final failedSources = _results
        .where((r) => r.canDisable)
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
          content: Text(
            '已成功禁用 ${failedSources.length} 个确定失效书源；待复测/需处理书源不会自动禁用。',
          ),
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
    final checked = _successCount + _failCount + _blockedCount + _skippedCount;
    final progress = total == 0 ? 0.0 : checked / total;
    final nonSuccessCount = _failCount + _blockedCount;
    final visibleResults = _filteredResults();

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('一键测源'),
        backgroundColor: CupertinoTheme.of(
          context,
        ).barBackgroundColor.withValues(alpha: 0.9),
        border: null,
        trailing: _isChecking ? const CupertinoActivityIndicator() : null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildProgressHeader(progress, checked, total),
            _buildFilterBar(),
            const Divider(height: 1, color: CupertinoColors.systemGrey5),
            Expanded(
              child: visibleResults.isEmpty
                  ? Center(
                      child: Text(
                        _emptyFilterText(),
                        style: const TextStyle(
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: _scrollController,
                      itemCount: visibleResults.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: CupertinoColors.systemGrey5,
                      ),
                      itemBuilder: (context, index) {
                        final result = visibleResults[index];
                        return _buildResultItem(result);
                      },
                    ),
            ),
            if (!_isChecking && nonSuccessCount > 0)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CupertinoButton(
                      onPressed: _copyReport,
                      child: const Text('复制检测报告'),
                    ),
                    if (_failCount > 0) ...[
                      const SizedBox(height: 8),
                      CupertinoButton.filled(
                        onPressed: _isDisabling ? null : _disableFailedSources,
                        child: _isDisabling
                            ? const CupertinoActivityIndicator()
                            : Text('一键禁用确定失效书源 ($_failCount)'),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<SourceCheckResult> _filteredResults() {
    return switch (_filter) {
      SourceCheckFilter.all => _results,
      SourceCheckFilter.success => _results.where((r) => r.isSuccess).toList(),
      SourceCheckFilter.failed => _results.where((r) => r.canDisable).toList(),
      SourceCheckFilter.blocked => _results.where((r) => r.isBlocked).toList(),
      SourceCheckFilter.skipped => _results.where((r) => r.isSkipped).toList(),
    };
  }

  String _emptyFilterText() {
    return switch (_filter) {
      SourceCheckFilter.all => _isChecking ? '正在等待检测结果...' : '暂无检测结果',
      SourceCheckFilter.success => '当前没有检测通过的书源',
      SourceCheckFilter.failed => '当前没有确定失效的书源',
      SourceCheckFilter.blocked => '当前没有待复测书源',
      SourceCheckFilter.skipped => '当前没有跳过的非小说源',
    };
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: CupertinoSlidingSegmentedControl<SourceCheckFilter>(
        groupValue: _filter,
        children: {
          SourceCheckFilter.all: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('全部 ${_results.length}'),
          ),
          SourceCheckFilter.success: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('有效 $_successCount'),
          ),
          SourceCheckFilter.failed: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('失效 $_failCount'),
          ),
          SourceCheckFilter.blocked: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('待复测 $_blockedCount'),
          ),
          SourceCheckFilter.skipped: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('跳过 $_skippedCount'),
          ),
        },
        onValueChanged: (value) {
          if (value == null) return;
          setState(() => _filter = value);
        },
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
          const Text(
            '默认关键词：$_batchKeyword；单源配置 checkKeyWord 时自动使用源内测试词；并发：2。',
            style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
          ),
          const SizedBox(height: 12),
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
              _buildStatCard(
                '待复测',
                _blockedCount,
                CupertinoColors.systemOrange,
              ),
              _buildStatCard('跳过', _skippedCount, CupertinoColors.systemGrey),
            ],
          ),
          if (!_isChecking && (_failCount + _blockedCount) > 0) ...[
            const SizedBox(height: 12),
            _buildFailureStepSummary(),
          ],
        ],
      ),
    );
  }

  Widget _buildFailureStepSummary() {
    final counts = _failureStepCounts();
    if (counts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: counts.entries.map((entry) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey5,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${entry.key} ${entry.value}',
            style: const TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
        );
      }).toList(),
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
    final color = result.isSuccess
        ? CupertinoColors.activeGreen
        : result.isSkipped
        ? CupertinoColors.systemGrey
        : result.isBlocked
        ? CupertinoColors.systemOrange
        : CupertinoColors.destructiveRed;
    final icon = result.isSuccess
        ? CupertinoIcons.check_mark_circled_solid
        : result.isSkipped
        ? CupertinoIcons.minus_circle_fill
        : result.isBlocked
        ? CupertinoIcons.exclamationmark_triangle_fill
        : CupertinoIcons.clear_circled_solid;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
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
                      '${result.durationInMs}ms',
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
                      ? '成功搜索到 ${result.booksCount} 本书'
                      : result.errorMessage != null &&
                            result.errorMessage!.length > 50
                      ? '${result.errorMessage!.substring(0, 50)}...'
                      : '${result.errorMessage}',
                  style: TextStyle(
                    fontSize: 13,
                    color: result.isSuccess
                        ? CupertinoColors.systemGrey
                        : color.withValues(alpha: 0.85),
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
