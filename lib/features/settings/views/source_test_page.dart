import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/book_source.dart';
import '../../../data/parsers/legado_parser.dart';

class SourceTestPage extends StatefulWidget {
  final BookSource source;

  const SourceTestPage({super.key, required this.source});

  @override
  State<SourceTestPage> createState() => _SourceTestPageState();
}

class _SourceTestPageState extends State<SourceTestPage> {
  final TextEditingController _keywordController = TextEditingController(
    text: '斗破苍穹',
  );

  bool _isTesting = false;
  bool _isDiagnosticMode = false;
  LegadoTestReport? _report;
  final Map<int, bool> _expandedSteps = {};

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final separator = isDark
        ? const Color(0xFF2C2C2E)
        : CupertinoColors.systemGrey6;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('书源测试'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isTesting ? null : () => _runTest(),
          child: _isTesting
              ? const CupertinoActivityIndicator()
              : const Text('测试'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.source.bookSourceName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.source.bookSourceUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CupertinoTextField(
                    controller: _keywordController,
                    placeholder: '输入测试关键词',
                    clearButtonMode: OverlayVisibilityMode.editing,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runTest(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      onPressed: _isTesting ? null : () => _runTest(),
                      child: Text(_isTesting ? '测试中...' : '开始测试'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      onPressed: _isTesting ? null : _openVerification,
                      child: const Text('跳验证 / 保存站点 Cookie'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      onPressed: _isTesting ? null : () => _runTest(diagnostic: true),
                      child: const Text('抓取诊断 (收集详细日志)'),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 10, color: separator),
            if (_report == null)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 28, 20, 0),
                child: Text(
                  '会依次测试：搜索 URL、搜索结果、书籍详情、目录、正文。遇到验证码、Cloudflare 或登录页时，可以先点“跳验证”完成验证后再重试。',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
              )
            else ...[
              ..._report!.steps.map(_buildStep),
              if (_isDiagnosticMode) _buildDiagnosticConsole(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runTest({bool diagnostic = false}) async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty || _isTesting) return;

    setState(() {
      _isTesting = true;
      _isDiagnosticMode = diagnostic;
      _report = null;
      _expandedSteps.clear();
    });

    final report = await LegadoParser.testSource(widget.source, keyword);
    if (!mounted) return;
    setState(() {
      _report = report;
      _isTesting = false;
    });
  }

  Future<void> _openVerification() async {
    final result = await context.push<bool>(
      '/source_verify',
      extra: widget.source,
    );
    if (result == true && mounted) {
      await _runTest();
    }
  }

  Widget _buildStep(LegadoTestStep step) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final index = _report?.steps.indexOf(step) ?? -1;
    final isExpanded = _expandedSteps[index] ?? false;

    final color = switch (step.status) {
      LegadoStepStatus.ok => CupertinoColors.activeGreen,
      LegadoStepStatus.fail => CupertinoColors.destructiveRed,
      LegadoStepStatus.skip => CupertinoColors.systemGrey,
    };
    final icon = switch (step.status) {
      LegadoStepStatus.ok => CupertinoIcons.check_mark_circled_solid,
      LegadoStepStatus.fail => CupertinoIcons.xmark_circle_fill,
      LegadoStepStatus.skip => CupertinoIcons.minus_circle_fill,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.message,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (step.sample != null && step.sample!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  step.sample!,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
              ),
            ),
          ],
          if (step.logs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 6),
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: () {
                  setState(() {
                    _expandedSteps[index] = !isExpanded;
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isExpanded ? '收起诊断详情' : '展开诊断详情',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Icon(
                      isExpanded
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 8),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 250),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemGrey6,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey4,
                      width: 0.5,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      step.logs.join('\n'),
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        height: 1.3,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiagnosticConsole() {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final allLogs = <String>[];
    if (_report != null) {
      for (final step in _report!.steps) {
        allLogs.add('=== ${step.title} ===');
        allLogs.add('Status: ${step.status.name.toUpperCase()}');
        allLogs.add('Message: ${step.message}');
        if (step.logs.isNotEmpty) {
          allLogs.addAll(step.logs);
        }
        allLogs.add('');
      }
    }
    final logText = allLogs.join('\n');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '诊断日志控制台',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 250,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey4,
                width: 0.5,
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                logText,
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 11,
                  height: 1.3,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              color: CupertinoColors.activeBlue,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: logText));
                if (!mounted) return;
                showCupertinoDialog(
                  context: context,
                  builder: (context) => CupertinoAlertDialog(
                    title: const Text('复制成功'),
                    content: const Text('所有诊断日志已复制到剪贴板。'),
                    actions: [
                      CupertinoDialogAction(
                        child: const Text('确定'),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('复制全部诊断日志'),
            ),
          ),
        ],
      ),
    );
  }
}
