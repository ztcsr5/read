import 'package:flutter/cupertino.dart';
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
  LegadoTestReport? _report;

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
          onPressed: _isTesting ? null : _runTest,
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
                      onPressed: _isTesting ? null : _runTest,
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
            else
              ..._report!.steps.map(_buildStep),
          ],
        ),
      ),
    );
  }

  Future<void> _runTest() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty || _isTesting) return;

    setState(() {
      _isTesting = true;
      _report = null;
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
      child: Row(
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
                if (step.sample != null && step.sample!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
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
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
